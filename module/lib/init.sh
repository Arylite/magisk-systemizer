# init.sh - usage text, capability detection, startup and cleanup.

usage() {
  printf '%s\n' 'systemizer - systemize installed apps through the Magisk overlay

Usage: systemizer <command> [options]

Commands:
  list [--managed]              User apps (or only the apps managed here)
  install [PACKAGE] [options]   Systemize an app; pick from a list if no PACKAGE
  status [PACKAGE]              Managed apps, or the details of one
  refresh [PACKAGE | --all]     Re-copy the APKs after the app was updated
  remove PACKAGE [--yes]        Stop managing an app (after a reboot)
  doctor                        Check this device and the module
  help | version

Install options:
  --package NAME   Package name (same as the positional PACKAGE)
  --apk PATH       APK file: must be byte-identical to the installed copy, or the
                   app must not be installed and aapt/aapt2 must read its name
  --mode MODE      system (default) or privileged
  --grant PERM     privileged only, repeatable: allowlist one privileged permission
  -y, --yes        Do not ask for confirmation
  -n, --dry-run    Prepare and verify everything, change nothing

Exit codes: 0 ok, 1 failure, 2 usage, 3 not found, 4 unsupported device or setup,
            5 verification failed, 6 stale (run refresh), 7 refused for safety
Every change takes effect after a reboot.'
}

sz_cleanup() {
  [ -e "$SZ_TMP" ] && sz_safe_rm "$SZ_TMP"
  if [ "$SZ_LOCKED" = 1 ]; then
    sz_safe_rm "$SZ_WORK/stage.$$" "$SZ_WORK/trash"
    rm -f "$SZ_WORK/lock"
    SZ_LOCKED=0
  fi
}

# Detect what this device offers instead of assuming it.
sz_detect() {
  SZ_CMP='' SZ_CHCON='' SZ_AAPT='' SZ_AAPT_KIND='' SZ_SDK='' SZ_PRIVPROP='' SZ_SELINUX=''
  if sz_have cmp; then SZ_CMP=1; elif ! sz_have cksum; then
    sz_die "$SZ_UNSUPPORTED" "neither cmp nor cksum is available: cannot verify copied APKs"
  fi
  sz_have chcon && SZ_CHCON=1
  sz_have getenforce && SZ_SELINUX=$(getenforce 2>/dev/null)
  [ -n "$SZ_SELINUX" ] || SZ_SELINUX=Enforcing # unknown: assume the strict case
  if sz_have getprop; then
    SZ_SDK=$(getprop ro.build.version.sdk 2>/dev/null)
    SZ_PRIVPROP=$(getprop ro.control_privapp_permissions 2>/dev/null)
  fi
  case $SZ_SDK in ''|*[!0-9]*) SZ_SDK= ;; esac
  for sd_c in "$SZ_MODDIR/bin/aapt2" aapt2 "$SZ_MODDIR/bin/aapt" aapt; do
    case $sd_c in /*) [ -x "$sd_c" ] || continue ;; *) sz_have "$sd_c" || continue ;; esac
    SZ_AAPT=$sd_c; SZ_AAPT_KIND=${sd_c##*/}; break
  done
  if [ -n "$SYSTEMIZER_TESTING" ]; then # test hooks: a non-root shell cannot relabel files
    [ "${SYSTEMIZER_AAPT+set}" != set ] || { SZ_AAPT=$SYSTEMIZER_AAPT; SZ_AAPT_KIND=${SZ_AAPT##*/}; }
    [ -z "$SYSTEMIZER_NO_CHCON" ] || SZ_CHCON=
    [ -z "$SYSTEMIZER_NO_CMP" ] || SZ_CMP=
  fi
}

sz_init() { # 1 = the command changes things (takes the lock)
  if [ "$(id -u)" != 0 ] && [ -z "$SYSTEMIZER_TESTING" ]; then
    sz_die "$SZ_UNSUPPORTED" "root is required (try: su -c \"systemizer $SZ_CMD\")"
  fi
  sz_detect
  mkdir -p "$SZ_STATE" "$SZ_WORK" || sz_die "$SZ_FAIL" "cannot create $SZ_WORK"
  TMPDIR=$SZ_WORK; export TMPDIR
  trap sz_cleanup EXIT
  trap 'exit 130' INT; trap 'exit 143' TERM; trap 'exit 129' HUP
  if [ "$1" = 1 ]; then
    [ ! -e "$SZ_MODDIR/remove" ] || sz_die "$SZ_REFUSED" "the module is scheduled for removal"
    [ ! -e "$SZ_MODDIR/update" ] || sz_die "$SZ_REFUSED" "a module update is pending: reboot first, or this change would be lost"
    sz_lock
    if [ -e "$SZ_MODDIR/disable" ] || [ -e "$SZ_MODDIR/skip_mount" ]; then
      sz_warn "the module is disabled or skip_mount is set: the overlay stays inactive until that is removed"
    fi
  fi
  mkdir -p "$SZ_TMP" || sz_die "$SZ_FAIL" "cannot create $SZ_TMP"
}
