#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."
manifest_version=$(sed -n '/^\[package\]$/,/^\[/s/^version = "\([^"]*\)"/\1/p' Cargo.toml)
lock_version=$(awk '/^\[\[package\]\]$/ { found = 0 } /^name = "keepy"$/ { found = 1; next } found && /^version = / { gsub(/^version = "|"$/, ""); print; exit }' Cargo.lock)
bundle_version=$(/usr/libexec/PlistBuddy -c 'Print CFBundleShortVersionString' macos/Info.plist)
build_version=$(/usr/libexec/PlistBuddy -c 'Print CFBundleVersion' macos/Info.plist)
changelog_version=$(sed -n 's/^## \([^[:space:]]*\) - .*/\1/p' CHANGELOG.md | head -n 1)
for version in "$lock_version" "$bundle_version" "$build_version" "$changelog_version"; do
  [[ -n "$manifest_version" && "$version" == "$manifest_version" ]] || { echo 'Cargo, native bundle and changelog versions must match.' >&2; exit 1; }
done
echo "Project version is synchronized at $manifest_version."
