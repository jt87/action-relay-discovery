import Foundation
import ObjectiveC

nonisolated(unsafe) private let RTLD_DEFAULT = UnsafeMutableRawPointer(bitPattern: -2)

// MARK: - ObjC Runtime Helpers

/// Call objc_msgSend with 1 object arg + 1 UInt64 arg.
private func msgSend_ObjUInt64(_ obj: AnyObject, _ sel: Selector, _ arg1: AnyObject?, _ arg2: UInt64) -> AnyObject {
    typealias Fn = @convention(c) (AnyObject, Selector, AnyObject?, UInt64) -> AnyObject
    let f = unsafeBitCast(dlsym(RTLD_DEFAULT!, "objc_msgSend")!, to: Fn.self)
    return f(obj, sel, arg1, arg2)
}

/// Call objc_msgSend with 5 object args.
private func msgSend_5obj(_ obj: AnyObject, _ sel: Selector,
                          _ a1: AnyObject, _ a2: AnyObject, _ a3: AnyObject?,
                          _ a4: AnyObject, _ a5: AnyObject) {
    typealias Fn = @convention(c) (AnyObject, Selector, AnyObject, AnyObject, AnyObject?, AnyObject, AnyObject) -> Void
    let f = unsafeBitCast(dlsym(RTLD_DEFAULT!, "objc_msgSend")!, to: Fn.self)
    f(obj, sel, a1, a2, a3, a4, a5)
}

// MARK: - Execution Result

struct ExecutionResult: Sendable {
    let values: [String]
    let error: String?
}

// MARK: - Intent Executor

actor IntentExecutor {
    private var frameworksLoaded = false
    private let xpcServiceName = "com.apple.WorkflowKit.BackgroundShortcutRunner"

    func loadFrameworks() {
        guard !frameworksLoaded else { return }
        let frameworks = [
            "/System/Library/PrivateFrameworks/WorkflowKit.framework/WorkflowKit",
            "/System/Library/PrivateFrameworks/VoiceShortcutClient.framework/VoiceShortcutClient",
        ]
        for path in frameworks {
            guard dlopen(path, RTLD_NOW) != nil else {
                let err = String(cString: dlerror())
                fatalError("Failed to load \(path): \(err)")
            }
        }
        frameworksLoaded = true
    }

    func execute(workflowData: Data) async throws -> ExecutionResult {
        loadFrameworks()

        return try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<ExecutionResult, Error>) in
            // Get XPC interfaces
            let (vendorInterface, hostInterface) = self.getXPCInterfaces()

            // Create host delegate with continuation
            let hostDelegate = XPCHostDelegate(continuation: continuation)

            // Set up XPC connection
            let connection = NSXPCConnection(serviceName: self.xpcServiceName)
            connection.remoteObjectInterface = vendorInterface
            connection.exportedInterface = hostInterface
            connection.exportedObject = hostDelegate

            connection.interruptionHandler = {
                // Only resume if not already completed
                hostDelegate.completeIfNeeded(with: .failure(ExecutionError.connectionInterrupted))
            }
            connection.invalidationHandler = {
                hostDelegate.completeIfNeeded(with: .failure(ExecutionError.connectionInvalidated))
            }

            connection.resume()

            // Create descriptor from workflow data
            let descriptor = self.createDataDescriptor(workflowData: workflowData)
            let request = self.createRequest()
            let context = self.createContext()

            // Get remote proxy
            let proxy = connection.remoteObjectProxyWithErrorHandler { error in
                hostDelegate.completeIfNeeded(with: .failure(error))
            }

            // Completion block
            let completionBlock: @convention(block) (AnyObject?, NSError?) -> Void = { result, error in
                if let error = error {
                    hostDelegate.completeIfNeeded(with: .success(ExecutionResult(
                        values: [], error: error.localizedDescription
                    )))
                    return
                }

                if let result = result as? NSObject {
                    // Check for error inside result
                    if let resultError = result.value(forKey: "error") as? NSError {
                        hostDelegate.completeIfNeeded(with: .success(ExecutionResult(
                            values: [], error: resultError.localizedDescription
                        )))
                        return
                    }

                    // Extract output
                    let values = OutputExtractor.extractFromResult(result)
                    hostDelegate.completeIfNeeded(with: .success(ExecutionResult(
                        values: values, error: nil
                    )))
                } else {
                    hostDelegate.completeIfNeeded(with: .success(ExecutionResult(
                        values: [], error: nil
                    )))
                }
            }

            // Send the workflow
            let sel = NSSelectorFromString("runWorkflowWithDescriptor:request:inEnvironment:runningContext:completion:")
            msgSend_5obj(proxy as AnyObject, sel,
                         descriptor, request, nil,
                         context, completionBlock as AnyObject)

            // Set up timeout
            DispatchQueue.global().asyncAfter(deadline: .now() + 30) {
                hostDelegate.completeIfNeeded(with: .failure(ExecutionError.timeout))
            }
        }
    }

    // MARK: - Private XPC Helpers

    nonisolated private func getXPCInterfaces() -> (vendor: NSXPCInterface, host: NSXPCInterface) {
        typealias Factory = @convention(c) () -> AnyObject

        guard let vendorSym = dlsym(RTLD_DEFAULT!, "WFOutOfProcessWorkflowControllerVendorXPCInterface"),
              let hostSym = dlsym(RTLD_DEFAULT!, "WFOutOfProcessWorkflowControllerHostXPCInterface")
        else {
            fatalError("Could not find XPC interface factory symbols")
        }

        let makeVendor = unsafeBitCast(vendorSym, to: Factory.self)
        let makeHost = unsafeBitCast(hostSym, to: Factory.self)

        guard let vendor = makeVendor() as? NSXPCInterface,
              let host = makeHost() as? NSXPCInterface
        else {
            fatalError("Interface factory returned unexpected type")
        }

        return (vendor, host)
    }

    nonisolated private func createDataDescriptor(workflowData: Data) -> AnyObject {
        guard let cls = NSClassFromString("WFWorkflowDataRunDescriptor") else {
            fatalError("WFWorkflowDataRunDescriptor not found")
        }
        let alloc = (cls as AnyObject).perform(NSSelectorFromString("alloc"))!.takeUnretainedValue()
        return alloc.perform(NSSelectorFromString("initWithWorkflowData:"), with: workflowData as NSData)!.takeUnretainedValue()
    }

    nonisolated private func createRequest() -> AnyObject {
        guard let cls = NSClassFromString("WFWorkflowRunRequest") else {
            fatalError("WFWorkflowRunRequest not found")
        }
        let alloc = (cls as AnyObject).perform(NSSelectorFromString("alloc"))!.takeUnretainedValue()
        let obj = msgSend_ObjUInt64(alloc, NSSelectorFromString("initWithInput:presentationMode:"), nil, 0)
        let nsobj = obj as! NSObject
        nsobj.setValue(2 as NSNumber, forKey: "outputBehavior")
        return obj
    }

    nonisolated private func createContext() -> AnyObject {
        guard let cls = NSClassFromString("WFWorkflowRunningContext") else {
            fatalError("WFWorkflowRunningContext not found")
        }
        let alloc = (cls as AnyObject).perform(NSSelectorFromString("alloc"))!.takeUnretainedValue()
        let ctxID = UUID().uuidString as NSString
        return alloc.perform(NSSelectorFromString("initWithWorkflowIdentifier:"), with: ctxID)!.takeUnretainedValue()
    }
}

