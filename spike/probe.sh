#!/usr/bin/env bash
# probe.sh - check the phone's web page once a minute and log up or down.
#
# Run it on a laptop on the same Wi-Fi as the phone. It writes one CSV row
# per check: timestamp, status (up or down), HTTP code, response time in ms.
#
# Usage: ./probe.sh http://192.168.1.50:8080 [logfile] [interval-seconds]
# Stop it with Ctrl-C. Run it for 72 hours with the laptop awake.
set -u

URL=${1:-}
LOG=${2:-probe-log.csv}
INTERVAL=${3:-60}

if [ -z "$URL" ]; then
  echo "Usage: $0 URL [logfile] [interval-seconds]" >&2
  echo "Example: $0 http://192.168.1.50:8080" >&2
  exit 1
fi

# Write the header once, so you can stop and restart without losing it.
[ -s "$LOG" ] || echo "timestamp,status,http_code,time_ms" >> "$LOG"

echo "Probing $URL every ${INTERVAL}s. Logging to $LOG. Press Ctrl-C to stop."

while true; do
  # Time in UTC ISO format works on both Linux and macOS.
  now=$(date -u +%Y-%m-%dT%H:%M:%SZ)
  # -m 10: give up after 10 seconds. -w prints the code and total time.
  # curl prints 000 as the code when it cannot connect at all.
  result=$(curl -s -o /dev/null -m 10 -w '%{http_code} %{time_total}' "$URL" 2>/dev/null) || true
  code=${result%% *}
  secs=${result##* }
  [ -n "$code" ] || { code=000; secs=0; }
  if [ "$code" = 200 ]; then status=up; else status=down; fi
  # Convert seconds to whole milliseconds with awk, which handles decimals.
  ms=$(awk -v s="$secs" 'BEGIN { printf "%d", s * 1000 }')
  echo "$now,$status,$code,$ms" >> "$LOG"
  sleep "$INTERVAL"
done
