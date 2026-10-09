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
  macos/Sources/BunchOfKeys/Models.swift macos/Sources/BunchOfKeys/CoreClient.swift \
  macos/Sources/BunchOfKeys/AppStore.swift macos/Sources/BunchOfKeys/WorkspaceView.swift \
  macos/Sources/BunchOfKeys/VaultOutline.swift macos/Sources/BunchOfKeys/Editors.swift \
  macos/Sources/BunchOfKeys/SSHKeysEditor.swift macos/Tests/NativeStore.swift \
  macos/Sources/BunchOfKeys/WindowSurface.swift \
  macos/Tests/NativeOutline.swift macos/Tests/NativeWindowSurface.swift \
  macos/Tests/Integration.swift -o "$scratch/integration"
BUNCH_OF_KEYS_DATA_DIR="$scratch/data" "$scratch/integration" \
  "$PWD/target/macos/$arch/bunch-of-keys.app/Contents/MacOS/bunch-of-keys-core" "$scratch/test-key"
