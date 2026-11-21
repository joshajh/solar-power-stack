# Raspberry Pi image

The image is Raspberry Pi OS Lite (64-bit, Debian 12 "bookworm") with the solar-power-stack installer already run. A beginner flashes it with Raspberry Pi Imager, edits one file on the card and powers on the Pi. No keyboard, monitor or command line is needed.

## Build tool: pi-gen

The build uses [pi-gen](https://github.com/RPi-Distro/pi-gen), pinned to the release tag `2026-10-06-raspios-bookworm-arm64`. Reasons:

- It is the tool that builds the official Raspberry Pi OS, so the image matches what Raspberry Pi Imager users expect.
- A custom stage (`image/stage-solar`) adds our files without patching pi-gen.
- It has a Docker build (`build-docker.sh`) that runs on a GitHub Actions runner.
- `rpi-image-gen` builds faster, but it is newer and has fewer examples. We choose pi-gen for stability. Revisit this if the build exceeds the Actions time limit (the workflow allows 180 minutes; pi-gen Lite normally takes about an hour on QEMU, which is an estimate from other projects, not a measurement from this repository).

## How to build

```
image/build.sh <output-dir>
```

The script needs Docker, and on an x86 machine it needs QEMU for arm64. It writes `<name>.img.xz` and `<name>.img.xz.sha256` to the output directory. The `image` workflow runs the same script on every tag (`v*`) and on manual dispatch, and uploads both files as the artefact `solar-image`.

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

The Wi-Fi password stays in `solar.conf` on the card after the first boot. Delete the line when you no longer need it.

The image has a user named `solar` with a random password that nobody knows. This is why SSH needs a key.

## Tests

Run in CI and locally (debian:12 container, stubbed system commands):

- `tests/test-firstboot.sh`: the first-boot script applies hostname, site name, Wi-Fi keyfile (mode 600), SSH key; leaves SSH off by default; refuses `ssh=true` without a key; handles Windows line endings and a missing file.
- `tests/test-installer.sh`: `--image-build` enables Caddy and the status timer, starts nothing.

## Hardware and build status

None of the following has run yet. **Josh fills in the results.**

| Item | Result |
| --- | --- |
| Image builds in GitHub Actions (`.img.xz` and checksum produced) | Not run. The build box had no arm64 emulation, so the workflow and scripts are validated only by shellcheck, actionlint and a check of pi-gen's variable names. |
| Pi 5 flashed, Wi-Fi set only in `solar.conf`, no keyboard or monitor: starter page at `http://<hostname>.local` within 3 minutes | Not run |
| Second model (for example Pi 4 or Zero 2 W) | Not run |
| NVMe boot on a Pi 5 (flash to NVMe with Imager) | Not run |
| SSH off by default, on with `ssh=true` and a key | Script tested with stubs. Not run on a Pi. |
| Boot time | Not measured |

Tested models: none yet.

## NVMe boot on a Pi 5

1. Connect the NVMe drive to the Pi 5 (with an M.2 HAT or a PCIe adapter).
2. In Raspberry Pi Imager, choose the image and choose the NVMe drive as the target. Connect the drive to your computer with a USB adapter to write it.
3. Edit `solar.conf` on the drive's boot partition.
4. Put the drive in the Pi and power on. A Pi 5 with current firmware boots from NVMe when no SD card is present. If it does not, run `sudo raspi-config` on a Pi with Raspberry Pi OS, open Advanced Options, Boot Order, and choose NVMe first.

This route is untested.
