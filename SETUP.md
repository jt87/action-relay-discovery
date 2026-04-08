# Setup Guide: Disabling SIP and AMFI

> **You are about to disable core macOS security protections.** This is not a drill. Read this entire document before touching anything.

## What you're doing and why

Action Relay executes App Intents by sending raw workflow plists to `BackgroundShortcutRunner.xpc`. This XPC service checks for the `com.apple.shortcuts.background-running` entitlement, and AMFI (Apple Mobile File Integrity) is what enforces entitlement validation at runtime. SIP (System Integrity Protection) protects AMFI and other system components from being tampered with.

To run action-relay with execution support, both need to be disabled:

- **SIP off** — so AMFI can be disabled
- **AMFI off** — so the self-signed entitlement on the action-relay binary is actually honored

Without these, discovery still works (`--list`), but execution will fail with entitlement errors.

---

## The warnings

**Do not do this on a machine you rely on for daily use unless you understand the risks.**

With SIP and AMFI disabled:

- Any application can claim any entitlement. Sandboxing, hardened runtime, and entitlement checks are effectively gone.
- Malware that would normally be blocked by Gatekeeper, notarization, or AMFI can run freely.
- System files are no longer protected from modification.
- Kernel extensions can be loaded without approval.
- You will not get macOS security updates that depend on SIP being enabled.
- **FileVault still works**, but the overall attack surface of your machine is dramatically larger.

**Recommended**: Do this on a dedicated development machine or a VM (UTM works well for this). Not on the laptop you take to coffee shops.

---

## Step 1: Disable SIP

SIP can only be changed from Recovery Mode.

### Intel Mac

1. Shut down your Mac
2. Turn it on and immediately hold **Cmd + R** until you see the Apple logo
3. Once in Recovery, open **Terminal** from the Utilities menu
4. Run:
   ```
   csrutil disable
   ```
5. Reboot:
   ```
   reboot
   ```

### Apple Silicon (M1/M2/M3/M4)

1. Shut down your Mac completely
2. Press and **hold the power button** until you see "Loading startup options..."
3. Click **Options**, then **Continue**
4. If prompted, select a user and enter their password
5. From the menu bar, open **Utilities > Terminal**
6. Run:
   ```
   csrutil disable
   ```
7. When prompted, confirm and enter your password
8. Reboot:
   ```
   reboot
   ```

### Verify

After rebooting, open Terminal and run:

```
csrutil status
```

You should see:

```
System Integrity Protection status: disabled.
```

---

## Step 2: Disable AMFI

This is done with an NVRAM boot argument. **Requires SIP to be disabled first.**

From a normal Terminal session (not Recovery):

```
sudo nvram boot-args="amfi_get_out_of_my_way=1"
```

Then reboot:

```
sudo reboot
```

### Verify

After rebooting, check that the boot arg is set:

```
nvram boot-args
```

You should see:

```
boot-args	amfi_get_out_of_my_way=1
```

You can also confirm AMFI is not enforcing by building and running action-relay — if execution works, AMFI is out of the way.

---

## Undoing everything

### Re-enable AMFI

From a normal Terminal session:

```
sudo nvram -d boot-args
```

This deletes the `boot-args` variable entirely. If you have other boot args you want to keep, set them explicitly without the `amfi_get_out_of_my_way=1` part.

Reboot:

```
sudo reboot
```

### Re-enable SIP

Boot into Recovery Mode (same process as above — Cmd+R on Intel, hold power button on Apple Silicon).

Open Terminal from Utilities and run:

```
csrutil enable
```

Reboot:

```
reboot
```

### Verify everything is back to normal

```
csrutil status
# → System Integrity Protection status: enabled.

nvram boot-args
# → should show nothing or error "nvram: Error getting variable - 'boot-args': (iokit/common) data was not found"
```

---

## If you have other boot-args

The `nvram -d boot-args` command deletes **all** boot args. If you use other boot arguments (e.g., `keepsyms=1` for kernel debugging), you need to set them back without the AMFI flag:

```
# Example: keep other args, remove only the AMFI one
sudo nvram boot-args="keepsyms=1"
```

---

## Quick reference

| State | Command | Where |
|---|---|---|
| Disable SIP | `csrutil disable` | Recovery Mode Terminal |
| Disable AMFI | `sudo nvram boot-args="amfi_get_out_of_my_way=1"` | Normal Terminal (SIP must be off) |
| Re-enable AMFI | `sudo nvram -d boot-args` | Normal Terminal |
| Re-enable SIP | `csrutil enable` | Recovery Mode Terminal |
| Check SIP | `csrutil status` | Anywhere |
| Check AMFI | `nvram boot-args` | Anywhere |
