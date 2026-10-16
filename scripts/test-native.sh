#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."
source scripts/macos-toolchain.sh
arch=$(uname -m)
scratch=$(mktemp -d)
trap 'rm -rf "$scratch"' EXIT
ssh-keygen -q -t ed25519 -N '' -f "$scratch/test-key"
ssh-keygen -q -t ed25519 -N 'synthetic-tray-passphrase' -f "$scratch/tray-key"
"$KEEPY_SWIFTC" -swift-version 5 -warnings-as-errors -sdk "$SDKROOT" -target "$arch-apple-macosx14.0" \
  -F target/sparkle -framework Sparkle -Xlinker -rpath -Xlinker "$PWD/target/sparkle" \
  -module-cache-path "$KEEPY_SWIFT_MODULE_CACHE" \
  macos/Sources/Keepy/AppLogo.swift \
  macos/Sources/Keepy/Models.swift macos/Sources/Keepy/CoreClient.swift \
  macos/Sources/Keepy/TouchID.swift macos/Sources/Keepy/VaultManagement.swift \
  macos/Tests/NativeTouchID.swift \
  macos/Sources/Keepy/AppStore.swift macos/Sources/Keepy/WorkspaceView.swift \
  macos/Sources/Keepy/VaultOutline.swift macos/Sources/Keepy/Editors.swift \
  macos/Sources/Keepy/SSHKeysEditor.swift macos/Tests/NativeStore.swift \
  macos/Sources/Keepy/WindowSurface.swift \
  macos/Sources/Keepy/UpdateController.swift macos/Tests/NativeUpdates.swift \
  macos/Tests/NativeOutline.swift macos/Tests/NativeWindowSurface.swift \
  macos/Tests/NativeOutlineKeyboard.swift macos/Tests/NativeSearchExpansion.swift \
  macos/Tests/NativeTagFilter.swift \
  macos/Sources/Keepy/TrayShortcut.swift macos/Sources/Keepy/TrayMenu.swift macos/Sources/Keepy/TrayTags.swift \
  macos/Tests/NativeTrayShortcut.swift macos/Tests/NativeVaultManagement.swift macos/Tests/NativeTrayTags.swift \
  macos/Tests/Integration.swift -o "$scratch/integration"
KEEPY_DATA_DIR="$scratch/data" "$scratch/integration" \
  "$PWD/target/macos/$arch/Keepy.app/Contents/MacOS/keepy-core" "$scratch/test-key" "$scratch/tray-key" | tee "$scratch/native-output.log"
if ! grep -q '^Native pipe integration passed:' "$scratch/native-output.log"; then
  printf '%s\n' 'Native tests exited before completing integration.' >&2
  exit 1
fi
