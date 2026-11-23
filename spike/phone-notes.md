# Phone spike: run a web server on an old Android phone for 72 hours

This test finds out whether an old Android phone keeps a web server running for 72 hours. You need an Android phone, a charger, a Wi-Fi network and a laptop on the same network.

Write down your results as you go. The section "After 72 hours" lists what to write up.

## Before you start

1. Note the phone model and the Android version (Settings, About phone).
2. Note the battery health if the phone shows it.
3. If you own a USB power meter, plug it between the charger and the phone. Note the watts at the start and at the end.

## Set up the phone

1. Install F-Droid from <https://f-droid.org>. Do not install Termux from the Google Play Store, because that version no longer receives updates.
2. In F-Droid, install **Termux**, **Termux:Boot** and **Termux:API**.
3. Open Termux:Boot once. It needs a single launch to register itself.
4. Open Termux and run:

   ```
   pkg update -y && pkg install -y caddy termux-api
   ```

5. Create the site and the config:

   ```
   mkdir -p ~/site && echo '<h1>Spike test</h1>' > ~/site/index.html
   printf ':8080 {\n\troot * %s/site\n\tfile_server\n}\n' "$HOME" > ~/Caddyfile
   ```

6. Keep the phone awake and start the server:

   ```
   termux-wake-lock
   caddy run --config ~/Caddyfile
   ```

   Leave this Termux session open. You can swipe it away from the screen with the notification still showing.

7. Find the phone's address: open a second Termux session and run `ifconfig 2>/dev/null | grep 'inet 192'` (or look in Settings, Wi-Fi). It looks like `192.168.1.50`.
8. From the laptop, open `http://<phone address>:8080` in a browser and confirm that you see "Spike test".

## Settings that may matter

Change one setting at a time and write down each one, so the report names the ones that were necessary.

- Battery optimisation: Settings, Apps, Termux, Battery, choose **Unrestricted** (the wording differs between phones). Do the same for Termux:Boot.
- Allow Termux to run in the background and show notifications.
- Wi-Fi: set "Keep Wi-Fi on during sleep" to **Always**.
- Developer options: switch on **Stay awake** only if the phone stays on the charger. Note whether you needed it.
- Turn the screen off with the power button, not by leaving it on a timeout.
- Plug the phone into the charger and leave it there.

## Run the probe from the laptop

1. Copy `spike/probe.sh` to the laptop and make it executable: `chmod +x probe.sh`.
2. Run it, replacing the address:

   ```
   ./probe.sh http://192.168.1.50:8080 probe-log.csv
   ```

3. Keep the laptop awake for 72 hours. If the laptop sleeps, the log shows false outages.
4. Leave the phone alone: screen off, on the charger, on Wi-Fi.

## During the 72 hours

Write a note each time you check the phone. For each outage, note the time and what you see in Termux (is the session still there? is the notification still there?).

Check twice a day, if you can, how warm the phone feels. If you have a thermometer app on another phone, or Termux:API, run `termux-battery-status` and note `temperature` and `status`.

## Measure power draw

- With a USB power meter: read the average watts over an hour.
- Without one: unplug the charger for a measured period, for example one hour with the screen off. Note the battery percentage before and after, and the battery capacity in mAh (Settings, About phone, or the spec sheet). Estimate watts as `(percent drop / 100) × capacity in Ah × 3.8 volts ÷ hours`.

## After 72 hours

1. Stop the probe with Ctrl-C.
2. Summarise the log: `./summarise.sh probe-log.csv`.
3. Copy the log to `spike/data/` in this repository.
4. Write up the results: the phone model and Android version, the settings that were necessary, the uptime from the log, any outages, the battery temperature and the average power draw. Open an issue or a pull request in this repository with it. A verdict of go means 99% uptime or better over the 72 hours with settings you can document.
