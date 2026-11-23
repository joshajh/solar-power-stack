#!/usr/bin/env bash
# install.sh - turn this device into a web server you own.
#
# It installs Caddy, copies the starter site, writes a Caddyfile, starts the
# server and prints the address. You can run it again safely: it never
# overwrites files you edited in the site folder.
set -euo pipefail

# ---------------------------------------------------------------- defaults
PORT=80
SITE_DIR=/srv/site
SITE_NAME="My Solar Server"
HOSTNAME_WANTED=""
STATUS_PUBLIC=false
CONF_FILE=""
# The starter site lives next to this script's parent directory.
# When you pipe the script into bash (curl ... | bash), there is no folder
# next to it. ensure_repo() then downloads the starter files.
# Never guess the folder when the script arrives on stdin: a planted folder next
# to the current directory would then run as root.
if [ -n "${BASH_SOURCE[0]:-}" ] && [ -f "${BASH_SOURCE[0]}" ]; then
  REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." 2>/dev/null && pwd || echo /nonexistent)"
else
  REPO_DIR=/nonexistent
fi
TEMPLATE_DIR="$REPO_DIR/site-template"
SRC_URL="${SOLAR_SRC_URL:-https://github.com/joshajh/solar-power-stack/archive/refs/heads/main.tar.gz}"
# Tests point this at a fake os-release file.
OS_RELEASE="${SOLAR_OS_RELEASE:-/etc/os-release}"

usage() {
  cat <<USAGE
Usage: install.sh [options]

Install the Caddy web server and a starter site on this device.

Options:
  --port N        Port the server listens on. Default: 80 (8080 on Termux).
  --site-dir DIR  Folder that holds your site. Default: /srv/site.
  --name TEXT     Site name shown on the starter page. Default: My Solar Server.
  --harden        Protect the device against power cuts: automatic security
                  updates, faster Caddy restarts, fewer SD-card writes and a
                  disk check at boot. The Raspberry Pi image turns this on.
  --readonly-root Make the root filesystem read-only (Raspberry Pi OS only).
                  Edits to your site vanish at reboot while this is on. See
                  docs/hardening.md. Implies --harden.
  --image-build   Prepare a disk image: set everything up and enable the
                  services, but do not start them. The Pi image build uses this.
  --conf FILE     Read settings from FILE. Default: ./solar.conf if it exists.
  --no-setup      Do not offer solar-setup, the guided setup, at the end.
  --apply         Apply new settings to a server that is already installed:
                  skip package installs and hints. solar-setup uses this.
  --help          Show this text.

solar.conf keys (one key=value per line, lines starting with # are comments):
  hostname        Name of this device, for example "solar" for solar.local.
  site_name       Same as --name.
  status_public   true or false (default false). false limits /status and
                  /status.json to private addresses (home network).
  victron         true or false (default false). Read a Victron solar charger.
  victron_device  Serial port of the VE.Direct cable. Default: /dev/ttyUSB0.

Command-line flags override solar.conf.
USAGE
}

say()  { printf '%s\n' "$*"; }
fail() { printf 'Error: %s\n' "$*" >&2; exit 1; }

# ----------------------------------------------------------------- options
PORT_SET=no
SITE_DIR_SET=no
HARDEN=no
IMAGE_BUILD=no
READONLY_ROOT=no
NO_SETUP=no
APPLY=no
while [ $# -gt 0 ]; do
  case "$1" in
    --port)     [ $# -ge 2 ] || fail "--port needs a number."; PORT="$2"; PORT_SET=yes; shift 2 ;;
    --site-dir) [ $# -ge 2 ] || fail "--site-dir needs a folder."; SITE_DIR="$2"; SITE_DIR_SET=yes; shift 2 ;;
    --name)     [ $# -ge 2 ] || fail "--name needs text."; SITE_NAME="$2"; FLAG_NAME=1; shift 2 ;;
    --conf)     [ $# -ge 2 ] || fail "--conf needs a file."; CONF_FILE="$2"; shift 2 ;;
    --no-setup) NO_SETUP=yes; shift ;;
    --apply)    APPLY=yes; NO_SETUP=yes; shift ;;
    --harden)   HARDEN=yes; shift ;;
    --image-build) IMAGE_BUILD=yes; shift ;;
    --readonly-root) HARDEN=yes; READONLY_ROOT=yes; shift ;;
    --help|-h)  usage; exit 0 ;;
    *)          usage >&2; fail "Unknown option: $1" ;;
  esac
