#!/usr/bin/env bash
set -e

# Get the directory where this script is located
SCRIPT_DIR=$( cd -- "$( dirname -- "${BASH_SOURCE[0]}" )" &> /dev/null && pwd )

# Navigate to the project root (4 levels up from bench/evm/runners/tevm)
PROJECT_ROOT="$SCRIPT_DIR/../../../.."
cd "$PROJECT_ROOT"

# Build the tevm-runner executable
{
    zig build tevm-runner --release=fast
} > /dev/null 2>&1

# Run the executable with all provided arguments
exec "./zig-out/bin/tevm-runner" "$@"