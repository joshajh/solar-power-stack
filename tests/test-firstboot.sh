#!/usr/bin/env bash
# Test image/first-boot/solar-firstboot.sh with stub commands. Run inside debian:12:
#   docker run --rm -v "$PWD:/repo:ro" debian:12 bash /repo/tests/test-firstboot.sh
set -euo pipefail
ok()  { echo "PASS: $*"; }
bad() { echo "FAIL: $*"; exit 1; }

S=/repo/image/first-boot/solar-firstboot.sh
CALLS=/tmp/calls; BIN=/tmp/bin; mkdir -p $BIN
# Stubs record each call instead of changing the container.
for c in hostnamectl systemctl raspi-config nmcli; do
  printf '#!/bin/sh\necho "%s $*" >> %s\n' "$c" "$CALLS" > "$BIN/$c"; chmod +x "$BIN/$c"
done
export PATH=$BIN:$PATH
useradd -m solar
export SOLAR_NM_DIR=/tmp/nm SOLAR_STATE_DIR=/tmp/state SOLAR_SITE_DIR=/tmp/site
mkdir -p /tmp/site; printf '<h1>My Solar Server</h1>\n' > /tmp/site/index.html
run() { : > $CALLS; bash $S >/tmp/out 2>&1; }

# 1. Full config with Windows line endings.
printf 'hostname=garden\r\nsite_name=Garden & Co\r\nwifi_ssid=Home Net\r\nwifi_password=secret pass\r\nwifi_country=GB\r\nssh=true\r\nssh_key=ssh-ed25519 AAAAtest me@laptop\r\n' > /tmp/solar.conf
SOLAR_CONF=/tmp/solar.conf run
grep -q 'hostnamectl set-hostname garden$' $CALLS || bad "hostname call"
grep -q 'raspi-config nonint do_wifi_country GB$' $CALLS || bad "wifi country"
grep -q '^ssid=Home Net$' /tmp/nm/solar-wifi.nmconnection || bad "ssid"
grep -q '^psk=secret pass$' /tmp/nm/solar-wifi.nmconnection || bad "psk"
[ "$(stat -c %a /tmp/nm/solar-wifi.nmconnection)" = 600 ] || bad "keyfile mode"
grep -q '<h1>Garden &amp; Co</h1>' /tmp/site/index.html || bad "site name"
grep -q 'systemctl enable --now ssh$' $CALLS || bad "ssh enable"
grep -q 'ssh-ed25519 AAAAtest' /home/solar/.ssh/authorized_keys || bad "ssh key"
grep -q 'systemctl disable solar-firstboot.service' $CALLS || bad "self-disable"
[ -f /tmp/state/firstboot.done ] || bad "done marker"
ok "full config applied, then the service disables itself"

grep -q '^#wifi_password= (removed' /tmp/solar.conf || bad "wifi password not removed"
grep -q 'AAAAtest' /tmp/solar.conf && bad "ssh key not removed"
grep -q '^hostname=garden' /tmp/solar.conf || bad "other keys lost"
ok "secrets removed from solar.conf after use"

# 2. No ssh line: SSH never turns on.
rm -rf /tmp/nm /tmp/state /home/solar/.ssh
printf 'hostname=plain\n' > /tmp/solar.conf
SOLAR_CONF=/tmp/solar.conf run
grep -q 'ssh' $CALLS && bad "ssh touched without ssh=true"
ok "SSH stays off by default"

# 3. ssh=true without a key: SSH stays off.
printf 'ssh=true\n' > /tmp/solar.conf
SOLAR_CONF=/tmp/solar.conf run
grep -q 'enable --now ssh' $CALLS && bad "ssh enabled without key"
grep -q 'needs an ssh_key' /tmp/out || bad "no warning"
ok "ssh=true without a key keeps SSH off and says why"

# 4. Missing file: finishes cleanly.
SOLAR_CONF=/tmp/none run
grep -q 'done' /tmp/out || bad "missing conf"
ok "missing solar.conf is fine"
