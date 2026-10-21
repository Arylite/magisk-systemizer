# state.sh - state/<pkg>.conf: key=value lines, parsed (never sourced).

sz_kv_get() { # file key
  [ -r "$1" ] || return 1
  while IFS='=' read -r kv_k kv_v; do
    if [ "$kv_k" = "$2" ]; then printf '%s\n' "$kv_v"; return 0; fi
  done < "$1"
  return 1
}

# Comma list -> SZ_S_GRANTLIST (space separated, every item validated).
sz_split_grants() {
  SZ_S_GRANTLIST=
  [ -n "$1" ] || return 0
  case $1 in *[!A-Za-z0-9._,]*) return 1 ;; esac # also keeps globs out of the split
  sg_old=$IFS; IFS=,
  for sg_p in $1; do
    IFS=$sg_old
    sz_valid_perm "$sg_p" || return 1
    SZ_S_GRANTLIST="$SZ_S_GRANTLIST $sg_p"
    IFS=,
  done
  IFS=$sg_old
  return 0
}

# Load and validate state/<pkg>.conf into SZ_S_*. Status 1 = missing, 2 = corrupt.
sz_state_load() {
  sz_paths "$1"
  [ -f "$SZ_P_STATE" ] || return 1
  SZ_S_MODE=$(sz_kv_get "$SZ_P_STATE" mode)
  SZ_S_SOURCE=$(sz_kv_get "$SZ_P_STATE" source)
  SZ_S_APKS=$(sz_kv_get "$SZ_P_STATE" apks)
  SZ_S_VCODE=$(sz_kv_get "$SZ_P_STATE" versioncode)
  SZ_S_GRANTS=$(sz_kv_get "$SZ_P_STATE" grants)
  [ "$(sz_kv_get "$SZ_P_STATE" schema)" = 1 ] || return 2
  [ "$(sz_kv_get "$SZ_P_STATE" package)" = "$1" ] || return 2
  case $SZ_S_MODE in system|privileged) ;; *) return 2 ;; esac
  case $SZ_S_SOURCE in installed|file) ;; *) return 2 ;; esac
  case $SZ_S_APKS in ''|*[!0-9]*) return 2 ;; esac
  [ "$SZ_S_APKS" -ge 1 ] && [ "$SZ_S_APKS" -le 64 ] || return 2
  case $SZ_S_VCODE in *[!0-9]*) return 2 ;; esac
  sz_split_grants "$SZ_S_GRANTS" || return 2
  return 0
}

sz_state_write() { # pkg mode source apks versioncode grants(comma list)
  sz_paths "$1"
  mkdir -p "$SZ_STATE" || return 1
  sw_t=$SZ_P_STATE.tmp.$$
  printf 'schema=1\npackage=%s\nmode=%s\nsource=%s\napks=%s\nversioncode=%s\ngrants=%s\n' \
    "$1" "$2" "$3" "$4" "$5" "$6" > "$sw_t" || { rm -f "$sw_t"; return 1; }
  mv -f "$sw_t" "$SZ_P_STATE" || { rm -f "$sw_t"; return 1; }
  sync 2>/dev/null || :
}

sz_join_comma() { # file -> a,b,c
  jc_s=
  while IFS= read -r jc_l; do
    [ -n "$jc_l" ] && jc_s=${jc_s:+$jc_s,}$jc_l
  done < "$1"
  printf '%s\n' "$jc_s"
}

sz_same_set() { # "a b" "b a"
  ss_a=" $1 " ss_b=" $2 "
  for ss_x in $1; do case $ss_b in *" $ss_x "*) ;; *) return 1 ;; esac; done
  for ss_x in $2; do case $ss_a in *" $ss_x "*) ;; *) return 1 ;; esac; done
  return 0
}
