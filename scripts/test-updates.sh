#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."
scratch=$(mktemp -d)
trap 'rm -rf "$scratch"' EXIT
umask 077
xcrun swift -sdk "${SDKROOT:-$(xcrun --sdk macosx --show-sdk-path)}" \
  -module-cache-path target/swift-module-cache scripts/test-update-signatures.swift "$scratch"
signer=target/sparkle/bin/sign_update
signature=$("$signer" --ed-key-file "$scratch/test-key" -p "$scratch/valid.zip")
"$signer" --ed-key-file "$scratch/test-key" --verify "$scratch/valid.zip" "$signature"
for invalid in tampered interrupted; do
  if "$signer" --ed-key-file "$scratch/test-key" --verify "$scratch/$invalid.zip" "$signature"; then
    echo "Sparkle accepted an invalid archive: $invalid" >&2
    exit 1
  fi
done
echo 'Sparkle signature tests passed: authentic, tampered and interrupted archives.'
for feed in new old future-os; do
  "$signer" --ed-key-file "$scratch/test-key" "$scratch/$feed.xml"
done
target/macos/verify-update "$scratch/Probe.app/Contents/Info.plist" "$scratch/new.xml" "$scratch/valid.zip"
mkdir "$scratch/tampered"
cp "$scratch/tampered.zip" "$scratch/tampered/valid.zip"
if target/macos/verify-update "$scratch/Probe.app/Contents/Info.plist" "$scratch/new.xml" "$scratch/tampered/valid.zip"; then
  echo 'Public-key verification accepted a modified archive' >&2
  exit 1
fi
xcrun swiftc -swift-version 5 -warnings-as-errors \
  -sdk "${SDKROOT:-$(xcrun --sdk macosx --show-sdk-path)}" \
  -module-cache-path target/swift-module-cache -parse-as-library \
  -F target/sparkle -framework Sparkle -Xlinker -rpath -Xlinker "$PWD/target/sparkle" \
  macos/Tests/UpdateTransport.swift -o "$scratch/transport"
python3 - "$scratch" <<'PY'
import functools, http.server, pathlib, subprocess, sys, threading
root = pathlib.Path(sys.argv[1])
class QuietHandler(http.server.SimpleHTTPRequestHandler):
    def log_message(self, *args): pass
handler = functools.partial(QuietHandler, directory=str(root))
with http.server.ThreadingHTTPServer(('127.0.0.1', 0), handler) as server:
    thread = threading.Thread(target=server.serve_forever, daemon=True)
    thread.start()
    try:
        subprocess.run([str(root / 'transport'), str(root / 'Probe.app'), f'http://127.0.0.1:{server.server_port}'], check=True, timeout=120)
    finally:
        server.shutdown()
PY
