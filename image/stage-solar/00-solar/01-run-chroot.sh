#!/bin/bash -e
# Runs inside the image's filesystem. Run the same installer that any Debian
# machine uses, then add the first-boot service.

# --image-build sets everything up without starting the server.
/opt/solar/install/install.sh --image-build --harden

# First boot: apply solar.conf from the boot partition.
install -m 755 /opt/solar/first-boot/solar-firstboot.sh /usr/local/bin/solar-firstboot
install -m 644 /opt/solar/first-boot/solar-firstboot.service /etc/systemd/system/solar-firstboot.service
systemctl enable solar-firstboot.service

# The image ships with SSH off. solar.conf turns it on at first boot.
systemctl disable ssh

# Put an example solar.conf on the boot partition for the user to edit.
install -m 644 /opt/solar/first-boot/solar.conf.example /boot/firmware/solar.conf
