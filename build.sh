#!/bin/bash
set -euo pipefail

cd "$(dirname "$0")"

echo "Building action-relay..."
swift build

BINARY=".build/debug/action-relay"

echo "Built: $(pwd)/$BINARY"
echo ""
echo "Usage:"
echo "  $BINARY <app> --list     # List discovered tools as JSON"
echo "  $BINARY <app>            # Start MCP server (stdio, list_tools only)"
