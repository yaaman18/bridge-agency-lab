#!/bin/sh
# S52 gates A0-A3 (spec section 5). Runs on the Mac.
# Usage:
#   check_ambient.sh a0 FILE          no identifiers in the rows (stdin if FILE is -)
#   check_ambient.sh a1 FILE          smoke: row shape, interval >= 30 s, fail marks
#   check_ambient.sh a2               wlan0 disconnected, only wired/loopback connections
#   check_ambient.sh a3               no onelife-run process on the Pi
#   check_ambient.sh neg              negative controls (each broken input must fail)
# Exit 0 = pass. Prints PASS/FAIL lines.
set -u
PI=${PI:-pi@bridge-pi.local}
SSH="ssh -o BatchMode=yes $PI"
HEADER='pi_s	boot	uptime_s	t_mc	w_n	w_max	w_sum	w_24	w_5	w_h1	w_h2	w_h3	w_h4	w_h5	b_n	b_max	b_r	b_h1	b_h2	b_h3	b_h4	w_ms	b_ms	fail'
NCOL=24

# A0: header exact; every data field is a number, NA, or (column 2 only) 8 hex digits;
# and no MAC/BSSID shape anywhere (plain or nmcli-escaped colons, or dashes).
a0_check() {
  awk -F'\t' -v hdr="$HEADER" '
    { line = $0; g = line; gsub(/\\:/, ":", g) }
    g ~ /[0-9A-Fa-f][0-9A-Fa-f][:-][0-9A-Fa-f][0-9A-Fa-f][:-][0-9A-Fa-f][0-9A-Fa-f][:-][0-9A-Fa-f][0-9A-Fa-f][:-][0-9A-Fa-f][0-9A-Fa-f][:-][0-9A-Fa-f][0-9A-Fa-f]/ {
      print "A0 FAIL line " NR ": address shape"; bad = 1; next }
    NR == 1 { if (line != hdr) { print "A0 FAIL header differs"; bad = 1 }; next }
    { for (i = 1; i <= NF; i++) {
        f = $i
        if (f == "NA") continue
        if (f ~ /^-?[0-9]+(\.[0-9]+)?$/) continue
        if (i == 2 && f ~ /^[0-9a-f]+$/ && length(f) == 8) continue
        print "A0 FAIL line " NR " col " i ": non-numeric field"; bad = 1; break } }
    END { if (NR < 1) { print "A0 FAIL empty"; bad = 1 }
          if (!bad) print "A0 PASS (" NR - 1 " rows)"; exit bad }'
}

# A1: shape and intervals of the smoke file.
a1_check() {
  awk -F'\t' -v hdr="$HEADER" -v nc="$NCOL" '
    NR == 1 { if ($0 != hdr) { print "A1 FAIL header"; bad = 1 }; next }
    { n++
      if (NF != nc) { print "A1 FAIL line " NR ": " NF " columns"; bad = 1; next }
      if ($24 !~ /^[0-7]$/) { print "A1 FAIL line " NR ": fail mark"; bad = 1 }
      if ($24 + 0 > 0) nf++
      if (int($24 / 1) % 2 == 1 && $5 != "NA") { print "A1 FAIL line " NR ": wifi fail but values"; bad = 1 }
      if (int($24 / 2) % 2 == 1 && $15 != "NA") { print "A1 FAIL line " NR ": bt fail but values"; bad = 1 }
      if (int($24 / 4) % 2 == 1 && $4 != "NA") { print "A1 FAIL line " NR ": temp fail but value"; bad = 1 }
      if ($5 != "NA" && $10 + $11 + $12 + $13 + $14 != $5) { print "A1 FAIL line " NR ": wifi bins"; bad = 1 }
      if ($17 != "NA" && $18 + $19 + $20 + $21 != $17) { print "A1 FAIL line " NR ": bt bins"; bad = 1 }
      if ($17 != "NA" && $17 + 0 > $15 + 0) { print "A1 FAIL line " NR ": b_r > b_n"; bad = 1 }
      if (n > 1 && $2 == pb) {
        du = $3 - pu; dp = $1 - pp
        if (du < 30 || dp < 30) { print "A1 FAIL line " NR ": interval " du " s"; bad = 1 }
        if (du > 120) { print "A1 FAIL line " NR ": gap " du " s"; bad = 1 }
        if (n == 2 || du < mn) mn = du; if (du > mx) mx = du }
      pb = $2; pu = $3; pp = $1 }
    END { if (n < 18) { print "A1 FAIL only " n " rows"; bad = 1 }
          if (!bad) printf "A1 PASS (%d rows, interval %.2f-%.2f s, %d failed rows)\n", n, mn, mx, nf
          exit bad }'
}

# A2: reads `nmcli -t -f DEVICE,TYPE,STATE dev` then a line "--", then `nmcli -t -f TYPE con show --active`.
a2_parse() {
  awk -F: '
    $0 == "--" { part = 2; next }
    part != 2 && $1 == "wlan0" { seen = 1; if ($3 != "disconnected") { print "A2 FAIL wlan0 " $3; bad = 1 } }
    part == 2 && $0 != "" && $1 != "802-3-ethernet" && $1 != "loopback" { print "A2 FAIL active " $1; bad = 1 }
    END { if (!seen) { print "A2 FAIL no wlan0"; bad = 1 }
          if (!bad) print "A2 PASS (wlan0 disconnected, active: wired/loopback only)"; exit bad }'
}
a2_live() { $SSH 'nmcli -t -f DEVICE,TYPE,STATE dev; echo --; nmcli -t -f TYPE con show --active' | a2_parse; }

