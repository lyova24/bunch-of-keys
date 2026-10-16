#!/usr/bin/env bash
# Cargo invokes this for both supported targets; never fall back to PATH's cc/ld.
set -euo pipefail
: "${KEEPY_CLANG:?Run through scripts/with-macos-toolchain.sh}"
: "${KEEPY_APPLE_BIN:?Missing selected Apple linker directory}"
: "${SDKROOT:?Missing selected SDK}"
exec "$KEEPY_CLANG" -B"$KEEPY_APPLE_BIN/" -isysroot "$SDKROOT" -mmacosx-version-min=14.0 "$@"
