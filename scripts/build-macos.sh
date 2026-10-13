#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."
[[ "$(uname -s)" == Darwin ]] || { echo 'macOS is required.' >&2; exit 1; }
bash scripts/check-version-sync.sh
arch="${BOK_ARCH:-$(uname -m)}"
case "$arch" in
  arm64) rust_target=aarch64-apple-darwin ;;
  x86_64) rust_target=x86_64-apple-darwin ;;
  *) echo "Unsupported architecture: $arch" >&2; exit 1 ;;
esac
export SDKROOT="${SDKROOT:-$(xcrun --sdk macosx --show-sdk-path)}"
export MACOSX_DEPLOYMENT_TARGET=14.0
cargo build --release --locked --target "$rust_target"
mkdir -p "target/macos/$arch"
staging=$(mktemp -d "target/macos/$arch/staging.XXXXXX")
trap 'rm -rf "$staging"' EXIT
app="$staging/Keepy.app"
mkdir -p "$app/Contents/MacOS" "$app/Contents/Resources" target/swift-module-cache
xcrun swiftc -swift-version 5 -warnings-as-errors -sdk "$SDKROOT" \
  -target "$(uname -m)-apple-macosx14.0" -module-cache-path target/swift-module-cache \
  macos/Sources/BunchOfKeys/AppLogo.swift scripts/render-logo.swift -o "$staging/render-logo"
"$staging/render-logo" "$staging/icons"
xcrun swiftc -O -swift-version 5 -warnings-as-errors -sdk "$SDKROOT" \
  -target "$arch-apple-macosx14.0" -module-cache-path target/swift-module-cache \
  macos/Sources/BunchOfKeys/*.swift -o "$app/Contents/MacOS/bunch-of-keys"
cp "target/$rust_target/release/bunch-of-keys-core" "$app/Contents/MacOS/"
cp macos/Info.plist "$app/Contents/Info.plist"
iconset="target/macos/$arch/AppIcon.iconset"
mkdir -p "$iconset"
for size in 16 32 128 256 512; do
  sips -z "$size" "$size" "$staging/icons/icon.png" --out "$iconset/icon_${size}x${size}.png" >/dev/null
  double=$((size * 2))
  sips -z "$double" "$double" "$staging/icons/icon.png" --out "$iconset/icon_${size}x${size}@2x.png" >/dev/null
done
python3 scripts/create-icns.py "$iconset" "$app/Contents/Resources/AppIcon.icns"
codesign --force --sign "${BOK_SIGN_IDENTITY:--}" --options runtime "$app/Contents/MacOS/bunch-of-keys-core"
codesign --force --sign "${BOK_SIGN_IDENTITY:--}" --options runtime "$app"
destination="target/macos/$arch/Keepy.app"
# Replacing the directory preserves running executable mappings during rebuilds.
python3 - "$app" "$destination" "$staging/previous.app" <<'PY_RENAME'
import os
import sys
source, destination, previous = sys.argv[1:]
if os.path.exists(destination):
    os.rename(destination, previous)
try:
    os.rename(source, destination)
except OSError:
    if os.path.exists(previous):
        os.rename(previous, destination)
    raise
PY_RENAME
app="$destination"
echo "Built $app"
if [[ "${1:-}" == --dmg ]]; then
  version=$(/usr/libexec/PlistBuddy -c 'Print CFBundleShortVersionString' macos/Info.plist)
  stage="target/macos/$arch/dmg-stage"
  mkdir -p "$stage" dist
  ditto "$app" "$stage/Keepy.app"
  ln -sfn /Applications "$stage/Applications"
  dmg="dist/Keepy_${version}_${arch}.dmg"
  hdiutil create -ov -format UDZO -volname Keepy -srcfolder "$stage" "$dmg"
  (cd dist && shasum -a 256 "$(basename "$dmg")" > "$(basename "$dmg").sha256")
  echo "Built $dmg"
fi
