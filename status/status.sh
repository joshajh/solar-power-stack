#!/usr/bin/env bash
# status.sh - write a status page and a status.json for this device.
#
# Run it every minute (the installer sets up a systemd timer). It writes:
#   <site-dir>/status.json         the numbers, for programs
#   <site-dir>/status/index.html   the same numbers, for people
#
# Optional settings come from solar.conf (default /etc/solar/solar.conf):
#   victron=true             read a Victron solar charger over VE.Direct
#   victron_device=/dev/ttyUSB0   the serial port of the VE.Direct cable
set -u

SITE_DIR=${1:-/srv/site}
CONF=${SOLAR_CONF:-/etc/solar/solar.conf}

# Look up one key in the conf file. Print nothing when the key is missing.
conf_get() {
  [ -f "$CONF" ] || return 0
  grep -E "^$1=" "$CONF" | tail -n 1 | cut -d= -f2-
}

# Remove characters that would break JSON or HTML.
clean() { printf '%s' "$1" | tr -d '"\\<>&' | tr -d '\000-\037'; }

# ------------------------------------------------------------ core fields
uptime_s=$(cut -d. -f1 /proc/uptime 2>/dev/null || echo 0)
load1=$(cut -d' ' -f1 /proc/loadavg 2>/dev/null || echo 0)
# Free space on the disk that holds the site, in megabytes.
disk_free_mb=$(df -Pm "$SITE_DIR" 2>/dev/null | awk 'NR==2 {print $4}')
disk_free_mb=${disk_free_mb:-0}

# The Pi reports its model here. Other devices report nothing, so fall back.
[ -r /sys/firmware/devicetree/base/model ] && model=$(tr -d "\000" < /sys/firmware/devicetree/base/model) || model=""
if [ -z "$model" ] && command -v getprop >/dev/null 2>&1; then
  model="$(getprop ro.product.manufacturer) $(getprop ro.product.model)"
fi
[ -n "$model" ] || model=$(uname -m)
model=$(clean "$model")

# CPU temperature: the kernel reports thousandths of a degree Celsius.
cpu_temp=null
f=/sys/class/thermal/thermal_zone0/temp
if [ -r "$f" ]; then
  raw=$(cat "$f" 2>/dev/null || true)
  case "$raw" in ''|*[!0-9]*) ;; *) cpu_temp=$(awk -v t="$raw" 'BEGIN { printf "%.1f", t/1000 }') ;; esac
fi

days=$((uptime_s / 86400)); hours=$(((uptime_s % 86400) / 3600)); mins=$(((uptime_s % 3600) / 60))
uptime_human="${days} days, ${hours} hours, ${mins} minutes"

# ---------------------------------------------------------- phone battery
# termux-battery-status needs the Termux:API add-on. Skip quietly without it.
battery_json=""; battery_html=""
if command -v termux-battery-status >/dev/null 2>&1; then
  out=$(timeout 10 termux-battery-status 2>/dev/null || true)
  pct=$(printf '%s' "$out" | grep -o '"percentage": *[0-9.]*' | grep -o '[0-9.]*$' || true)
  if [ -n "$pct" ]; then
    state=$(printf '%s' "$out" | grep -o '"status": *"[A-Z_]*"' | grep -o '"[A-Z_]*"$' | tr -d '"')
    btemp=$(printf '%s' "$out" | grep -o '"temperature": *[0-9.-]*' | grep -o '[-0-9.]*$' || true)
    [ -n "$btemp" ] || btemp=null
    battery_json=$(printf ',\n  "battery": {"percentage": %s, "state": "%s", "temperature_c": %s}' "$pct" "$(clean "$state")" "$btemp")
    battery_html=$(printf '<tr><th>Battery</th><td>%s%%, %s</td></tr>\n<tr><th>Battery temperature</th><td>%s &deg;C</td></tr>' "$pct" "$(clean "$state")" "$btemp")
  fi
fi

