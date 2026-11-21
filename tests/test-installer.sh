#!/usr/bin/env bash
# Run inside a fresh debian:12 container with the repo mounted at /repo.
# Usage (from the repo root):
#   docker run --rm --cap-add NET_ADMIN -v "$PWD:/repo:ro" debian:12 bash /repo/tests/test-installer.sh
set -euo pipefail
ok()   { echo "PASS: $*"; }
bad()  { echo "FAIL: $*"; exit 1; }

apt-get update -qq && apt-get install -y -qq curl iproute2 >/dev/null 2>&1
cp -r /repo /work && cd /work

# 1. Unsupported OS exits non-zero with a message.
printf 'ID=plan9\n' > /tmp/os-release
if out=$(SOLAR_OS_RELEASE=/tmp/os-release bash install/install.sh 2>&1); then bad "unsupported OS exited 0"; fi
echo "$out" | grep -q "supports Debian" || bad "unsupported OS message missing"
ok "unsupported OS message"

# 2. --help documents every flag and conf key.
help=$(bash install/install.sh --help)
for w in --port --site-dir --name --conf hostname site_name; do
  echo "$help" | grep -q -- "$w" || bad "help misses $w"
done
ok "help lists flags and keys"

# 3. Fresh install serves the starter page.
bash install/install.sh --name "Test Site" >/dev/null
sleep 1
curl -fsS localhost | grep -q "Test Site" || bad "starter page missing"
ok "curl localhost returns the starter page"

# 4. Edit the page, run again: nothing changes.
echo "<p>my edit</p>" > /srv/site/index.html
# The status files change every minute by design, so leave them out.
snapshot() { find /srv/site /etc/caddy -type f ! -name 'status.json' ! -path '*/status/*' ! -name '.status.*' -exec sha256sum {} + | sort; }
before=$(snapshot)
bash install/install.sh --name "Test Site" >/dev/null
after=$(snapshot)
[ "$before" = "$after" ] || bad "second run changed files"
curl -fsS localhost | grep -q "my edit" || bad "edit lost"
ok "second run changes nothing and keeps the edit"

# 5. solar.conf sets the site name.
rm -rf /srv/site
printf '# comment\nsite_name=From Conf\n' > /tmp/solar.conf
bash install/install.sh --conf /tmp/solar.conf >/dev/null
curl -fsS localhost | grep -q "From Conf" || bad "solar.conf ignored"
ok "solar.conf site_name applied"

# 6. A name with HTML characters appears escaped and intact; a flag beats solar.conf.
rm -rf /srv/site
bash install/install.sh --conf /tmp/solar.conf --name 'A&B <x>' >/dev/null
curl -fsS localhost | grep -q '<h1>A&amp;B &lt;x&gt;</h1>' || bad "name not escaped"
ok "flag overrides solar.conf and the name is escaped"

# 7. Status page: JSON shape, and 403 for a non-private source address.
rm -rf /srv/site /etc/solar
printf 'status_public=false\n' > /tmp/solar.conf
bash install/install.sh --conf /tmp/solar.conf >/dev/null
curl -fsS localhost/status.json | grep -q '"uptime_seconds": [0-9]' || bad "status.json shape"
for k in updated model load_1min disk_free_mb cpu_temp_c; do
  curl -fsS localhost/status.json | grep -q "\"$k\"" || bad "status.json lacks $k"
done
curl -fsS localhost/status/ | grep -q "Device status" || bad "status page"
ok "status page and status.json load"
# No Termux:API here, so the JSON must not mention a battery.
curl -fsS localhost/status.json | grep -q battery && bad "battery shown without Termux:API"
ok "no battery fields without Termux:API"
# Give the loopback interface a public-looking address to simulate a remote visitor
# (needs --cap-add NET_ADMIN; the test skips this check without it).
if ip addr add 203.0.113.9/32 dev lo 2>/dev/null; then
  code=$(curl -s -o /dev/null -w '%{http_code}' --interface 203.0.113.9 localhost/status.json)
  [ "$code" = 403 ] || bad "remote status request returned $code, not 403"
  code=$(curl -s -o /dev/null -w '%{http_code}' --interface 203.0.113.9 localhost/)
  [ "$code" = 200 ] || bad "remote request for the site returned $code"
  ok "non-private address gets 403 on /status.json, 200 on the site"
