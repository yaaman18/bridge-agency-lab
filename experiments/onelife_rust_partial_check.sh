#!/bin/sh
# S49d (discussion/specs/S49d-partial-line.md r2; predictions experiments/predictions-rust-onelife-d.md PD1-PD5): an audit
# whose last line has no newline gets one newline before its "break mismatch" line (onelife-run, Audit::open only).
# Plan B of the S-R: PI1 and PI3-PI6 of S49c re-run with the S49d build (their logic copied from
# experiments/onelife_rust_audit_check.sh, which is not changed); PI2 replaced by PD2 (byte identity of run files and
# audits between the S49c build, commit 46680d1, and the S49d build for audits that end in a newline, empty or missing).
# Usage (from anywhere):
#   sh experiments/onelife_rust_partial_check.sh gates   gates F, I0 (with sh core/check/run.sh), I1 (with H2), I2, I3
#   sh experiments/onelife_rust_partial_check.sh smoke   the gates, then all PDs on one life with a short drive (N = 40)
#   sh experiments/onelife_rust_partial_check.sh         the gates, then PD1-PD5 on the 8 lives (seeds 627-628 x L2, L2+SF
#                                                        x D1, D3); lines appended to experiments/results-rust-onelife-d.out
# Gate I3: the source diff against 46680d1 is only the newline branch in Audit::open (and the file's doc comment).
# PD5 uses a full HFS+ disk image (hdiutil, no root) so that the newline itself cannot be written.
set -eu
cd "$(dirname "$0")/.."
LAB=$PWD
MODE=${1:-full}
W=$(mktemp -d "${TMPDIR:-/tmp}/onelife-partial.XXXXXX")
BT=$PWD/rust/target/release/being-tools
RUN=$PWD/rust/target/release/onelife-run
FT=$W/fast-target; FRUN=$FT/release/onelife-run
CT=$W/crash-target; CRUN=$CT/release/onelife-run
CREV=46680d1
CFT=$W/c-fast-target; CFRUN=$CFT/release/onelife-run
CCT=$W/c-crash-target; CCRUN=$CCT/release/onelife-run
OLDREV=d5a7f6d
OT=$W/old-target; ORUN=$OT/release/onelife-run
SRC=rust/being-tools/src/bin/onelife-run.rs
MAIN=rust/being-tools/src/main.rs
GEN=0000000000000000000000000000000000000000000000000000000000000000
case "$MODE" in
  full) OUT=experiments/results-rust-onelife-d.out; N=10000; N0=1999; K=20
        LIVES="627:L2:D1 627:L2:D3 627:L2+SF:D1 627:L2+SF:D3 628:L2:D1 628:L2:D3 628:L2+SF:D1 628:L2+SF:D3" ;;
  smoke) OUT=$W/smoke.out; N=40; N0=10; K=20; LIVES="627:L2:D1" ;;
  gates) OUT=$W/gates.out; N=40; N0=10; K=20; LIVES="627:L2:D1" ;;
  *) echo "usage: onelife_rust_partial_check.sh [gates|smoke]"; exit 2 ;;
esac
H=$((N / 2))
touch "$OUT"
say() { echo "$*" | tee -a "$OUT"; }
nof() { od -An -t u8 -j 16 -N 8 "$1" | tr -d ' \n'; }
psha() { "$BT" onelife-info "$1" | sed 's/.*"payload_sha":"\([0-9a-f]*\)".*/\1/'; }
fsha() { shasum -a 256 "$1" | awk '{print $1}'; }
shaat() { awk -v n="$2" '$1 == n { print $2 }' "$1"; }
jv() { echo "$1" | sed -n "s/.*\"$2\":\([^,}]*\).*/\1/p"; }
jvs() { echo "$1" | sed -n "s/.*\"$2\":\(\[[^]]*\]\).*/\1/p"; }
now() { perl -MTime::HiRes=time -e 'printf "%.3f", time'; }
say "S49d partial-line check, mode $MODE, work dir $W, $(date '+%Y-%m-%d %H:%M:%S')"
say "note: PD1 is judged in its r3 form, written after a smoke run on one life (627-L2-D1, N = 40); this run is a confirmation of its generalisation and does not cancel the miss of r2's PD1 (exactly 1 malformed line at all three cuts; the cut just before the newline gives 0)"

# ---------- F: the freeze ----------
FZ=experiments/freeze-rust-onelife-d.txt
f1v() { awk '/^# S49d freeze 3/ { f = 1; next } /^#/ { f = 0 } f' "$FZ" | grep " $1\$" | awk '{print $1}'; }
fs=$(f1v ../discussion/specs/S49d-partial-line.md); fp=$(f1v predictions-rust-onelife-d.md)
f1=false; [ -n "$fs" ] && [ "$fs" = "$(fsha discussion/specs/S49d-partial-line.md)" ] && [ -n "$fp" ] && [ "$fp" = "$(fsha experiments/predictions-rust-onelife-d.md)" ] && f1=true
CF=experiments/freeze-rust-onelife-d-code.txt
cfn=0; cfok=0
if [ -f "$CF" ]; then
  while read -r h p; do
    case "$h" in ''|'#'*) continue ;; esac
    cfn=$((cfn + 1)); [ "$(fsha "experiments/$p")" = "$h" ] && cfok=$((cfok + 1))
  done < "$CF"
fi
fg=$f1
if [ "$MODE" = full ]; then
  if [ "$cfn" = 0 ] || [ "$cfok" != "$cfn" ]; then fg=false; fi
fi
say "F freeze: spec r3 and predictions r3 as in freeze 3 $f1; code freeze $CF files $cfn, matching $cfok (required in the full mode) -> $fg"

# ---------- I0 (PD4): builds without warnings; being-core and core/ unchanged; sh core/check/run.sh ----------
(cd rust && cargo build --release -p being-tools) > "$W/build.txt" 2>&1
(cd rust && cargo build --release -p being-tools --features fastinterval --target-dir "$FT") > "$W/build-fast.txt" 2>&1
(cd rust && cargo build --release -p being-tools --features crashpoint,fastinterval --target-dir "$CT") > "$W/build-crash.txt" 2>&1
nw=$(grep -c '^warning' "$W/build.txt" || true)
nwf=$(grep -c '^warning' "$W/build-fast.txt" || true)
nwc=$(grep -c '^warning' "$W/build-crash.txt" || true)
ndeps=$(cd rust && cargo tree -p being-core -e normal --prefix none | sort -u | wc -l | tr -d ' ')
ncore=0
for f in onelife.rs matter.rs fdexp.rs sha256.rs; do
  want=$(grep " \.\./rust/being-core/src/$f\$" experiments/freeze-rust-onelife-c-code.txt | awk '{print $1}')
  [ -n "$want" ] && [ "$(fsha rust/being-core/src/$f)" = "$want" ] && ncore=$((ncore + 1))
done
crs=0; sh core/check/run.sh > "$W/runsh.txt" 2>&1 || crs=$?
gcore=$(git diff --name-only "$CREV" -- core rust/being-core | wc -l | tr -d ' ')
ucore=$(git status --porcelain -- core rust/being-core | wc -l | tr -d ' ')
i0=false; [ "$nw" = 0 ] && [ "$nwf" = 0 ] && [ "$nwc" = 0 ] && [ "$ndeps" = 1 ] && [ "$ncore" = 4 ] && [ "$crs" = 0 ] && [ "$gcore" = 0 ] && [ "$ucore" = 0 ] && i0=true
say "I0 build: warnings $nw (fastinterval build $nwf, crashpoint+fastinterval build $nwc); being-core crates in its tree $ndeps; being-core files with the S49 sha $ncore of 4; files of core/ and rust/being-core differing from $CREV $gcore, changed or new in the work tree $ucore; sh core/check/run.sh exit $crs ($W/runsh.txt) -> $i0"