# ----------------------------------------------------- Victron (read only)
# VE.Direct sends text lines (KEY<tab>VALUE) about once a second. This code
# only reads. It never writes to the device. It stays off unless you set
# victron=true in solar.conf.
victron_json=""; victron_html=""
if [ "$(conf_get victron)" = true ]; then
  dev=$(conf_get victron_device); dev=${dev:-/dev/ttyUSB0}
  if [ -c "$dev" ]; then
    # Set the line speed (this changes the port setting, not the device),
    # then read for 3 seconds. Redirecting from the device opens it read only.
    stty -F "$dev" 19200 raw -echo 2>/dev/null || true
    block=$(timeout 3 cat <"$dev" 2>/dev/null || true)
    field() { printf '%s\n' "$block" | tr -d '\r' | awk -F'\t' -v k="$1" '$1==k {v=$2} END {print v}'; }
    v=$(field V); i=$(field I); ppv=$(field PPV)
    case "$v$i$ppv" in
      *[!0-9-]*|'') ;;
      *)
        victron_json=$(printf ',\n  "victron": {"battery_volts": %s, "battery_amps": %s, "solar_watts": %s}' \
          "$(awk -v x="$v" 'BEGIN{printf "%.2f", x/1000}')" "$(awk -v x="$i" 'BEGIN{printf "%.2f", x/1000}')" "$ppv")
        victron_html=$(printf '<tr><th>Solar charger battery</th><td>%s V, %s A</td></tr>\n<tr><th>Solar power</th><td>%s W</td></tr>' \
          "$(awk -v x="$v" 'BEGIN{printf "%.2f", x/1000}')" "$(awk -v x="$i" 'BEGIN{printf "%.2f", x/1000}')" "$ppv") ;;
    esac
  fi
fi

# -------------------------------------------------------------- write out
now=$(date -u +%Y-%m-%dT%H:%M:%SZ)
mkdir -p "$SITE_DIR/status"

# Write to a temporary file first, then rename, so a visitor never sees half a file.
tmp=$(mktemp "$SITE_DIR/.status.XXXXXX")
cat >"$tmp" <<JSON
{
  "updated": "$now",
  "uptime_seconds": $uptime_s,
  "model": "$model",
  "load_1min": $load1,
  "disk_free_mb": $disk_free_mb,
  "cpu_temp_c": $cpu_temp$battery_json$victron_json
}
JSON
chmod a+r "$tmp"; mv "$tmp" "$SITE_DIR/status.json"

cpu_html="not available"; [ "$cpu_temp" = null ] || cpu_html="$cpu_temp &deg;C"
tmp=$(mktemp "$SITE_DIR/.status.XXXXXX")
cat >"$tmp" <<HTML
<!doctype html>
<html lang="en">
<head>
  <meta charset="utf-8">
  <meta name="viewport" content="width=device-width, initial-scale=1">
  <meta http-equiv="refresh" content="60">
  <title>Device status</title>
  <style>
    body { font-family: system-ui, sans-serif; max-width: 36rem; margin: 3rem auto; padding: 0 1rem; line-height: 1.6; color: #1c1c1c; }
    th { text-align: left; padding-right: 1.5rem; font-weight: 600; }
  </style>
</head>
<body>
  <h1>Device status</h1>
  <p>This device updated this page at $now. The page reloads every minute.</p>
  <table>
    <tr><th>Device</th><td>$model</td></tr>
    <tr><th>Uptime</th><td>$uptime_human</td></tr>
    <tr><th>Load (1 minute)</th><td>$load1</td></tr>
    <tr><th>Free disk space</th><td>$disk_free_mb MB</td></tr>
    <tr><th>CPU temperature</th><td>$cpu_html</td></tr>
$battery_html
$victron_html
  </table>
  <p>Programs can read the same numbers from <a href="/status.json">status.json</a>.</p>
</body>
</html>
HTML
chmod a+r "$tmp"; mv "$tmp" "$SITE_DIR/status/index.html"
