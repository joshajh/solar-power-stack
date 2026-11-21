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
CONF_FILE=""
# The starter site lives next to this script's parent directory.
TEMPLATE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/site-template"
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
  --conf FILE     Read settings from FILE. Default: ./solar.conf if it exists.
  --help          Show this text.

solar.conf keys (one key=value per line, lines starting with # are comments):
  hostname        Name of this device, for example "solar" for solar.local.
  site_name       Same as --name.

Command-line flags override solar.conf.
USAGE
}

say()  { printf '%s\n' "$*"; }
fail() { printf 'Error: %s\n' "$*" >&2; exit 1; }

# ----------------------------------------------------------------- options
PORT_SET=no
while [ $# -gt 0 ]; do
  case "$1" in
    --port)     [ $# -ge 2 ] || fail "--port needs a number."; PORT="$2"; PORT_SET=yes; shift 2 ;;
    --site-dir) [ $# -ge 2 ] || fail "--site-dir needs a folder."; SITE_DIR="$2"; shift 2 ;;
    --name)     [ $# -ge 2 ] || fail "--name needs text."; SITE_NAME="$2"; FLAG_NAME=1; shift 2 ;;
    --conf)     [ $# -ge 2 ] || fail "--conf needs a file."; CONF_FILE="$2"; shift 2 ;;
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
  apt-get install -y -qq caddy >/dev/null
}

# Copy the starter site without replacing any file that already exists.
install_site() {
  [ -d "$TEMPLATE_DIR" ] || fail "Cannot find the starter site at $TEMPLATE_DIR."
  mkdir -p "$SITE_DIR"
  # cp -n skips files that exist, so your edits survive a second run.
  cp -rn "$TEMPLATE_DIR"/. "$SITE_DIR"/
  # The starter page holds a placeholder. Fill it in only when the file
  # still contains it, which means you have not edited the page yet.
  if grep -q '{{SITE_NAME}}' "$SITE_DIR/index.html"; then
    # Escape characters that mean something to sed.
    safe_name=$(printf '%s' "$SITE_NAME" | sed -e 's/[&|\\]/\\&/g' -e 's/</\&lt;/g')
    sed -i "s|{{SITE_NAME}}|$safe_name|g" "$SITE_DIR/index.html"
  fi
  # If you ran the script with sudo, give the site to your own user.
  if [ -n "${SUDO_USER:-}" ]; then chown -R "$SUDO_USER" "$SITE_DIR"; fi
  # Caddy runs as its own user and needs to read the folder.
  chmod -R a+rX "$SITE_DIR"
}

# Write the Caddyfile. Return 0 when the file changed, 1 when it stayed the same.
write_caddyfile() {
  local target=$1 tmp
  tmp=$(mktemp)
  cat >"$tmp" <<CADDY
# Written by solar-power-stack install.sh. Edit with care: the installer
# replaces this file when you run it again with different options.
:$PORT {
	root * $SITE_DIR
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

have_systemd() { [ -d /run/systemd/system ]; }

# Make systemd restart Caddy whenever it stops for any reason.
write_restart_dropin() {
  local dir=/etc/systemd/system/caddy.service.d
  mkdir -p "$dir"
  printf '[Service]\nRestart=always\nRestartSec=3\n' >"$dir/solar.conf"
}

start_debian() {
  local changed=$1
  if have_systemd; then
    write_restart_dropin
    systemctl daemon-reload
    systemctl enable caddy >/dev/null 2>&1
    if [ "$changed" = yes ]; then systemctl restart caddy; else systemctl start caddy; fi
  else
    # No systemd (a container, for example): start Caddy in the background.
    if [ "$changed" = yes ]; then caddy stop >/dev/null 2>&1 || true; fi
    # "caddy start" fails harmlessly when Caddy already runs.
    caddy start --config /etc/caddy/Caddyfile >/dev/null 2>&1 || true
  fi
}

set_hostname() {
  [ -n "$HOSTNAME_WANTED" ] || return 0
  if have_systemd && command -v hostnamectl >/dev/null 2>&1; then
    hostnamectl set-hostname "$HOSTNAME_WANTED"
  else
    say "Skipping hostname: this device has no systemd."
  fi
}

print_address() {
  local ip name
  ip=$(hostname -I 2>/dev/null | awk '{print $1}')
  name=$(hostname)
  local suffix=""; [ "$PORT" = 80 ] || suffix=":$PORT"
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
  changed=no
  if write_caddyfile /etc/caddy/Caddyfile; then changed=yes; fi
  set_hostname
  start_debian "$changed"
  print_address
fi
