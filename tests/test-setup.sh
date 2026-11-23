#!/usr/bin/env bash
# Run inside a fresh debian:12 container with the repo mounted at /repo.
# Usage (from the repo root):
#   docker run --rm -v "$PWD:/repo:ro" debian:12 bash /repo/tests/test-setup.sh
#
# Tests solar-setup (the guided setup) and its hand-over from install.sh:
# plain mode with scripted answers, the fallbacks, the gum checksum check, the
# /dev/tty hand-over, and a gum run in tmux that decodes the QR code.
set -euo pipefail
export LC_ALL=C.UTF-8     # grep must treat the block characters as one character each
ok()  { echo "PASS: $*"; }
bad() { echo "FAIL: $*"; exit 1; }

apt-get update -qq && apt-get install -y -qq curl tmux zbar-tools procps >/dev/null 2>&1
cp -r /repo /work && cd /work

# ---- 0. Install. --no-setup keeps the installer from starting solar-setup.
bash install/install.sh --no-setup --name "Test Site" >/tmp/install.log 2>&1 || { cat /tmp/install.log; bad "installer failed"; }
[ -x /usr/local/bin/solar-setup ] || bad "solar-setup is not installed"
GUM=/usr/local/lib/solar/bin/gum
[ -x "$GUM" ] || { cat /tmp/install.log; bad "the installer did not install gum"; }
"$GUM" --version | grep -q 2.0.2 || bad "gum version"
command -v qrencode >/dev/null || bad "qrencode is not installed"
grep -q "Start it now" /tmp/install.log && bad "--no-setup still offered solar-setup"
ok "the installer installs solar-setup, gum 2.0.2 and qrencode; --no-setup does not offer the setup"

snapshot() { find /srv/site /etc/caddy /etc/solar -type f ! -name status.json ! -path '*/status/*' ! -name '.status.*' -exec sha256sum {} + | sort; }

# ---- 1. Plain mode, scripted answers: Enter, name, hostname, status 2, title, paragraph.
LONG=$(printf 'word%03d ' $(seq 1 60))      # one line of about 480 characters
answers() { printf '\nRiver Notes\nriver\n2\nWelcome\n%s\n' "$LONG"; }
out=$(answers | solar-setup --plain) || { echo "$out"; bad "plain run failed"; }
conf=$(cat /etc/solar/solar.conf)
echo "$conf" | grep -qx 'site_name=River Notes' || bad "site_name key"
echo "$conf" | grep -qx 'hostname=river'        || bad "hostname key"
echo "$conf" | grep -qx 'status_public=true'    || bad "status_public key"
grep -q '<h1>River Notes</h1>' /srv/site/index.html || bad "heading not renamed"
[ "$(grep -c 'solar-setup:begin' /srv/site/index.html)" = 1 ] || bad "page block count"
block=$(sed -n '/solar-setup:begin/,/solar-setup:end/p' /srv/site/index.html)
echo "$block" | grep -q '<h2>Welcome</h2>' || bad "page title"
echo "$block" | grep -qF "<p>${LONG% }</p>" || bad "the long paragraph is not in the page whole"
grep -q 'status_outside' /etc/caddy/Caddyfile && bad "public status page still has the 403 rule"
ok "plain mode writes solar.conf, the page block, the heading and a 480-character paragraph"

# ---- 2. The same answers again change nothing.
before=$(snapshot)
answers | solar-setup --plain >/dev/null
after=$(snapshot)
[ "$before" = "$after" ] || { diff <(echo "$before") <(echo "$after"); bad "second run changed files"; }
ok "a second run with the same answers changes nothing"

# ---- 3. A changed answer replaces only the block, and keeps other keys.
printf 'victron=true\n' >> /etc/solar/solar.conf
printf '\n\n\n1\nSecond\nSecond text\n' | solar-setup --plain >/dev/null
[ "$(grep -c 'solar-setup:begin' /srv/site/index.html)" = 1 ] || bad "block was added twice"
grep -q '<h2>Second</h2>' /srv/site/index.html || bad "block not replaced"
grep -q 'Welcome' /srv/site/index.html && bad "old block text stayed"
grep -qx 'victron=true' /etc/solar/solar.conf || bad "an unrelated key was lost"
grep -q 'status_outside' /etc/caddy/Caddyfile || bad "private status page lost its 403 rule"
ok "a changed answer replaces the block, keeps other keys and re-applies the status rule"

