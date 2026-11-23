#!/usr/bin/env bash
# build.sh - build the Raspberry Pi OS Lite arm64 image with pi-gen.
#
# Usage: image/build.sh <output-dir>
# Needs Docker and an x86 or arm64 Linux machine. On x86 it also needs QEMU
# for arm64 (binfmt). The build takes about an hour and writes
# solar-*.img.xz and its .sha256 file into <output-dir>.
set -euo pipefail

OUT=${1:?Usage: $0 <output-dir>}
HERE=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
REPO=$(cd "$HERE/.." && pwd)
# Pin pi-gen to a release tag so builds repeat.
PIGEN_TAG=${PIGEN_TAG:-2026-10-06-raspios-bookworm-arm64}

WORK=$(mktemp -d)
trap 'rm -rf "$WORK"' EXIT
git clone --quiet --depth 1 --branch "$PIGEN_TAG" https://github.com/RPi-Distro/pi-gen.git "$WORK/pi-gen"
cd "$WORK/pi-gen"

# Stage 2 would export its own image. Only our stage exports one.
rm -f stage2/EXPORT_IMAGE stage2/EXPORT_NOOBS
cp -r "$HERE/stage-solar" ./stage-solar

# Give the stage the files it copies into the image.
mkdir -p stage-solar/00-solar/files
cp -r "$REPO/install" "$REPO/setup" "$REPO/site-template" "$REPO/status" stage-solar/00-solar/files/
cp -r "$HERE/first-boot" stage-solar/00-solar/files/first-boot

# A random password nobody keeps: password login is not part of the design.
{ cat "$HERE/config"; echo "FIRST_USER_PASS=$(head -c 24 /dev/urandom | base64 | tr -d '/+=')"; } > config

./build-docker.sh

mkdir -p "$OUT"
for img in deploy/*.img.xz; do
  cp "$img" "$OUT/"
  (cd "$OUT" && sha256sum "$(basename "$img")" > "$(basename "$img").sha256")
done
ls -l "$OUT"
