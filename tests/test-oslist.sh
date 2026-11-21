#!/usr/bin/env bash
# Check that make-os-list.sh writes valid JSON with correct sizes and checksums.
set -euo pipefail
cd "$(dirname "$0")/.."
tmp=$(mktemp -d); trap 'rm -rf "$tmp"' EXIT
head -c 1000000 /dev/urandom > "$tmp/solar.img"; xz -k "$tmp/solar.img"
image/make-os-list.sh "$tmp/solar.img.xz" v0.0.0-test https://example.invalid/dl https://example.invalid/icon.png > "$tmp/os-list.json"
python3 - "$tmp" <<'PY'
import json, sys, hashlib, os
d = sys.argv[1]
e = json.load(open(f"{d}/os-list.json"))["os_list"][0]
img = open(f"{d}/solar.img", "rb").read()
xz = open(f"{d}/solar.img.xz", "rb").read()
assert e["extract_size"] == len(img)
assert e["extract_sha256"] == hashlib.sha256(img).hexdigest()
assert e["image_download_size"] == len(xz)
assert e["image_download_sha256"] == hashlib.sha256(xz).hexdigest()
assert e["url"] == "https://example.invalid/dl/solar.img.xz"
for k in ("name", "description", "icon", "release_date", "devices"):
    assert e[k], k
print("PASS: os-list.json is valid and its checksums match")
PY
