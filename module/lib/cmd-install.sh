# cmd-install.sh - systemizer install [PACKAGE] [--apk P] [--mode M] [--grant X]

sz_install_parse() {
  in_name='' in_apk='' in_mode=system in_dry=0 in_grants='' in_popt='' in_yes=0
  while [ $# -gt 0 ]; do
    in_o=$1 in_v=
    case $1 in
      --package|--apk|--mode|--grant)
        [ $# -ge 2 ] || sz_usage_die "$1 needs a value"
        in_v=$2; shift ;;
      --package=*|--apk=*|--mode=*|--grant=*) in_v=${1#*=}; in_o=${1%%=*} ;;
    esac
    shift
    case $in_o in
      '') sz_usage_die "empty argument" ;;
      --package) [ -z "$in_popt" ] || sz_usage_die "--package given twice"; in_popt=$in_v ;;
      --apk) [ -z "$in_apk" ] || sz_usage_die "--apk given twice"; in_apk=$in_v ;;
      --mode) in_mode=$in_v ;;
      --grant)
        sz_valid_perm "$in_v" || sz_usage_die "invalid permission name: $in_v"
        case " $in_grants " in *" $in_v "*) ;; *) in_grants="$in_grants $in_v" ;; esac ;;
      -y|--yes) in_yes=1 ;;
      -n|--dry-run) in_dry=1 ;;
      -h|--help) usage; exit 0 ;;
      -*) sz_usage_die "unknown option: $in_o" ;;
      *) [ -z "$in_name" ] || sz_usage_die "only one package may be given"; in_name=$in_o ;;
    esac
  done
  case $in_mode in system|privileged) ;; *) sz_usage_die "--mode must be system or privileged" ;; esac
  if [ -n "$in_popt" ]; then
    if [ -n "$in_name" ] && [ "$in_name" != "$in_popt" ]; then
      sz_usage_die "conflicting package names: $in_name and $in_popt"
    fi
    in_name=$in_popt
  fi
  if [ -n "$in_grants" ] && [ "$in_mode" != privileged ]; then
    sz_usage_die "--grant only makes sense with --mode privileged"
  fi
  [ -z "$in_name" ] || sz_valid_pkg "$in_name" || sz_usage_die "invalid package name: $in_name"
}

# Package already managed: succeed when nothing differs, otherwise say what to run.
sz_install_existing() {
  [ "$SZ_S_MODE" = "$in_mode" ] || sz_die "$SZ_REFUSED" "$in_name is already managed as $SZ_S_MODE; remove it first to change the mode"
  sz_same_set "$SZ_S_GRANTLIST" "$in_grants" || sz_die "$SZ_REFUSED" "$in_name is already managed with other --grant values; remove it first to change them"
  sz_fresh "$in_name"
  case $SZ_FRESH in
    fresh|absent) sz_say "$in_name is already systemized as $SZ_S_MODE. Nothing to do." ;;
    stale) sz_err "$in_name is managed but the installed APK differs from the overlay; run: systemizer refresh $in_name"; exit "$SZ_STALE" ;;
    *) sz_die "$SZ_FAIL" "the overlay of $in_name is incomplete; run: systemizer remove $in_name --yes, then install again" ;;
  esac
}

cmd_install() {
  sz_install_parse "$@"
  sz_init 1
  sz_have pm || sz_die "$SZ_UNSUPPORTED" "pm is not available"
  [ -d "$SZ_SYSTEM/app" ] || sz_die "$SZ_UNSUPPORTED" "this device has no $SZ_SYSTEM/app directory"
  if [ -z "$in_name" ] && [ -z "$in_apk" ]; then
    sz_pick_package
    sz_confirm "Systemize $in_name as a $in_mode app?"
  fi
  sz_resolve_sources
  sz_paths "$in_name"
  sz_state_load "$in_name"; in_st=$?
  [ $in_st -ne 2 ] || sz_die "$SZ_FAIL" "the state of $in_name is corrupt; run: systemizer remove $in_name --yes"
  [ $in_st -ne 0 ] || { sz_install_existing; return 0; }
  if [ "$SZ_KIND" = system ]; then
    read -r in_where < "$SZ_TMP/paths"
    sz_die "$SZ_REFUSED" "$in_name is already a system app ($in_where) that this module does not manage"
  fi
  if [ -e "$SZ_P_APP" ] || [ -e "$SZ_P_PRIV" ] || [ -e "$SZ_P_XML" ]; then
    sz_warn "found an incomplete overlay for $in_name from an interrupted run; it will be replaced"
  fi
  sz_conflicts "$in_name"
  sz_modedir "$in_name" "$in_mode"
  sz_priv_reset
  if [ "$in_mode" = privileged ]; then
    [ "$SZ_SRC" = installed ] || sz_die "$SZ_UNSUPPORTED" "privileged mode needs the app installed so its requested permissions can be inspected"
    sz_priv_plan "$in_name" "$in_grants"
  fi
  sz_say "Package:  $in_name"
  sz_say "Mode:     $in_mode  (/system/$SZ_P_SUB/$in_name)"
  sz_say "Source:   $SZ_SRC, $SZ_NPATHS APK file(s)"
  sz_stage "$in_name" || { sz_safe_rm "$SZ_STG"; sz_die "$SZ_FAIL" "staging failed; nothing was changed"; }
  if [ $in_dry -eq 1 ]; then sz_say "Dry run: everything verified, nothing changed."; return 0; fi
  sz_commit "$in_name" "$in_mode" || sz_die "$SZ_FAIL" "could not publish the overlay; run: systemizer doctor"
  in_vc=0
  if sz_have dumpsys && dumpsys package "$in_name" > "$SZ_TMP/dump.raw" 2>/dev/null && sz_parse_dump "$SZ_TMP/dump.raw" "$in_name"; then
    in_vc=${SZ_D_VCODE:-0}
  fi
  sz_state_write "$in_name" "$in_mode" "$SZ_SRC" "$SZ_NPATHS" "$in_vc" "$(sz_join_comma "$SZ_TMP/g.list")" \
    || sz_die "$SZ_FAIL" "overlay published but the state file could not be written; run: systemizer doctor"
  sz_say "Done. Reboot to apply. The app becomes a $in_mode app; a user copy, if installed, stays as its update."
}
