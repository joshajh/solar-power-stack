#!/usr/bin/env bash
# Run inside a fresh debian:12 container with the repo mounted at /repo.
# Usage (from the repo root):
#   docker run --rm -v "$PWD:/repo:ro" debian:12 bash /repo/tests/test-installer.sh
set -euo pipefail
ok()   { echo "PASS: $*"; }
bad()  { echo "FAIL: $*"; exit 1; }

apt-get update -qq && apt-get install -y -qq curl >/dev/null 2>&1
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
snapshot() { find /srv/site /etc/caddy -type f -exec sha256sum {} + | sort; }
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
