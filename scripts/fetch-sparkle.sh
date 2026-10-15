#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."
version=2.10.0
checksum=c2bf58aa8387266ac179357b1415d6f2635f044da8be41042af32425dae6da0c
destination=target/sparkle
archive="$destination/Sparkle-$version.tar.xz"
mkdir -p "$destination"
if [[ ! -f "$archive" ]]; then
  curl --fail --location --retry 3 "https://github.com/sparkle-project/Sparkle/releases/download/$version/Sparkle-$version.tar.xz" -o "$archive.part"
  mv "$archive.part" "$archive"
fi
echo "$checksum  $archive" | shasum -a 256 -c -
tar -xf "$archive" -C "$destination"
