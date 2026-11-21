# Run a web server on an old Android phone (Termux)

Phones cannot take a flashable image, so the phone route is one pasted command in Termux. The server listens on port **8080**, because Android blocks apps without root from using ports below 1024.

## What you need

- An Android phone on Wi-Fi, ideally on its charger.
- [F-Droid](https://f-droid.org). Install Termux, Termux:Boot and Termux:API from F-Droid, not from the Google Play Store, which holds an outdated Termux.
- Open Termux:Boot once, and open Termux:API once. Android registers each app on its first launch.

## Install

Open Termux and paste:

```
pkg install -y curl && curl -fsSL https://raw.githubusercontent.com/joshajh/solar-power-stack/main/install/install.sh | bash
```

The command works after the repository becomes public. Until then, clone the repository with a token and run `bash install/install.sh`.

The script does this:

1. Installs Caddy and the Termux:API command-line tools with `pkg`.
2. Copies the starter site to `~/site` and never overwrites a page you edited.
3. Writes the Caddyfile (`$PREFIX/etc/caddy/Caddyfile`) for port 8080.
4. Writes `solar-serve` (`$PREFIX/bin/solar-serve`). It keeps the phone awake with `termux-wake-lock`, starts Caddy, restarts Caddy when it stops, and refreshes the status page every minute.
5. Writes `~/.termux/boot/solar-start.sh`, which starts `solar-serve` when the phone starts (Termux:Boot).
6. Reports which add-on apps are missing and opens Android's battery-optimisation settings.
7. Prints the address, for example `http://192.168.1.50:8080`. Open it from another device on the same Wi-Fi.

You can run the script again. It changes only what differs.

## Android settings

Do these once. Android otherwise stops Termux in the background.

1. Open Settings, Apps, Termux, Battery and choose Unrestricted. The name differs between phones.
2. Do the same for Termux:Boot and Termux:API.
3. Leave the phone on its charger, with Wi-Fi on. Set "Keep Wi-Fi on during sleep" to Always if your phone has that option.

The spike report (`docs/spike-termux.md`, from the 72-hour test) lists the settings that the test found necessary. Apply any that this list misses.

## Status page

`http://<phone address>:8080/status` shows uptime, load, free disk space and, with Termux:API installed, battery percentage, charging state and battery temperature. By default only private addresses (your home network) can see it. See `status/README.md`.

## Test results

None of this has run on a phone yet. The installer logic runs in CI against a simulated Termux (`tests/test-termux.sh`: a fake `$PREFIX`, stub Termux commands, real Caddy). The simulation cannot show how Android treats the server.

| Check | Result |
| --- | --- |
| Tested phone model and Android version | Not tested. **Josh fills in.** |
| One pasted command on a fresh Termux gives a server reachable from another device | Not run |
| Server survives a phone reboot (Termux:Boot) | Not run |
| Server survives 24 hours with the screen off | Not run |
| `am start -a android.settings.IGNORE_BATTERY_OPTIMIZATION_SETTINGS` opens the settings list | Not run |
| `pm list packages` reports Termux:Boot (else the script prints a reminder) | Not run |
| Termux:Boot starts `solar-serve` with `PATH` set (the script uses absolute paths) | Not run |

## Behaviour that the script assumes from the Termux documentation

Each of these is unverified on a phone:

- `pkg install caddy` provides a working Caddy binary.
- `termux-wake-lock` keeps the CPU awake while Termux runs.
- Termux:Boot runs every executable script in `~/.termux/boot/` after the phone boots, and the script can start long-running processes.
- Caddy's admin address (`127.0.0.1:2019`) works inside Termux, and `curl` can reach it.
- `termux-battery-status` answers within 10 seconds when Termux:API is installed.
