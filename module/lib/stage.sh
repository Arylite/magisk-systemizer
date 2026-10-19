# stage.sh - build a payload next to the overlay, verify it, then publish it.

sz_stage() { # pkg  (APKs listed in $SZ_TMP/paths, XML plan from sz_priv_plan)
  SZ_STG=$SZ_WORK/stage.$$
  sz_safe_rm "$SZ_STG" || return 1
  mkdir -p "$SZ_STG/app" || return 1
  sk_i=0
  while IFS= read -r sk_src; do
    sk_i=$((sk_i + 1))
    if [ $sk_i -eq 1 ]; then sk_n=base.apk; else sk_n=split_$sk_i.apk; fi
    cp "$sk_src" "$SZ_STG/app/$sk_n" || { sz_err "cannot copy $sk_src"; return 1; }
    sz_same "$sk_src" "$SZ_STG/app/$sk_n" || { sz_err "the copy of $sk_src differs from the original (disk full?)"; return 1; }
  done < "$SZ_TMP/paths"
  if [ "$SZ_XML_NEEDED" = 1 ]; then
    if ! sz_gen_xml "$1" "$SZ_TMP/g.list" "$SZ_TMP/d.list" "$SZ_STG/perm.xml" \
      || ! sz_xml_ok "$SZ_STG/perm.xml" "$1"; then
      sz_err "internal: the generated permission XML is invalid"; return 1
    fi
  fi
  chmod 755 "$SZ_STG" "$SZ_STG/app" && chmod 644 "$SZ_STG"/app/*.apk || return 1
  [ ! -f "$SZ_STG/perm.xml" ] || chmod 644 "$SZ_STG/perm.xml" || return 1
  if [ "$(id -u)" = 0 ]; then chown -R 0:0 "$SZ_STG" || return 1; fi
  sz_label "$SZ_STG"
}

# Publish the staged payload. The allowlist goes in before the APKs and comes out
# after them, so a priv-app APK is never visible without its allowlist.
sz_commit() { # pkg mode
  sz_modedir "$1" "$2"
  if [ "$2" = privileged ]; then sc_other=$SZ_P_APP; else sc_other=$SZ_P_PRIV; fi
  sz_ensure_dir "$SZ_OVL/$SZ_P_SUB" || return 1
  sc_xml=0
  if [ -f "$SZ_STG/perm.xml" ]; then
    sc_xml=1
    sz_ensure_dir "$SZ_OVL/etc" && sz_ensure_dir "$SZ_OVL/etc/permissions" || return 1
    sz_swap "$SZ_STG/perm.xml" "$SZ_P_XML" || return 1
  fi
  sz_swap "$SZ_STG/app" "$SZ_P_DIR" || return 1
  [ ! -e "$sc_other" ] || sz_safe_rm "$sc_other" || return 1
  if [ $sc_xml -eq 0 ] && [ -e "$SZ_P_XML" ]; then sz_safe_rm "$SZ_P_XML" || return 1; fi
  return 0
}

# After sz_state_load + sz_installed_paths: sets SZ_FRESH to fresh|stale|absent|broken.
sz_fresh() { # pkg
  sz_modedir "$1" "$SZ_S_MODE"
  SZ_FRESH=fresh
  fr_n=0
  for fr_f in "$SZ_P_DIR"/*.apk; do [ -f "$fr_f" ] && fr_n=$((fr_n + 1)); done
  if [ $fr_n -ne "$SZ_S_APKS" ] || [ ! -f "$SZ_P_DIR/base.apk" ]; then SZ_FRESH=broken; return 0; fi
  case $SZ_KIND in
    none) SZ_FRESH=absent ;;
    data)
      if [ "$SZ_NPATHS" -ne "$SZ_S_APKS" ]; then SZ_FRESH=stale; return 0; fi
      fr_i=0
      while IFS= read -r fr_src; do
        fr_i=$((fr_i + 1)); if [ $fr_i -eq 1 ]; then fr_nm=base.apk; else fr_nm=split_$fr_i.apk; fi
        sz_same "$fr_src" "$SZ_P_DIR/$fr_nm" || { SZ_FRESH=stale; break; }
      done < "$SZ_TMP/paths" ;;
  esac
  return 0
}
