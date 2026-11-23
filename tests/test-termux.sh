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
# Count processes by command line. Under QEMU the line starts with the emulator and the program path.
count_procs() {
  local f n=0 c
  for f in /proc/[0-9]*/cmdline; do
    c=$(tr '\0' ' ' < "$f" 2>/dev/null || true)
    [[ $c =~ ^(/usr/bin/qemu-[^\ ]+\ [^\ ]+\ )?$1 ]] && n=$((n + 1))
  done
  echo "$n"
}
# Stubs: pkg does nothing (Caddy is already installed), the rest log their calls.
for c in pkg termux-wake-lock am; do
  printf '#!/bin/sh\necho "%s $*" >> /tmp/calls\n' "$c" > "$PREFIX/bin/$c"; chmod +x "$PREFIX/bin/$c"
done
printf '#!/bin/sh\nexit 1\n' > "$PREFIX/bin/pm"; chmod +x "$PREFIX/bin/pm"
export PATH=$PREFIX/bin:$PATH
: > /tmp/calls

export SOLAR_ADDRESS_PROBE_URL=http://127.0.0.1:9
cd /work
out=$(bash install/install.sh 2>&1) || { echo "$out"; bad "installer failed"; }
curl -fsS localhost:8080 | grep -q "My Solar Server" || bad "starter page on 8080"
ok "one command serves the starter page on port 8080"
grep -q "pkg install -y libqrencode" /tmp/calls || bad "the installer must install libqrencode with pkg"
if grep -E "^pkg install.* qrencode( |$)" /tmp/calls; then bad "Termux has no package called qrencode"; fi
grep -q "pkg install -y ncurses-utils" /tmp/calls || bad "the installer must install ncurses-utils (tput)"
ok "Termux installs gum and libqrencode, and never asks for a package called qrencode"
echo "$out" | grep -q 'http://<phone address>:8080' || bad "no address found: the script prints the placeholder"
ok "with no address available, the script prints the placeholder and where to look"
printf '#!/bin/sh\necho "{ \\"ip\\": \\"192.168.1.77\\" }"\n' > "$PREFIX/bin/termux-wifi-connectioninfo"; chmod +x "$PREFIX/bin/termux-wifi-connectioninfo"
out2=$(bash install/install.sh 2>&1) || { echo "$out2"; bad "installer failed on the second run"; }
echo "$out2" | grep -q 'http://192.168.1.77:8080' || { echo "$out2"; bad "address from termux-wifi-connectioninfo"; }
ok "the address comes from termux-wifi-connectioninfo when Termux:API answers"
rm -f "$PREFIX/bin/termux-wifi-connectioninfo"
# curl path: probe the container's own non-loopback address; curl reports it as its local address.
myip=$(hostname -I | awk '{print $1}')
out3=$(SOLAR_ADDRESS_PROBE_URL="http://$myip:8080" bash install/install.sh 2>&1) || { echo "$out3"; bad "installer failed on the third run"; }
echo "$out3" | grep -q "http://$myip:8080" || { echo "$out3"; bad "address from curl's local_ip"; }
ok "the address comes from curl's local address when Termux:API is missing"
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
[ "$(count_procs "caddy run ")" = 1 ] || bad "more than one Caddy"
[ "$(count_procs "/.*/sh .*solar-serve")" = 1 ] || bad "not exactly one solar-serve"
ok "second run changes nothing and starts nothing twice"

# Battery fields appear once Termux:API answers.
printf '#!/bin/sh\necho "{\\"percentage\\": 55, \\"status\\": \\"DISCHARGING\\", \\"temperature\\": 29.0}"\n' > "$PREFIX/bin/termux-battery-status"; chmod +x "$PREFIX/bin/termux-battery-status"
SOLAR_CONF=/none "$PREFIX/bin/solar-status" "$HOME/site"
grep -q '"percentage": 55' "$HOME/site/status.json" || bad "battery"
ok "battery fields appear when Termux:API answers"

# --apply (what solar-setup calls) writes the settings and installs no packages.
: > /tmp/calls
printf 'site_name=Applied\nstatus_public=true\n' > /tmp/apply.conf
out=$(bash install/install.sh --apply --conf /tmp/apply.conf 2>&1) || { echo "$out"; bad "--apply failed"; }
grep -q '^pkg ' /tmp/calls && bad "--apply ran pkg"
echo "$out" | grep -q 'Do this once' && bad "--apply printed the Android hints"
grep -qx 'site_name=Applied' "$PREFIX/etc/solar/solar.conf" || bad "--apply did not save solar.conf"
grep -q 'status_outside' "$PREFIX/etc/caddy/Caddyfile" && bad "--apply kept the private status rule"
curl -fsS localhost:8080 >/dev/null || bad "server down after --apply"
ok "--apply saves solar.conf, rewrites the Caddyfile, installs no packages and prints no hints"

# Piped install: no folder next to the script, so it downloads the starter files.
pkill -f 'caddy run' 2>/dev/null || caddy stop >/dev/null 2>&1 || true
sleep 1
rm -rf "$HOME/site" "$HOME/.termux" "$PREFIX/etc/caddy"
tar -czf /tmp/src.tgz -C / --transform 's|^work|solar-power-stack-main|' work
SOLAR_SRC_URL=file:///tmp/src.tgz bash < /work/install/install.sh >/tmp/piped.log 2>&1 || { cat /tmp/piped.log; bad "piped install failed"; }
curl -fsS localhost:8080 | grep -q "My Solar Server" || bad "piped install page"
ok "piped install downloads the starter files and serves the page"
