# Raspberry Pi image

The image is Raspberry Pi OS Lite (64-bit, Debian 12 "bookworm") with the solar-power-stack installer already run. A beginner flashes it with Raspberry Pi Imager, edits one file on the card and powers on the Pi. No keyboard, monitor or command line is needed.

## What the image contains

- The installer (`install/install.sh --image-build --harden`) ran at build time. Caddy, the starter site (`/srv/site`), the status page and the power-cut protection are in the image, so the first boot needs no internet for the server itself.
- `solar-firstboot.service` reads `solar.conf` from the boot partition at the first boot, applies it and then disables itself.
- Pi OS expands the root filesystem to fill the card at the first boot.
- SSH is off.

## solar.conf

Edit `solar.conf` on the card's boot partition before the first boot. The file is `solar.conf.example` with every line commented out.

| Key | Meaning |
| --- | --- |
| `hostname` | Device name. `solar` gives `http://solar.local`. |
| `site_name` | Name on the starter page. |
| `wifi_ssid`, `wifi_password`, `wifi_country` | Wi-Fi network, password (omit for an open network) and two-letter country code. |
| `ssh=true`, `ssh_key` | Turn SSH on. SSH accepts keys only, so `ssh=true` without `ssh_key` leaves SSH off and logs the reason. |

After the first boot, the device replaces the `wifi_password` and `ssh_key` lines with comments, so the card does not keep them. To connect to a different network, add the lines again and flash the card again.

The image has a user named `solar` with a random password that nobody knows. This is why SSH needs a key.

The status page keys (`status_public`, `victron`, `victron_device`) do not work in the boot-partition `solar.conf`. The image ships with the defaults (status page private, Victron reader off). To change them, put the keys in a file and run `sudo /opt/solar/install/install.sh --conf <file>` on the Pi. With the read-only root on, turn it off first (see `docs/hardening.md`).

## NVMe boot on a Pi 5

1. Connect the NVMe drive to the Pi 5 (with an M.2 HAT or a PCIe adapter).
2. In Raspberry Pi Imager, choose the image and choose the NVMe drive as the target. Connect the drive to your computer with a USB adapter to write it.
3. Edit `solar.conf` on the drive's boot partition.
4. Put the drive in the Pi and power on. A Pi 5 with current firmware boots from NVMe when no SD card is present. If it does not, run `sudo raspi-config` on a Pi with Raspberry Pi OS, open Advanced Options, Boot Order, and choose NVMe first.

This route is untested.

## Status

The image builds in GitHub Actions. No one has flashed it on a Pi yet, so no Pi model counts as tested. The build and test notes for contributors are in [`image/README.md`](../image/README.md).