# A3: reads `ps -eo args`.
a3_parse() {
  awk '/onelife-run/ { print "A3 FAIL process: onelife-run"; bad = 1 }
       END { if (!bad) print "A3 PASS (no onelife-run)"; exit bad }'
}
a3_live() { $SSH 'ps -eo args' | grep -v -e 'grep' | a3_parse; }

neg() {
  ok=0
  T=$(mktemp -d)
  good="1793000000	6fdcb2c4	9467.99	52350	3	94	250	2	1	0	0	0	1	2	3	-52	3	1	2	0	0	2700	8100	0"
  printf '%s\n%s\n' "$HEADER" "$good" > "$T/good"
  expect_fail() { if "$@" >/dev/null 2>&1; then echo "NEG FAIL: not caught: $label"; ok=1; else echo "NEG ok: caught: $label"; fi; }
  expect_pass() { if "$@" >/dev/null 2>&1; then echo "NEG ok: passes: $label"; else echo "NEG FAIL: rejected: $label"; ok=1; fi; }
  label="A0 clean row"; expect_pass a0_check < "$T/good"
  for bad in 'aa:bb:cc:11:22:33' 'AA\:BB\:CC\:11\:22\:33' 'aa-bb-cc-11-22-33' 'MyHomeWiFi' 'Galaxy Buds'; do
    printf '%s\n%s\t%s\n' "$HEADER" "$good" "$bad" > "$T/b"; label="A0 extra field [$bad]"; expect_fail a0_check < "$T/b"
    printf '%s\n%s\n' "$HEADER" "$(printf '%s' "$good" | awk -F'\t' -v OFS='\t' -v x="$bad" '{ $16 = x; print }')" > "$T/b"
    label="A0 replaced field [$bad]"; expect_fail a0_check < "$T/b"
  done
  label="A0 name in boot column"; printf '%s\n%s\n' "$HEADER" "$(printf '%s' "$good" | sed 's/6fdcb2c4/ssidname/')" > "$T/b"; expect_fail a0_check < "$T/b"
  label="A0 extra header column"; printf '%s\tssid\n%s\n' "$HEADER" "$good" > "$T/b"; expect_fail a0_check < "$T/b"
  # A1: build a valid 20-row smoke, then break it.
  awk -F'\t' -v OFS='\t' -v h="$HEADER" -v g="$good" 'BEGIN { print h; split(g, f, "\t"); for (k = 0; k < 20; k++) { f[1] = 1793000000 + 30 * k; f[3] = sprintf("%.2f", 9467.99 + 30.01 * k); s = f[1]; for (j = 2; j <= 24; j++) s = s OFS f[j]; print s } }' > "$T/s"
  label="A1 valid smoke"; expect_pass a1_check < "$T/s"
  label="A1 20 s interval"; awk -F'\t' -v OFS='\t' 'NR == 10 { $1 -= 10; $3 -= 10 } { print }' "$T/s" > "$T/b"; expect_fail a1_check < "$T/b"
  label="A1 missing column"; awk -F'\t' -v OFS='\t' 'NR == 5 { NF = 23 } { print }' "$T/s" > "$T/b"; expect_fail a1_check < "$T/b"
  label="A1 wifi fail mark with values"; awk -F'\t' -v OFS='\t' 'NR == 5 { $24 = 1 } { print }' "$T/s" > "$T/b"; expect_fail a1_check < "$T/b"
  label="A1 bad bins"; awk -F'\t' -v OFS='\t' 'NR == 5 { $10 = 5 } { print }' "$T/s" > "$T/b"; expect_fail a1_check < "$T/b"
  label="A1 too few rows"; head -10 "$T/s" > "$T/b"; expect_fail a1_check < "$T/b"
  label="A2 disconnected"; expect_pass sh -c "printf 'eth0:ethernet:connected\nwlan0:wifi:disconnected\n--\n802-3-ethernet\nloopback\n' | sh \"$0\" a2parse"
  label="A2 wlan0 connected"; expect_fail sh -c "printf 'eth0:ethernet:connected\nwlan0:wifi:connected\n--\n802-3-ethernet\n802-11-wireless\n' | sh \"$0\" a2parse"
  label="A2 wifi profile active"; expect_fail sh -c "printf 'wlan0:wifi:disconnected\n--\n802-11-wireless\n' | sh \"$0\" a2parse"
  label="A3 none"; expect_pass sh -c "printf 'sshd\n/bin/sh /home/pi/s52/ambient-log.sh\n' | sh \"$0\" a3parse"
  label="A3 onelife-run present"; expect_fail sh -c "printf 'sshd\n/home/pi/s51/onelife-run --x\n' | sh \"$0\" a3parse"
  rm -r "$T"
  [ $ok = 0 ] && echo "NEG PASS" || echo "NEG FAIL"
  return $ok
}

cmd=${1:-}
case "$cmd" in
  a0) if [ "${2:--}" = - ]; then a0_check; else a0_check < "$2"; fi ;;
  a1) a1_check < "$2" ;;
  a2) a2_live ;;
  a2parse) a2_parse ;;
  a3) a3_live ;;
  a3parse) a3_parse ;;
  neg) neg ;;
  *) echo "usage: $0 a0 FILE|- | a1 FILE | a2 | a3 | neg" >&2; exit 2 ;;
esac
