#!/bin/bash
set -euo pipefail

cd "$(dirname "$0")"

echo "Building action-relay..."
swift build

BINARY=".build/debug/action-relay"

# Sign with dev certificate if available
IDENTITY=$(security find-identity -v -p codesigning | grep "Apple Development" | head -1 | awk -F'"' '{print $2}')
if [ -n "$IDENTITY" ]; then
    # Check if AMFI is disabled — if so, sign with entitlements for Option B support
    if nvram boot-args 2>/dev/null | grep -q "amfi_get_out_of_my_way"; then
        codesign --force --sign "$IDENTITY" --entitlements execution/workflowkit-xpc/entitlements.plist "$BINARY"
        echo "Signed with: $IDENTITY (+ entitlements, AMFI disabled)"
    else
        codesign --force --sign "$IDENTITY" "$BINARY"
        echo "Signed with: $IDENTITY (no entitlements — Option A only)"
    fi
else
    echo "No Apple Development certificate found, using ad-hoc signature"
    codesign --force --sign - "$BINARY"
fi

echo "Built: $(pwd)/$BINARY"
echo ""
echo "Usage:"
echo "  $BINARY <app> --list     # List discovered tools as JSON"
echo "  $BINARY <app>            # Start MCP server (stdio)"
