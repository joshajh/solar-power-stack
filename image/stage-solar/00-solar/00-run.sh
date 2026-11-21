#!/bin/bash -e
# Runs on the build machine. Copy the solar-power-stack files into the image.
# image/build.sh puts them in ./files before the build starts.
install -d "${ROOTFS_DIR}/opt/solar"
cp -r files/. "${ROOTFS_DIR}/opt/solar/"
