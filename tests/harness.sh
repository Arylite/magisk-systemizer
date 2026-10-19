# harness.sh - tiny test harness for the systemizer shell code. POSIX sh, sourced.
# Builds a throw-away "device": a copy of the module, a fake /system, fake
# pm/dumpsys/getprop/getenforce, and fake installed apps. Nothing here needs root.

HERE=$(cd "$(dirname "$0")" && pwd)
REPO=$(cd "$HERE/.." && pwd)
CLI=$REPO/module/system/bin/systemizer
T_SH=${T_SH:-sh}
T_PASS=0 T_FAIL=0 T_ROOT=

t_pass() { T_PASS=$((T_PASS + 1)); }
t_bad()  { T_FAIL=$((T_FAIL + 1)); printf 'FAIL %s\n' "$1"; [ -z "$2" ] || printf '     %s\n' "$2"; }
t_eq()   { if [ "$2" = "$3" ]; then t_pass; else t_bad "$1" "want [$2] got [$3]"; fi; }
t_rc()   { t_eq "$1 (exit code)" "$2" "$T_RC"; }
t_out()  { case $T_OUT in *"$2"*) t_pass ;; *) t_bad "$1" "output lacks [$2]; got: $T_OUT" ;; esac; }
t_noout() { case $T_OUT in *"$2"*) t_bad "$1" "output has [$2]: $T_OUT" ;; *) t_pass ;; esac; }
t_file() { if [ -f "$2" ]; then t_pass; else t_bad "$1" "missing file $2"; fi; }
t_nofile() { if [ ! -e "$2" ]; then t_pass; else t_bad "$1" "unexpected $2"; fi; }
t_same() { if cmp -s "$2" "$3"; then t_pass; else t_bad "$1" "$2 differs from $3"; fi; }
t_grep() { if grep -Fq -- "$2" "$3" 2>/dev/null; then t_pass; else t_bad "$1" "$3 lacks [$2]"; fi; }
t_nogrep() { if grep -Fq -- "$2" "$3" 2>/dev/null; then t_bad "$1" "$3 has [$2]"; else t_pass; fi; }
# Run a shell function in this shell and compare its status (side effects kept).
t_status() { t_sn=$1 t_sw=$2; shift 2; "$@" > /dev/null 2>&1; t_eq "$t_sn" "$t_sw" "$?"; }
t_done() { rm -rf "$T_ROOT"; printf '%-14s %s passed, %s failed\n' "$T_NAME" "$T_PASS" "$T_FAIL"; [ $T_FAIL -eq 0 ]; }

# Run the CLI as a non-root user in test mode; result in T_RC and T_OUT.
t_cli() { T_OUT=$("$T_SH" "$CLI" "$@" 2>&1 < /dev/null); T_RC=$?; }

t_shim() { # name body
  printf '#!/bin/sh\n%s\n' "$2" > "$T_ROOT/bin/$1"
  chmod +x "$T_ROOT/bin/$1"
}

# Fresh device: call at the start of every scenario.
t_new() {
  [ -z "$T_ROOT" ] || rm -rf "$T_ROOT"
  T_ROOT=$(mktemp -d) || exit 1
  mkdir -p "$T_ROOT/sys/app" "$T_ROOT/sys/priv-app" "$T_ROOT/sys/etc/permissions" \
    "$T_ROOT/fake" "$T_ROOT/bin" "$T_ROOT/data/app"
  cp -R "$REPO/module" "$T_ROOT/mod"
  cp "$HERE/fixtures/permissions.txt" "$T_ROOT/fake/permissions"
  t_prop ro.build.version.sdk 36
  t_prop ro.control_privapp_permissions enforce
  printf 'Permissive\n' > "$T_ROOT/fake/enforce"
  # Like system_server under SELinux: pm and dumpsys only write to a pipe, never to a file.
  t_shim pm '[ -p /dev/fd/1 ] || { echo "stdout is not a pipe" >&2; exit 1; }
case "$1 $2" in
  "path "*) [ -f "$FAKE/path.$2" ] && { cat "$FAKE/path.$2"; exit 0; }; exit 1 ;;
  "list packages") cat "$FAKE/packages" 2>/dev/null; exit 0 ;;
  "list permissions") cat "$FAKE/permissions"; exit 0 ;;
esac
exit 1'
  t_shim dumpsys '[ -p /dev/fd/1 ] || { echo "stdout is not a pipe" >&2; exit 1; }
[ -f "$FAKE/dump.$2" ] && cat "$FAKE/dump.$2"; exit 0'
  t_shim getprop '[ -f "$FAKE/prop.$1" ] && cat "$FAKE/prop.$1"; exit 0'
  t_shim getenforce 'cat "$FAKE/enforce"'
  FAKE=$T_ROOT/fake
  PATH=$T_ROOT/bin:$PATH
  SYSTEMIZER_TESTING=1 SYSTEMIZER_MODDIR=$T_ROOT/mod SYSTEMIZER_SYSTEM=$T_ROOT/sys
  SYSTEMIZER_DATA=$T_ROOT/data SYSTEMIZER_AAPT=
  export FAKE PATH SYSTEMIZER_TESTING SYSTEMIZER_MODDIR SYSTEMIZER_SYSTEM SYSTEMIZER_DATA SYSTEMIZER_AAPT
  MOD=$T_ROOT/mod
}

t_prop() { printf '%s\n' "$2" > "$T_ROOT/fake/prop.$1"; }

# Fake dumpsys output in the layout of a real Android 16 device.
t_dump() { # pkg vcode perm...
  td_p=$1 td_v=$2; shift 2
  {
    printf 'Packages:\n  Package [%s] (abc123):\n    appId=10001\n' "$td_p"
    printf '    versionCode=%s minSdk=21 targetSdk=33\n    versionName=%s.0\n' "$td_v" "$td_v"
    printf '    flags=[ HAS_CODE ]\n    requested permissions:\n'
    for td_x in "$@"; do printf '      %s\n' "$td_x"; done
    printf '    install permissions:\n      android.permission.INTERNET: granted=true\n'
  } > "$FAKE/dump.$td_p"
}

# Install a fake user app: nsplits APK files under a randomized /data/app path.
t_app() { # pkg vcode nsplits [perm...]
  ta_p=$1 ta_v=$2 ta_n=$3; shift 3
  ta_d="$T_ROOT/data/app/~~r1==/$ta_p-h1=="
  [ -z "$T_SPACE" ] || ta_d="$T_ROOT/data/app/~~r 1==/$ta_p h1=="
  mkdir -p "$ta_d"
  : > "$FAKE/path.$ta_p"
  ta_i=1
  while [ $ta_i -le "$ta_n" ]; do
    if [ $ta_i -eq 1 ]; then ta_f=base.apk; else ta_f=split_config.x$ta_i.apk; fi
    printf 'apk %s v%s part%s\n' "$ta_p" "$ta_v" "$ta_i" > "$ta_d/$ta_f"
    printf 'package:%s/%s\n' "$ta_d" "$ta_f" >> "$FAKE/path.$ta_p"
    ta_i=$((ta_i + 1))
  done
  t_dump "$ta_p" "$ta_v" "$@"
  grep -qx "package:$ta_p" "$FAKE/packages" 2>/dev/null || printf 'package:%s\n' "$ta_p" >> "$FAKE/packages"
}

t_ovl() { printf '%s\n' "$MOD/system/app/$1/base.apk"; }
