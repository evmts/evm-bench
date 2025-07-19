#!/usr/bin/env bash
set -e

SCRIPT_DIR=$( cd -- "$( dirname -- "${BASH_SOURCE[0]}" )" &> /dev/null && pwd )

cd $SCRIPT_DIR
zig build -Doptimize=ReleaseFast
./zig-out/bin/guillotine-runner "$@"