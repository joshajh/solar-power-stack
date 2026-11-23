# Flash the Solar Server image

This guide takes you from an empty SD card to a running web server. You need a Raspberry Pi 3, 4 or 5 (no model has been tested yet, and a Pi Zero 2 W is not supported; see [image.md](image.md)), a microSD card (8 GB or larger), a card reader and a computer.

## Before you start

You do not need a keyboard or a monitor for the Pi. You need the name and password of your Wi-Fi network, unless you connect the Pi with a network cable.

## Steps

1. Install Raspberry Pi Imager from <https://www.raspberrypi.com/software/>. Use a current version.
2. Open Raspberry Pi Imager. Open its settings (the gear icon, or App Options) and find the content repository setting. Choose **Use custom** and paste this address:

   ```
   https://github.com/joshajh/solar-power-stack/releases/latest/download/os-list.json
   ```

   Save the setting and restart Imager if it asks.
3. Choose your Pi model, then choose **Solar Server** as the operating system. Choose your SD card as the storage.
4. Click **Next**. If Imager offers OS customisation, skip it. Step 7 sets the Wi-Fi, hostname and SSH options in `solar.conf`.
5. Click **Yes** to write the card and wait until Imager reports that it finished. Imager usually ejects the card at the end.
6. Take the card out and put it back into your computer. A drive named `bootfs` appears.
7. Open `solar.conf` on that drive in a text editor. Remove the `#` at the start of each line you want to use and fill in the values:

   ```
   hostname=solar
   site_name=My Solar Server
   wifi_ssid=YourNetworkName
   wifi_password=YourWifiPassword
   wifi_country=GB
   ```

   Use your own network name, password and two-letter country code. To use SSH, add `ssh=true` and a line `ssh_key=` followed by your public key. SSH stays off without these lines.
8. Eject the card, put it in the Pi and power on the Pi. The first start takes about two to three minutes.
9. On a computer or phone on the same Wi-Fi, open `http://solar.local` (use the hostname you chose). If your device does not understand `.local` names, find the Pi's address on your router and open `http://<address>`.

The Pi serves a starter page. To change it, follow the [SOLAR POWER guide](https://solarpower.possibleworlds.space).

## Use an older release

Every release has its own `os-list.json`. Replace `latest/download` in the address with `download/<version>`, for example `download/v0.1.0`.

## Downloads without Imager

Each release lists `.img.xz` and `.img.xz.sha256` files on the [releases page](https://github.com/joshajh/solar-power-stack/releases). Check the download with `sha256sum -c <file>.sha256`, unpack it with `xz -d`, and write the `.img` file to the card with any imaging tool. If the maintainer set up Backblaze B2, a mirror holds the same files.

## Versions

Releases use `vMAJOR.MINOR.PATCH`, for example `v0.1.0`.

- Increase PATCH for fixes that change no behaviour.
- Increase MINOR for new features and for changes to `solar.conf` keys that stay compatible.
- Increase MAJOR when a change needs you to flash again or edit `solar.conf` again.
- A tag with a dash, such as `v0.1.0-test` or `v0.2.0-rc1`, is a pre-release. GitHub does not count pre-releases as the latest release, so the address above never points to one.