# ---- 4. Text is escaped.
printf '\nA & <b>\n\n1\n<i>x</i>\nT & C\n' | solar-setup --plain >/dev/null
grep -q '<h1>A &amp; &lt;b&gt;</h1>' /srv/site/index.html || bad "name not escaped"
grep -q '&lt;i&gt;x&lt;/i&gt;' /srv/site/index.html || bad "title not escaped"
ok "HTML in answers is escaped"

# ---- 5. Fallbacks. gum is installed here, but there is no terminal.
out=$(solar-setup </dev/null) || { echo "$out"; bad "no-terminal run failed"; }
echo "$out" | grep -q 'step 1 of 5' || bad "no-terminal run did not ask plain questions"
echo "$out" | grep -q 'step 5 of 5' || bad "plain numbering"
ok "without a terminal, solar-setup asks plain questions (steps 1 to 5)"

# ---- 6. Refuse a gum download whose checksum does not match.
echo "not gum" > /tmp/fake.tar.gz
if SOLAR_GUM_URL=file:///tmp/fake.tar.gz bash setup/install-gum.sh /tmp/gumtest 2>/tmp/gum.err; then bad "a wrong checksum was accepted"; fi
grep -q 'does not match' /tmp/gum.err || bad "no message for the wrong checksum"
[ ! -e /tmp/gumtest/gum ] || bad "a file with a wrong checksum was installed"
ok "install-gum.sh refuses a download with the wrong SHA-256"

# ---- tmux helpers for the next tests.
screen() { tmux capture-pane -t "$1" -p; }
# wait_for SESSION TEXT: wait up to 90 seconds (arm64 runs under QEMU) for TEXT on screen.
wait_for() {
  for _ in $(seq 1 180); do
    screen "$1" | grep -qF -- "$2" && return 0
    sleep 0.5
  done
  echo "--- screen of $1:"; screen "$1"
  bad "timed out waiting for: $2"
}
# press KEYS: send keys to the gum session. Wait first: keys that arrive before
# gum has taken over the terminal are lost or echoed.
press() { sleep 1; tmux send-keys -t g "$@"; }
newsession() { tmux kill-server 2>/dev/null || true; tmux new-session -d -s "$1" -x "$2" -y 24 "env TERM=xterm-256color COLORTERM=truecolor $3; sleep 600"; }

# ---- 7. No gum, but a terminal: plain questions and a message.
mv "$GUM" "$GUM.off"
newsession nogum 40 "solar-setup"
wait_for nogum "gum is not installed"
wait_for nogum "step 1 of 6"        # plain numbering counts the QR screen when qrencode exists
tmux kill-server
mv "$GUM.off" "$GUM"
ok "without gum, solar-setup says so and asks plain questions"

# ---- 8. Hand-over from the installer.
# 8a. No /dev/tty (a docker run without -t has none; setsid makes sure): print the hint, do not prompt.
out=$(setsid -w bash install/install.sh </dev/null 2>&1) || { echo "$out"; bad "installer failed without a tty"; }
echo "$out" | grep -q 'Run solar-setup to finish' || bad "no hint without a tty"
echo "$out" | grep -q 'Start it now' && bad "prompted without a tty"
ok "without /dev/tty the installer prints the hint and does not prompt"
# 8b. A terminal, answer n: no solar-setup.
newsession ho 60 "bash install/install.sh"
wait_for ho "Start it now?"
tmux send-keys -t ho n Enter
sleep 2
screen ho | grep -q 'SOLAR POWER' && bad "answer n still started solar-setup"
ok "with a terminal the installer asks, and n skips solar-setup"
# 8c. A terminal, answer Enter: solar-setup starts.
newsession ho 60 "bash install/install.sh"
wait_for ho "Start it now?"
tmux send-keys -t ho Enter
wait_for ho "SOLAR POWER"
tmux kill-server
ok "with a terminal, Enter starts solar-setup"
# 8d. --no-setup: no prompt even on a terminal.
newsession ho 60 "bash install/install.sh --no-setup; echo FINISHED"
wait_for ho "FINISHED"
screen ho | grep -q 'Start it now' && bad "--no-setup prompted"
tmux kill-server
ok "--no-setup never prompts"

