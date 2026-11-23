# solar-setup (prototype)

A short, guided setup for your Solar server, drawn with [gum](https://github.com/charmbracelet/gum). It asks for the site name, the hostname (Debian and Pi), who can open the status page and a first page, then shows the address as text and as a QR code. On Termux it also walks through the Android settings.

This is a prototype for a design decision. It is not part of a release.

## Run it

```
sudo setup/solar-setup          # Debian and Pi (root writes /etc and /srv)
setup/solar-setup               # Termux
setup/solar-setup --plain       # plain questions, no gum, no colour
```

It uses gum only when gum is installed and both stdin and stdout are terminals. Otherwise it asks plain questions, and it reads answers from a pipe. `NO_COLOR=1` and 16-colour terminals get plain borders.

Settings you can try:

- `SOLAR_SETUP_DEVICE=termux|pi|debian` pretends to be that device.
- `SOLAR_SETUP_IP=192.168.1.50` overrides the address it shows.
- `SOLAR_INSTALLER=FILE` names the installer to call.

## What each answer changes

| Answer | Where it goes |
| --- | --- |
| Site name | `site_name` in `solar.conf`, and the title and heading of `index.html` when they still hold the old name |
| Hostname | `hostname` in `solar.conf` (the installer applies it) |
| Status page | `status_public` in `solar.conf` (the installer writes the Caddyfile) |
| First page | A block in `index.html` between `solar-setup:begin` and `solar-setup:end` comments. Running again replaces only that block. |

The installer applies the answers: `install.sh --conf FILE --site-dir DIR --port N --no-setup`. On Termux the prototype prints that command and does not run it.

## Hand-over from the installer

`install.sh` copies `solar-setup` next to the other commands, keeps a copy of itself and the starter files in `<prefix>/lib/solar`, prints `Run solar-setup to finish`, and, when `/dev/tty` works, asks `Start it now? [Y/n]` and runs `exec solar-setup </dev/tty`. Pass `--no-setup` to skip all of this.

## gum

Screenshots use gum v2.0.2 (Linux x86_64, sha256 `d842e06d93dbed90af48cb8dd10698db6f22e331fc40346bb37bbc753109edc2`; arm64 `8ebf8b54ec1e8c81f2bb58b59ff9b70998186a4d11375f0cf357b80e0ccfa1d5`). The binary is 14 MB.
