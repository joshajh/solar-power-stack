# Epic report: Solar server stack (#10)

Branch: `epic/stack-all` (top of the stack plus the spike branch). Nothing is merged. #4 (web editor) is post-launch and skipped.

## PRs, bottom to top

| Order | Issue | PR | Branch | Base |
| --- | --- | --- | --- | --- |
| 1 | #1 scaffold | #11 | `epic/stack/1-scaffold` | `main` |
| 2 | #2 installer | #12 | `epic/stack/2-installer` | #11 |
| 3 | #3 spike harness | #13 | `epic/stack/3-spike-harness` | #12 |
| 4 | #5 status page | #14 | `epic/stack/5-status` | #12 |
| 5 | #6 hardening | #15 | `epic/stack/6-hardening` | #14 |
| 6 | #8 Pi image | #16 | `epic/stack/8-image` | #15 |
| 7 | #9 release pipeline | #17 | `epic/stack/9-release` | #16 |
| 8 | #7 Termux path | #18 | `epic/stack/7-termux` | #17 |
| Epic | #10 | (epic PR) | `epic/stack-all` | `main` |

#3 branches off #12, not off the chain, so the epic PR is the one place where all eight are together. Merge bottom-up (#11, #12, #14 … #18, with #13 any time after #12) or merge the epic PR alone.

## Built against each acceptance criterion

Legend: **verified** = I ran it this session; **simulated** = ran against stubs or a container stand-in; **unverified** = not run.

### #1 Scaffold (PR #11)
- README (purpose, devices, tiers, licence, status), five directories with stub READMEs, shellcheck workflow: **verified** (actionlint clean; CI green).
- "CI goes red on a broken script" scratch test: **unverified** (not run).

### #2 Installer (PR #12)
- `curl localhost` returns the starter page on debian:12: **verified** amd64 locally and in CI; **verified** arm64 in CI (QEMU).
- Second run changes nothing, edited `index.html` untouched: **verified** (hash snapshot).
- `--help` lists every flag and `solar.conf` key; unsupported OS exits non-zero with a plain message: **verified**.
- shellcheck clean, beginner comments: **verified** / judged by reading.
- Starter page copy: checked by hand.
- systemd path (restart drop-in, `hostnamectl`) and a hand run on a VM: **unverified** (containers have no systemd).

### #3 Spike harness (PR #13)
- `probe.sh` writes a CSV on Linux: **verified** against a local server and a closed port. macOS: **unverified**.
- `phone-notes.md`: written from Termux documentation, **unverified** on a phone.
- 72 hours of data, filled-in report, measured watts, go / no-go: **not done**. Needs Josh. `docs/spike-termux.md` holds empty fields marked "Josh fills in after the run". No result is invented.

### #5 Status page (PR #14)
- `/status` and `/status.json` load on Debian: **verified**. On Termux: **simulated** (fake `$PREFIX`), phone **unverified**.
- Battery fields present with Termux:API and absent without: **simulated** with a stub.
- 403 for a non-private address with `status_public=false`, 200 elsewhere and with `status_public=true`: **verified** (loopback given source address 203.0.113.9; CI fails if it cannot run this test).
- VE.Direct reader read-only and off by default: off by default **verified**; read-only by code reading; **unverified** on hardware or a pty.
- Behind a tunnel, Caddy sees a local address, so the page stays reachable: documented in `status/README.md`.

### #6 Hardening (PR #15)
- Config written, idempotent, security-only update list effective (counted with `apt-config dump`), tmpfs log folders recreated, `fsck.repair=yes` added once, `--readonly-root` refused off Pi OS: **verified** in debian:12.
- Ten hard power cuts on a Pi: **unverified**, needs Josh's Pi. Table in `docs/hardening.md` says "Not run".
- Killed Caddy returns within 10 s: **unverified** (setting is `Restart=always`, `RestartSec=3`; needs systemd).
- Actual unattended update run and `raspi-config nonint enable_overlayfs` behaviour: **unverified**.
- Cut-order note: the read-only root is small and is included.

