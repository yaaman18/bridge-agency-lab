#!/bin/sh
# S54 §1 (discussion/specs/S54-trial-run.md r2): the gates before the trial, on the Mac with the fast (fastinterval)
# test build of onelife-run built from rust/ into a work dir.
#   H1 a partial last audit line (cut 1 byte after the line's head, in its middle, just before its newline): the run
#      appends "break mismatch", goes on, ends in the state of the uninterrupted run; onelife-audit reports break 1
#   H2 the strengthened source check (raw FFI clock_gettime / gettimeofday / time(, std::process::Command, /proc/uptime);
#      passes on the current sources, catches the 5 new and the 7 old negative controls
#   H3 the birth procedure makes an empty audit: first line "start 0"; without the audit file the first line is
#      "break missing"
# Usage: sh experiments/trial/gates_h.sh    (lines appended to experiments/results-trial-gates.out)
set -eu
cd "$(dirname "$0")/../.."
OUT=experiments/results-trial-gates.out
W=$(mktemp -d "${TMPDIR:-/tmp}/s54-gates.XXXXXX")
FT=$W/fast-target; FRUN=$FT/release/onelife-run; BT=$FT/release/being-tools
SRC=rust/being-tools/src/bin/onelife-run.rs
MAIN=rust/being-tools/src/main.rs
DR=core/check/out/onelife-drives/D3.txt
touch "$OUT"
say() { echo "$*" | tee -a "$OUT"; }
fsha() { shasum -a 256 "$1" | awk '{print $1}'; }
nof() { od -An -t u8 -j 16 -N 8 "$1" | tr -d ' \n'; }
jv() { echo "$1" | sed -n "s/.*\"$2\":\([^,}]*\).*/\1/p"; }
jvs() { echo "$1" | sed -n "s/.*\"$2\":\(\[[^]]*\]\).*/\1/p"; }
say ""
say "S54 gates H1-H3, work dir $W, $(date '+%Y-%m-%d %H:%M:%S')"

# ---------- F: spec and predictions as in freeze 1 ----------
FZ=experiments/freeze-trial-run.txt
f1() { awk '/^# S54 freeze 1/ { f = 1; next } /^#/ { f = 0 } f' "$FZ" | grep " $1\$" | awk '{print $1}'; }
fs=$(f1 ../discussion/specs/S54-trial-run.md); fp=$(f1 predictions-trial-run.md)
gf=false; [ -n "$fs" ] && [ "$fs" = "$(fsha discussion/specs/S54-trial-run.md)" ] && [ -n "$fp" ] && [ "$fp" = "$(fsha experiments/predictions-trial-run.md)" ] && gf=true
say "F spec and predictions as in freeze 1: $gf"

(cd rust && cargo build --release -p being-tools --features fastinterval --target-dir "$FT") > "$W/build-fast.txt" 2>&1
nwf=$(grep -c '^warning' "$W/build-fast.txt" || true)
say "fast build: warnings $nwf; onelife-run.rs $(fsha $SRC); main.rs $(fsha $MAIN)"

