#!/usr/bin/env bash
# install-gum.sh DEST_DIR - install gum, the tool solar-setup draws its screens with.
#
# Debian 12 has no gum package, so this script downloads one pinned release from
# GitHub, checks its SHA-256 against the value written below, and only then
# unpacks it. A file that does not match is deleted and never run.
#
# gum is MIT licensed: https://github.com/charmbracelet/gum
# The two checksums below are the entries for the tar.gz files in the release's
# own checksums.txt: https://github.com/charmbracelet/gum/releases/tag/v2.0.2
#
# Exit status 0: DEST_DIR/gum is installed. Anything else: it is not, and the
# reason is on stderr. solar-setup then asks plain questions.
set -euo pipefail

VERSION=2.0.2
SHA256_X86_64=d842e06d93dbed90af48cb8dd10698db6f22e331fc40346bb37bbc753109edc2
SHA256_ARM64=8ebf8b54ec1e8c81f2bb58b59ff9b70998186a4d11375f0cf357b80e0ccfa1d5

DEST=${1:?Usage: install-gum.sh DEST_DIR}
# Tests set SOLAR_GUM_URL to a local file. The checksum check still applies.
BASE=https://github.com/charmbracelet/gum/releases/download/v$VERSION

case "$(uname -m)" in
  x86_64|amd64)  ARCH=x86_64; WANT=$SHA256_X86_64 ;;
  aarch64|arm64) ARCH=arm64;  WANT=$SHA256_ARM64 ;;
  *) echo "gum: no pinned download for $(uname -m). solar-setup will ask plain questions." >&2; exit 1 ;;
esac
FILE=gum_${VERSION}_Linux_$ARCH.tar.gz
URL=${SOLAR_GUM_URL:-$BASE/$FILE}

# Already installed at this version: nothing to do.
if [ -x "$DEST/gum" ] && "$DEST/gum" --version 2>/dev/null | grep -q "$VERSION"; then
  exit 0
fi

command -v curl >/dev/null 2>&1 || { echo "gum: curl is missing, so gum cannot be downloaded." >&2; exit 1; }
command -v sha256sum >/dev/null 2>&1 || { echo "gum: sha256sum is missing, so the download cannot be checked." >&2; exit 1; }

work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT
echo "Downloading gum $VERSION ($ARCH)..."
curl -fsSL --max-time 120 -o "$work/$FILE" "$URL" \
  || { echo "gum: the download from $URL failed." >&2; exit 1; }

got=$(sha256sum "$work/$FILE" | cut -d' ' -f1)
if [ "$got" != "$WANT" ]; then
  echo "gum: the checksum of the download does not match, so it was not used." >&2
  echo "gum:   expected $WANT" >&2
  echo "gum:   got      $got" >&2
  exit 1
fi

# The release holds one folder with the gum program, its licence and its manual.
tar -xzf "$work/$FILE" -C "$work" --strip-components=1 "gum_${VERSION}_Linux_$ARCH/gum" \
  || { echo "gum: the download does not contain the gum program." >&2; exit 1; }
mkdir -p "$DEST"
install -m 755 "$work/gum" "$DEST/gum"
echo "Installed gum $VERSION in $DEST/gum"
