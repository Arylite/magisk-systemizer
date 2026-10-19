# interact.sh - interactive selection, confirmation, and clash checks.

sz_pick_package() { # -> in_name
  if [ ! -t 0 ] || [ ! -t 1 ]; then
    sz_usage_die "no package given and no terminal to choose from; pass a package name"
  fi
  sz_user_packages
  : > "$SZ_TMP/pick.list"
  pk_n=0
  while IFS= read -r pk_p; do
    [ -f "$SZ_STATE/$pk_p.conf" ] && continue
    pk_n=$((pk_n + 1))
    printf '%s\n' "$pk_p" >> "$SZ_TMP/pick.list"
    printf '%4d  %s\n' "$pk_n" "$pk_p"
  done < "$SZ_TMP/pk.list"
  [ $pk_n -gt 0 ] || sz_die "$SZ_NOTFOUND" "no user-installed app left to systemize"
  printf 'Number of the app to systemize (q to quit): '
  read -r pk_c
  case $pk_c in ''|q|Q) sz_say "Cancelled."; exit 0 ;; *[!0-9]*) sz_usage_die "not a number: $pk_c" ;; esac
  [ "$pk_c" -ge 1 ] && [ "$pk_c" -le $pk_n ] || sz_usage_die "out of range: $pk_c"
  pk_i=0
  while IFS= read -r pk_p; do
    pk_i=$((pk_i + 1))
    [ $pk_i -eq "$pk_c" ] && { in_name=$pk_p; break; }
  done < "$SZ_TMP/pick.list"
  sz_say "Selected: $in_name"
}

sz_confirm() {
  [ "$in_yes" = 1 ] && return 0
  [ -t 0 ] || sz_die "$SZ_USAGE" "confirmation needed and no terminal; pass --yes"
  printf '%s [y/N] ' "$1"
  read -r cf_a
  case $cf_a in y|Y|yes|YES) return 0 ;; esac
  sz_say "Cancelled."
  exit 0
}

# Another enabled module that already ships this package would shadow or clash.
sz_conflicts() {
  for cx_m in "$SZ_MODDIR"/../*; do
    [ -d "$cx_m/system" ] || continue
    grep -qx "id=$SZ_ID" "$cx_m/module.prop" 2>/dev/null && continue
    [ -e "$cx_m/disable" ] || [ -e "$cx_m/remove" ] && continue
    for cx_s in app priv-app; do
      [ -e "$cx_m/system/$cx_s/$1" ] && sz_die "$SZ_REFUSED" "module ${cx_m##*/} already provides /system/$cx_s/$1"
    done
  done
  return 0
}
