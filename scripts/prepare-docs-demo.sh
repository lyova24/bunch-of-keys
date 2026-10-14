#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."
app="target/macos/$(uname -m)/Keepy.app"
demo="target/docs-demo-app/Keepy.app"
[[ -d "$app" ]] || { echo 'Build Keepy before preparing screenshots.' >&2; exit 1; }
[[ ! -e target/docs-demo-app && ! -e target/docs-demo ]] || {
  echo 'Demo directories already exist. Move them aside before creating a fresh demo.' >&2
  exit 1
}
python3 scripts/seed-docs-demo.py
mkdir -p target/docs-demo-app
cp -R "$app" "$demo"
# Separate app identity keeps screenshot windows/preferences distinct from real Keepy.
/usr/libexec/PlistBuddy -c 'Set CFBundleIdentifier dev.keepy.docs-demo' "$demo/Contents/Info.plist"
codesign --force --sign - "$demo"
echo 'Run: KEEPY_DATA_DIR="$PWD/target/docs-demo" target/docs-demo-app/Keepy.app/Contents/MacOS/keepy'
