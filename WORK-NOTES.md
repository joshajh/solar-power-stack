# Work notes

- #5 follow-up for #7: `install_status` writes to /usr/local/bin and /etc/solar and `status.sh` defaults to /etc/solar/solar.conf. Termux uses `$PREFIX`; the Termux path must pass paths under `$PREFIX` (SOLAR_CONF env already overrides the conf path) and run status.sh in a loop since Termux has no systemd.
- Victron VE.Direct parsing is untested against a real device or a pty.
