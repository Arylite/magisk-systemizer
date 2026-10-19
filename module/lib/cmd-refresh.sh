# cmd-refresh.sh - systemizer refresh PACKAGE | --all

# Re-copy the APKs of one managed app. Runs in a subshell for --all.
sz_refresh_one() { # pkg
  sz_state_load "$1"; rf_rc=$?
  [ $rf_rc -ne 1 ] || { sz_err "$1 is not managed by systemizer"; return "$SZ_NOTFOUND"; }
  [ $rf_rc -ne 2 ] || { sz_err "the state of $1 is corrupt; run: systemizer remove $1 --yes"; return "$SZ_FAIL"; }
  if [ "$SZ_S_SOURCE" != installed ]; then
    sz_err "$1 was systemized from a file; remove it and install --apk again"; return "$SZ_REFUSED"
  fi
  sz_installed_paths "$1"
  case $SZ_KIND in
    none) sz_err "$1 is not visible to pm"; return "$SZ_NOTFOUND" ;;
    system) sz_say "$1: up to date (no user-installed update over the overlay)"; return 0 ;;
    data) ;;
    *) sz_err "pm reports unexpected APK locations for $1"; return "$SZ_VERIFY" ;;
  esac
  while IFS= read -r rf_p; do
    [ -f "$rf_p" ] && [ -r "$rf_p" ] || { sz_err "APK missing or unreadable: $rf_p"; return "$SZ_VERIFY"; }
  done < "$SZ_TMP/paths"
  rf_mode=$SZ_S_MODE rf_grants=$SZ_S_GRANTLIST rf_src=$SZ_S_SOURCE
  sz_fresh "$1"
  if [ "$SZ_FRESH" = fresh ]; then # APKs equal, but the allowlist may have fallen behind
    if [ "$rf_mode" != privileged ] || ! sz_priv_drift "$1"; then sz_say "$1: up to date"; return 0; fi
  fi
  sz_priv_reset
  if [ "$rf_mode" = privileged ]; then sz_priv_plan "$1" "$rf_grants" 1; fi
  sz_stage "$1" || { sz_safe_rm "$SZ_STG"; sz_err "staging failed; nothing was changed"; return "$SZ_FAIL"; }
  if [ "$rf_dry" = 1 ]; then sz_say "$1: dry run, would refresh $SZ_NPATHS APK file(s)"; return 0; fi
  sz_commit "$1" "$rf_mode" || { sz_err "could not publish the overlay of $1; run: systemizer doctor"; return "$SZ_FAIL"; }
  rf_vc=0
  if sz_have dumpsys && dumpsys package "$1" > "$SZ_TMP/dump.raw" 2>/dev/null && sz_parse_dump "$SZ_TMP/dump.raw" "$1"; then
    rf_vc=${SZ_D_VCODE:-0}
  fi
  rf_gl=
  if [ "$rf_mode" = privileged ]; then rf_gl=$(sz_join_comma "$SZ_TMP/g.list"); fi
  sz_state_write "$1" "$rf_mode" "$rf_src" "$SZ_NPATHS" "$rf_vc" "$rf_gl" || { sz_err "state file of $1 not written"; return "$SZ_FAIL"; }
  sz_say "$1: refreshed. Reboot to apply."
}

cmd_refresh() {
  rf_pkg='' rf_all=0 rf_dry=0
  for rf_a in "$@"; do
    case $rf_a in
      --all) rf_all=1 ;;
      -n|--dry-run) rf_dry=1 ;;
      -h|--help) usage; exit 0 ;;
      -*) sz_usage_die "unknown option: $rf_a" ;;
      *) [ -z "$rf_pkg" ] || sz_usage_die "only one package may be given"; rf_pkg=$rf_a ;;
    esac
  done
  if [ $rf_all -eq 1 ] && [ -n "$rf_pkg" ]; then sz_usage_die "give a package or --all, not both"; fi
  if [ $rf_all -eq 0 ] && [ -z "$rf_pkg" ]; then sz_usage_die "refresh needs a package or --all"; fi
  [ -z "$rf_pkg" ] || sz_valid_pkg "$rf_pkg" || sz_usage_die "invalid package name: $rf_pkg"
  sz_init 1
  sz_have pm || sz_die "$SZ_UNSUPPORTED" "pm is not available"
  if [ $rf_all -eq 0 ]; then sz_refresh_one "$rf_pkg"; exit $?; fi
  rf_worst=0 rf_n=0
  for rf_f in "$SZ_STATE"/*.conf; do
    [ -f "$rf_f" ] || continue
    rf_q=${rf_f##*/}; rf_q=${rf_q%.conf}
    sz_valid_pkg "$rf_q" || continue
    rf_n=$((rf_n + 1))
    ( sz_refresh_one "$rf_q" ); rf_rc=$?
    [ $rf_rc -le $rf_worst ] || rf_worst=$rf_rc
  done
  [ $rf_n -gt 0 ] || sz_say "No managed apps."
  exit $rf_worst
}