# ---------- H1: a partial last audit line ----------
N=40; M=20
mkdir -p "$W/h1"
"$BT" onelife-birth-run 627 L2 "$W/h1/u"; : > "$W/h1/u.audit"
cu=0; sed -n "1,${N}p" "$DR" | "$FRUN" "$W/h1/u" > /dev/null 2>&1 || cu=$?
"$BT" onelife-birth-run 627 L2 "$W/h1/m"; : > "$W/h1/m.audit"
cm=0; sed -n "1,${M}p" "$DR" | "$FRUN" "$W/h1/m" > /dev/null 2>&1 || cm=$?
"$BT" onelife-birth-run 627 L2 "$W/h1/r39"; : > "$W/h1/r39.audit"
sed -n "1,$((N - 1))p" "$DR" | "$FRUN" "$W/h1/r39" > /dev/null 2>&1
sz=$(wc -c < "$W/h1/m.audit" | tr -d ' ')
ll=$(tail -1 "$W/h1/m.audit" | wc -c | tr -d ' ')
st=$((sz - ll))
# h1case NAME BYTES: the run at n = M with its audit cut to BYTES bytes, continued with drives M+1..N
h1case() {
  d=$W/h1/$1; mkdir -p "$d"; cp "$W/h1/m" "$d/r"; head -c "$2" "$W/h1/m.audit" > "$d/r.audit"
  pb=$("$BT" onelife-audit "$d/r")
  c=0; sed -n "$((M + 1)),${N}p" "$DR" | "$FRUN" "$d/r" > /dev/null 2> "$d/err" || c=$?
  a=$("$BT" onelife-audit "$d/r")
  same=false; cmp -s "$d/r" "$W/h1/u" && same=true
  same39=false; cmp -s "$d/r" "$W/h1/r39" && same39=true
  nb=$(grep -c 'break mismatch' "$d/r.audit" || true)
  nbl=$(grep -c '^break mismatch ' "$d/r.audit" || true)
  ok=false; [ "$c" = 0 ] && [ "$(nof "$d/r")" = $N ] && [ "$same" = true ] && [ "$(jv "$a" breaks)" = 1 ] && [ "$(jvs "$a" break_reasons)" = '["mismatch"]' ] && ok=true
  echo "H1 $1 (audit cut to $2 of $sz bytes; last line starts at $st, $ll bytes): before {\"partial_last_line\":$(jv "$pb" partial_last_line),\"chain_ok\":$(jv "$pb" chain_ok)}; run exit $c, n $(nof "$d/r"), end = uninterrupted $same (= the 39-drive state $same39); 'break mismatch' in the audit $nb (at a line's head $nbl); after {\"lines\":$(jv "$a" lines),\"chain_ok\":$(jv "$a" chain_ok),\"chain_failures\":$(jv "$a" chain_failures),\"breaks\":$(jv "$a" breaks),\"break_reasons\":$(jvs "$a" break_reasons),\"starts\":$(jv "$a" starts),\"commits\":$(jv "$a" commits),\"run_vs_last_commit\":$(jv "$a" run_vs_last_commit)} -> $ok" > "$d/row"
  echo "$ok" > "$d/ok"
}
h1case head1 $((st + 1))
h1case middle $((st + ll / 2))
h1case before_newline $((sz - 1))
h1case uncut "$sz"
h1=true
for k in head1 middle before_newline; do say "$(cat "$W/h1/$k/row")"; [ "$(cat "$W/h1/$k/ok")" = true ] || h1=false; done
say "$(cat "$W/h1/uncut/row")"
# negative controls: the uncut audit (no break, the condition must be false); the end compared with the 39-drive state
neg1=false; [ "$(cat "$W/h1/uncut/ok")" = false ] && neg1=true
neg2=false; cmp -s "$W/h1/head1/r" "$W/h1/r39" || neg2=true
[ "$cu" = 0 ] && [ "$cm" = 0 ] || h1=false
[ "$neg1" = true ] && [ "$neg2" = true ] || h1=false
say "H1: $h1 (uninterrupted exit $cu, to n = $M exit $cm; negative controls: uncut audit fails the condition $neg1, end against the 39-drive state differs $neg2)"

