# cmd-list.sh - systemizer list [--managed]

cmd_list() {
  ls_managed=0
  for ls_a in "$@"; do
    case $ls_a in
      --managed) ls_managed=1 ;;
      -h|--help) usage; exit 0 ;;
      *) sz_usage_die "unknown argument: $ls_a" ;;
    esac
  done
  sz_init 0
  if [ $ls_managed -eq 1 ]; then
    ls_n=0
    for ls_f in "$SZ_STATE"/*.conf; do
      [ -f "$ls_f" ] || continue
      ls_p=${ls_f##*/}; ls_p=${ls_p%.conf}
      sz_valid_pkg "$ls_p" || continue
      ls_n=$((ls_n + 1))
      if sz_state_load "$ls_p"; then sz_say "$ls_p  [managed, $SZ_S_MODE]"
      else sz_say "$ls_p  [managed, state file unreadable]"; fi
    done
    [ $ls_n -gt 0 ] || sz_say "No managed apps."
    return 0
  fi
  sz_have pm || sz_die "$SZ_UNSUPPORTED" "pm is not available"
  sz_user_packages
  while IFS= read -r ls_p; do
    if [ -f "$SZ_STATE/$ls_p.conf" ]; then sz_say "$ls_p  [managed]"; else sz_say "$ls_p"; fi
  done < "$SZ_TMP/pk.list"
}
