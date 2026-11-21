#!/usr/bin/env bash
# make-os-list.sh - write os-list.json, the file Raspberry Pi Imager reads
# from a custom repository.
#
# Usage: make-os-list.sh <image.img.xz> <tag> <download-url-base> <icon-url> > os-list.json
# <download-url-base> is the folder that holds the .img.xz, without a trailing slash.
set -euo pipefail

IMG=${1:?Usage: $0 image.img.xz tag url-base icon-url}
TAG=${2:?missing tag}
BASE=${3:?missing url base}
ICON=${4:?missing icon url}
FILE=$(basename "$IMG")

# Imager wants the size and checksum of the compressed file and of the
# image after it unpacks. xz -dc unpacks to the pipe without a temporary file.
dl_size=$(stat -c %s "$IMG")
dl_sha=$(sha256sum "$IMG" | cut -d' ' -f1)
extract_size=$(xz -dc "$IMG" | wc -c)
extract_sha=$(xz -dc "$IMG" | sha256sum | cut -d' ' -f1)
released=$(date -u +%Y-%m-%d)

cat <<JSON
{
  "os_list": [
    {
      "name": "Solar Server ${TAG}",
      "description": "Raspberry Pi OS Lite with a Caddy web server, a starter site, a status page and power-cut protection. Edit solar.conf on the card before the first boot.",
      "icon": "${ICON}",
      "url": "${BASE}/${FILE}",
      "release_date": "${released}",
      "extract_size": ${extract_size},
      "extract_sha256": "${extract_sha}",
      "image_download_size": ${dl_size},
      "image_download_sha256": "${dl_sha}",
      "devices": ["pi3-64bit", "pi4-64bit", "pi5-64bit"]
    }
  ]
}
JSON
