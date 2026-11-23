#!/bin/bash -e
# Runs inside the image's filesystem. Run the same installer that any Debian
# machine uses, then add the first-boot service.

# --image-build sets everything up without starting the server.
# </dev/null: this script arrives on stdin, so keep the installer from reading it.
/opt/solar/install/install.sh --image-build --harden </dev/null

# install.sh installs solar-setup, qrencode (apt) and gum. The gum download is
# pinned to one release and checked with its SHA-256 (setup/install-gum.sh).
# The installer treats a missing gum as a warning. An image must not ship
# without them, so stop the build when either one is missing.
[ -x /usr/local/lib/solar/bin/gum ] || { echo "gum is missing from the image" >&2; exit 1; }
command -v qrencode >/dev/null || { echo "qrencode is missing from the image" >&2; exit 1; }

# First boot: apply solar.conf from the boot partition.
install -m 755 /opt/solar/first-boot/solar-firstboot.sh /usr/local/bin/solar-firstboot
install -m 644 /opt/solar/first-boot/solar-firstboot.service /etc/systemd/system/solar-firstboot.service
systemctl enable solar-firstboot.service

# The image ships with SSH off. solar.conf turns it on at first boot.
systemctl disable ssh

# Put an example solar.conf on the boot partition for the user to edit.
install -m 644 /opt/solar/first-boot/solar.conf.example /boot/firmware/solar.conf