# ---------- I1: the sources, the S49c check strengthened as gate H2 of S54 (copied from experiments/trial/gates_h.sh) ----------
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
ncaught=0; negrows=""
for k in a b c d e f g h i j k l; do
  r=$(src2 "$W/neg/$k.rs" | head -1)
  dif=$(diff "$SRC" "$W/neg/$k.rs" | grep -c '^[<>]' || true)
  if [ -n "$r" ] && [ "$dif" -ge 1 ]; then ncaught=$((ncaught + 1)); fi
  negrows="$negrows $k:[$r]"
done
rm1=$(src2main "$W/neg/m.rs" | head -1)
mcaught=false; [ -n "$rm1" ] && mcaught=true
i1=false; [ -z "$b2" ] && [ -z "$bm" ] && [ "$ncaught" = 12 ] && [ "$mcaught" = true ] && i1=true
say "I1 sources (S49c I1 with the S54 H2 strengthening): onelife-run.rs findings '$(echo $b2)'; main.rs onelife_tools module findings '$(echo $bm)'; negative controls caught $ncaught of 12, main.rs control caught $mcaught:$negrows m:[$rm1] -> $i1"

# ---------- I2: no fastinterval or crashpoint path in the production build (as S49c) ----------
m0=$(strings "$RUN" | grep -c ONELIFE-CRASHPOINT || true)
m1=$(strings "$CRUN" | grep -c ONELIFE-CRASHPOINT || true)
ndef=$(grep -cE '^default *=' rust/being-tools/Cargo.toml || true)
ncf=$(grep -c '^#\[cfg(feature = "fastinterval")\]$' "$SRC" || true)
ncn=$(grep -c '^#\[cfg(not(feature = "fastinterval"))\]$' "$SRC" || true)
nfa=$(grep -c 'fastinterval' "$SRC" || true)
mkdir -p "$W/i2"
cp rust/being-tools/Cargo.toml "$W/i2/Cargo.toml"; echo 'default = ["fastinterval"]' >> "$W/i2/Cargo.toml"
negdef=false; [ "$(grep -cE '^default *=' "$W/i2/Cargo.toml")" != 0 ] && negdef=true
"$BT" onelife-birth-run 627 L2 "$W/i2/p"; "$BT" onelife-birth-run 627 L2 "$W/i2/f"; "$BT" onelife-birth-run 627 L2 "$W/i2/c"
cc=0; echo "3 2" | "$RUN" "$W/i2/p" --crash 1 1 > /dev/null 2>&1 || cc=$?
ccn=$(nof "$W/i2/p")
t0=$(now); cp0=0; echo "3 2" | "$RUN" "$W/i2/p" > /dev/null 2>&1 || cp0=$?; t1=$(now)
tf0=$(now); cf0=0; echo "3 2" | "$FRUN" "$W/i2/f" > /dev/null 2>&1 || cf0=$?; tf1=$(now)
ck=0; (echo "3 2" | "$CRUN" "$W/i2/c" --crash 1 1 > /dev/null 2>&1) 2> /dev/null || ck=$?
dp=$(echo "$t1 - $t0" | bc); df=$(echo "$tf1 - $tf0" | bc)
slow=$(echo "$dp >= 10" | bc); fast=$(echo "$df < 1" | bc)
i2=false; [ "$m0" = 0 ] && [ "$m1" -ge 1 ] && [ "$ndef" = 0 ] && [ "$ncf" = 1 ] && [ "$ncn" = 1 ] && [ "$cc" = 2 ] && [ "$ccn" = 0 ] && [ "$cp0" = 0 ] && [ "$slow" = 1 ] && [ "$cf0" = 0 ] && [ "$fast" = 1 ] && [ "$ck" = 134 ] && [ "$negdef" = true ] && i2=true
say "I2 production build: crash marker $m0 (crashpoint build $m1); default features in Cargo.toml $ndef (negative control caught $negdef); cfg lines fastinterval $ncf / not $ncn (lines naming it $nfa); --crash 1 1 refused with exit $cc, n $ccn; one drive in ${dp} s exit $cp0 (fast build ${df} s exit $cf0; crashpoint build --crash 1 1 exit $ck) -> $i2"

# ---------- I3: the source diff against the S49c build is only the newline branch in Audit::open ----------
git show "$CREV:$SRC" > "$W/old-onelife-run.rs"
oldwant=$(grep ' \.\./rust/being-tools/src/bin/onelife-run.rs$' experiments/freeze-rust-onelife-c-code.txt | awk '{print $1}')
oldsha=false; [ "$(fsha "$W/old-onelife-run.rs")" = "$oldwant" ] && oldsha=true
# openrange FILE: the first and last line numbers of Audit::open
openrange() { awk '/^    fn open\(path: &Path\) -> Result<Audit, String> \{$/ { a = NR } a && !b && NR > a && /^    }$/ { b = NR } END { print a + 0, b + 0 }' "$1"; }
# diffcheck OLD NEW: one line per changed line that is neither a doc comment line nor inside Audit::open
diffcheck() {
  set -- "$1" "$2" $(openrange "$1") $(openrange "$2")
  [ "$3" -gt 0 ] && [ "$4" -gt "$3" ] && [ "$5" -gt 0 ] && [ "$6" -gt "$5" ] || echo "open:range"
  # the normal diff output: a hunk header "a[,b]{a|c|d}c[,d]", then "< " old lines and "> " new lines in order
  diff "$1" "$2" | awk -v oa="$3" -v ob="$4" -v na="$5" -v nb="$6" '
    /^[0-9]/ { h = $0; sub(/[acd].*/, "", h); split(h, o, ","); m = $0; sub(/^[0-9,]*[acd]/, "", m); split(m, q, ","); on = o[1]; nn = q[1]; next }
    /^---$/ { next }
    /^< / { t = substr($0, 3); ln = on++; if (t ~ /^\/\/!/ || (ln >= oa && ln <= ob)) next; print "outside:O " ln " " t; next }
    /^> / { t = substr($0, 3); ln = nn++; if (t ~ /^\/\/!/ || (ln >= na && ln <= nb)) next; print "outside:N " ln " " t; next }
    { print "unparsed:" $0 }' || true
  [ "$(grep -c 'write_all(b"\\n")' "$1")" = 0 ] || echo "old:newline-write"
  [ "$(grep -c 'write_all(b"\\n")' "$2")" = 1 ] || echo "new:newline-write-count"
  set -- $(openrange "$2") "$2"
  [ "$(sed -n "$1,$2p" "$3" | grep -c 'write_all(b"\\n")')" = 1 ] || echo "new:newline-write-outside-open"
}
d3=$(diffcheck "$W/old-onelife-run.rs" "$SRC")
nchg=$(diff "$W/old-onelife-run.rs" "$SRC" | grep -c '^[<>]' || true)
others=$(git diff --name-only "$CREV" -- rust | grep -vx "$SRC" | tr '\n' ' ' || true)
untr=$(git status --porcelain --untracked-files=all -- rust | grep -v " $SRC\$" | tr '\n' ' ' || true)
sed 's|^const E_AUDIT: i32 = 10;$|const E_AUDIT: i32 = 11;|' "$SRC" > "$W/neg/i3a.rs"
perl -pe 's|^        let body = format!\("\{\} \{\}", record, self.tail\);$|        let body = format!("{} {}", record, self.tail);\n        let _ = 0;|' "$SRC" > "$W/neg/i3b.rs"
perl -pe 's|^            if nl \{$|            if !nl {|' "$SRC" > "$W/neg/i3c.rs"
n3a=$(diffcheck "$W/old-onelife-run.rs" "$W/neg/i3a.rs" | head -1); n3b=$(diffcheck "$W/old-onelife-run.rs" "$W/neg/i3b.rs" | head -1)
n3c=$(diffcheck "$W/old-onelife-run.rs" "$W/neg/i3c.rs" | head -1)
d3a=$(diff "$SRC" "$W/neg/i3a.rs" | grep -c '^[<>]' || true); d3b=$(diff "$SRC" "$W/neg/i3b.rs" | grep -c '^[<>]' || true); d3c=$(diff "$SRC" "$W/neg/i3c.rs" | grep -c '^[<>]' || true)
neg3=false; [ -n "$n3a" ] && [ -n "$n3b" ] && [ "$d3a" -ge 1 ] && [ "$d3b" -ge 1 ] && neg3=true
i3=false; [ "$oldsha" = true ] && [ -z "$d3" ] && [ -z "$others" ] && [ -z "$untr" ] && [ "$neg3" = true ] && i3=true
say "I3 diff against $CREV: old onelife-run.rs as in freeze-rust-onelife-c-code $oldsha; changed lines $nchg; findings '$(echo $d3)'; other files in rust/ differing '$others', changed or untracked '$untr'; negative controls: E_AUDIT changed [$n3a], a line added in log [$n3b] caught $neg3 (the condition inverted inside open, not a diff finding by design: [$n3c], $d3c lines) -> $i3"