### #8 Pi image (PR #16)
- pi-gen chosen (reasons in `docs/image.md`), pinned to tag `2026-10-06-raspios-bookworm-arm64`. Stage layout and variable names checked against that tag.
- **The image build did not run.** This box has no arm64 emulation. CI producing `.img.xz` and `.sha256`: **unverified**.
- First-boot script (hostname, site name, Wi-Fi keyfile mode 600, SSH key, SSH off by default, secrets blanked afterwards): **simulated** with stubs. `--image-build` enables services and starts none: **verified** in a container.
- Flash test (3 minutes, no keyboard), Pi 5 plus a second model, NVMe boot: **unverified**, needs Josh's Pi. `docs/image.md` lists no tested models.
- Deviation to confirm: `ssh=true` also needs `ssh_key`; without a key SSH stays off, because the image has no known password.

### #9 Release pipeline (PR #17)
- `release.yml` (tag-triggered, calls `image.yml`), GitHub Release, B2 mirror with skip-when-no-secrets, `os-list.json`, `docs/flashing.md`, README URL: written, actionlint clean.
- `os-list.json` generator: **verified** (valid JSON, sizes and checksums match a fake image). B2 skip branch exercised locally.
- `v0.1.0-test` release, Imager listing with icon, B2 upload and checksum: **unverified**. Needs a tag, Imager, and B2 secrets.
- The stable URL (`releases/latest/download/os-list.json`) works only once a full release exists and the repo is public.

### #7 Termux path (PR #18)
- Written from documented Termux behaviour. **Nothing ran on a phone.**
- **Simulated** in debian:12 with a fake `$PREFIX`, stub Termux commands and real Caddy: one command serves port 8080, boot script written, wake-lock and battery intent called, add-ons reported as not detected, idempotent second run with one Caddy and one `solar-serve`, piped (`curl | bash`) install downloads the starter files.
- Reboot survival, 24 h screen-off, Termux:Boot behaviour, `am` and `pm` calls, Caddy admin port in Termux, Android 12 child-process restriction: **unverified**. Listed in `docs/termux.md`.
- Spike findings are **not applied**, because the spike has no results.
- Tested phone model and Android version: empty, for Josh.

## Review rounds

