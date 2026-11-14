#!/bin/sh
# S52 ambient logger (spec discussion/specs/S52-ambient-log.md r2).
# Measures received Wi-Fi / Bluetooth signal and chip temperature only. Runs no individual.
# Writes counts and strengths only: never SSID, BSSID, MAC or device names.
# Usage: ambient-log.sh [OUT_TSV] [MAX_ROWS]   (run as root; MAX_ROWS unset = forever)
# Columns: see HEADER. Missing value = NA. fail bitmask: 1 wifi, 2 bluetooth, 4 temperature.
set -u
OUT=${1:-/home/pi/s52/ambient.tsv}
MAX=${2:-0}
PERIOD=30
BT_SECS=8
BT_SNAP=6
HEADER='pi_s	boot	uptime_s	t_mc	w_n	w_max	w_sum	w_24	w_5	w_h1	w_h2	w_h3	w_h4	w_h5	b_n	b_max	b_r	b_h1	b_h2	b_h3	b_h4	w_ms	b_ms	fail'

now_ms() { echo $(( $(date +%s%N) / 1000000 )); }
up_s() { awk '{print $1}' /proc/uptime; }

# Wi-Fi: request SIGNAL and FREQ only, so no identifier is ever read.
# Prints: w_n w_max w_sum w_24 w_5 w_h1..w_h5
wifi_read() {
  out=$(nmcli -t -f SIGNAL,FREQ dev wifi list --rescan yes 2>/dev/null) || return 1
  printf '%s\n' "$out" | awk -F: '
    $0 == "" { next }
    { s = $1 + 0; f = $2 + 0; n++; sum += s; if (n == 1 || s > mx) mx = s
      if (f < 3000) b24++; else if (f >= 4900) b5++
      if (s < 20) h1++; else if (s < 40) h2++; else if (s < 60) h3++; else if (s < 80) h4++; else h5++ }
    END { printf "%d %s %d %d %d %d %d %d %d %d\n", n, (n ? mx : "NA"), sum, b24, b5, h1, h2, h3, h4, h5 }'
}

# Bluetooth: 8 s discovery. A device counts as seen if it appears in this scan's
# [NEW]/[CHG] Device lines or has an RSSI while discovery is on (BlueZ clears RSSI
# when discovery stops, so carried-over devices without RSSI are not counted).
# RSSI comes from `bluetoothctl info` taken during the scan, else from the scan's CHG lines.
# Addresses live only in this pipeline's memory and are dropped.
# Prints: ok b_n b_max b_r b_h1..b_h4
bt_read() {
  {
    bluetoothctl --timeout "$BT_SECS" scan on 2>&1 &
    sleep "$BT_SNAP"
    for a in $(bluetoothctl devices 2>/dev/null | awk '$1 == "Device" { print $2 }'); do
      r=$(bluetoothctl info "$a" 2>/dev/null | awk '$1 == "RSSI:" { if (match($0, /\(-?[0-9]+\)/)) print substr($0, RSTART + 1, RLENGTH - 2); exit }')
      printf 'SNAP %s %s\n' "$a" "${r:-NA}"
    done
    wait
  } | awk '
    { gsub(/\033\[[0-9;]*m/, "") }
    /Discovery started/ { ok = 1 }
    $1 == "SNAP" { if ($3 != "NA") { seen[$2] = 1; srs[$2] = $3 + 0 }; next }
    { for (i = 2; i <= NF; i++) if ($i == "Device" && $(i - 1) ~ /\[(NEW|CHG)\]$/) {
        a = $(i + 1); seen[a] = 1
        if ($(i + 2) == "RSSI:" && match($0, /\(-?[0-9]+\)/)) ors[a] = substr($0, RSTART + 1, RLENGTH - 2) + 0
        break } }
    END {
      for (a in seen) { n++; has = 0
        if (a in srs) { r = srs[a]; has = 1 } else if (a in ors) { r = ors[a]; has = 1 }
        if (has) { nr++; if (nr == 1 || r > mx) mx = r
          if (r >= -60) h1++; else if (r >= -75) h2++; else if (r >= -90) h3++; else h4++ } }
      printf "%d %d %s %d %d %d %d %d\n", ok, n, (nr ? mx : "NA"), nr, h1, h2, h3, h4 }'
}

mkdir -p "$(dirname "$OUT")"
[ -s "$OUT" ] || printf '%s\n' "$HEADER" >> "$OUT"
BOOT=$(cut -c1-8 /proc/sys/kernel/random/boot_id)
rows=0
while :; do
  u0=$(up_s); pi_s=$(date +%s); fail=0

  t=$(cat /sys/class/thermal/thermal_zone0/temp 2>/dev/null)
  case "$t" in ''|*[!0-9-]*) t=NA; fail=$((fail | 4)) ;; esac

  m0=$(now_ms)
  if w=$(wifi_read); then :; else w="NA NA NA NA NA NA NA NA NA NA"; fail=$((fail | 1)); fi
  m1=$(now_ms)
  b=$(bt_read)
  m2=$(now_ms)
  set -- $b
  if [ "${1:-0}" = 1 ]; then shift; b="$*"; else b="NA NA NA NA NA NA NA"; fail=$((fail | 2)); fi

  printf '%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\n' "$pi_s" "$BOOT" "$u0" "$t" \
    "$(echo $w | tr ' ' '\t')" "$(echo $b | tr ' ' '\t')" "$((m1 - m0))" "$((m2 - m1))" "$fail" >> "$OUT"

  rows=$((rows + 1))
  [ "$MAX" -gt 0 ] && [ "$rows" -ge "$MAX" ] && break
  # Wait the rest of PERIOD measured from this reading's start; no catch-up.
  wait_s=$(awk -v a="$u0" -v p="$PERIOD" '{ w = a + p - $1; if (w < 0) w = 0; printf "%.2f", w }' /proc/uptime)
  sleep "$wait_s"
done
