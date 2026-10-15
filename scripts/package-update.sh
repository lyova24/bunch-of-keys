#!/usr/bin/env bash
# Make a signed Sparkle update, matching release notes and architecture feed.
set -euo pipefail
cd "$(dirname "$0")/.."
arch="${KEEPY_ARCH:-$(uname -m)}"
case "$arch" in arm64|x86_64) ;; *) echo 'Unsupported architecture' >&2; exit 1 ;; esac
version=$(/usr/libexec/PlistBuddy -c 'Print CFBundleVersion' macos/Info.plist)
app="target/macos/$arch/Keepy.app"
codesign --verify --deep --strict "$app"
[[ "$(lipo -archs "$app/Contents/MacOS/keepy")" == "$arch" ]] || { echo 'Update architecture does not match its feed.' >&2; exit 1; }
public_key=$(/usr/libexec/PlistBuddy -c 'Print SUPublicEDKey' "$app/Contents/Info.plist")
[[ -n "$public_key" ]] || { echo 'An update signing public key is required.' >&2; exit 1; }
stage="target/updates/$arch"
mkdir -p "$stage" dist
archive="Keepy_${version}_${arch}.zip"
ditto -c -k --sequesterRsrc --keepParent "$app" "$stage/$archive"
python3 - "$version" "$stage/${archive%.zip}.html" <<'PY'
import html, pathlib, sys
version, destination = sys.argv[1:]
section = pathlib.Path('CHANGELOG.md').read_text().split(f'## {version} - ', 1)[1].split('\n', 1)[1].split('\n## ', 1)[0]
pathlib.Path(destination).write_text('<h2>Keepy ' + html.escape(version) + '</h2><pre>' + html.escape(section.strip()) + '</pre>\n')
PY
key_args=(--account keepy)
if [[ -n "${KEEPY_UPDATE_KEY_FILE:-}" ]]; then key_args=(--ed-key-file "$KEEPY_UPDATE_KEY_FILE"); fi
target/sparkle/bin/generate_appcast "${key_args[@]}" --maximum-deltas 0 \
  --download-url-prefix "https://github.com/lyova24/keepy/releases/download/v$version/" \
  --embed-release-notes -o "$stage/appcast-$arch.xml" "$stage"
# Verify with the publishing key before any artifacts can be uploaded.
target/sparkle/bin/sign_update "${key_args[@]}" --verify "$stage/appcast-$arch.xml"
python3 scripts/validate-update.py "$stage/appcast-$arch.xml" "$stage/$archive" "$version" "$arch"
target/macos/verify-update "$app/Contents/Info.plist" "$stage/appcast-$arch.xml" "$stage/$archive"
cp "$stage/$archive" "$stage/appcast-$arch.xml" dist/
(cd dist && shasum -a 256 "$archive" > "$archive.sha256")