# ---- 9. gum run in tmux at the phone's size, 40 by 24.
# Each step waits for gum's own prompt before it sends keys: gum draws its prompt
# after solar-setup prints the title, and keys that arrive earlier are lost.
rm -rf /srv/site /etc/solar; bash install/install.sh --no-setup >/dev/null 2>&1
newsession g 40 "solar-setup"
wait_for g "(1 of 6)";                         screen g > /tmp/s1.txt; press Enter
wait_for g "Site name:";                       press C-u "Sunny Garden" Enter
wait_for g "Hostname:";                        press C-u "garden" Enter
wait_for g "Who can open it?";                 screen g | grep -q 'Status page  (3 of 6)' || bad "status screen number"; press Enter
wait_for g "Title:";                           screen g | grep -q 'Your first page  (4 of 6)' || bad "page screen number"; press "Hello from my server" Enter
wait_for g "A few sentences about your site"
press "$LONG"
wait_for g "word060"; screen g > /tmp/s4.txt   # the end of the text shows: it wraps inside the box
press Enter
wait_for g "Press Enter to show the QR code"; screen g > /tmp/s5.txt; grep -q "Done  (5 of 6)" /tmp/s5.txt || bad "done screen number"
grep -q 'Sunny Garden' /tmp/s5.txt || bad "done screen: site name"
grep -q 'Status:  private' /tmp/s5.txt || bad "done screen: status"
grep -q 'Press Enter to show the QR code' /tmp/s5.txt || bad "done screen: QR prompt"
press Enter
wait_for g "Open your site  (6 of 6)"; wait_for g "solarpower.possibleworlds.space"; screen g > /tmp/s6.txt
grep -q 'word060' /srv/site/index.html || bad "the paragraph did not reach the page"
grep -qx 'site_name=Sunny Garden' /etc/solar/solar.conf || bad "gum run: site_name"
ok "gum run at 40x24: six screens numbered 1 to 6, the long paragraph wraps, the answers apply"