done

# Read solar.conf by hand instead of sourcing it, so a typo cannot run code.
[ -z "$CONF_FILE" ] && [ -f solar.conf ] && CONF_FILE=solar.conf
if [ -n "$CONF_FILE" ]; then
  [ -f "$CONF_FILE" ] || fail "Cannot find $CONF_FILE."
  while IFS='=' read -r key value; do
    case "$key" in
      hostname)  HOSTNAME_WANTED="$value" ;;
      site_name) [ -n "${FLAG_NAME:-}" ] || SITE_NAME="$value" ;;
      status_public) STATUS_PUBLIC="$value" ;;
    esac
  done < <(grep -v '^[[:space:]]*#' "$CONF_FILE" || true)
fi

# The folder name goes into the Caddyfile and a boot script. Keep it plain.
case "$SITE_DIR" in
  *[\"\\\$\`]*|*$'\n'*) fail "--site-dir may not contain quotes, backslashes, dollar signs, backticks or line breaks." ;;
  /|"$HOME"|"$HOME"/) fail "--site-dir must be a folder just for your site, not $SITE_DIR itself." ;;
esac

case "$PORT" in ''|*[!0-9]*) fail "The port must be a number, not '$PORT'." ;; esac

# ------------------------------------------------------- detect environment
detect_os() {
  if [ -n "${PREFIX:-}" ] && [ -d "$PREFIX/etc" ] && case "$PREFIX" in *com.termux*) true ;; *) false ;; esac; then
    echo termux; return
  fi
  if [ -f "$OS_RELEASE" ]; then
    # shellcheck disable=SC1090
    . "$OS_RELEASE"
    case " ${ID:-} ${ID_LIKE:-} " in
      *" debian "*|*" ubuntu "*|*" raspbian "*) echo debian; return ;;
    esac
  fi
  echo unsupported
}

OS=$(detect_os)
[ "$OS" != unsupported ] || fail "This installer supports Debian, Ubuntu, Raspberry Pi OS and Termux. This device runs something else."

case "$(uname -m)" in
  aarch64|arm64|x86_64|amd64) ;;
  # Old phones often report a 32-bit ARM or x86 processor. Termux supports them.
  arm*|i686) [ "$OS" = termux ] || fail "This installer supports arm64 and x86_64 processors. This device reports $(uname -m)." ;;
  *) fail "This installer supports arm64 and x86 processors. This device reports $(uname -m)." ;;
esac

# ---------------------------------------------------------- Termux hook
# Where the status script and its settings go. Termux has no /usr/local or /etc.
BIN_DIR=/usr/local/bin
CONF_DIR=/etc/solar
if [ "$OS" = termux ]; then
  BIN_DIR="$PREFIX/bin"
  CONF_DIR="$PREFIX/etc/solar"
  [ "$PORT_SET" = yes ] || PORT=8080          # Android blocks ports below 1024
  [ "$SITE_DIR_SET" = yes ] || SITE_DIR="$HOME/site"
fi

# Download the starter files when the script runs without its folder.
ensure_repo() {
  local dir
  if [ -d "$TEMPLATE_DIR" ] && [ -f "$REPO_DIR/status/status.sh" ]; then return 0; fi
  command -v curl >/dev/null 2>&1 || fail "curl is missing. Install it, then run this script again."
  say "Downloading the starter files..."
  dir=$(mktemp -d)
  curl -fsSL "$SRC_URL" | tar -xz -C "$dir" --strip-components=1 \
    || fail "Could not download the starter files from $SRC_URL."
  REPO_DIR=$dir
  TEMPLATE_DIR="$dir/site-template"
  # Delete the downloaded files when the script ends.
  FETCHED_DIR=$dir
  trap 'rm -rf "$FETCHED_DIR"' EXIT
}

