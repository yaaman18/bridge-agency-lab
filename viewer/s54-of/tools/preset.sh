#!/bin/sh
# S54 garden: save / restore / list sets of the look and the sound (the viewer's own source, not the being).
#   sh tools/preset.sh save NAME      copy src/, bin/data/ (with the saved looks), addons.make, config.make, README.md,
#                                     openFrameworks-Info.plist (and the built app) to presets/NAME
#   sh tools/preset.sh restore NAME   first saves the current set as presets/_before-restore-<time>, then copies NAME back
#                                     (then rebuild: make -j8 Release, or open presets/NAME/bin/s54Garden.app directly)
#   sh tools/preset.sh list           names and the date each was saved
#   sh tools/preset.sh check NAME     compare the saved files with their recorded sha256
set -eu
cd "$(dirname "$0")/.."
P=presets
FILES="src bin/data addons.make config.make README.md openFrameworks-Info.plist"
save() {
  sd=$P/$1
  [ -e "$sd" ] && { echo "presets/$1 exists; choose another name"; exit 1; }
  mkdir -p "$sd"
  for f in $FILES; do mkdir -p "$sd/$(dirname "$f")"; cp -R "$f" "$sd/$f"; done
  [ -d bin/s54Garden.app ] && cp -R bin/s54Garden.app "$sd/bin/s54Garden.app"
  ( cd "$sd" && find src bin addons.make config.make README.md openFrameworks-Info.plist -type f 2>/dev/null | sort | xargs shasum -a 256 > MANIFEST.sha256 )
  date '+%Y-%m-%d %H:%M:%S' > "$sd/SAVED_AT"
  echo "saved presets/$1 ($(wc -l < "$sd/MANIFEST.sha256" | tr -d ' ') files)"
}
case ${1:-} in
  save) [ $# -eq 2 ] || exit 2; save "$2" ;;
  restore)
    [ $# -eq 2 ] || exit 2; d=$P/$2
    [ -f "$d/MANIFEST.sha256" ] || { echo "no preset $2"; exit 1; }
    ( cd "$d" && shasum -a 256 -c --quiet MANIFEST.sha256 ) || { echo "preset $2 does not match its manifest"; exit 1; }
    save "_before-restore-$(date +%Y%m%d-%H%M%S)"
    for f in $FILES; do
      [ -e "$d/$f" ] || { echo "note: $f is not in presets/$2; the current one is kept"; continue; }
      rm -rf "$f"; mkdir -p "$(dirname "$f")"; cp -R "$d/$f" "$f"
    done
    echo "restored presets/$2; rebuild with: make -j8 Release (or open $d/bin/s54Garden.app)" ;;
  list) for d in $P/*/; do [ -f "$d/SAVED_AT" ] && echo "$(basename "$d")  $(cat "$d/SAVED_AT")"; done ;;
  check) [ $# -eq 2 ] || exit 2; ( cd "$P/$2" && shasum -a 256 -c MANIFEST.sha256 ) ;;
  *) sed -n 2,8p "$0"; exit 2 ;;
esac
