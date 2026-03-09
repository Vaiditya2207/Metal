#!/usr/bin/env bash
set -e

URL="${1:-https://www.google.com}"

echo "[Fidelity Test] Target URL: $URL"

# 1. Fetch reference using Chrome/Puppeteer
pushd tests/fidelity > /dev/null
node chrome_dump.js "$URL"
popd > /dev/null

# 2. Build our DOM dumper
echo "[Fidelity Test] Building tools/dump_dom..."
zig build dump_dom

# 3. Process with Metal
echo "[Fidelity Test] Generating layout for Metal..."
./zig-out/bin/dump_dom tests/fidelity/google_snapshot.html tests/fidelity/metal_dump.json

# 4. Compare
pushd tests/fidelity > /dev/null
node compare.js
popd > /dev/null
