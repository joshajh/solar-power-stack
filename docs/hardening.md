# Hardening for power loss

A solar server loses power more often than a mains server. A hard power cut in the middle of a write can corrupt an SD card. The `--harden` option of `install/install.sh` reduces that risk and keeps the server running without a keyboard or monitor. The Raspberry Pi image runs the installer with `--harden`. On other machines, add the option yourself:

```
sudo ./install/install.sh --harden
```

You can run the command again. It changes only what differs. If the read-only root is on, the installer stops and tells you to turn it off first.

## What each setting does

| Setting | What it does | Why |
| --- | --- | --- |
| Security updates | Installs `unattended-upgrades` and clears Debian's default list, so only the Debian security channel stays. | Your device fixes known security holes without you. Other updates never install themselves, so an update cannot change how your server behaves. |
| `Restart=always` for Caddy | systemd starts Caddy again 3 seconds after it stops for any reason, and never stops trying (`StartLimitIntervalSec=0`). | A crash or a killed process takes the site down for about 3 seconds, not until you notice. |
| Journal in memory | `Storage=volatile`, at most 32 MB. | The system log no longer writes to the SD card all day. |
| `/var/log` in memory | Mounts `/var/log` as a 32 MB `tmpfs` (with `nofail`, so a mistake never blocks the boot) and recreates the log folders that the update job needs at every boot. | This replaces `log2ram` with a built-in feature. Other logs no longer write to the SD card. Logs disappear at reboot, so read them before you restart the device. |
| Disk check at boot | Adds `fsck.repair=yes` to the Raspberry Pi kernel command line (`/boot/firmware/cmdline.txt`). | After a power cut, the Pi checks the filesystem and repairs it before it starts the server. |
| Read-only root (`--readonly-root`, optional) | Runs `raspi-config nonint enable_overlayfs`. The Pi then writes changes to memory, not the card. | The root filesystem receives no writes, so a power cut cannot corrupt it. The small boot partition stays writable. |

## Read-only root: changes vanish at reboot

With the read-only root on, everything you change after the next reboot disappears at the following reboot: edits to your site, installed packages, and security updates. Turn the mode off before you edit or update, then turn it on again.

To turn it off:

```
sudo raspi-config nonint disable_overlayfs
sudo reboot
```

Edit your site or run `sudo apt update && sudo apt upgrade`, then turn it on again:

```
sudo raspi-config nonint enable_overlayfs
sudo reboot
```

Security updates apply by themselves only while the read-only root is off. With the mode on, plan to switch it off about once a month.

## Test results

These tests need a Raspberry Pi and have not run yet. **Josh fills in the results after the test.**

| Test | Result |
| --- | --- |
| Ten hard power cuts at random moments, Pi running from SD: boots and serves the starter page each time with no repair | Not run |
| Kill the Caddy process (`sudo pkill caddy`): it returns within 10 seconds (the setting waits 3 seconds, then starts Caddy) | Not run |
| Security updates apply with read-only root off | Not run |
| `raspi-config nonint enable_overlayfs` works as described on the image | Not run |

What CI checks: the installer writes each setting, a second run changes nothing, and `--readonly-root` refuses on systems without `raspi-config`. CI runs in containers without systemd, so it cannot test restarts or the boot-time disk check.
