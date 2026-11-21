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
REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TEMPLATE_DIR="$REPO_DIR/site-template"
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
  --conf FILE     Read settings from FILE. Default: ./solar.conf if it exists.
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
HARDEN=no
READONLY_ROOT=no
while [ $# -gt 0 ]; do
  case "$1" in
    --port)     [ $# -ge 2 ] || fail "--port needs a number."; PORT="$2"; PORT_SET=yes; shift 2 ;;
    --site-dir) [ $# -ge 2 ] || fail "--site-dir needs a folder."; SITE_DIR="$2"; shift 2 ;;
    --name)     [ $# -ge 2 ] || fail "--name needs text."; SITE_NAME="$2"; FLAG_NAME=1; shift 2 ;;
    --conf)     [ $# -ge 2 ] || fail "--conf needs a file."; CONF_FILE="$2"; shift 2 ;;
    --harden)   HARDEN=yes; shift ;;
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
  *) fail "This installer supports arm64 and x86 processors. This device reports $(uname -m)." ;;
esac

# ---------------------------------------------------------- Termux hook
# TERMUX HOOK: the Termux install path fills this function in. It will
# install Caddy with pkg, keep the phone awake and start the server at boot.
termux_setup() {
  say "Termux support is not ready yet."
  return 1
}

# Stop early if the options cannot work on this device.
if [ "$OS" = termux ] && [ "$HARDEN" = yes ]; then
  fail "--harden and --readonly-root work only on Debian systems, not on Termux."
fi
if [ "$READONLY_ROOT" = yes ] && ! command -v raspi-config >/dev/null 2>&1; then
  fail "--readonly-root works only on Raspberry Pi OS (raspi-config not found)."
fi
# With the read-only root on, every change vanishes at reboot. Refuse to install.
if [ "$OS" = debian ] && command -v raspi-config >/dev/null 2>&1 \
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
  install -m 755 "$REPO_DIR/status/status.sh" /usr/local/bin/solar-status
  mkdir -p /etc/solar
  # Keep a copy of solar.conf where the status script looks for it.
  if [ -n "$CONF_FILE" ]; then
    cmp -s "$CONF_FILE" /etc/solar/solar.conf 2>/dev/null || cp "$CONF_FILE" /etc/solar/solar.conf
  fi
  if have_systemd; then
    # A timer runs the script every minute.
    printf '[Service]\nType=oneshot\nExecStart=/usr/local/bin/solar-status %s\n' "$SITE_DIR" > /etc/systemd/system/solar-status.service
    printf '[Timer]\nOnBootSec=10\nOnUnitActiveSec=60\n[Install]\nWantedBy=timers.target\n' > /etc/systemd/system/solar-status.timer
    systemctl daemon-reload
    systemctl enable --now solar-status.timer >/dev/null 2>&1
  else
    say "This device has no systemd, so the status page updates only when you run: solar-status $SITE_DIR"
  fi
  /usr/local/bin/solar-status "$SITE_DIR"
}

have_systemd() { [ -d /run/systemd/system ]; }

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
    if [ "$changed" = yes ]; then systemctl restart caddy; else systemctl start caddy; fi
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

print_address() {
  local ip name suffix=""
  ip=$(hostname -I 2>/dev/null | awk '{print $1}')
  name=$(hostname)
  [ "$PORT" = 80 ] || suffix=":$PORT"
  say ""
  say "Your server is running. Open one of these addresses in a browser:"
  [ -n "$ip" ] && say "  http://$ip$suffix"
  say "  http://$name.local$suffix"
}

# -------------------------------------------------------------------- main
if [ "$OS" = termux ]; then
  [ "$PORT_SET" = yes ] || PORT=8080
  termux_setup || fail "The Termux setup did not finish."
else
  install_caddy_debian
  install_site
  install_status
  changed=no
  if write_caddyfile /etc/caddy/Caddyfile; then changed=yes; fi
  set_hostname
  [ "$HARDEN" = no ] || harden
  start_debian "$changed"
  print_address
fi