# TERMUX HOOK: everything that only a phone needs.
termux_setup() {
  local caddyfile="$PREFIX/etc/caddy/Caddyfile" changed=no

  # A half-updated Termux has a newer libcurl than OpenSSL, and then both curl and pkg fail.
  # pkg calls curl itself, so tell the reader to use apt.
  curl --version >/dev/null 2>&1 \
    || fail "curl does not run, because Termux is only partly updated. Run: apt update && apt full-upgrade -y, then run this script again."

  # --apply changes settings on a server that already runs, so it installs no packages.
  if [ "$APPLY" = no ]; then
    say "Installing Caddy..."
    # termux-api is the command-line half of Termux:API. The Android app is a separate install.
    # A fresh Termux often has an old package list, so update it first.
    { pkg update -y && pkg install -y caddy curl termux-api; } >"$HOME/solar-pkg.log" 2>&1 \
      || fail "pkg could not install Caddy. The log is in $HOME/solar-pkg.log. Run: apt update && apt full-upgrade -y, then run this script again."
  fi
  # A half-updated Termux has a newer libcurl than OpenSSL, and curl then fails to start.
  # The script needs curl to fetch the starter files, so stop early with the fix.
  curl --version >/dev/null 2>&1 \
    || fail "curl does not run, because Termux is only partly updated. Run: apt update && apt full-upgrade -y, then run this script again."

  ensure_repo
  install_site
  install_status
  install_setup
  write_caddyfile "$caddyfile" && changed=yes

  # solar-serve starts Caddy and refreshes the status page every minute.
  # The boot script and this installer both run it.
  cat >"$PREFIX/bin/solar-serve" <<SERVE
#!$PREFIX/bin/sh
# Keep the phone awake, start Caddy and refresh the status page every minute.
export SOLAR_CONF="$CONF_DIR/solar.conf"
# Termux:Boot may start this script with a short PATH.
export PATH="$PREFIX/bin:\$PATH"
pidfile="$PREFIX/tmp/solar-serve.pid"
# Stop if another copy runs already. Android reuses process numbers, so check
# that the number in the file belongs to solar-serve.
if [ -f "\$pidfile" ] && grep -q solar-serve "/proc/\$(cat "\$pidfile")/cmdline" 2>/dev/null; then exit 0; fi
echo \$\$ >"\$pidfile"
trap 'rm -f "\$pidfile"' EXIT
termux-wake-lock
while true; do
  # Every minute: start Caddy if it stopped, then refresh the status page.
  if ! curl -fsS http://127.0.0.1:2019/config/ >/dev/null 2>&1; then
    caddy run --config "$caddyfile" >"$HOME/solar-caddy.log" 2>&1 &
  fi
  "$BIN_DIR/solar-status" "$SITE_DIR"
  sleep 60
done
SERVE
  chmod 755 "$PREFIX/bin/solar-serve"

  # Termux:Boot runs every script in this folder when the phone starts.
  mkdir -p "$HOME/.termux/boot"
  printf '#!%s/bin/sh\n%s/bin/solar-serve\n' "$PREFIX" "$PREFIX" >"$HOME/.termux/boot/solar-start.sh"
  chmod 755 "$HOME/.termux/boot/solar-start.sh"

  # Start the server now. A running Caddy only needs a reload when the config changed.
  if curl -fsS http://127.0.0.1:2019/config/ >/dev/null 2>&1; then
    if [ "$changed" = yes ]; then caddy reload --config "$caddyfile" >/dev/null 2>&1 || true; fi
  fi
  # Stop an older solar-serve first, so exactly one copy runs. It starts Caddy when needed.
  if [ -f "$PREFIX/tmp/solar-serve.pid" ]; then
    old=$(cat "$PREFIX/tmp/solar-serve.pid")
    if grep -q solar-serve "/proc/$old/cmdline" 2>/dev/null; then kill "$old" 2>/dev/null || true; fi
    rm -f "$PREFIX/tmp/solar-serve.pid"
  fi
  nohup "$PREFIX/bin/solar-serve" >/dev/null 2>&1 &
  local _
  for _ in 1 2 3 4 5 6 7 8 9 10; do
    curl -fsS "http://127.0.0.1:$PORT" >/dev/null 2>&1 && break
    sleep 1
  done
  curl -fsS "http://127.0.0.1:$PORT" >/dev/null 2>&1 \
    || fail "Caddy did not answer on port $PORT. Look at $HOME/solar-caddy.log"

  [ "$APPLY" = yes ] || { termux_check_addons; termux_battery_help; print_address; }
}

