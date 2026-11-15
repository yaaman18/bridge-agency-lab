#!/bin/sh
# S54 §4 (discussion/specs/S54-trial-run.md r4): the read-only watch of the trial, from the Mac (claude-lab runs it
# hourly; it does not loop by itself). On the Pi it only reads: one copy of each run file (one "cat", so n and the SHA
# come from the same version), vcgencmd get_throttled, systemctl is-active, the boot id, the ext4 errors in the
# kernel log that remains (sudo -n dmesg), and the filesystem state and error count (sudo -n tune2fs -l, read only).
# It never stops, starts or writes anything on the Pi.
# On the Mac, n and the payload SHA are read from the copy (being-tools onelife-info) and compared with the reference
# line of that n; one row is appended to OUT.
# Usage: sh experiments/trial/watch.sh BEING_TOOLS [trial|rehearsal [OUT]]
#   trial (default): lives t1 (unit s54-trial-1, reference 669-L2) and t2 (s54-trial-2, 669-L2SF) in /home/pi/s54;
#     OUT default experiments/s54-watch.tsv
#   rehearsal: the life in /home/pi/s54/rehearsal (unit s54-rehearsal, reference 627-L2-D1);
#     OUT default experiments/s54-rehearsal-watch.tsv
# Columns: mac_time mac_epoch boot_id throttled ext4_errors fs_state fs_errors, then per life:
#   unit n payload_sha ref_match copy_sha256
set -eu
cd "$(dirname "$0")/../.."
[ $# -ge 1 ] || { echo "usage: watch.sh BEING_TOOLS [trial|rehearsal [OUT]]"; exit 2; }
BT=$1; MODE=${2:-trial}
case $MODE in
  trial) LIVES="t1:s54-trial-1:669-L2 t2:s54-trial-2:669-L2SF"; OUT=${3:-experiments/s54-watch.tsv} ;;
  rehearsal) LIVES="rehearsal:s54-rehearsal:627-L2-D1"; OUT=${3:-experiments/s54-rehearsal-watch.tsv} ;;
  *) echo "watch.sh: mode $MODE"; exit 2 ;;
esac
BASE=/home/pi/s54
HOST=pi@bridge-pi.local
D=experiments/trial-data
W=$(mktemp -d "${TMPDIR:-/tmp}/s54-watch.XXXXXX")
pis() { ssh -o BatchMode=yes -o ConnectTimeout=20 "$HOST" "$@"; }
fsha() { shasum -a 256 "$1" | awk '{print $1}'; }
if [ ! -s "$OUT" ]; then
  h='mac_time\tmac_epoch\tboot_id\tthrottled\text4_errors\tfs_state\tfs_errors'
  for l in $LIVES; do t=${l%%:*}; h="$h\t${t}_unit\t${t}_n\t${t}_sha\t${t}_ref_match\t${t}_copy_sha256"; done
  printf "$h\n" >> "$OUT"
fi
mt=$(date '+%Y-%m-%dT%H:%M:%S%z'); me=$(date +%s)
sys=$(pis 'cat /proc/sys/kernel/random/boot_id; vcgencmd get_throttled | sed "s/^throttled=//"; sudo -n dmesg 2> /dev/null | grep -ci "ext4-fs error" || true; sudo -n tune2fs -l /dev/mmcblk0p2 2> /dev/null | sed -n "s/^Filesystem state: *//p"; sudo -n tune2fs -l /dev/mmcblk0p2 2> /dev/null | sed -n "s/^FS Error count: *//p" | grep . || echo 0' 2> /dev/null || echo "unreachable")
boot=$(echo "$sys" | sed -n 1p); thr=$(echo "$sys" | sed -n 2p); ext=$(echo "$sys" | sed -n 3p)
fst=$(echo "$sys" | sed -n 4p | tr ' ' '_'); fer=$(echo "$sys" | sed -n 5p)
row="$mt	$me	$boot	${thr:-?}	${ext:-?}	${fst:-?}	${fer:-?}"
for l in $LIVES; do
  t=${l%%:*}; r=${l#*:}; unit=${r%%:*}; ref=${r#*:}
  u=$(pis "systemctl is-active $unit 2> /dev/null || true" 2> /dev/null || echo unreachable)
  c=ok; pis "cat $BASE/$t/run" > "$W/$t" 2> /dev/null || c=fail
  n=-; s=-; m=-; cs=-
  if [ "$c" = ok ]; then
    cs=$(fsha "$W/$t")
    i=$("$BT" onelife-info "$W/$t" 2> /dev/null || true)
    n=$(echo "$i" | sed -n 's/^{"n":\([0-9]*\),.*/\1/p'); s=$(echo "$i" | sed -n 's/.*"payload_sha":"\([0-9a-f]*\)".*/\1/p')
    rs=$(awk -v n="$n" '$1 == n { print $2 }' "$D/ref-$ref.sha")
    m=false; [ -n "$n" ] && [ -n "$s" ] && [ "$s" = "$rs" ] && m=true
  fi
  row="$row	$u	${n:--}	${s:--}	$m	$cs"
done
printf '%s\n' "$row" >> "$OUT"
printf '%s\n' "$row"
