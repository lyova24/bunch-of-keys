#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."
source scripts/macos-toolchain.sh
[[ "$(uname -s)" == Darwin ]] || { echo 'macOS is required.' >&2; exit 1; }
bash scripts/check-version-sync.sh
bash scripts/fetch-sparkle.sh
arch="${KEEPY_ARCH:-$(uname -m)}"
case "$arch" in
  arm64) rust_target=aarch64-apple-darwin ;;
  x86_64) rust_target=x86_64-apple-darwin ;;
  *) echo "Unsupported architecture: $arch" >&2; exit 1 ;;
esac
cargo build --release --locked --target "$rust_target"
mkdir -p "target/macos/$arch"
"$KEEPY_SWIFTC" -swift-version 5 -warnings-as-errors -sdk "$SDKROOT" \
  -target "$(uname -m)-apple-macosx14.0" -module-cache-path "$KEEPY_SWIFT_MODULE_CACHE" \
  scripts/verify-update.swift -o target/macos/verify-update
staging=$(mktemp -d "target/macos/$arch/staging.XXXXXX")
trap 'rm -rf "$staging"' EXIT
app="$staging/Keepy.app"
mkdir -p "$app/Contents/MacOS" "$app/Contents/Resources" "$app/Contents/Frameworks" target/swift-module-cache
ditto target/sparkle/Sparkle.framework "$app/Contents/Frameworks/Sparkle.framework"
"$KEEPY_SWIFTC" -swift-version 5 -warnings-as-errors -sdk "$SDKROOT" \
  -target "$(uname -m)-apple-macosx14.0" -module-cache-path "$KEEPY_SWIFT_MODULE_CACHE" \
  macos/Sources/Keepy/AppLogo.swift scripts/render-logo.swift -o "$staging/render-logo"
"$staging/render-logo" "$staging/icons"
"$KEEPY_SWIFTC" -O -swift-version 5 -warnings-as-errors -sdk "$SDKROOT" \
  -target "$arch-apple-macosx14.0" -module-cache-path "$KEEPY_SWIFT_MODULE_CACHE" \
  -F target/sparkle -framework Sparkle -Xlinker -rpath -Xlinker @executable_path/../Frameworks \
  macos/Sources/Keepy/*.swift -o "$app/Contents/MacOS/keepy"
cp "target/$rust_target/release/keepy-core" "$app/Contents/MacOS/"
cp macos/Info.plist "$app/Contents/Info.plist"
iconset="target/macos/$arch/AppIcon.iconset"
mkdir -p "$iconset"
for size in 16 32 128 256 512; do
  sips -z "$size" "$size" "$staging/icons/icon.png" --out "$iconset/icon_${size}x${size}.png" >/dev/null
  double=$((size * 2))
  sips -z "$double" "$double" "$staging/icons/icon.png" --out "$iconset/icon_${size}x${size}@2x.png" >/dev/null
done
python3 scripts/create-icns.py "$iconset" "$app/Contents/Resources/AppIcon.icns"
codesign --force --sign "${KEEPY_SIGN_IDENTITY:--}" --options runtime "$app/Contents/MacOS/keepy-core"
# Keep Sparkle's upstream signature for ad-hoc development bundles. Developer ID
# distribution must sign nested helpers inside-out with the same identity.
if [[ "${KEEPY_SIGN_IDENTITY:--}" != - ]]; then
  framework="$app/Contents/Frameworks/Sparkle.framework/Versions/B"
  for nested in "$framework/XPCServices/Downloader.xpc" "$framework/XPCServices/Installer.xpc" "$framework/Autoupdate" "$framework/Updater.app" "$app/Contents/Frameworks/Sparkle.framework"; do
    codesign --force --sign "$KEEPY_SIGN_IDENTITY" --options runtime --timestamp "$nested"
  done
fi
app_signing=()
if [[ -n "${KEEPY_PROVISIONING_PROFILE:-}" ]]; then
  [[ "${KEEPY_SIGN_IDENTITY:--}" != - ]] || { echo 'Touch ID provisioning requires an Apple signing identity.' >&2; exit 1; }
  security cms -D -i "$KEEPY_PROVISIONING_PROFILE" -o "$staging/profile.plist"
  python3 scripts/prepare-keychain-signing.py "$staging/profile.plist" dev.keepy.desktop "$staging/keychain.entitlements"
  cp "$KEEPY_PROVISIONING_PROFILE" "$app/Contents/embedded.provisionprofile"
  app_signing=(--entitlements "$staging/keychain.entitlements")
fi
if [[ "${KEEPY_SIGN_IDENTITY:--}" == - ]]; then
  # Ad-hoc executables have no Team ID. Library validation would reject even
  # the checksum-pinned Sparkle framework at launch without this entitlement.
  app_signing=(--entitlements macos/AdHoc.entitlements)
fi
codesign --force --sign "${KEEPY_SIGN_IDENTITY:--}" --options runtime "${app_signing[@]}" "$app"
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
codesign --verify --deep --strict "$app"
python3 scripts/verify-macos-build.py "$app" --arch "$arch" --helper target/macos/verify-update
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
