# parse.sh - parsers for dumpsys / pm output, in plain shell (no awk or sed).

# dumpsys package <pkg> -> SZ_D_FOUND SZ_D_VCODE SZ_D_VNAME SZ_D_FLAGS and the
# requested permissions, one per line, in $SZ_TMP/reqperms. Reads the first
# "Package [pkg]" block only (an updated system app also has a hidden copy).
sz_parse_dump() { # dumpfile pkg
  SZ_D_FOUND=0 SZ_D_VCODE='' SZ_D_VNAME='' SZ_D_FLAGS=''
  : > "$SZ_TMP/reqperms"
  pd_in=0 pd_perm=0
  while IFS= read -r pd_l; do
    if [ $pd_in -eq 0 ]; then
      case $pd_l in "  Package [$2]"*) pd_in=1; SZ_D_FOUND=1 ;; esac
      continue
    fi
    case $pd_l in "  Package ["*|[!' ']*) break ;; esac
    if [ $pd_perm -eq 1 ]; then
      case $pd_l in
        "      "[!' ']*)
          pd_n=${pd_l#"      "}; pd_n=${pd_n%%[: ]*}
          printf '%s\n' "$pd_n" >> "$SZ_TMP/reqperms"; continue ;;
        *) pd_perm=0 ;;
      esac
    fi
    case $pd_l in
      "    versionCode="*)
        if [ -z "$SZ_D_VCODE" ]; then pd_v=${pd_l#*versionCode=}; SZ_D_VCODE=${pd_v%%[!0-9]*}; fi ;;
      "    versionName="*) [ -n "$SZ_D_VNAME" ] || SZ_D_VNAME=${pd_l#*versionName=} ;;
      "    flags=["*) SZ_D_FLAGS=$pd_l ;;
      "    requested permissions:") pd_perm=1 ;;
    esac
  done < "$1"
  [ $SZ_D_FOUND -eq 1 ]
}

# pm list permissions -f -> "name protection" lines.
sz_parse_perms() { # rawfile outfile
  : > "$2"
  pp_n=
  while IFS= read -r pp_l; do
    case $pp_l in
      "+ permission:"*|"permission:"*|"  permission:"*)
        pp_n=${pp_l#*permission:}; pp_n=${pp_n%%[ ]*} ;;
      "  protectionLevel:"*)
        [ -n "$pp_n" ] && printf '%s %s\n' "$pp_n" "${pp_l#*protectionLevel:}" >> "$2"
        pp_n= ;;
    esac
  done < "$1"
  [ -s "$2" ]
}

# Requested permissions that are privileged-level -> $SZ_TMP/priv.list, and
# signature-only ones (never grantable without the platform key) -> sig.list.
sz_priv_scan() {
  ps_set=" " ps_seen=" "
  while IFS= read -r ps_n; do ps_set="$ps_set$ps_n "; done < "$SZ_TMP/reqperms"
  : > "$SZ_TMP/priv.list"; : > "$SZ_TMP/sig.list"
  while IFS=' ' read -r ps_n ps_l; do
    case $ps_set in *" $ps_n "*) ;; *) continue ;; esac
    case $ps_seen in *" $ps_n "*) continue ;; esac
    ps_seen="$ps_seen$ps_n "
    case $ps_l in
      *privileged*|*signatureOrSystem*) printf '%s\n' "$ps_n" >> "$SZ_TMP/priv.list" ;;
      *signature*) printf '%s\n' "$ps_n" >> "$SZ_TMP/sig.list" ;;
    esac
  done < "$SZ_TMP/permlevels"
}