# ---------- H2: the strengthened source check ----------
# the S49c I1 check (copied from experiments/onelife_rust_audit_check.sh, unchanged)
PAT='std::env|env::|SystemTime|Instant|(^|[^A-Za-z0-9_])rand([^A-Za-z0-9_]|$)|std::net|TcpStream|UdpSocket|getenv|env!|option_env!'
LPAT='read\(true\)|read_to_end|read_to_string|fs::read\(&?lp|File::open\(&?lp|fs::read_to'
OKOUT='let mut audit = match Audit::open\(path\) \{$|if let Err\(e\) = audit\.log\(&format!\("(start|wait|begin|end|commit) [^"]*"[^;]*\)\) \{$|return stop\(&mut audit, n, E_[A-Z]+\);$'
INBAD='onelife::|step\(|run_encode|replace\(|(^|[^A-Za-z0-9_])s2([^A-Za-z0-9_]|$)|saves|payload|crash'
src1() {
  f=$1
  sed 's/std::env::args()//g' "$f" | grep -nE "$PAT" | sed 's/^/forbidden:/' || true
  grep -vE '^ *//' "$f" > "$W/code.rs"
  grep -oE '[A-Za-z0-9_:]*time::[A-Za-z_]+' "$W/code.rs" | grep -vx 'std::time::Duration' | sed 's/^/time:/' || true
  grep -oE 'thread::[^;]*' "$W/code.rs" | grep -vx 'thread::sleep(INTERVAL)' | sed 's/^/thread:/' || true
  [ "$(grep -o 'thread::sleep(INTERVAL)' "$f" | wc -l | tr -d ' ')" = 1 ] || echo "sleep:count"
  [ "$(grep -o 'std::env::args()' "$f" | wc -l | tr -d ' ')" = 1 ] || echo "args:count"
  grep -nE "$LPAT" "$f" | sed 's/^/lockread:/' || true
  [ "$(grep -oE 'std::fs::read\([^)]*\)' "$f" | sort | tr '\n' ' ')" = 'std::fs::read(&ap) std::fs::read(path) ' ] || echo "fsread:targets"
  [ "$(grep -c '^// ---- audit begin' "$f")" = 1 ] && [ "$(grep -c '^// ---- audit end' "$f")" = 1 ] || echo "region:markers"
  sed '/^\/\/ ---- audit begin/,/^\/\/ ---- audit end/d' "$f" > "$W/outside.rs"
  sed -n '/^\/\/ ---- audit begin/,/^\/\/ ---- audit end/p' "$f" > "$W/inside.rs"
  grep -nE 'tail|chain_tail|audit_line|GENESIS' "$W/outside.rs" | grep -vE '^[0-9]+: *//' | sed 's/^/outside-tail:/' || true
  grep -nE 'audit|Audit' "$W/outside.rs" | grep -vE '^[0-9]+: *//' | sed 's/^[0-9]*: *//' | grep -vE "$OKOUT" | sed 's/^/outside-use:/' || true
  grep -nE "$INBAD" "$W/inside.rs" | grep -vE '^[0-9]+: *//' | sed 's/^/inside-state:/' || true
  [ "$(grep -c 'fn log(&mut self, record: &str) -> Result<(), String> {' "$W/inside.rs")" = 1 ] || echo "log:signature"
}
# the strengthening (S54 H2): no clock or uptime reading by FFI, no other process, no /proc; the only foreign function
# block is the one of flock, with that one declaration
CPAT='clock_gettime|gettimeofday|(^|[^A-Za-z0-9_])time *\(|process::Command|Command::|(^|[^A-Za-z0-9_])Command([^A-Za-z0-9_]|$)|/proc|uptime|libc|#\[link|asm!|syscall|dlsym|(^|[^A-Za-z0-9_])mach_|sysctl|rdtsc|cntvct'
FFIOK='extern "C" {
    fn flock(fd: i32, operation: i32) -> i32;
}'
src2() {
  f=$1
  src1 "$f"
  grep -vE '^ *//' "$f" | grep -nE "$CPAT" | sed 's/^/clock:/' || true
  [ "$(grep -c 'extern' "$f")" = 1 ] || echo "extern:count"
  [ "$(sed -n '/^extern "C" {$/,/^}$/p' "$f")" = "$FFIOK" ] || echo "extern:block"
}
# being-tools main.rs: the module of the onelife tools (onelife-info, onelife-audit, used by the wrapper and the watch)
src2main() {
  sed -n '/^mod onelife_tools {$/,$p' "$1" > "$W/mainmod.rs"
  [ -s "$W/mainmod.rs" ] || echo "main:module"
  grep -vE '^ *//' "$W/mainmod.rs" | grep -nE "$CPAT|SystemTime|Instant|std::env|env::|getenv|extern|std::net|TcpStream|UdpSocket" | sed 's/^/main-clock:/' || true
}
b2=$(src2 "$SRC"); bm=$(src2main "$MAIN")
mkdir -p "$W/neg"
neg() { cp "$SRC" "$W/neg/$1.rs"; }
neg a; echo 'fn _x() { let _ = std::env::var("X"); }' >> "$W/neg/a.rs"
neg b; echo 'fn _x() -> std::time::Instant { std::time::Instant::now() }' >> "$W/neg/b.rs"
neg c; echo 'fn _z(a: &Audit) -> u64 { a.tail.len() as u64 }' >> "$W/neg/c.rs"
neg d; perl -pe 's|^// ---- audit end ----$|fn _w(s: &onelife::OneLife) -> bool { s.dead }\n// ---- audit end ----|' "$SRC" > "$W/neg/d.rs"
neg e; echo 'fn _y(lp: &Path) { let _ = std::fs::read(lp); }' >> "$W/neg/e.rs"
neg f; echo 'fn _v() { std::thread::sleep(Duration::from_secs(1)); }' >> "$W/neg/f.rs"
neg g; sed 's|^        n += 1;$|        n += audit.tail.len() as u64 * 0 + 1;|' "$SRC" > "$W/neg/g.rs"
neg h; printf '%s\n' 'extern "C" {' '    fn clock_gettime(clk: i32, ts: *mut [i64; 2]) -> i32;' '}' 'fn _h() -> i64 { let mut t = [0i64; 2]; unsafe { clock_gettime(1, &mut t) }; t[0] }' >> "$W/neg/h.rs"
neg i; perl -pe 's|^    fn flock\(fd: i32, operation: i32\) -> i32;$|    fn flock(fd: i32, operation: i32) -> i32;\n    fn gettimeofday(tv: *mut [i64; 2], tz: *mut u8) -> i32;|' "$SRC" > "$W/neg/i.rs"
neg j; printf '%s\n' 'extern "C" {' '    fn time(t: *mut i64) -> i64;' '}' 'fn _j() -> i64 { unsafe { time(std::ptr::null_mut()) } }' >> "$W/neg/j.rs"
neg k; echo 'fn _k() -> bool { std::process::Command::new("date").status().is_ok() }' >> "$W/neg/k.rs"
neg l; echo 'fn _l() -> usize { let mut f = std::fs::File::open("/proc/uptime").unwrap(); let mut b = [0u8; 64]; std::io::Read::read(&mut f, &mut b).unwrap() }' >> "$W/neg/l.rs"
cp "$MAIN" "$W/neg/m.rs"; echo 'fn _m() -> std::time::Instant { std::time::Instant::now() }' >> "$W/neg/m.rs"
ncaught=0; nold=0; negrows=""
for k in a b c d e f g h i j k l; do
  r=$(src2 "$W/neg/$k.rs" | head -1); o=$(src1 "$W/neg/$k.rs" | head -1)
  dif=$(diff "$SRC" "$W/neg/$k.rs" | grep -c '^[<>]' || true)
  if [ -n "$r" ] && [ "$dif" -ge 1 ]; then ncaught=$((ncaught + 1)); fi
  case $k in h|i|j|k|l) if [ -n "$o" ]; then nold=$((nold + 1)); fi ;; esac
  negrows="$negrows $k:[$r]"
  case $k in h|i|j|k|l) negrows="$negrows(S49c check: [$o])" ;; esac
