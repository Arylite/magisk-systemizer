#!/bin/sh
# run.sh - every check that runs on a development machine (no device, no root).
#   sh tests/run.sh            run everything under each shell found: bash dash sh
# Sections: source hygiene, then each t-*.sh under each available shell.
cd "$(dirname "$0")/.." || exit 1
FAIL=0
bad() { echo "FAIL $*"; FAIL=$((FAIL + 1)); }

echo "== source hygiene"
FILES="$(ls module/lib/*.sh tests/*.sh build.py module/customize.sh module/system/bin/systemizer)"
for f in $FILES; do
  n=$(grep -c '' "$f")
  [ "$n" -le 150 ] || bad "$f has $n lines (limit 150)"
done
if grep -nP '[^\x00-\x7F]' $FILES module/module.prop README.md docs/*.md > /dev/null 2>&1; then bad "non-ASCII character in the sources"; fi
if grep -l "$(printf '\r')" $FILES module/module.prop > /dev/null 2>&1; then bad "CR line ending in the sources"; fi
if cat module/lib/*.sh module/system/bin/systemizer | grep -v '^[[:space:]]*#' \
  | grep -E '(^|[;&|(]|then|do)[[:space:]]*(eval|local|source)[[:space:]]|\[\[' > /dev/null; then
  bad "eval, source, local or [[ ]] used in the module shell code"; fi
SHELLS=${SHELLS:-bash dash} # add busybox-ash or mksh here when you have them, e.g. SHELLS="bash dash mksh"
for sh in $SHELLS; do
  command -v $sh > /dev/null 2>&1 || continue
  for f in module/lib/*.sh module/customize.sh module/system/bin/systemizer module/META-INF/com/google/android/update-binary; do
    $sh -n "$f" 2>/dev/null || bad "$sh -n $f"
  done
done
[ $FAIL -eq 0 ] && echo "ok"

for sh in $SHELLS; do
  command -v $sh > /dev/null 2>&1 || continue
  echo "== tests under $sh"
  for t in tests/t-*.sh; do
    T_SH=$sh $sh "$t" || FAIL=$((FAIL + 1))
  done
done

if [ $FAIL -eq 0 ]; then echo "ALL PASSED"; else echo "$FAIL FAILURE GROUP(S)"; fi
[ $FAIL -eq 0 ]
