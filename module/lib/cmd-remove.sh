# cmd-remove.sh - systemizer remove PACKAGE [--yes]

cmd_remove() {
  rm_pkg='' in_yes=0
  for rm_a in "$@"; do
    case $rm_a in
      -y|--yes) in_yes=1 ;;
      -h|--help) usage; exit 0 ;;
      -*) sz_usage_die "unknown option: $rm_a" ;;
      *) [ -z "$rm_pkg" ] || sz_usage_die "only one package may be given"; rm_pkg=$rm_a ;;
    esac
  done
  [ -n "$rm_pkg" ] || sz_usage_die "remove needs a package"
  sz_valid_pkg "$rm_pkg" || sz_usage_die "invalid package name: $rm_pkg"
  sz_init 1
  sz_have pm || sz_die "$SZ_UNSUPPORTED" "pm is not available"
  sz_paths "$rm_pkg"
  if [ ! -e "$SZ_P_STATE" ] && [ ! -e "$SZ_P_APP" ] && [ ! -e "$SZ_P_PRIV" ] && [ ! -e "$SZ_P_XML" ]; then
    sz_say "$rm_pkg is not managed by systemizer. Nothing to do."
    return 0
  fi
  sz_installed_paths "$rm_pkg"
  if [ "$SZ_KIND" != data ]; then
    sz_warn "no user-installed copy of $rm_pkg exists: once the overlay is gone, Android removes the app at the next boot and may delete its data"
    sz_confirm "Remove it anyway?"
  fi
  mkdir -p "$SZ_WORK/trash" || sz_die "$SZ_FAIL" "cannot create the trash directory"
  trap '' INT TERM HUP # do not stop between the APKs and their allowlist
  rm_i=0
  # Renames are atomic. APK directories go first, the allowlist after them.
  for rm_t in "$SZ_P_APP" "$SZ_P_PRIV" "$SZ_P_XML" "$SZ_P_STATE"; do
    [ -e "$rm_t" ] || continue
    rm_i=$((rm_i + 1))
    mv "$rm_t" "$SZ_WORK/trash/rm.$rm_i" || sz_die "$SZ_FAIL" "cannot remove $rm_t"
  done
  sync 2>/dev/null
  sz_say "Removed $rm_pkg from the overlay. Reboot to apply. Its app data is untouched by this tool."
}
