#!/usr/bin/env bash
set -euo pipefail

manifest_version="$(
  sed -n '/^\[package\]$/,/^\[/s/^version = "\([^"]*\)"/\1/p' Cargo.toml
)"
lock_version="$(
  awk '
    /^\[\[package\]\]$/ { in_package = 0 }
    /^name = "bunch-of-keys"$/ { in_package = 1; next }
    in_package && /^version = / {
      gsub(/^version = "|"$/, "")
      print
      exit
    }
  ' Cargo.lock
)"
tauri_version="$(
  sed -n 's/^[[:space:]]*"version": "\([^"]*\)",/\1/p' tauri.conf.json
)"
changelog_version="$(
  sed -n 's/^## \([^[:space:]]*\) - .*/\1/p' CHANGELOG.md | head -n 1
)"

if [[ -z "$manifest_version" || -z "$lock_version" || -z "$tauri_version" || -z "$changelog_version" ]]; then
  echo "Could not read all project versions." >&2
  exit 1
fi

if [[ "$manifest_version" != "$lock_version" ||
      "$manifest_version" != "$tauri_version" ||
      "$manifest_version" != "$changelog_version" ]]; then
  echo "Project versions are out of sync:" >&2
  echo "  Cargo.toml:      $manifest_version" >&2
  echo "  Cargo.lock:      $lock_version" >&2
  echo "  tauri.conf.json: $tauri_version" >&2
  echo "  CHANGELOG.md:    $changelog_version" >&2
  exit 1
fi

echo "Project version is synchronized at $manifest_version."