# Tell the user which Android apps are missing.
termux_check_addons() {
  local packages
  # pm lists the installed apps. It may refuse to run on some phones.
  if packages=$(pm list packages 2>/dev/null) && [ -n "$packages" ]; then
    echo "$packages" | grep -q 'com.termux.boot' \
      || say "NOT DETECTED: Termux:Boot. If it is not installed, install it from F-Droid and open it once. Without it, the server does not start after a reboot."
  else
    say "Check that Termux:Boot is installed (F-Droid) and that you opened it once. Without it, the server does not start after a reboot."
  fi
  if ! timeout 10 termux-battery-status 2>/dev/null | grep -q percentage; then
    say "NOT DETECTED: Termux:API. If it is not installed, install it from F-Droid and open it once. The status page then shows the battery."
  fi
}

# Keep Android from stopping Termux in the background.
termux_battery_help() {
  # This opens Android's list of battery-optimisation settings, if the phone allows it.
  am start -a android.settings.IGNORE_BATTERY_OPTIMIZATION_SETTINGS >/dev/null 2>&1 || true
  say ""
  say "Do this once so Android keeps the server running:"
  say "  1. Open Settings, Apps, Termux, Battery."
  say "  2. Choose Unrestricted (the name differs between phones)."
  say "  3. Repeat for Termux:Boot and Termux:API."
  say "  4. On Android 12 or newer, open Settings, Developer options and switch on"
  say "     Disable child process restrictions (the name differs between phones)."
  say "  5. Leave the phone on its charger with Wi-Fi on."
}

# Stop early if the options cannot work on this device.
if [ "$OS" = termux ] && [ "$HARDEN" = yes ]; then
  fail "--harden and --readonly-root work only on Debian systems, not on Termux."
fi
if [ "$READONLY_ROOT" = yes ] && ! command -v raspi-config >/dev/null 2>&1; then
  fail "--readonly-root works only on Raspberry Pi OS (raspi-config not found)."
fi
# With the read-only root on, every change vanishes at reboot. Refuse to install.
if [ "$OS" = debian ] && [ "$IMAGE_BUILD" = no ] && command -v raspi-config >/dev/null 2>&1 \
   && [ "$(raspi-config nonint get_overlay_now 2>/dev/null)" = 0 ]; then
  fail "The read-only root is on. Turn it off first: sudo raspi-config nonint disable_overlayfs, then reboot. See docs/hardening.md."
fi

# ------------------------------------------------------------ Debian steps
install_caddy_debian() {
  [ "$(id -u)" -eq 0 ] || fail "Run this script as root: sudo ./install.sh"
  if command -v caddy >/dev/null 2>&1; then
    say "Caddy is already installed."
    return
  fi
  say "Installing Caddy..."
  export DEBIAN_FRONTEND=noninteractive
  apt-get update -qq
  # Debian 12 and newer carry Caddy in their own package list.
  apt-get install -y -qq caddy >/dev/null \
    || fail "Could not install Caddy. This installer needs Debian 12 or newer."
  # avahi lets other devices find this one at <hostname>.local.
  apt-get install -y -qq avahi-daemon >/dev/null || say "Could not install avahi. Use the IP address instead of the .local name."
}

