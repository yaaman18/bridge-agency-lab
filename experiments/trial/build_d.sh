#!/bin/sh
# S54 §3 (discussion/specs/S54-trial-run.md r3): the S49d executables. The work-tree rust/ (frozen in
# experiments/freeze-rust-onelife-d-code.txt) is copied outside the tree to BUILD/rust (without target/), checked
# against the code freeze and against the work tree, and built four ways: production (10 s) and fastinterval, for the
# Mac and for the Pi (aarch64-unknown-linux-musl, static, linker rust-lld as in S51). Nothing is compiled on the Pi.
# Usage: sh experiments/trial/build_d.sh BUILD     (BUILD must not exist; BUILD/builds.txt lists the SHA-256)
set -eu
cd "$(dirname "$0")/../.."
[ $# -eq 1 ] || { echo "usage: build_d.sh BUILD"; exit 2; }
B=$1
[ ! -e "$B" ] || { echo "build_d.sh: $B exists"; exit 2; }
mkdir -p "$B"
fsha() { shasum -a 256 "$1" | awk '{print $1}'; }
DF=experiments/freeze-rust-onelife-d-code.txt
(cd rust && find . -path ./target -prune -o -type f -print | LC_ALL=C sort | cpio -pdm "$B/rust" 2> /dev/null)
nok=0
for p in rust/being-tools/src/bin/onelife-run.rs rust/being-tools/src/main.rs rust/being-tools/Cargo.toml rust/Cargo.lock rust/being-core/src/onelife.rs rust/being-core/src/matter.rs rust/being-core/src/fdexp.rs rust/being-core/src/sha256.rs; do
  w=$(grep " \.\./$p\$" "$DF" | awk '{print $1}'); [ -n "$w" ] && [ "$w" = "$(fsha "$B/$p")" ] && nok=$((nok + 1))
done
same=false; diff -r -x target rust "$B/rust" > /dev/null && same=true
echo "sources: files with the code-freeze sha $nok of 8; copy = work tree (without target) $same"
[ "$nok" = 8 ] && [ "$same" = true ] || { echo "build_d.sh: the sources differ from the code freeze; nothing built"; exit 1; }
(cd "$B/rust" && cargo build --release -p being-tools --target-dir "$B/mac-prod") > "$B/build-mac-prod.txt" 2>&1
(cd "$B/rust" && cargo build --release -p being-tools --features fastinterval --target-dir "$B/mac-fast") > "$B/build-mac-fast.txt" 2>&1
(cd "$B/rust" && CARGO_TARGET_AARCH64_UNKNOWN_LINUX_MUSL_LINKER=rust-lld cargo build --release -p being-tools --target aarch64-unknown-linux-musl --target-dir "$B/pi-prod") > "$B/build-pi-prod.txt" 2>&1
(cd "$B/rust" && CARGO_TARGET_AARCH64_UNKNOWN_LINUX_MUSL_LINKER=rust-lld cargo build --release -p being-tools --features fastinterval --target aarch64-unknown-linux-musl --target-dir "$B/pi-fast") > "$B/build-pi-fast.txt" 2>&1
nw=$(cat "$B"/build-*.txt | grep -c '^warning' || true)
: > "$B/builds.txt"
for k in mac-prod/release mac-fast/release pi-prod/aarch64-unknown-linux-musl/release pi-fast/aarch64-unknown-linux-musl/release; do
  for x in onelife-run being-tools; do
    f=$B/$k/$x
    echo "$(fsha "$f")  $k/$x  $(file -b "$f" | cut -c1-90)" >> "$B/builds.txt"
  done
done
npi=$(grep -c 'pi-.*ELF 64-bit LSB executable, ARM aarch64.*statically linked' "$B/builds.txt" || true)
cat "$B/builds.txt"
echo "build warnings $nw; Pi executables aarch64 static ELF $npi of 4"
[ "$nw" = 0 ] && [ "$npi" = 4 ] || exit 1