else
  [ "${SOLAR_REQUIRE_NET:-}" != 1 ] || bad "cannot add an address; CI must run with --cap-add NET_ADMIN"
  echo "SKIP: cannot add an address (run with --cap-add NET_ADMIN)"
fi
# status_public=true lets everyone in.
printf 'status_public=true\n' > /tmp/solar.conf
bash install/install.sh --conf /tmp/solar.conf >/dev/null
curl -fsS localhost/status.json >/dev/null || bad "status_public=true"
ok "status_public=true serves status"

# 8. With a fake termux-battery-status, the battery fields appear.
mkdir -p /tmp/fakebin
cat > /tmp/fakebin/termux-battery-status <<'FAKE'
#!/bin/sh
printf '{\n  "health": "GOOD",\n  "percentage": 87,\n  "plugged": "PLUGGED_AC",\n  "status": "CHARGING",\n  "temperature": 31.5\n}\n'
FAKE
chmod +x /tmp/fakebin/termux-battery-status
PATH=/tmp/fakebin:$PATH /usr/local/bin/solar-status /srv/site
grep -q '"percentage": 87, "state": "charging", "temperature_c": 31.5' /srv/site/status.json || bad "battery JSON"
grep -q '87%' /srv/site/status/index.html || bad "battery HTML"
ok "battery fields appear with Termux:API"
# 9. Victron stays off by default: no victron block.
grep -q victron /srv/site/status.json && bad "victron on by default"
ok "victron off by default"

# 10. --harden writes each protection, and a second run changes nothing.
bash install/install.sh --harden >/dev/null 2>&1
grep -q 'Unattended-Upgrade "1"' /etc/apt/apt.conf.d/20auto-upgrades || bad "auto-upgrades"
# The effective list must hold the security entry only (Debian's defaults cleared).
n=$(apt-config dump | grep -c 'Unattended-Upgrade::Origins-Pattern::')
[ "$n" = 1 ] || bad "origins list has $n entries, expected only the security one"
apt-config dump | grep 'Origins-Pattern::' | grep -q 'security' || bad "security-only origins"
grep -q 'unattended-upgrades' /etc/tmpfiles.d/solar-log.conf || bad "tmpfiles for log dirs"
grep -q 'Storage=volatile' /etc/systemd/journald.conf.d/solar.conf || bad "volatile journal"
grep -q '^tmpfs /var/log' /etc/fstab || bad "tmpfs /var/log"
ok "--harden wrote updates, journal and log settings"
printf 'console=tty1 root=/dev/mmcblk0p2 rootwait\n' > /tmp/cmdline.txt
mkdir -p /boot/firmware && cp /tmp/cmdline.txt /boot/firmware/cmdline.txt
bash install/install.sh --harden >/dev/null 2>&1
grep -q 'fsck.repair=yes' /boot/firmware/cmdline.txt || bad "fsck.repair"
h1=$(sha256sum /etc/fstab /boot/firmware/cmdline.txt /etc/apt/apt.conf.d/*solar* /etc/systemd/journald.conf.d/solar.conf)
bash install/install.sh --harden >/dev/null 2>&1
h2=$(sha256sum /etc/fstab /boot/firmware/cmdline.txt /etc/apt/apt.conf.d/*solar* /etc/systemd/journald.conf.d/solar.conf)
[ "$h1" = "$h2" ] || bad "second --harden run changed files"
[ "$(grep -c '/var/log' /etc/fstab)" = 1 ] || bad "fstab line duplicated"
[ "$(grep -o 'fsck.repair=yes' /boot/firmware/cmdline.txt | wc -l)" = 1 ] || bad "cmdline duplicated"
ok "fsck.repair added once; --harden is idempotent"
# The Caddy restart settings live in the systemd drop-in code path.
grep -q 'Restart=always' install/install.sh || bad "restart setting"
grep -q 'StartLimitIntervalSec=0' install/install.sh || bad "restart limit setting"
ok "restart settings present in the installer"
# --readonly-root fails with a clear message off Raspberry Pi OS.
if out=$(bash install/install.sh --readonly-root 2>&1); then bad "--readonly-root worked without raspi-config"; fi
echo "$out" | grep -q "Raspberry Pi OS" || bad "readonly-root message"
ok "--readonly-root refuses on non-Pi systems"