# The QR code: rows between the title and the address line. Half blocks, so each
# text row holds two rows of modules. ANSIUTF8 draws the code as black on white:
# space = two black modules, upper half block = white over black,
# lower half block = black over white, full block = two white modules.
url=$(grep -m1 '^http://' /tmp/s6.txt)
[ -n "$url" ] || bad "no address on the QR screen"
sed -n '/Open your site/,/^http:\/\//p' /tmp/s6.txt | sed '1d;$d' > /tmp/qr.txt
rows=$(wc -l < /tmp/qr.txt)
[ "$rows" -ge 13 ] || bad "QR code has only $rows rows"
# Quiet zone: the first and last text rows are all white, and every row starts and ends with two white modules.
head -n 1 /tmp/qr.txt | grep -qE "^█+\$" || { cat -A /tmp/qr.txt | head -3; bad "top quiet zone is missing or clipped"; }
grep -qE '^█+$' <(tail -n 1 /tmp/qr.txt) || bad "bottom quiet zone is missing"
[ "$(grep -cvE '^██.*██$' /tmp/qr.txt)" = 0 ] || bad "side quiet zone is missing"
# Draw the modules into a bitmap (8 pixels per module), then decode it with zbar.
perl -CSD -Mutf8 -e '
  my @rows = map { chomp; $_ } <STDIN>;
  my %top = (" " => 1, "▀" => 0, "▄" => 1, "█" => 0);
  my %bot = (" " => 1, "▀" => 1, "▄" => 0, "█" => 0);
  my (@m, $w);
  for my $r (@rows) { my (@a, @b); for my $c (split //, $r) { push @a, $top{$c}; push @b, $bot{$c}; } push @m, \@a, \@b; $w = @a; }
  my $s = 8; my $h = @m;
  print "P1\n", $w*$s, " ", $h*$s, "\n";
  for my $row (@m) { my $line = join " ", map { ($_) x $s } @$row; print "$line\n" for 1..$s; }
' < /tmp/qr.txt > /tmp/qr.pbm
decoded=$(zbarimg --quiet --raw /tmp/qr.pbm 2>/dev/null) || bad "zbarimg could not decode the QR code"
[ "$decoded" = "$url" ] || bad "the QR code decodes to '$decoded', not '$url'"
ok "the QR code is complete with its white border, and decodes to $url"

# The QR screen fits in 24 rows, and the title stays on screen.
[ "$(wc -l < /tmp/s6.txt)" -le 24 ] || bad "the QR screen is taller than 24 rows"
head -n 3 /tmp/s6.txt | grep -q 'Open your site' || bad "the title scrolled off"
ok "the QR screen fits in 24 rows with the title in view"
tmux kill-server

# ---- 9b. Nothing fills the last columns: some terminals (Termux) wrap a line that does.
for cols in 30 40 45 46 50 64 80 120; do
  newsession w "$cols" "solar-setup"
  wait_for w "(1 of 6)"
  screen w > /tmp/w.txt
  widest=$(perl -CSD -Mutf8 -ne 'chomp; next unless /[█╭│╰]/; $m = length if length > $m; END { print $m + 0 }' /tmp/w.txt)
  [ "$widest" -le $((cols - 2)) ] || { cat /tmp/w.txt; bad "a bar or box at $cols columns is $widest wide"; }
  [ "$widest" -ge $((cols < 66 ? cols - 2 : 64)) ] || { cat /tmp/w.txt; bad "the bars at $cols columns are only $widest wide"; }
  tmux kill-server
done
# A fresh Termux has no tput. The width then comes from stty, not a guess of 80.
mkdir -p /tmp/notput; printf '#!/bin/sh\nexit 127\n' > /tmp/notput/tput; chmod +x /tmp/notput/tput
newsession w 45 "PATH=/tmp/notput:\$PATH solar-setup"
wait_for w "(1 of 6)"
screen w > /tmp/w.txt
widest=$(perl -CSD -Mutf8 -ne 'chomp; next unless /[█╭│╰]/; $m = length if length > $m; END { print $m + 0 }' /tmp/w.txt)
[ "$widest" -le 43 ] || { cat /tmp/w.txt; bad "without tput, a bar or box at 45 columns is $widest wide"; }
tmux kill-server
ok "the bars and boxes leave the last two columns empty from 30 to 120 columns, with or without tput"

# ---- 10. The same run for Termux: no hostname question, plus the Android settings.
# This is a Debian container that pretends to be Termux (SOLAR_SETUP_DEVICE) and has a stand-in "am".
tmux kill-server 2>/dev/null || true
rm -rf /srv/site /etc/solar /root/site; bash install/install.sh --no-setup >/dev/null 2>&1
ln -sfn /srv/site /root/site                 # Termux keeps the site in ~/site
printf '#!/bin/sh\nexit 0\n' > /usr/local/bin/am; chmod +x /usr/local/bin/am
newsession g 40 "SOLAR_SETUP_IP=192.168.1.50 SOLAR_SETUP_DEVICE=termux solar-setup"
wait_for g "(1 of 7)";                         press Enter
wait_for g "Site name:";                       press C-u "Phone Site" Enter
wait_for g "Who can open it?";                 screen g | grep -q 'Status page  (3 of 7)' || bad "termux: status screen number"; press Enter
wait_for g "Title:";                           press Enter
wait_for g "A few sentences about your site";  press Enter
wait_for g "Choose a setting to change";                         screen g | grep -q 'Android settings  (5 of 7)' || bad "termux: android screen number"; press Enter
wait_for g "Did you change it?";                 press y
wait_for g "[x] Battery: Unrestricted";        screen g | grep -q 'Android settings  (5 of 7)' || bad "termux: redrawn screen was counted twice"
press Down Down Down Down Enter
wait_for g "Press Enter to show the QR code"; screen g | grep -q "Done  (6 of 7)" || bad "termux: done number"; press Enter
wait_for g "Open your site  (7 of 7)"; wait_for g "solarpower.possibleworlds.space"
screen g | grep -q 'http://192.168.1.50:8080' || bad "termux: address on the QR screen"
grep -qx 'site_name=Phone Site' /etc/solar/solar.conf || bad "termux: site_name"
grep -q 'hostname=' /etc/solar/solar.conf && bad "termux: asked for a hostname"
ok "Termux run: seven screens numbered 1 to 7, the Android screen counts once and says Choose a setting to change"
tmux kill-server 2>/dev/null || true

echo "ALL PASSED"