if [ "$f1" != true ] || [ "$fg" != true ] || [ "$i0" != true ] || [ "$i1" != true ] || [ "$i2" != true ] || [ "$i3" != true ]; then
  say "gates not all true: the PDs are not run ($(date '+%Y-%m-%d %H:%M:%S'))"
  exit 1
fi
if [ "$MODE" = gates ]; then say "gates done $(date '+%Y-%m-%d %H:%M:%S'); $OUT"; exit 0; fi

# ================= the S49c build (commit 46680d1) and the lives =================
mkdir -p "$W/c"
git archive "$CREV" rust | tar -x -C "$W/c"
csrc=false; [ "$(fsha "$W/c/$SRC")" = "$oldwant" ] && csrc=true
(cd "$W/c/rust" && cargo build --release -p being-tools --features fastinterval --target-dir "$CFT") > "$W/build-c-fast.txt" 2>&1
(cd "$W/c/rust" && cargo build --release -p being-tools --features crashpoint,fastinterval --target-dir "$CCT") > "$W/build-c-crash.txt" 2>&1
cbuild=false; [ "$csrc" = true ] && [ -x "$CFRUN" ] && [ -x "$CCRUN" ] && cbuild=true
say "S49c build from $CREV (git archive into the work dir): onelife-run.rs as in freeze-rust-onelife-c-code $csrc; fast and crashpoint builds $cbuild"
julia --project=. core/check/onelife_scenarios.jl drives "$W" $N
D1=$W/D1.txt; D3=$W/D3.txt
dfile() { if [ "$1" = D1 ]; then echo "$D1"; else echo "$D3"; fi; }
PTS=$(seq -s, $N0 $((N0 + K)))
for L in $LIVES; do
  seed=${L%%:*}; r=${L#*:}; law=${r%%:*}; dr=${r#*:}; tag=$seed-$law-$dr
  echo "life $seed $law $(dfile $dr) $N $W/jl-$tag $PTS" > "$W/job-$tag.txt"
  julia --project=. core/check/onelife_scenarios.jl jobs "$W/job-$tag.txt" > "$W/jl-$tag.json" &
done
wait
ref() { f=$W/ref-$1-$2; [ -f "$f" ] || "$BT" onelife-wrap "$W/jl-$1-$2.save" "$2" "$f"; echo "$f"; }
commits_ok() { awk '$1 == "commit" { print $2, $3 }' "$1" | while read -r n h; do if [ "$h" = "$(shaat "$W/jl-$2.sha" "$n")" ]; then echo ok; else echo bad; fi; done | sort | uniq -c | awk '{a[$2] = $1} END {print a["ok"] + 0, a["bad"] + 0}'; }
lastfield() { tail -1 "$1" | awk '{print $NF}'; }
forlives() { for L in $LIVES; do seed=${L%%:*}; r=${L#*:}; law=${r%%:*}; dr=${r#*:}; ( "$@" $seed $law $dr ) & done; wait; }
for L in $LIVES; do seed=${L%%:*}; r=${L#*:}; law=${r%%:*}; dr=${r#*:}; tag=$seed-$law-$dr; for p in $N0 $((N0 + 5)) $((N0 + 10)) $((N0 + K)); do ref $tag $p > /dev/null; done; done

# ================= PI1 (PD3): the interval, production build; empty, missing and newline-terminated audits =================
say "== PI1: 6 drives at once to the production onelife-run (wall time by this script), saved bytes against the $OLDREV build; audits empty, missing, newline-terminated at the start"
mkdir -p "$W/old"
git archive "$OLDREV" rust | tar -x -C "$W/old"
oldsrc=$(fsha "$W/old/rust/being-tools/src/bin/onelife-run.rs")
oldbwant=$(grep ' \.\./rust/being-tools/src/bin/onelife-run.rs$' experiments/freeze-rust-onelife-b-code.txt | awk '{print $1}')
(cd "$W/old/rust" && cargo build --release -p being-tools --target-dir "$OT") > "$W/build-old.txt" 2>&1
oldok=false; [ "$oldsrc" = "$oldbwant" ] && [ -x "$ORUN" ] && oldok=true
pi1_life() {
  seed=$1; law=$2; dr=$3; v=$4; tag=$seed-$law-$dr; df=$(dfile $dr); d=$W/pi1/$v/$tag; mkdir -p "$d"
  "$BT" onelife-birth-run $seed $law "$d/r"; "$BT" onelife-birth-run $seed $law "$d/o"
  case $v in
    empty) : > "$d/r.audit" ;;
    missing) ;;
    newline) : > "$d/r.audit"; "$FRUN" "$d/r" < /dev/null > /dev/null 2>&1 ;;
  esac
  sed -n 1,6p "$df" > "$d/in"
  t0=$(now); c=0; "$RUN" "$d/r" < "$d/in" > /dev/null 2>&1 || c=$?; t1=$(now)
  co=0; "$ORUN" "$d/o" < "$d/in" > /dev/null 2>&1 || co=$?
  same=false; cmp -s "$d/r" "$d/o" && same=true
  el=$(echo "$t1 - $t0" | bc); ge=$(echo "$el >= 60" | bc); lt=$(echo "$el < 63" | bc)
  a=$("$BT" onelife-audit "$d/r")
  case $v in
    empty) ws=1; wb=0; wr='[]' ;;
    missing) ws=1; wb=1; wr='["missing"]' ;;
    newline) ws=2; wb=0; wr='[]' ;;
  esac
  aok=false; [ "$(jv "$a" chain_ok)" = true ] && [ "$(jv "$a" starts)" = $ws ] && [ "$(jv "$a" waits)" = $((6 + ws)) ] && [ "$(jv "$a" commits)" = 6 ] && [ "$(jv "$a" ends)" = $ws ] && [ "$(jv "$a" breaks)" = $wb ] && [ "$(jvs "$a" break_reasons)" = "$wr" ] && aok=true
  ok=false; [ "$c" = 0 ] && [ "$co" = 0 ] && [ "$ge" = 1 ] && [ "$same" = true ] && [ "$(nof "$d/r")" = 6 ] && [ "$aok" = true ] && ok=true
  echo "PI1 $tag $v {\"exit\":$c,\"wall_s\":$el,\"at_least_60\":$ge,\"below_63_observation\":$lt,\"old_build_exit\":$co,\"bytes_same_as_old_build\":$same,\"audit\":{\"starts\":$(jv "$a" starts),\"waits\":$(jv "$a" waits),\"commits\":$(jv "$a" commits),\"breaks\":$(jv "$a" breaks),\"chain_ok\":$(jv "$a" chain_ok)},\"audit_counts_ok\":$aok,\"pass\":$ok}" > "$d/row"
}
for v in empty missing newline; do for L in $LIVES; do seed=${L%%:*}; r=${L#*:}; law=${r%%:*}; dr=${r#*:}; (pi1_life $seed $law $dr $v) & done; done
wait
pi1=$oldok
for v in empty missing newline; do for L in $LIVES; do
  seed=${L%%:*}; r=${L#*:}; law=${r%%:*}; dr=${r#*:}; tag=$seed-$law-$dr
  row=$(cat "$W/pi1/$v/$tag/row"); say "$row"
  echo "$row" | grep -q '"pass":true' || pi1=false
done; done
L1=${LIVES%% *}; seed=${L1%%:*}; r=${L1#*:}; law=${r%%:*}; dr=${r#*:}
"$BT" onelife-birth-run $seed $law "$W/pi1/neg"
t0=$(now); sed -n 1,6p "$(dfile $dr)" | "$FRUN" "$W/pi1/neg" > /dev/null 2>&1; t1=$(now)
eln=$(echo "$t1 - $t0" | bc); negc=$(echo "$eln < 60" | bc)
[ "$negc" = 1 ] || pi1=false
say "PI1: $pi1 (old build $OLDREV source as in freeze-rust-onelife-b-code $oldok; negative control: fast build ${eln} s, below 60 $negc)"

# ================= PD1: a partial last line =================
say "== PD1 (r3): from n = $N0, 10 drives (S49d fast build, empty audit), the audit cut inside its last line (1 byte into it, its middle, just before its newline; negative control: 2 hash bytes and the newline removed), then the drives to n = $((N0 + K)); the same cut audits with the S49c build; the uncut audit"
pd1_life() {
  seed=$1; law=$2; dr=$3; tag=$seed-$law-$dr; df=$(dfile $dr); d=$W/pd1/$tag; mkdir -p "$d"
  end=$((N0 + K)); mid=$((N0 + 10)); R=$(ref $tag $end)
  cp "$(ref $tag $N0)" "$d/m"; : > "$d/m.audit"
  c0=0; sed -n "$((N0 + 1)),${mid}p" "$df" | "$FRUN" "$d/m" > /dev/null 2>&1 || c0=$?
  sed -n "$((mid + 1)),${end}p" "$df" > "$d/in2"
  sz=$(wc -c < "$d/m.audit" | tr -d ' '); ll=$(tail -1 "$d/m.audit" | wc -c | tr -d ' '); st=$((sz - ll))
  rows=""; okall=true; negall=true
  for p in head1 middle before_newline hashcut uncut; do
    case $p in
      head1) cut=$((st + 1)) ;;
      middle) cut=$((st + ll / 2)) ;;
      before_newline) cut=$((sz - 1)) ;;
      hashcut) cut=$((sz - 3)) ;;
      uncut) cut=$sz ;;
    esac
    for b in d c; do
      e=$d/$p-$b; mkdir -p "$e"; cp "$d/m" "$e/r"; head -c "$cut" "$d/m.audit" > "$e/r.audit"; cp "$e/r.audit" "$e/cut"
      if [ $b = d ]; then X=$FRUN; else X=$CFRUN; fi
      c=0; "$X" "$e/r" < "$d/in2" > /dev/null 2>&1 || c=$?
      a=$("$BT" onelife-audit "$e/r")
      fin=false; cmp -s "$e/r" "$R" && fin=true
      # the bytes after the cut: a newline, then a line starting "break mismatch "
      pre=false; head -c "$cut" "$e/r.audit" | cmp -s - "$e/cut" && pre=true
      nlb=$(tail -c +$((cut + 1)) "$e/r.audit" | head -c 1 | od -An -c | tr -d ' ' | sed 's/^\\n$/LF/')
      nxt=$(tail -c +$((cut + 2)) "$e/r.audit" | head -1 | cut -c1-15)
      bl=$(grep -n '^break mismatch ' "$e/r.audit" | head -1 | cut -d: -f1); bl=${bl:-0}
      ff=$(jv "$a" first_failure_line)
      # r3: breaks 1 (mismatch) after a newline at all three cuts; malformed lines before the break 1 (head1, middle,
      # and the negative control hashcut: a record missing 2 hash bytes is not valid), 0 with chain_ok true (before_newline)
      okb=false; [ "$c" = 0 ] && [ "$fin" = true ] && [ "$pre" = true ] && [ "$nlb" = LF ] && [ "$nxt" = 'break mismatch ' ] && [ "$(jv "$a" breaks)" = 1 ] && [ "$(jvs "$a" break_reasons)" = '["mismatch"]' ] && [ "$bl" -ge 2 ] && okb=true
      ok=false
      case $p in
        uncut) [ "$c" = 0 ] && [ "$fin" = true ] && [ "$(jv "$a" breaks)" = 0 ] && [ "$(jv "$a" chain_ok)" = true ] && ok=true ;;
        before_newline) [ "$okb" = true ] && [ "$(jv "$a" chain_failures)" = 0 ] && [ "$(jv "$a" chain_ok)" = true ] && [ "$ff" = null ] && ok=true ;;
        *) [ "$okb" = true ] && [ "$(jv "$a" chain_failures)" = 1 ] && [ "$ff" = $((bl - 1)) ] && ok=true ;;
      esac
      if [ $b = d ]; then
        [ "$ok" = true ] || okall=false
      else
        # negative control: the S49c build on the cut audits reports breaks 0
        if [ $p != uncut ]; then [ "$(jv "$a" breaks)" = 0 ] || negall=false; fi
      fi
      rows="$rows{\"cut\":\"$p\",\"build\":\"S49$b\",\"bytes\":$cut,\"exit\":$c,\"end_same_as_uninterrupted\":$fin,\"next_byte\":\"$nlb\",\"next_line\":\"$nxt\",\"break_line\":$bl,\"audit\":{\"lines\":$(jv "$a" lines),\"chain_ok\":$(jv "$a" chain_ok),\"chain_failures\":$(jv "$a" chain_failures),\"first_failure_line\":$ff,\"breaks\":$(jv "$a" breaks),\"break_reasons\":$(jvs "$a" break_reasons)},\"condition\":$ok},"
    done
  done
  pass=false; [ "$c0" = 0 ] && [ "$okall" = true ] && [ "$negall" = true ] && pass=true
  echo "PD1 $tag {\"audit_bytes\":$sz,\"last_line_starts\":$st,\"last_line_bytes\":$ll,\"rows\":[${rows%,}],\"s49d_conditions\":$okall,\"s49c_breaks_0\":$negall,\"pass\":$pass}" > "$d/row"
}
forlives pd1_life
pd1=true
for L in $LIVES; do
  seed=${L%%:*}; r=${L#*:}; law=${r%%:*}; dr=${r#*:}; tag=$seed-$law-$dr
  row=$(cat "$W/pd1/$tag/row"); say "$row"
  echo "$row" | grep -q '"pass":true}$' || pd1=false
done
say "PD1: $pd1"

# ================= PD5: the newline cannot be written =================
say "== PD5: a partial last line, the audit not writable: (a) read-only (the open fails), (b) on a full HFS+ disk image with an audit of 8192 bytes (the newline write fails); control: the same audit writable"
pd5_life() {
  seed=$1; law=$2; dr=$3; tag=$seed-$law-$dr; df=$(dfile $dr); d=$W/pd5/$tag; mkdir -p "$d"
  cp "$(ref $tag $N0)" "$d/m"; : > "$d/m.audit"
  c0=0; sed -n "$((N0 + 1)),$((N0 + K))p" "$df" | "$FRUN" "$d/m" > /dev/null 2>&1 || c0=$?
  sed -n "$((N0 + K + 1)),$((N0 + K + 3))p" "$df" > "$d/in"
  L8=8192
  head -c $L8 "$d/m.audit" > "$d/a8192"
  lb=$(tail -c 1 "$d/a8192" | od -An -c | tr -d ' ' | sed 's/^\\n$/LF/')
  rows=""; okall=true
  # (a) read-only
  e=$d/ro; mkdir -p "$e"; cp "$d/m" "$e/r"; cp "$d/a8192" "$e/r.audit"; chmod 400 "$e/r.audit"
  ca=0; "$FRUN" "$e/r" < "$d/in" > /dev/null 2> "$e/err" || ca=$?
  chmod 600 "$e/r.audit"
  sa=false; cmp -s "$e/r" "$d/m" && sa=true; aa=false; cmp -s "$e/r.audit" "$d/a8192" && aa=true; ta=false; [ -e "$e/r.tmp" ] && ta=true
  oka=false; [ "$ca" != 0 ] && [ "$sa" = true ] && [ "$aa" = true ] && [ "$ta" = false ] && grep -q 'audit' "$e/err" && oka=true
  [ "$oka" = true ] || okall=false
  rows="$rows{\"case\":\"readonly\",\"exit\":$ca,\"run_file_unchanged\":$sa,\"audit_unchanged\":$aa,\"tmp_left\":$ta,\"message\":\"$(head -1 "$e/err" | tr -d '"' | cut -c1-80)\",\"ok\":$oka},"
  # (b) full disk image
  img=$W/pd5/$tag.dmg; mp=""
  hdiutil create -size 2m -fs HFS+ -volname "s49d-$tag" "$img" > /dev/null 2>&1 || true
  mp=$(hdiutil attach -nobrowse "$img" 2> /dev/null | awk -F'\t' '/\/Volumes\// {print $NF}' | tail -1)
  cb=x; sb=false; ab=false; tb=false; full=false; okb=false; msg=""
  if [ -n "$mp" ] && [ -d "$mp" ]; then
    cp "$d/m" "$mp/r"; : > "$mp/r.lock"; cp "$d/a8192" "$mp/r.audit"
    dd if=/dev/zero of="$mp/fill" bs=4096 > /dev/null 2>&1 || true
    dd if=/dev/zero of="$mp/fill1" bs=1 > /dev/null 2>&1 || true
    av=$(df -k "$mp" | tail -1 | awk '{print $4}'); [ "$av" = 0 ] && full=true
    cb=0; "$FRUN" "$mp/r" < "$d/in" > /dev/null 2> "$d/err-full" || cb=$?
    cmp -s "$mp/r" "$d/m" && sb=true; cmp -s "$mp/r.audit" "$d/a8192" && ab=true; [ -e "$mp/r.tmp" ] && tb=true
    msg=$(head -1 "$d/err-full" | tr -d '"' | cut -c1-80)
    hdiutil detach "$mp" > /dev/null 2>&1 || hdiutil detach -force "$mp" > /dev/null 2>&1 || true
    [ "$cb" != 0 ] && [ "$full" = true ] && [ "$sb" = true ] && [ "$ab" = true ] && [ "$tb" = false ] && echo "$msg" | grep -q 'writing the audit' && okb=true
  fi
  [ "$okb" = true ] || okall=false
  rows="$rows{\"case\":\"full_disk\",\"mounted\":\"$mp\",\"disk_full\":$full,\"exit\":$cb,\"run_file_unchanged\":$sb,\"audit_unchanged_no_newline\":$ab,\"tmp_left\":$tb,\"message\":\"$msg\",\"ok\":$okb},"
  # control: the same audit, writable
  e=$d/ctl; mkdir -p "$e"; cp "$d/m" "$e/r"; cp "$d/a8192" "$e/r.audit"
  cc=0; "$FRUN" "$e/r" < "$d/in" > /dev/null 2>&1 || cc=$?
  nb=$(tail -c +$((L8 + 1)) "$e/r.audit" | head -1 | cut -c1-15)
  ctl=false; [ "$cc" = 0 ] && [ "$(nof "$e/r")" = $((N0 + K + 3)) ] && [ "$nb" = "" ] && [ "$(tail -c +$((L8 + 2)) "$e/r.audit" | head -1 | cut -c1-15)" = 'break mismatch ' ] && ctl=true
  pass=false; [ "$c0" = 0 ] && [ "$(wc -c < "$d/m.audit" | tr -d ' ')" -gt $L8 ] && [ "$lb" != LF ] && [ "$okall" = true ] && [ "$ctl" = true ] && pass=true
  echo "PD5 $tag {\"last_byte_of_8192\":\"$lb\",\"cases\":[${rows%,}],\"control_writable_goes_on\":$ctl,\"pass\":$pass}" > "$d/row"
}
pd5=true
for L in $LIVES; do
  seed=${L%%:*}; r=${L#*:}; law=${r%%:*}; dr=${r#*:}; tag=$seed-$law-$dr
  pd5_life $seed $law $dr
  row=$(cat "$W/pd5/$tag/row"); say "$row"
  echo "$row" | grep -q '"pass":true}$' || pd5=false
done
say "PD5: $pd5"

# ================= PI3 (PD3) and PD2 on N steps: S49d and S49c builds, empty audit (uninterrupted) and missing audit (split at n = H) =================
say "== PI3 and PD2: runs of N = $N drives from birth with the S49d and the S49c fast builds: (empty) an empty audit, uninterrupted; (missing) no audit, the run cut at n = $H and started again on its newline-terminated audit, $(date '+%H:%M:%S')"
pi3_run() {
  seed=$1; law=$2; dr=$3; tag=$seed-$law-$dr; df=$(dfile $dr)
  for b in d c; do for v in empty missing; do
    d=$W/pi3-$b-$v/$tag; mkdir -p "$d"
    if [ $b = d ]; then X=$FRUN; else X=$CFRUN; fi
    "$BT" onelife-birth-run $seed $law "$d/u"
    c1=0; c2=0
    if [ $v = empty ]; then
      : > "$d/u.audit"
      sed -n "1,${N}p" "$df" | "$X" "$d/u" > /dev/null 2>&1 || c1=$?
    else
      sed -n "1,${H}p" "$df" | "$X" "$d/u" > /dev/null 2>&1 || c1=$?
      sed -n "$((H + 1)),${N}p" "$df" | "$X" "$d/u" > /dev/null 2>&1 || c2=$?
    fi
    echo "$c1 $c2" > "$d/exit"
  done; done
}
for L in $LIVES; do seed=${L%%:*}; r=${L#*:}; law=${r%%:*}; dr=${r#*:}; (pi3_run $seed $law $dr) & done
wait
pi3=true; pi3m=true; pd2a=true
for L in $LIVES; do
  seed=${L%%:*}; r=${L#*:}; law=${r%%:*}; dr=${r#*:}; tag=$seed-$law-$dr
  d=$W/pi3-d-empty/$tag; read -r c x < "$d/exit"
  a=$("$BT" onelife-audit "$d/u"); co=$(commits_ok "$d/u.audit" "$tag")
  fin=false; [ "$(psha "$d/u")" = "$(shaat "$W/jl-$tag.sha" $N)" ] && [ "$(nof "$d/u")" = $N ] && fin=true
  ok=false
  [ "$c" = 0 ] && [ "$(jv "$a" chain_ok)" = true ] && [ "$(jv "$a" starts)" = 1 ] && [ "$(jv "$a" waits)" = $((N + 1)) ] && [ "$(jv "$a" begins)" = $N ] && [ "$(jv "$a" commits)" = $N ] && [ "$(jv "$a" ends)" = 1 ] && [ "$(jv "$a" errors)" = 0 ] && [ "$(jv "$a" breaks)" = 0 ] && [ "$co" = "$N 0" ] && [ "$fin" = true ] && [ "$(jv "$a" run_vs_last_commit)" = '"match"' ] && ok=true
  first=$(head -1 "$d/u.audit" | awk '{print $1, $2, $3}')
  say "PI3 $tag empty {\"exit\":$c,\"lines\":$(jv "$a" lines),\"chain_ok\":$(jv "$a" chain_ok),\"starts\":$(jv "$a" starts),\"waits\":$(jv "$a" waits),\"begins\":$(jv "$a" begins),\"commits\":$(jv "$a" commits),\"ends\":$(jv "$a" ends),\"errors\":$(jv "$a" errors),\"breaks\":$(jv "$a" breaks),\"commits_julia_ok_bad\":\"$co\",\"final_is_julia\":$fin,\"run_vs_last_commit\":$(jv "$a" run_vs_last_commit),\"first_line\":\"$first\",\"pass\":$ok}"
  [ "$ok" = true ] || pi3=false
  d=$W/pi3-d-missing/$tag; read -r c c2 < "$d/exit"
  a=$("$BT" onelife-audit "$d/u"); co=$(commits_ok "$d/u.audit" "$tag")
  fin=false; [ "$(psha "$d/u")" = "$(shaat "$W/jl-$tag.sha" $N)" ] && [ "$(nof "$d/u")" = $N ] && fin=true
  first=$(head -1 "$d/u.audit" | awk '{print $1, $2}')
  ok=false
  [ "$c" = 0 ] && [ "$c2" = 0 ] && [ "$first" = "break missing" ] && [ "$(jv "$a" chain_ok)" = true ] && [ "$(jv "$a" starts)" = 2 ] && [ "$(jv "$a" waits)" = $((N + 2)) ] && [ "$(jv "$a" begins)" = $N ] && [ "$(jv "$a" commits)" = $N ] && [ "$(jv "$a" ends)" = 2 ] && [ "$(jv "$a" errors)" = 0 ] && [ "$(jv "$a" breaks)" = 1 ] && [ "$(jvs "$a" break_reasons)" = '["missing"]' ] && [ "$co" = "$N 0" ] && [ "$fin" = true ] && [ "$(jv "$a" run_vs_last_commit)" = '"match"' ] && ok=true
  say "PI3 $tag missing+newline {\"exits\":[$c,$c2],\"first_line\":\"$first\",\"chain_ok\":$(jv "$a" chain_ok),\"starts\":$(jv "$a" starts),\"waits\":$(jv "$a" waits),\"commits\":$(jv "$a" commits),\"ends\":$(jv "$a" ends),\"breaks\":$(jv "$a" breaks),\"break_reasons\":$(jvs "$a" break_reasons),\"commits_julia_ok_bad\":\"$co\",\"final_is_julia\":$fin,\"pass\":$ok}"
  [ "$ok" = true ] || pi3m=false
  for v in empty missing; do
    s1=false; cmp -s "$W/pi3-d-$v/$tag/u" "$W/pi3-c-$v/$tag/u" && s1=true
    s2=false; cmp -s "$W/pi3-d-$v/$tag/u.audit" "$W/pi3-c-$v/$tag/u.audit" && s2=true
    ec=$(cat "$W/pi3-c-$v/$tag/exit")
    say "PD2 $tag $v {\"run_file_same\":$s1,\"audit_same\":$s2,\"s49c_exits\":\"$ec\",\"audit_bytes\":$(wc -c < "$W/pi3-d-$v/$tag/u.audit" | tr -d ' ')}"
    [ "$s1" = true ] && [ "$s2" = true ] && [ "$ec" = "0 0" ] || pd2a=false
  done
done
tag=$seed-$law-$dr; nd=$W/pi3/neg; mkdir -p "$nd"; cp "$W/pi3-d-empty/$tag/u" "$nd/u"
perl -pe 'if (/^commit / && ++$c == 2) { s/^(commit \d+ )(.)/$1 . ($2 eq "0" ? "1" : "0")/e }' "$W/pi3-d-empty/$tag/u.audit" > "$nd/u.audit"
an=$("$BT" onelife-audit "$nd/u"); con=$(commits_ok "$nd/u.audit" "$tag")
neg1=false; [ "$(jv "$an" chain_ok)" = false ] && [ "$con" != "$N 0" ] && neg1=true
otag=$seed-$law-D3; [ "$dr" = D3 ] && otag=$seed-$law-D1
neg2=skipped
if [ -f "$W/jl-$otag.sha" ]; then cob=$(commits_ok "$W/pi3-d-empty/$tag/u.audit" "$otag"); neg2=false; [ "$cob" != "$N 0" ] && neg2=true; fi
# negative control of PD2: the changed audit is not byte-identical to the S49c build's audit
negpd2=false; cmp -s "$nd/u.audit" "$W/pi3-c-empty/$tag/u.audit" || negpd2=true
[ "$neg1" = true ] || pi3=false
[ "$neg2" = false ] && pi3=false
[ "$negpd2" = true ] || pd2a=false
say "PI3: $pi3 (negative controls on $tag: changed commit caught $neg1 (chain_ok $(jv "$an" chain_ok), commits $con); against the other drive's reference caught $neg2); missing audit and newline-terminated restart: $pi3m"
say "PD2 on N = $N: $pd2a (negative control: a changed audit differs from the S49c build's $negpd2) $(date '+%H:%M:%S')"

# ================= PI4 (PD3) and PD2: unfinished steps and stops, both builds =================
say "== PI4: from n = $N0: crash points 1-4 at the 2nd save, a SIGKILL while waiting for input, then the run to n = $((N0 + K)); S49d and S49c builds"
pi4_life() {
  seed=$1; law=$2; dr=$3; b=$4; tag=$seed-$law-$dr; df=$(dfile $dr); d=$W/pi4-$b/$tag; mkdir -p "$d"
  if [ $b = d ]; then XF=$FRUN; XC=$CRUN; else XF=$CFRUN; XC=$CCRUN; fi
  f=$d/run; cp "$(ref $tag $N0)" "$f"; : > "$f.audit"
  end=$((N0 + K)); rows=""; okall=true
  for s in 1 2 3 4; do
    n=$(nof "$f")
    c=0; sed -n "$((n + 1)),${end}p" "$df" | "$XC" "$f" --crash $s 2 > /dev/null 2>&1 || c=$?
    if [ $s -lt 4 ]; then want=$((n + 1)); else want=$((n + 2)); fi
    same=false; cmp -s "$f" "$(ref $tag $want)" && same=true
    [ "$c" = 134 ] && [ "$same" = true ] || okall=false
    rows="$rows{\"stage\":$s,\"exit\":$c,\"n\":$(nof "$f"),\"file_is_version\":$want,\"complete_version\":$same},"
  done
  n=$(nof "$f"); fifo=$W/fifo-$b-$tag; mkfifo "$fifo"
  "$XF" "$f" < "$fifo" > /dev/null 2>&1 &
  pid=$!
  exec 9> "$fifo"
  sed -n "$((n + 1)),$((n + 2))p" "$df" >&9
  i=0
  while [ $i -lt 2000 ]; do
    if [ "$(nof "$f")" = $((n + 2)) ] && tail -1 "$f.audit" | grep -q "^wait $((n + 3)) "; then break; fi
    sleep 0.05; i=$((i + 1))
  done
  kill -9 $pid 2> /dev/null || true
  ck=0; wait $pid || ck=$?
  exec 9>&-
  kn=$(nof "$f")
  [ "$ck" = 137 ] && [ "$kn" = $((n + 2)) ] || okall=false
  n=$(nof "$f")
  cr=0; sed -n "$((n + 1)),${end}p" "$df" | "$XF" "$f" > /dev/null 2>&1 || cr=$?
  fin=false; cmp -s "$f" "$(ref $tag $end)" && fin=true
  a=$("$BT" onelife-audit "$f"); co=$(commits_ok "$f.audit" "$tag")
  ok=false
  [ "$okall" = true ] && [ "$cr" = 0 ] && [ "$fin" = true ] && [ "$(jv "$a" chain_ok)" = true ] && [ "$(jv "$a" breaks)" = 0 ] && [ "$(jv "$a" starts)" = 6 ] && [ "$(jv "$a" unfinished_steps)" = 3 ] && [ "$(jv "$a" audit_behind)" = 1 ] && [ "$(jv "$a" unknown_stops)" = 1 ] && [ "$(jv "$a" stops_without_end)" = 5 ] && [ "$(jv "$a" ends)" = 1 ] && [ "$(jv "$a" errors)" = 0 ] && [ "$(jv "$a" unclassified)" = 0 ] && [ "$(jv "$a" open)" = false ] && [ "$(jv "$a" run_vs_last_commit)" = '"match"' ] && [ "${co#* }" = 0 ] && ok=true
  u=$d/u; cp "$(ref $tag $N0)" "$u"; : > "$u.audit"
  cu=0; sed -n "$((N0 + 1)),${end}p" "$df" | "$XF" "$u" > /dev/null 2>&1 || cu=$?
  au=$("$BT" onelife-audit "$u")
  ctl=false; [ "$cu" = 0 ] && [ "$(jv "$au" unfinished_steps)" = 0 ] && [ "$(jv "$au" unknown_stops)" = 0 ] && [ "$(jv "$au" stops_without_end)" = 0 ] && [ "$(jv "$au" audit_behind)" = 0 ] && cmp -s "$u" "$f" && ctl=true
  [ "$ctl" = true ] || ok=false
  echo "PI4 $tag S49$b {\"crashes\":[${rows%,}],\"kill_while_waiting_exit\":$ck,\"n_at_kill\":$kn,\"resume_exit\":$cr,\"end_same_as_uninterrupted\":$fin,\"audit\":{\"chain_ok\":$(jv "$a" chain_ok),\"breaks\":$(jv "$a" breaks),\"starts\":$(jv "$a" starts),\"unfinished_steps\":$(jv "$a" unfinished_steps),\"audit_behind\":$(jv "$a" audit_behind),\"unknown_stops\":$(jv "$a" unknown_stops),\"stops_without_end\":$(jv "$a" stops_without_end),\"ends\":$(jv "$a" ends),\"unclassified\":$(jv "$a" unclassified),\"sequence\":$(jvs "$a" sequence)},\"commits_julia_ok_bad\":\"$co\",\"control_uninterrupted_clean\":$ctl,\"pass\":$ok}" > "$d/row"
}
for b in d c; do for L in $LIVES; do seed=${L%%:*}; r=${L#*:}; law=${r%%:*}; dr=${r#*:}; (pi4_life $seed $law $dr $b) & done; done
wait
pi4=true
for L in $LIVES; do
  seed=${L%%:*}; r=${L#*:}; law=${r%%:*}; dr=${r#*:}; tag=$seed-$law-$dr
  row=$(cat "$W/pi4-d/$tag/row"); say "$row"
  echo "$row" | grep -q '"pass":true}$' || pi4=false
done
say "PI4: $pi4"

# ================= PI5 (PD3) and PD2: rollback and tampering, both builds =================
say "== PI5: from n = $N0, 10 drives, the tampering, then the run to n = $((N0 + K)); S49d and S49c builds"
pi5_life() {
  seed=$1; law=$2; dr=$3; b=$4; tag=$seed-$law-$dr; df=$(dfile $dr); d=$W/pi5-$b/$tag; mkdir -p "$d"
  if [ $b = d ]; then X=$FRUN; else X=$CFRUN; fi
  end=$((N0 + K)); mid=$((N0 + 10)); R=$(ref $tag $end); rows=""; okall=true
  for v in rollback bitflip delete_line delete_file unreadable; do
    f=$d/$v; cp "$(ref $tag $N0)" "$f"; : > "$f.audit"
    c1=0; sed -n "$((N0 + 1)),${mid}p" "$df" | "$X" "$f" > /dev/null 2>&1 || c1=$?
    case $v in
      rollback) cp "$(ref $tag $((N0 + 5)))" "$f.rb"; mv "$f.rb" "$f" ;;
      bitflip) perl -e 'local $/; open(F, "+<", $ARGV[0]) or die; $b = <F>; @l = split(/\n/, $b); $o = 0; $o += length($l[$_]) + 1 for 0 .. 3; $o += 2; seek(F, $o, 0); $c = substr($b, $o, 1); print F chr(ord($c) ^ 1); close F' "$f.audit" ;;
      delete_line) sed '3d' "$f.audit" > "$d/tmp"; cat "$d/tmp" > "$f.audit" ;;
      delete_file) mv "$f.audit" "$d/removed-$v.audit" ;;
      unreadable) chmod 200 "$f.audit" ;;
    esac
    bf=$("$BT" onelife-audit "$f")
    n=$(nof "$f")
    c2=0; sed -n "$((n + 1)),${end}p" "$df" | "$X" "$f" > /dev/null 2>&1 || c2=$?
    chmod 600 "$f.audit"
    a=$("$BT" onelife-audit "$f")
    fin=false; cmp -s "$f" "$R" && fin=true
    brk=$(grep '^break ' "$f.audit" | awk '{print $2 ":" ($3 == "'$GEN'" ? "genesis" : "chained")}' | tr '\n' ' ')
    det=false
    case $v in
      rollback) [ "$(jv "$bf" run_vs_last_commit)" = '"rollback or audit behind"' ] && [ "$(jv "$a" starts_below_last_commit)" = 1 ] && [ "$(jv "$a" chain_ok)" = true ] && [ "$(jv "$a" breaks)" = 0 ] && det=true ;;
      bitflip|delete_line) [ "$(jv "$bf" chain_ok)" = false ] && [ "$(jv "$a" chain_ok)" = false ] && [ "$(jv "$a" chain_failures)" = "$(jv "$bf" chain_failures)" ] && [ "$brk" = "mismatch:genesis " ] && det=true ;;
      delete_file) [ "$(jv "$bf" audit)" = '"missing"' ] && [ "$(jv "$a" chain_ok)" = true ] && [ "$brk" = "missing:genesis " ] && [ "$(head -1 "$f.audit" | awk '{print $1}')" = break ] && det=true ;;
      unreadable) [ "$(jv "$bf" audit)" = '"unreadable"' ] && [ "$(jv "$a" chain_ok)" = true ] && [ "$brk" = "unreadable:genesis " ] && det=true ;;
    esac
    ok=false; [ "$c1" = 0 ] && [ "$c2" = 0 ] && [ "$fin" = true ] && [ "$det" = true ] && ok=true
    [ "$ok" = true ] || okall=false
    rows="$rows{\"case\":\"$v\",\"before\":{\"audit\":$(jv "$bf" audit),\"chain_ok\":$(jv "$bf" chain_ok),\"chain_failures\":$(jv "$bf" chain_failures),\"run_vs_last_commit\":$(jv "$bf" run_vs_last_commit)},\"run_exit\":$c2,\"after\":{\"chain_ok\":$(jv "$a" chain_ok),\"chain_failures\":$(jv "$a" chain_failures),\"breaks\":\"$brk\",\"starts_below_last_commit\":$(jv "$a" starts_below_last_commit)},\"end_same_as_untampered\":$fin,\"reported\":$det,\"ok\":$ok},"
  done
  f=$d/ctl; cp "$(ref $tag $N0)" "$f"; : > "$f.audit"
  cc=0; sed -n "$((N0 + 1)),${end}p" "$df" | "$X" "$f" > /dev/null 2>&1 || cc=$?
  a=$("$BT" onelife-audit "$f")
  ctl=false; [ "$cc" = 0 ] && cmp -s "$f" "$R" && [ "$(jv "$a" chain_ok)" = true ] && [ "$(jv "$a" breaks)" = 0 ] && [ "$(jv "$a" run_vs_last_commit)" = '"match"' ] && [ "$(jv "$a" starts_below_last_commit)" = 0 ] && ctl=true
  A=$d/niA; B=$d/niB; cp "$(ref $tag $N0)" "$A"; cp "$(ref $tag $N0)" "$B"; : > "$A.audit"; cp "$f.audit" "$B.audit"
  t0a=$GEN; t0b=$(lastfield "$B.audit")
  sed -n "$((N0 + 1)),${mid}p" "$df" > "$d/in1"; sed -n "$((mid + 1)),${end}p" "$df" > "$d/in2"
  ca=0; "$X" "$A" < "$d/in1" > /dev/null 2>&1 || ca=$?
  cb=0; "$X" "$B" < "$d/in1" > /dev/null 2>&1 || cb=$?
  s1=false; cmp -s "$A" "$B" && cmp -s "$A" "$(ref $tag $mid)" && s1=true
  "$X" "$A" < "$d/in2" > /dev/null 2>&1 || ca=$?
  "$X" "$B" < "$d/in2" > /dev/null 2>&1 || cb=$?
  s2=false; cmp -s "$A" "$B" && cmp -s "$A" "$R" && s2=true
  aA=$("$BT" onelife-audit "$A"); aB=$("$BT" onelife-audit "$B")
  tails=false; [ "$t0a" != "$t0b" ] && [ "$(lastfield "$A.audit")" != "$(lastfield "$B.audit")" ] && tails=true
  ni=false; [ "$ca" = 0 ] && [ "$cb" = 0 ] && [ "$s1" = true ] && [ "$s2" = true ] && [ "$tails" = true ] && [ "$(jv "$aA" breaks)" = 0 ] && [ "$(jv "$aB" breaks)" = 0 ] && [ "$(jv "$aB" chain_ok)" = true ] && ni=true
  ok=false; [ "$okall" = true ] && [ "$ctl" = true ] && [ "$ni" = true ] && ok=true
  echo "PI5 $tag S49$b {\"cases\":[${rows%,}],\"control_untampered\":$ctl,\"two_tails\":{\"tails_differ\":$tails,\"same_after_10\":$s1,\"same_after_$K\":$s2,\"exits\":[$ca,$cb],\"pass\":$ni},\"pass\":$ok}" > "$d/row"
}
for b in d c; do for L in $LIVES; do seed=${L%%:*}; r=${L#*:}; law=${r%%:*}; dr=${r#*:}; (pi5_life $seed $law $dr $b) & done; done
wait
pi5=true
for L in $LIVES; do
  seed=${L%%:*}; r=${L#*:}; law=${r%%:*}; dr=${r#*:}; tag=$seed-$law-$dr
  row=$(cat "$W/pi5-d/$tag/row"); say "$row"
  echo "$row" | grep -q '"pass":true}$' || pi5=false
  echo "$row" | grep -q '"ok":false' && pi5=false
done
say "PI5: $pi5"

# PD2 in the PI4 and PI5 scenes: every run file and audit of the S49d build equals the S49c build's
pd2s=true; nf=0; nd2=0
for s in pi4 pi5; do
  for f in $(cd "$W/$s-d" && find . -type f ! -name row ! -name '*.lock' ! -name tmp | sort); do
    nf=$((nf + 1))
    cmp -s "$W/$s-d/$f" "$W/$s-c/$f" || { nd2=$((nd2 + 1)); say "PD2 scene file differs: $s $f"; }
  done
done
nc2=$(cd "$W/pi4-c" && find . -type f ! -name row ! -name '*.lock' ! -name tmp | wc -l | tr -d ' ')
nc2=$((nc2 + $(cd "$W/pi5-c" && find . -type f ! -name row ! -name '*.lock' ! -name tmp | wc -l | tr -d ' ')))
[ "$nf" -gt 0 ] && [ "$nd2" = 0 ] && [ "$nc2" = "$nf" ] || pd2s=false
say "PD2 in the PI4 and PI5 scenes: files compared $nf (S49c side $nc2), differing $nd2 -> $pd2s"
pd2=false; [ "$pd2a" = true ] && [ "$pd2s" = true ] && pd2=true

# ================= PI6 (PD3): the audit cannot be written =================
say "== PI6: the audit not writable (valid read-only, broken read-only, mode 000, missing in a read-only directory): exit and the run file"
pi6_life() {
  seed=$1; law=$2; dr=$3; tag=$seed-$law-$dr; df=$(dfile $dr); d=$W/pi6/$tag; mkdir -p "$d"
  B=$(ref $tag $N0); sed -n "$((N0 + 1)),$((N0 + 3))p" "$df" > "$d/in"; rows=""; okall=true
  for v in readonly broken_readonly mode000 missing_rodir; do
    dd=$d/$v; mkdir -p "$dd"; f=$dd/run; cp "$B" "$f"; touch "$f.lock"
    case $v in
      readonly) : > "$f.audit"; chmod 400 "$f.audit" ;;
      broken_readonly) echo "not an audit line" > "$f.audit"; chmod 400 "$f.audit" ;;
      mode000) : > "$f.audit"; chmod 000 "$f.audit" ;;
      missing_rodir) chmod 500 "$dd" ;;
    esac
    c=0; "$FRUN" "$f" < "$d/in" > /dev/null 2> "$d/err-$v" || c=$?
    msg=false; grep -q 'audit' "$d/err-$v" && msg=true
    chmod 700 "$dd"; [ -e "$f.audit" ] && chmod 600 "$f.audit"
    same=false; cmp -s "$f" "$B" && same=true
    tmp=false; [ -e "$f.tmp" ] && tmp=true
    ok=false; [ "$c" != 0 ] && [ "$msg" = true ] && [ "$same" = true ] && [ "$tmp" = false ] && ok=true
    [ "$ok" = true ] || okall=false
    rows="$rows{\"case\":\"$v\",\"exit\":$c,\"stopped_on_the_audit\":$msg,\"run_file_unchanged\":$same,\"tmp_left\":$tmp,\"ok\":$ok},"
  done
  dd=$d/control; mkdir -p "$dd"; f=$dd/run; cp "$B" "$f"; : > "$f.audit"
  cc=0; "$FRUN" "$f" < "$d/in" > /dev/null 2>&1 || cc=$?
  ctl=false; [ "$cc" = 0 ] && [ "$(nof "$f")" = $((N0 + 3)) ] && ctl=true
  ok=false; [ "$okall" = true ] && [ "$ctl" = true ] && ok=true
  echo "PI6 $tag {\"cases\":[${rows%,}],\"control_writable\":$ctl,\"pass\":$ok}" > "$d/row"
}
forlives pi6_life
pi6=true
for L in $LIVES; do
  seed=${L%%:*}; r=${L#*:}; law=${r%%:*}; dr=${r#*:}; tag=$seed-$law-$dr
  row=$(cat "$W/pi6/$tag/row"); say "$row"
  echo "$row" | grep -q '"pass":true}$' || pi6=false
done
say "PI6: $pi6"

pd3=false; [ "$pi1" = true ] && [ "$pi3" = true ] && [ "$pi3m" = true ] && [ "$pi4" = true ] && [ "$pi5" = true ] && [ "$pi6" = true ] && [ "$i3" = true ] && pd3=true
pd4=$i0
say "PD1: $pd1"
say "PD2: $pd2 (on N = $N $pd2a; in the PI4 and PI5 scenes $pd2s)"
say "PD3: $pd3 (PI1 $pi1, PI3 $pi3, PI3 missing and newline-terminated $pi3m, PI4 $pi4, PI5 $pi5, PI6 $pi6, source diff only the branch $i3)"
say "PD4: $pd4"
say "PD5: $pd5"
say "done $(date '+%Y-%m-%d %H:%M:%S'); $OUT"