One Sonnet reviewer per PR (none for #11 and #13, which hold only stubs and a skeleton). Findings fixed in each PR; details are in the PR comments.

| PR | Findings | Fixed | Rejected | Open |
| --- | --- | --- | --- | --- |
| #12 | 8 | 7 (name escaping, test assertions, avahi, Caddy path quoting and health check, `cp -n`, placeholder only on new page, hostname check) | chmod scope on `--site-dir` | none |
| #14 | 8 | 7 (Victron validation, truncated reads, null display, null disk, no-systemd note, CI fails without NET_ADMIN, stale page note) | install-time tunnel warning | Termux wiring moved to #7 |
| #15 | 8 | 7 (real security-only list, log folders for tmpfs, nofail, early option checks, overlay guard, apt update, doc claims) | fstab backup; drop-in test via systemd-less container | hardware tests |
| #16 | 8 | 8 (host QEMU, overlay guard in build, `SUDO_USER` for raspi-config, SSH after host keys, secret scrub, warnings, stdin) | none | needs a real build |
| #17 | 8 | 7 (B2 region and checksum env, tag injection and validation, secret scope, notes flags, doc wording) | devices assertion in test | needs a real tag |
| #18 | 8 | 7 (status shebang, Wi-Fi address, 32-bit ARM, phantom process killer, pidfile check, PATH, `pkg update`, add-on wording, temp cleanup) | lock directory | all phone behaviour |

Bugs I found myself while testing: the no-systemd path of #2 started a second Caddy on every run (fixed in #15 and covered by a test), and the Caddy process-count test failed under QEMU (fixed on #15, #16, #17, #18 as follow-up commits).

Final epic review: two Sonnet reviewers.
- Correctness and integration (all four test suites passed for them): 5 findings. Fixed: docs said the image workflow triggers on tags (it is the release workflow), status keys are not read from the boot-partition `solar.conf` (documented), a passive log line. Rejected: CR stripping in the installer's conf reader (the image never uses it; the failure is safe).
- Security: 10 findings. Fixed (CONFIRMED): `curl | bash` trusted a planted folder next to the current directory and ran it as root (now always downloads when piped; tested), `--site-dir` could inject Caddyfile directives or shell text (now refused; tested; `/` and `$HOME` refused), Wi-Fi keyfile was briefly world-readable (umask 077), `/etc/solar` is now mode 700, workflows now default to a read-only token. Not fixed, documented: the unpinned `main` download (recommend a tag and checksum at release; Needs Josh), tag-push and B2 key scope (use tag protection and a bucket-scoped key), tunnel makes `/status` public (documented), temp-file window in `status.sh`, pi-gen and actions pinned by tag not SHA. The `status_public` rule held against every bypass tried (case, `//`, `..`, `%73`, query, spoofed headers).

## Tests and checks run this session

- shellcheck (koalaman/shellcheck image) on every script under `install/`, `image/`, `status/`, `spike/`, `tests/`: clean except one info-level note in `tests/` that CI does not check.
- actionlint on all workflows: clean.
- `tests/test-installer.sh` in debian:12 amd64 (with `--cap-add NET_ADMIN`): all assertions pass (installer, status, hardening, image build).
- `tests/test-firstboot.sh`: pass. `tests/test-termux.sh`: pass. `tests/test-oslist.sh`: pass.
- GitHub Actions: debian:12 amd64 and arm64 (QEMU) ran on every PR. The arm64 job passed on #12, #13 and #14. Failures on #15 to #17 were my own test's process count under QEMU; fixes were pushed, and the CI state is shown on each PR.

## Unverified, summarised

The image build, every Pi test, every phone test, the release run, Imager, B2, macOS for the probe, the Victron reader, systemd behaviour.

## Rollout

1. Merge the stack bottom-up, or merge the epic PR.
2. Add B2 secrets `B2_KEY_ID`, `B2_APPLICATION_KEY`, `B2_BUCKET`, `B2_ENDPOINT` (S3 endpoint, for example `https://s3.us-west-004.backblazeb2.com`).
3. Run the `image` workflow by hand and download the artefact to check the build.
4. Tag `v0.1.0-test`, check the release and the Imager listing, then tag `v0.1.0`.
5. Make the repository public. The Termux one-liner and the stable `os-list.json` URL need that.

## Needs Josh

| Item | Recommendation |
| --- | --- |
| Run the phone spike (#3): follow `spike/phone-notes.md`, 72 hours, then fill `docs/spike-termux.md` | Start now. The Tier 0 and Tier 1 guides need the verdict and the watts figure. |
| Re-check #7 against the spike verdict and test it on the phone (reboot, 24 h screen off); add the phone model to `docs/termux.md` | Do it straight after the spike. Pay most attention to the Android 12 child-process setting. |
| Run the Pi tests: ten power cuts and kill-restart (#6), flash test on a Pi 5 and one other model, NVMe (#8) | Run the `image` workflow first. If the build exceeds the time limit or fails, the fallback is `rpi-image-gen`. |
| Add B2 secrets (#9) | Create an application key limited to one bucket. |
| Make the repository public | Do it before the first full tag, because the one-liner and the Imager URL need it. |
| Decide on `ssh=true` needing `ssh_key` (#8) | Keep it. A default password on an internet-facing SSH is worse. |
| Short install address for Termux (`curl ...install.sh \| bash` is long to read aloud) | Add a redirect such as `solarpower.possibleworlds.space/install` and pin the version to a tag. |
| Protect `v*` tags and scope the B2 key to one bucket (write-only) | Do both before the first release. |
| Pi Zero 2 W in the Imager device list | Remove the claim from `docs/flashing.md` if you do not test it. |
