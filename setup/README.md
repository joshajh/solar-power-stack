# setup

Developer notes. The user guide is [docs/setup.md](../docs/setup.md).

- `solar-setup`: the guided setup, one bash script. One function draws each screen (`screen_welcome`, `screen_name`, `screen_status`, `screen_page`, `screen_android`, `screen_done`, `screen_qr`). `apply` writes `solar.conf` and calls `install.sh --apply`, the one place that writes the Caddyfile.
- `install-gum.sh DEST_DIR`: downloads gum v2.0.2 for amd64 or arm64, checks the SHA-256 of the tar.gz against the values in the script and installs `DEST_DIR/gum`. The installer calls it with `/usr/local/lib/solar/bin`, and the Pi image build gets the same copy through `install.sh`. To change the version, change `VERSION` and both checksums together, copy the checksums from the release's `checksums.txt`, and run `tests/test-setup.sh`.

Settings for tests and screenshots: `SOLAR_SETUP_DEVICE=termux|pi|debian` pretends to be that device, `SOLAR_SETUP_IP` sets the address, `SOLAR_INSTALLER` names the installer and `SOLAR_GUM` names the gum program. The installer sets `SOLAR_GUM_URL` in tests to point the download at a local file (the checksum check still applies).

Tests: `tests/test-setup.sh` in a `debian:12` container (see its first lines). Run shellcheck on `setup/solar-setup` and `setup/install-gum.sh`.
