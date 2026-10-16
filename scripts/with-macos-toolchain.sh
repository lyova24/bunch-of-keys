#!/usr/bin/env bash
# Run any development check with the same SDK, linker and runtime target.
set -euo pipefail
cd "$(dirname "$0")/.."
source scripts/macos-toolchain.sh
[[ $# -gt 0 ]] || { echo 'Usage: bash scripts/with-macos-toolchain.sh COMMAND [ARGS...]' >&2; exit 1; }
exec "$@"
