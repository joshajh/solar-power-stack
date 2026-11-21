#!/usr/bin/env bash
# summarise.sh - read a probe log and print the uptime percentage and every outage.
# Usage: ./summarise.sh probe-log.csv
set -eu
LOG=${1:?Usage: $0 probe-log.csv}
awk -F, '
  NR == 1 { next }                       # skip the header
  { total++ }
  $2 == "up" { up++; if (down_start != "") { print "outage: " down_start " to " $1 " (" n " checks)"; down_start = "" } ; n = 0 }
  $2 == "down" { if (down_start == "") down_start = $1; n++ }
  END {
    if (down_start != "") print "outage: " down_start " to end of log (" n " checks, still down)"
    if (total) printf "checks: %d  up: %d  uptime: %.2f%%\n", total, up, 100 * up / total
  }
' "$LOG"
