# solar-power-stack

Software that turns an old phone, a Raspberry Pi or any Debian machine into a web server you own. It is the companion to the SOLAR POWER curriculum (`joshajh/solar-power`).

The goal: you run your own web server on a device you already have, then you add solar power to it.

## Target devices

- An old Android phone, through Termux. The server listens on port 8080.
- A Raspberry Pi 3, 4 or 5, through a flashable image. A Pi Zero 2 W is not tested yet.
- Any machine that runs Debian 12 or newer, on arm64 or x86.

## Tiers

- Tier 0: an old phone running the one-line Termux install.
- Tier 1: a phone or Pi that you power from a battery and a solar panel.
- Tier 2: a Raspberry Pi running the flashable image.

## What the stack contains

| Directory | Contents |
| --- | --- |
| `install/` | The installer script. One script serves the Pi image, Termux and Debian. |
| `site-template/` | The starter site that the installer copies to your device. |
| `status/` | The status page. |
| `image/` | The Raspberry Pi OS image build. |
| `docs/` | Guides: flash the image, run it on a phone with Termux, protect against power loss, and what the image contains. |

## Flash the image

Open Raspberry Pi Imager, set a custom repository and paste this address:

```
https://github.com/joshajh/solar-power-stack/releases/latest/download/os-list.json
```

The full steps are in [docs/flashing.md](docs/flashing.md).

## Licence

The code in this repository uses the MIT licence. See `LICENSE`.

## Status

Early release. What has been tested so far:

- The installer, the status page and the first-boot setup run in Debian containers on amd64 and arm64 in CI.
- The Raspberry Pi image builds in GitHub Actions. No one has flashed it on a Pi yet.
- The Termux install has not been tested on a phone yet.

Each guide in `docs/` lists what has and has not been tested.
