#!/usr/bin/env bash
# Simulate Termux inside debian:12: a fake PREFIX, stub Termux commands, real Caddy.
# This checks the script's logic. It does not prove anything about a real phone.
#   docker run --rm -v "$PWD:/repo:ro" debian:12 bash /repo/tests/test-termux.sh
set -euo pipefail
ok()  { echo "PASS: $*"; }
bad() { echo "FAIL: $*"; exit 1; }

apt-get update -qq && apt-get install -y -qq curl caddy >/dev/null 2>&1
caddy stop >/dev/null 2>&1 || true
cp -r /repo /work

export PREFIX=/tmp/data/data/com.termux/files/usr HOME=/tmp/home
mkdir -p "$PREFIX/bin" "$PREFIX/etc" "$PREFIX/tmp" "$HOME"
ln -s /bin/sh "$PREFIX/bin/sh"; ln -s /bin/bash "$PREFIX/bin/bash"
rm -f /usr/bin/env.bak # Termux has no /usr/bin/env; the test checks the installed script does not need it
mv /usr/bin/env /usr/bin/env.bak
# Stubs: pkg does nothing (Caddy is already installed), the rest log their calls.
for c in pkg termux-wake-lock am; do
  printf '#!/bin/sh\necho "%s $*" >> /tmp/calls\n' "$c" > "$PREFIX/bin/$c"; chmod +x "$PREFIX/bin/$c"
done
printf '#!/bin/sh\nexit 1\n' > "$PREFIX/bin/pm"; chmod +x "$PREFIX/bin/pm"
export PATH=$PREFIX/bin:$PATH
: > /tmp/calls

cd /work
out=$(bash install/install.sh 2>&1) || { echo "$out"; bad "installer failed"; }
curl -fsS localhost:8080 | grep -q "My Solar Server" || bad "starter page on 8080"
ok "one command serves the starter page on port 8080"
[ -f "$HOME/site/index.html" ] || bad "site folder"
grep -q ':8080' "$PREFIX/etc/caddy/Caddyfile" || bad "Caddyfile port"
curl -fsS localhost:8080/status.json | grep -q uptime_seconds || bad "status.json"
ok "site in ~/site, Caddyfile in PREFIX, status.json served"
boot="$HOME/.termux/boot/solar-start.sh"
[ -x "$boot" ] || bad "boot script missing"
grep -q solar-serve "$boot" || bad "boot script content"
grep -q '^termux-wake-lock' /tmp/calls || bad "wake lock"
grep -q 'IGNORE_BATTERY_OPTIMIZATION_SETTINGS' /tmp/calls || bad "battery intent"
ok "boot script written, wake lock and battery settings intent called"
echo "$out" | grep -q "Termux:Boot" || bad "no Termux:Boot hint"
echo "$out" | grep -q "NOT DETECTED: Termux:API" || bad "no Termux:API hint"
ok "missing add-ons reported"

# Second run: nothing changes, one Caddy.
echo "<p>edit</p>" > "$HOME/site/index.html"
before=$(find "$HOME/site" "$PREFIX/etc/caddy" "$HOME/.termux" -type f ! -name 'status.json' ! -path '*/status/*' ! -name '.status.*' -exec sha256sum {} + | sort)
bash install/install.sh >/dev/null 2>&1
after=$(find "$HOME/site" "$PREFIX/etc/caddy" "$HOME/.termux" -type f ! -name 'status.json' ! -path '*/status/*' ! -name '.status.*' -exec sha256sum {} + | sort)
[ "$before" = "$after" ] || bad "second run changed files"
curl -fsS localhost:8080 | grep -q edit || bad "edit lost"
[ "$(grep -al '^caddy.run' /proc/[0-9]*/cmdline 2>/dev/null | wc -l)" = 1 ] || bad "more than one Caddy"
[ "$(for p in /proc/[0-9]*; do tr "\0" " " < "$p/cmdline"; echo; done | grep -ac "^/.*/sh .*solar-serve")" = 1 ] || bad "not exactly one solar-serve"
ok "second run changes nothing and starts nothing twice"

# Battery fields appear once Termux:API answers.
printf '#!/bin/sh\necho "{\\"percentage\\": 55, \\"status\\": \\"DISCHARGING\\", \\"temperature\\": 29.0}"\n' > "$PREFIX/bin/termux-battery-status"; chmod +x "$PREFIX/bin/termux-battery-status"
SOLAR_CONF=/none "$PREFIX/bin/solar-status" "$HOME/site"
grep -q '"percentage": 55' "$HOME/site/status.json" || bad "battery"
ok "battery fields appear when Termux:API answers"

# Piped install: no folder next to the script, so it downloads the starter files.
pkill -f 'caddy run' 2>/dev/null || caddy stop >/dev/null 2>&1 || true
sleep 1
rm -rf "$HOME/site" "$HOME/.termux" "$PREFIX/etc/caddy"
tar -czf /tmp/src.tgz -C / --transform 's|^work|solar-power-stack-main|' work
SOLAR_SRC_URL=file:///tmp/src.tgz bash < /work/install/install.sh >/tmp/piped.log 2>&1 || { cat /tmp/piped.log; bad "piped install failed"; }
curl -fsS localhost:8080 | grep -q "My Solar Server" || bad "piped install page"
ok "piped install downloads the starter files and serves the page"
