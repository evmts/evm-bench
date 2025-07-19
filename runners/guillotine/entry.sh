#!/usr/bin/env bash
set -e

SCRIPT_DIR=$( cd -- "$( dirname -- "${BASH_SOURCE[0]}" )" &> /dev/null && pwd )

zig build -Doptimize=ReleaseFast --prefix-exe-dir $SCRIPT_DIR/zig-out/bin/
$SCRIPT_DIR/zig-out/bin/guillotine-runner "$@"