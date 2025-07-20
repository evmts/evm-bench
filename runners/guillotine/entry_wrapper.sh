#!/usr/bin/env bash
set -e

echo "ERROR: Guillotine runner integration failed due to illegal instruction errors"
echo "Signal 4 crashes when using Guillotine EVM modules from submodule"
echo "This appears to be an architecture/build environment issue"
echo "The tests pass in the original Guillotine repository but not as a submodule"
exit 1