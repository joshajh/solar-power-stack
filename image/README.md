# image

The Raspberry Pi OS image build. `build.sh` builds it with pi-gen, `stage-solar/` holds our pi-gen stage, `first-boot/` holds the service that reads `solar.conf`, and `make-os-list.sh` writes the `os-list.json` file for Raspberry Pi Imager. For flashing, see [`docs/flashing.md`](../docs/flashing.md). For what the image contains, see [`docs/image.md`](../docs/image.md).

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

The script needs Docker, and on an x86 machine it needs QEMU for arm64. It writes `<name>.img.xz` and `<name>.img.xz.sha256` to the output directory. The `image` workflow runs the same script on manual dispatch, and the `release` workflow runs it on every version tag (`v*`). Both upload the two files as the artefact `solar-image`.

## Tests

Run in CI and locally (debian:12 container, stubbed system commands):

- `tests/test-firstboot.sh`: the first-boot script applies hostname, site name, Wi-Fi keyfile (mode 600), SSH key; leaves SSH off by default; refuses `ssh=true` without a key; handles Windows line endings and a missing file.
- `tests/test-installer.sh`: `--image-build` enables Caddy and the status timer, starts nothing.

## Build and test status

| Item | Result |
| --- | --- |
| Image builds in GitHub Actions (`.img.xz` and checksum produced) | Yes. Run 45043183810 on `ubuntu-24.04` produced a 473 MiB `.img.xz` in about 40 minutes. |
| Pi 5 flashed, Wi-Fi set only in `solar.conf`, no keyboard or monitor: starter page at `http://<hostname>.local` within 3 minutes | Not run |
| Second model (for example Pi 4) | Not run |
| NVMe boot on a Pi 5 (flash to NVMe with Imager) | Not run |
| SSH off by default, on with `ssh=true` and a key | Script tested with stubs. Not run on a Pi. |
| Boot time | Not measured |

Tested models: none yet.

## Maintainer notes

Pushing a version tag runs `.github/workflows/release.yml`. It builds the image, creates the GitHub Release with the image, checksum, `os-list.json` and icon, and uploads the same files to Backblaze B2 when these repository secrets exist: `B2_KEY_ID`, `B2_APPLICATION_KEY`, `B2_BUCKET` and `B2_ENDPOINT` (the S3 endpoint of the bucket, for example `https://s3.us-west-004.backblazeb2.com`). Without them, the workflow prints a warning and skips the upload. The tag must match `vMAJOR.MINOR.PATCH` with an optional `-suffix`.

Status of the release checks that need people and hardware:

| Check | Result |
| --- | --- |
| `v0.1.0-test` produces a release with `.img.xz`, `.sha256` and `os-list.json` | Not run |
| Imager started with the custom repository lists the image with name, description and icon | Not run |
| B2 upload runs with secrets, and the downloaded file matches its checksum | Not run |
