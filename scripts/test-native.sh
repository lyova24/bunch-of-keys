#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."
arch=$(uname -m)
export SDKROOT="${SDKROOT:-$(xcrun --sdk macosx --show-sdk-path)}"
scratch=$(mktemp -d)
trap 'rm -rf "$scratch"' EXIT
ssh-keygen -q -t ed25519 -N '' -f "$scratch/test-key"
xcrun swiftc -swift-version 5 -warnings-as-errors -sdk "$SDKROOT" \
  -module-cache-path target/swift-module-cache \
  macos/Sources/Keepy/AppLogo.swift \
  macos/Sources/Keepy/Models.swift macos/Sources/Keepy/CoreClient.swift \
  macos/Sources/Keepy/AppStore.swift macos/Sources/Keepy/WorkspaceView.swift \
  macos/Sources/Keepy/VaultOutline.swift macos/Sources/Keepy/Editors.swift \
  macos/Sources/Keepy/SSHKeysEditor.swift macos/Tests/NativeStore.swift \
  macos/Sources/Keepy/WindowSurface.swift \
  macos/Tests/NativeOutline.swift macos/Tests/NativeWindowSurface.swift \
  macos/Tests/NativeTagFilter.swift \
  macos/Tests/Integration.swift -o "$scratch/integration"
KEEPY_DATA_DIR="$scratch/data" "$scratch/integration" \
  "$PWD/target/macos/$arch/Keepy.app/Contents/MacOS/keepy-core" "$scratch/test-key" | tee "$scratch/native-output.log"
if ! grep -q '^Native pipe integration passed:' "$scratch/native-output.log"; then
  printf '%s\n' 'Native tests exited before completing integration.' >&2
  exit 1
fi
