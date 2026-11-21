#!/bin/bash -e
# pi-gen runs this before the stage. Start from a copy of the previous stage.
if [ ! -d "${ROOTFS_DIR}" ]; then
  copy_previous
fi