done
rm1=$(src2main "$W/neg/m.rs" | head -1)
mcaught=false; [ -n "$rm1" ] && mcaught=true
h2=false; [ -z "$b2" ] && [ -z "$bm" ] && [ "$ncaught" = 12 ] && [ "$mcaught" = true ] && h2=true
say "H2 sources: onelife-run.rs findings '$(echo $b2)'; main.rs onelife_tools module findings '$(echo $bm)'; negative controls caught $ncaught of 12 (old a-g; new h clock_gettime FFI, i gettimeofday in the flock block, j time( FFI, k std::process::Command, l File::open /proc/uptime); the S49c check alone catches $nold of the 5 new; main.rs control (Instant) caught $mcaught:$negrows m:[$rm1]"
say "H2: $h2"

# ---------- H3: the birth procedure makes an empty audit ----------
mkdir -p "$W/h3"
"$BT" onelife-birth-run 627 L2 "$W/h3/e"; : > "$W/h3/e.audit"
"$BT" onelife-birth-run 627 L2 "$W/h3/x"
ce=0; sed -n 1,3p "$DR" | "$FRUN" "$W/h3/e" > /dev/null 2>&1 || ce=$?
cx=0; sed -n 1,3p "$DR" | "$FRUN" "$W/h3/x" > /dev/null 2>&1 || cx=$?
fe=$(head -1 "$W/h3/e.audit" | awk '{print $1, $2}'); fx=$(head -1 "$W/h3/x.audit" | awk '{print $1, $2}')
sx=$(sed -n 2p "$W/h3/x.audit" | awk '{print $1, $2}')
ae=$("$BT" onelife-audit "$W/h3/e"); ax=$("$BT" onelife-audit "$W/h3/x")
same=false; cmp -s "$W/h3/e" "$W/h3/x" && same=true
ok_e=false; [ "$ce" = 0 ] && [ "$fe" = "start 0" ] && [ "$(jv "$ae" breaks)" = 0 ] && [ "$(jv "$ae" chain_ok)" = true ] && ok_e=true
ok_x=false; [ "$cx" = 0 ] && [ "$fx" = "break missing" ] && [ "$sx" = "start 0" ] && [ "$(jv "$ax" breaks)" = 1 ] && ok_x=true
# negative control: the two first lines are told apart (each condition fails on the other audit)
negx=false; [ "$fx" != "start 0" ] && [ "$fe" != "break missing" ] && negx=true
h3=false; [ "$ok_e" = true ] && [ "$ok_x" = true ] && [ "$negx" = true ] && [ "$same" = true ] && h3=true
say "H3 birth with an empty audit: exit $ce, first line '$fe', breaks $(jv "$ae" breaks), chain_ok $(jv "$ae" chain_ok) -> $ok_e; without the audit file: exit $cx, first line '$fx', second '$sx', breaks $(jv "$ax" breaks) -> $ok_x; run files the same $same; negative control (each first line fails the other's condition) $negx"
say "H3: $h3"
all=false; [ "$gf" = true ] && [ "$nwf" = 0 ] && [ "$h1" = true ] && [ "$h2" = true ] && [ "$h3" = true ] && all=true
say "gates F H1 H2 H3: $gf $h1 $h2 $h3 (fast build warnings $nwf) -> $all ($(date '+%Y-%m-%d %H:%M:%S'))"
if [ "$all" = true ]; then exit 0; fi
exit 1
