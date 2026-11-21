#!/usr/bin/env bash
# solar-firstboot.sh - apply the settings in solar.conf on the first boot.
#
# You edit solar.conf on the SD card (the boot partition, which Windows, macOS
# and Linux all show as a normal drive). This script reads it once, applies
# it, then disables itself. Keys, one key=value per line:
#   hostname        name of the device: "solar" gives http://solar.local
#   site_name       name on the starter page
#   wifi_ssid       Wi-Fi network name
#   wifi_password   Wi-Fi password (leave out for an open network)
#   wifi_country    two-letter country code, for example GB
#   ssh             true turns SSH on (needs ssh_key)
#   ssh_key         your public SSH key, on one line
set -u

CONF=${SOLAR_CONF:-/boot/firmware/solar.conf}
DONE_DIR=${SOLAR_STATE_DIR:-/var/lib/solar}
SITE_DIR=${SOLAR_SITE_DIR:-/srv/site}
SSH_USER=${SOLAR_SSH_USER:-solar}
DEFAULT_NAME="My Solar Server"   # the name the installer wrote at build time
NM_DIR=${SOLAR_NM_DIR:-/etc/NetworkManager/system-connections}

log() { echo "solar-firstboot: $*"; }

# Read one key from solar.conf. Print nothing when the key is missing.
# Windows editors add a carriage return at the end of each line: strip it.
get() {
  [ -f "$CONF" ] || return 0
  grep -E "^$1=" "$CONF" | tail -n 1 | cut -d= -f2- | tr -d '\r'
}

if [ ! -f "$CONF" ]; then
  log "no $CONF found, keeping the defaults."
fi

# ---------------------------------------------------------------- hostname
name=$(get hostname)
if [ -n "$name" ]; then
  case "$name" in
    -*|*[!A-Za-z0-9-]*) log "ignoring hostname: use only letters, digits and hyphens." ;;
    *)
      hostnamectl set-hostname "$name"
      # Debian maps the hostname to 127.0.1.1 in /etc/hosts. Keep that line in step.
      if grep -q '^127\.0\.1\.1' /etc/hosts; then
        sed -i "s/^127\.0\.1\.1.*/127.0.1.1\t$name/" /etc/hosts
      fi
      # Tell the mDNS service about the new name.
      systemctl restart avahi-daemon 2>/dev/null || true ;;
  esac
fi

# -------------------------------------------------------------- site name
site=$(get site_name)
if [ -n "$site" ] && [ -f "$SITE_DIR/index.html" ]; then
  # Escape HTML characters. Quote the replacement so "&" stays literal.
  esc=${site//&/"&amp;"}; esc=${esc//</"&lt;"}; esc=${esc//>/"&gt;"}
  page=$(<"$SITE_DIR/index.html")
  # Change the page only when it still has the default name.
  printf '%s\n' "${page//"$DEFAULT_NAME"/"$esc"}" > "$SITE_DIR/index.html"
fi

# ------------------------------------------------------------------ Wi-Fi
ssid=$(get wifi_ssid)
if [ -n "$ssid" ]; then
  country=$(get wifi_country)
  # The Wi-Fi radio stays off until you set a country.
  if [ -n "$country" ]; then
    # raspi-config reads SUDO_USER, as it does in pi-gen's own build scripts.
    SUDO_USER="$SSH_USER" raspi-config nonint do_wifi_country "$country" || log "could not set the Wi-Fi country."
  else
    log "wifi_ssid is set but wifi_country is missing. The Wi-Fi radio may stay off."
  fi
  password=$(get wifi_password)
  conn="$NM_DIR/solar-wifi.nmconnection"
  mkdir -p "$NM_DIR"
  {
    echo "[connection]"
    echo "id=solar-wifi"
    echo "uuid=$(cat /proc/sys/kernel/random/uuid)"
    echo "type=wifi"
    echo "autoconnect=true"
    echo
    echo "[wifi]"
    echo "mode=infrastructure"
    echo "ssid=$ssid"
    if [ -n "$password" ]; then
      echo
      echo "[wifi-security]"
      echo "key-mgmt=wpa-psk"
      echo "psk=$password"
    fi
    echo
    echo "[ipv4]"
    echo "method=auto"
    echo
    echo "[ipv6]"
    echo "method=auto"
  } > "$conn"
  # NetworkManager refuses keyfiles that other users can read.
  chmod 600 "$conn"
  nmcli connection reload 2>/dev/null || true
fi

# -------------------------------------------------------------------- SSH
# SSH stays off unless solar.conf says ssh=true. The device has no password
# you know, so SSH also needs your public key.
sshval=$(get ssh)
case "$sshval" in ''|true|false) ;; *) log "ssh=$sshval is not understood. Use ssh=true. SSH stays off." ;; esac
if [ "$sshval" = true ]; then
  key=$(get ssh_key)
  if [ -z "$key" ]; then
    log "ssh=true needs an ssh_key line in solar.conf. SSH stays off."
  else
    home=$(getent passwd "$SSH_USER" | cut -d: -f6)
    if [ -z "$home" ]; then
      log "user $SSH_USER does not exist. SSH stays off."
    else
      install -d -m 700 -o "$SSH_USER" "$home/.ssh"
      printf '%s\n' "$key" > "$home/.ssh/authorized_keys"
      chown "$SSH_USER" "$home/.ssh/authorized_keys"; chmod 600 "$home/.ssh/authorized_keys"
      # Allow keys only. Never allow passwords over SSH.
      mkdir -p /etc/ssh/sshd_config.d
      printf 'PasswordAuthentication no\n' > /etc/ssh/sshd_config.d/solar.conf
      systemctl enable --now ssh
    fi
  fi
fi

# --------------------------------------------------- remove stored secrets
# The boot partition is readable by anyone who holds the card. Blank the
# Wi-Fi password and the SSH key line now that the device has copied them.
if [ -f "$CONF" ]; then
  sed -i -E 's/^(wifi_password|ssh_key)=.*/#\1= (removed after the first boot)/' "$CONF" 2>/dev/null || log "could not clean $CONF."
fi

# ------------------------------------------------------------ finish up
mkdir -p "$DONE_DIR"
touch "$DONE_DIR/firstboot.done"
systemctl disable solar-firstboot.service 2>/dev/null || true
log "done."
