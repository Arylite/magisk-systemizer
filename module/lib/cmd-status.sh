# cmd-status.sh - systemizer status [PACKAGE]

# Report for one package. Returns 0 up to date, 6 stale, 1 broken, 3 not managed.
sz_status_one() { # pkg verbose
  sz_state_load "$1"; st_rc=$?
  if [ $st_rc -eq 1 ]; then
    [ "$2" = 1 ] && sz_say "$1 is not managed by systemizer."
    return 3
  fi
  if [ $st_rc -eq 2 ]; then sz_say "$1  state file unreadable (run: systemizer remove $1 --yes)"; return 1; fi
  sz_installed_paths "$1"
  sz_fresh "$1"
  st_active="pending reboot"
  [ -d "$SZ_SYSTEM/$SZ_P_SUB/$1" ] && st_active=yes
  if [ -e "$SZ_MODDIR/disable" ] || [ -e "$SZ_MODDIR/skip_mount" ] || [ -e "$SZ_MODDIR/remove" ]; then
    st_active="no (module disabled)"
  fi
  case $SZ_KIND in
    data) st_inst="user copy installed (runs as the update of the system app)" ;;
    system) st_inst="system copy only (this overlay is what runs)" ;;
    none) st_inst="not visible to pm yet" ;;
    *) st_inst="unexpected: $SZ_KIND" ;;
  esac
  st_res=0
  case $SZ_FRESH in
    fresh) st_state="up to date" ;;
    absent) st_state="up to date (app not visible to pm yet)" ;;
    stale) st_state="STALE: the installed APK differs from the overlay. Run: systemizer refresh $1"; st_res=6 ;;
    *) st_state="BROKEN: overlay files are missing. Run: systemizer remove $1 --yes, then install again"; st_res=1 ;;
  esac
  if [ "$SZ_S_MODE" = privileged ] && [ "$2" = 1 ] && [ $st_res -eq 0 ] && sz_priv_drift "$1"; then
    st_state="STALE: the app now requests $SZ_DRIFT_PERM, missing from its allowlist (boot risk). Run: systemizer refresh $1"
    st_res=6
  fi
  if [ "$2" != 1 ]; then sz_say "$1  $SZ_S_MODE  $st_state"; return $st_res; fi
  sz_say "Package:    $1"
  sz_say "Managed:    yes"
  sz_say "Mode:       $SZ_S_MODE"
  sz_say "Source:     $SZ_S_SOURCE"
  sz_say "Overlay:    $SZ_P_DIR ($SZ_S_APKS APK file(s))"
  [ -z "$SZ_S_GRANTLIST" ] || sz_say "Granted:    $SZ_S_GRANTLIST"
  sz_say "Active:     $st_active"
  sz_say "Installed:  $st_inst"
  sz_say "State:      $st_state"
  return $st_res
}

cmd_status() {
  st_pkg=
  for st_a in "$@"; do
    case $st_a in
      -h|--help) usage; exit 0 ;;
      -*) sz_usage_die "unknown option: $st_a" ;;
      *) [ -z "$st_pkg" ] || sz_usage_die "only one package may be given"; st_pkg=$st_a ;;
    esac
  done
  [ -z "$st_pkg" ] || sz_valid_pkg "$st_pkg" || sz_usage_die "invalid package name: $st_pkg"
  sz_init 0
  sz_have pm || sz_die "$SZ_UNSUPPORTED" "pm is not available"
  if [ -n "$st_pkg" ]; then sz_status_one "$st_pkg" 1; exit $?; fi
  st_worst=0 st_n=0
  for st_f in "$SZ_STATE"/*.conf; do
    [ -f "$st_f" ] || continue
    st_p=${st_f##*/}; st_p=${st_p%.conf}
    sz_valid_pkg "$st_p" || continue
    st_n=$((st_n + 1))
    sz_status_one "$st_p" 0; st_rc=$?
    [ $st_rc -le $st_worst ] || st_worst=$st_rc
  done
  [ $st_n -gt 0 ] || sz_say "No managed apps."
  exit $st_worst
}
