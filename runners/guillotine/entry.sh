#!/usr/bin/env bash
set -e

# Get the directory where this script is located
SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"

# Build with ReleaseFast optimization (required for ARM64 compatibility)
cd "$SCRIPT_DIR"
# Always rebuild to pick up code changes - it's fast enough
zig build -Doptimize=ReleaseFast >/dev/null 2>&1

# Execute the runner, redirecting debug output to stderr
exec "$SCRIPT_DIR/zig-out/bin/guillotine-runner" "$@" 2>/dev/null