// MARK: - Errors

enum ExecutionError: Error, CustomStringConvertible {
    case connectionInterrupted
    case connectionInvalidated
    case timeout

    var description: String {
        switch self {
        case .connectionInterrupted: return "XPC connection interrupted"
        case .connectionInvalidated: return "XPC connection invalidated"
        case .timeout: return "Execution timed out after 30 seconds"
        }
    }
}

// MARK: - XPC Host Delegate

/// Receives callbacks from BackgroundShortcutRunner.
/// Thread-safe: uses a lock to ensure the continuation is only resumed once.
private class XPCHostDelegate: NSObject, @unchecked Sendable {
    private let continuation: CheckedContinuation<ExecutionResult, Error>
    private var completed = false
    private let lock = NSLock()

    init(continuation: CheckedContinuation<ExecutionResult, Error>) {
        self.continuation = continuation
    }

    func completeIfNeeded(with result: Result<ExecutionResult, Error>) {
        lock.lock()
        defer { lock.unlock() }
        guard !completed else { return }
        completed = true
        continuation.resume(with: result)
    }

    @objc func workflowDidStartRunning(_ arg1: Any?,
                                        isAutomation arg2: Any?,
                                        dialogAttribution arg3: Any?) {
        // Workflow started — no action needed
    }

    @objc func actionWithUUID(_ uuid: Any?,
                              didFinishRunningWithError error: Any?,
                              serializedVariable variable: Any?,
                              executionResultMetadata metadata: Any?) {
        // Individual action finished — completion block handles final result
    }

    @objc func presenterRequestedUpdatedRunViewSource(_ source: Any?,
                                                       completionHandler handler: Any?) {
        if let block = handler {
            typealias ReplyBlock = @convention(block) (AnyObject?) -> Void
            let callback = unsafeBitCast(block as AnyObject, to: ReplyBlock.self)
            callback(nil)
        }
    }

    @objc func runnerDidPunchToShortcutsJr() {}

    @objc func runnerWillExit() {}

    @objc func workflowDidPause() {}
}