# Copy the starter site without replacing any file that already exists.
install_site() {
  [ -d "$TEMPLATE_DIR" ] || fail "Cannot find the starter site at $TEMPLATE_DIR."
  mkdir -p "$SITE_DIR"
  # The starter page holds a placeholder for the site name. Fill it in only
  # when this run creates the page, so a page you edited stays as you left it.
  local fresh=no
  [ -e "$SITE_DIR/index.html" ] || fresh=yes
  # cp -n skips files that exist, so your edits survive a second run.
  # Newer versions of cp report skipped files as an error, so ignore that.
  cp -rn "$TEMPLATE_DIR"/. "$SITE_DIR"/ || true
  if [ "$fresh" = yes ]; then
    # Escape the characters that mean something in HTML. Quoting $name below
    # stops bash from treating an "&" in it as a placeholder.
    local name=${SITE_NAME//&/"&amp;"}
    name=${name//</"&lt;"}; name=${name//>/"&gt;"}
    local page
    page=$(<"$SITE_DIR/index.html")
    printf '%s\n' "${page//\{\{SITE_NAME\}\}/"$name"}" > "$SITE_DIR/index.html"
  fi
  # If you ran the script with sudo, give the site to your own user.
  if [ -n "${SUDO_USER:-}" ]; then chown -R "$SUDO_USER" "$SITE_DIR"; fi
  # Caddy runs as its own user and needs to read the folder.
  chmod -R a+rX "$SITE_DIR"
}

# Install the guided setup next to the other commands, with the tools it draws
# its screens with. The tools are optional: without them solar-setup asks plain
# questions, so a failure here never stops the install.
install_setup() {
  [ "$APPLY" = no ] || return 0
  [ -f "$REPO_DIR/setup/solar-setup" ] || return 0
  # solar-setup calls this installer again to apply your answers. Keep a copy
  # with the starter files it needs, so that run works offline.
  local lib; lib="$(dirname "$BIN_DIR")/lib/solar"
  { install -m 755 "$REPO_DIR/setup/solar-setup" "$BIN_DIR/solar-setup" \
    && mkdir -p "$lib" \
    && cp -r "$REPO_DIR/install" "$REPO_DIR/setup" "$REPO_DIR/site-template" "$REPO_DIR/status" "$lib"/; } \
    || { say "Could not install solar-setup. The server itself is installed."; return 0; }
  if [ "$OS" = termux ]; then
    pkg install -y gum qrencode >>"$HOME/solar-pkg.log" 2>&1 \
      || say "Could not install gum or qrencode. solar-setup still works: it asks plain questions and skips the QR code."
  else
    # A box that already ran Caddy may have an old package list, so refresh it.
    { apt-get update -qq && apt-get install -y -qq qrencode; } >/dev/null 2>&1 \
      || say "Could not install qrencode. solar-setup shows no QR code."
    # gum is not in Debian 12. install-gum.sh downloads a pinned release and checks its SHA-256.
    bash "$REPO_DIR/setup/install-gum.sh" "$lib/bin" \
      || say "Could not install gum. solar-setup asks plain questions."
  fi
}

# Hand over to solar-setup. Under "curl | bash", stdin is the script, not a
# terminal, so read the answer from /dev/tty, and only when /dev/tty works.
offer_setup() {
  [ "$NO_SETUP" = no ] && [ "$IMAGE_BUILD" = no ] || return 0
  [ -x "$BIN_DIR/solar-setup" ] || return 0
  say ""
  say "Run solar-setup to finish. It asks a few questions and shows your address."
  if ( : </dev/tty ) 2>/dev/null; then
    local answer=""
    printf 'Start it now? [Y/n] '
    read -r answer </dev/tty || answer=n
    case "$answer" in
      n|N|no) return 0 ;;
    esac
    # exec skips the EXIT trap, so delete the downloaded files first.
    [ -z "${FETCHED_DIR:-}" ] || rm -rf "$FETCHED_DIR"
    exec "$BIN_DIR/solar-setup" </dev/tty
  fi
}

# Write the Caddyfile. Return 0 when the file changed, 1 when it stayed the same.
write_caddyfile() {
  local target=$1 tmp status_rule=""
  tmp=$(mktemp)
  # Unless status_public=true, answer 403 to status requests that come from
  # outside the private address ranges (home network and this device).
  if [ "$STATUS_PUBLIC" != true ]; then
    status_rule='	@status_outside {
		path /status /status/* /status.json
		not remote_ip private_ranges
	}
	respond @status_outside "Forbidden" 403'
  fi
  cat >"$tmp" <<CADDY
# Written by solar-power-stack install.sh. Edit with care: the installer
# replaces this file when you run it again with different options.
:$PORT {
	root * "$SITE_DIR"
$status_rule
	file_server
}
CADDY
  if [ -f "$target" ] && cmp -s "$tmp" "$target"; then
    rm -f "$tmp"; return 1
  fi
  mkdir -p "$(dirname "$target")"
  mv "$tmp" "$target"
  chmod a+r "$target"
  return 0
}

# Install the status script, save the settings it reads and write the first page.
install_status() {
  install -m 755 "$REPO_DIR/status/status.sh" "$BIN_DIR/solar-status"
  # Termux has no /usr/bin/env, so point the script at Termux's own bash.
  if [ "$OS" = termux ]; then sed -i "1s|.*|#!$PREFIX/bin/bash|" "$BIN_DIR/solar-status"; fi
  mkdir -p "$CONF_DIR"
  chmod 700 "$CONF_DIR"   # solar.conf may hold secrets
  # Keep a copy of solar.conf where the status script looks for it.
  if [ -n "$CONF_FILE" ]; then
    cmp -s "$CONF_FILE" "$CONF_DIR/solar.conf" 2>/dev/null || cp "$CONF_FILE" "$CONF_DIR/solar.conf"
  fi
  if have_systemd; then
    # A timer runs the script every minute.
    printf '[Service]\nType=oneshot\nExecStart=%s/solar-status %s\n' "$BIN_DIR" "$SITE_DIR" > /etc/systemd/system/solar-status.service
    printf '[Timer]\nOnBootSec=10\nOnUnitActiveSec=60\n[Install]\nWantedBy=timers.target\n' > /etc/systemd/system/solar-status.timer
    systemctl daemon-reload
    if [ "$IMAGE_BUILD" = yes ]; then
      systemctl enable solar-status.timer >/dev/null 2>&1
    else
      systemctl enable --now solar-status.timer >/dev/null 2>&1
    fi
  elif [ "$OS" != termux ]; then
    say "This device has no systemd, so the status page updates only when you run: solar-status $SITE_DIR"
  fi
  # An image build has no running system to report on yet.
  [ "$IMAGE_BUILD" = yes ] || "$BIN_DIR/solar-status" "$SITE_DIR"
}

# Inside an image build, systemd is installed but not running. Treat it as present.
have_systemd() { [ "$IMAGE_BUILD" = yes ] || [ -d /run/systemd/system ]; }

# Make systemd restart Caddy whenever it stops for any reason, after 3 seconds,
# and never give up however often it stops.
write_restart_dropin() {
  local dir=/etc/systemd/system/caddy.service.d
  mkdir -p "$dir"
  printf '[Unit]\nStartLimitIntervalSec=0\n[Service]\nRestart=always\nRestartSec=3\n' >"$dir/solar.conf"
}

# Write a file only when its content differs, so a second run changes nothing.
put_file() {
  local target=$1 content=$2
  mkdir -p "$(dirname "$target")"
  if [ "$(cat "$target" 2>/dev/null || true)" != "$content" ]; then
    printf '%s\n' "$content" > "$target"
  fi
}

# Power-cut protection. Each step is explained in docs/hardening.md.
harden() {
  say "Hardening this device against power cuts..."
  export DEBIAN_FRONTEND=noninteractive

  apt-get update -qq
  # 1. Install security updates by themselves, and nothing else.
  apt-get install -y -qq unattended-upgrades >/dev/null
  put_file /etc/apt/apt.conf.d/20auto-upgrades 'APT::Periodic::Update-Package-Lists "1";
APT::Periodic::Unattended-Upgrade "1";'
  # Clear Debian's default list, then allow only Debian security updates.
  # shellcheck disable=SC2016 # apt, not the shell, expands ${distro_codename}
  put_file /etc/apt/apt.conf.d/52solar-security-only '#clear Unattended-Upgrade::Origins-Pattern;
Unattended-Upgrade::Origins-Pattern:: "origin=Debian,codename=${distro_codename}-security,label=Debian-Security";'

  # 2. Keep the journal in memory so it does not write to the SD card.
  put_file /etc/systemd/journald.conf.d/solar.conf '[Journal]
Storage=volatile
RuntimeMaxUse=32M'

  # 3. Keep /var/log in memory too. This is the simple stand-in for log2ram:
  # logs vanish at reboot, and the SD card takes far fewer writes.
  # nofail: a problem with this line never stops the boot.
  if ! grep -qE '^[^#]*[[:space:]]/var/log[[:space:]]' /etc/fstab 2>/dev/null; then
    printf '\ntmpfs /var/log tmpfs defaults,noatime,nosuid,nodev,mode=0755,size=32m,nofail 0 0\n' >> /etc/fstab
  fi
  # An empty /var/log has none of the folders that programs expect. Create
  # them at every boot. Without this, the daily update job crashes.
  put_file /etc/tmpfiles.d/solar-log.conf 'd /var/log/apt 0755 root root -
d /var/log/unattended-upgrades 0755 root root -
d /var/log/caddy 0755 caddy caddy -'


  # 4. Check and repair the filesystem at every boot (Raspberry Pi kernel option).
  local cmdline
  for cmdline in /boot/firmware/cmdline.txt /boot/cmdline.txt; do
    if [ -f "$cmdline" ] && ! grep -q 'fsck.repair=yes' "$cmdline"; then
      sed -i '1 s/$/ fsck.repair=yes/' "$cmdline"
    fi
  done

  # 5. Optional read-only root. Only Raspberry Pi OS has the tool for it.
  if [ "$READONLY_ROOT" = yes ]; then
    raspi-config nonint enable_overlayfs || fail "raspi-config could not enable the read-only root."
    say "The read-only root starts after the next reboot."
  fi
}

start_debian() {
  local changed=$1
  if have_systemd; then
    write_restart_dropin
    systemctl daemon-reload
    systemctl enable caddy >/dev/null 2>&1
    if [ "$IMAGE_BUILD" = yes ]; then
      return 0   # the server starts when the image boots
    elif [ "$changed" = yes ]; then systemctl restart caddy; else systemctl start caddy; fi
  else
    # No systemd (a container, for example). Caddy's admin address answers
    # when Caddy already runs. Then reload the config. Otherwise start Caddy.
    if curl -fsS http://127.0.0.1:2019/config/ >/dev/null 2>&1; then
      if [ "$changed" = yes ]; then caddy reload --config /etc/caddy/Caddyfile >/dev/null 2>&1 || true; fi
    else
      caddy start --config /etc/caddy/Caddyfile >/dev/null 2>&1 || true
    fi
  fi
  # Check that the server answers before you tell the user it runs.
  local _
  for _ in 1 2 3 4 5; do
    curl -fsS "http://127.0.0.1:$PORT" >/dev/null 2>&1 && return 0
    sleep 1
  done
  fail "Caddy did not answer on port $PORT. Run: caddy validate --config /etc/caddy/Caddyfile"
}

set_hostname() {
  [ -n "$HOSTNAME_WANTED" ] || return 0
  case "$HOSTNAME_WANTED" in
    -*|*[!A-Za-z0-9-]*) fail "The hostname may contain only letters, digits and hyphens." ;;
  esac
  if have_systemd && command -v hostnamectl >/dev/null 2>&1; then
    hostnamectl set-hostname "$HOSTNAME_WANTED"
  else
    say "Skipping hostname: this device has no systemd."
  fi
}

# True for a dotted IPv4 address that is not empty, loopback or unspecified.
usable_address() {
  [[ "${1:-}" =~ ^[0-9]+(\.[0-9]+){3}$ ]] && [ "$1" != 0.0.0.0 ] && [[ "$1" != 127.* ]]
}

print_address() {
  local ip name suffix=""
  [ "$PORT" = 80 ] || suffix=":$PORT"
  say ""
  say "Your server is running. Open one of these addresses in a browser:"
  if [ "$OS" = termux ]; then
    # Termux's hostname command has no -I, and Android 11 and newer stop apps from reading the
    # Wi-Fi interface with ip or ifconfig. Try three ways, and keep the first real address.
    local probe="${SOLAR_ADDRESS_PROBE_URL:-https://github.com}"
    ip=$( { ip -4 addr show wlan0 2>/dev/null || ifconfig wlan0 2>/dev/null; } | grep -oE 'inet [0-9.]+' | head -n 1 | cut -d' ' -f2) || true
    usable_address "$ip" || ip=$(timeout 5 termux-wifi-connectioninfo 2>/dev/null | grep -oE '"ip": *"[0-9.]+"' | grep -oE '[0-9]+(\.[0-9]+){3}' | head -n 1) || true
    # curl reports the local address of its own connection, which needs no special permission.
    usable_address "$ip" || ip=$(curl -4 -s -o /dev/null -w '%{local_ip}' --max-time 8 "$probe" 2>/dev/null) || true
    if usable_address "$ip"; then
      say "  http://$ip$suffix"
      say "  (Use this address from a phone or computer on the same Wi-Fi.)"
    else say "  http://<phone address>$suffix  (find the address in Settings, About phone, Status, IP address)"; fi
    return 0
  fi
  ip=$(hostname -I 2>/dev/null | awk '{print $1}')
  name=$(hostname)
  [ -n "$ip" ] && say "  http://$ip$suffix"
  say "  http://$name.local$suffix"
}

# -------------------------------------------------------------------- main
if [ "$OS" = termux ]; then
  termux_setup
else
  install_caddy_debian
  ensure_repo
  install_site
  install_status
  install_setup
  changed=no
  if write_caddyfile /etc/caddy/Caddyfile; then changed=yes; fi
  # An image gets its hostname from solar.conf at first boot instead.
  [ "$IMAGE_BUILD" = yes ] || set_hostname
  [ "$HARDEN" = no ] || harden
  start_debian "$changed"
  [ "$IMAGE_BUILD" = yes ] || [ "$APPLY" = yes ] || print_address
fi
offer_setup
