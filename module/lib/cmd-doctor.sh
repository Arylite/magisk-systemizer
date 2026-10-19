# cmd-doctor.sh - systemizer doctor

dr_ok()   { printf '[ ok ] %s\n' "$*"; }
dr_warn() { printf '[warn] %s\n' "$*"; dr_nwarn=$((dr_nwarn + 1)); }
dr_fail() { printf '[FAIL] %s\n' "$*"; dr_nfail=$((dr_nfail + 1)); }

sz_doctor_device() {
  for dr_f in disable remove skip_mount update; do
    [ -e "$SZ_MODDIR/$dr_f" ] && dr_warn "module flag file present: $dr_f (the overlay is inactive or a change is pending)"
  done
  if sz_have magisk; then dr_ok "magisk $(magisk -V 2>/dev/null)"; else dr_warn "magisk binary not on PATH (KernelSU/APatch, or a limited shell)"; fi
  if [ -n "$SZ_SDK" ]; then
    if [ "$SZ_SDK" -ge 21 ]; then dr_ok "Android API level $SZ_SDK"; else dr_fail "Android API level $SZ_SDK is below 21"; fi
  else dr_warn "cannot read the Android API level (getprop missing)"; fi
  for dr_d in app priv-app etc/permissions; do
    if [ -d "$SZ_SYSTEM/$dr_d" ]; then dr_ok "$SZ_SYSTEM/$dr_d exists"
    else dr_fail "$SZ_SYSTEM/$dr_d is missing: this device layout is not supported"; fi
  done
  if sz_have pm; then dr_ok "pm"; else dr_fail "pm is missing"; fi
  if sz_have dumpsys; then dr_ok "dumpsys"; else dr_warn "dumpsys missing: privileged mode and version display are unavailable"; fi
  if [ -n "$SZ_CMP" ]; then dr_ok "cmp"; else dr_warn "cmp missing: using cksum to verify copies"; fi
  if [ -n "$SZ_AAPT" ]; then dr_ok "$SZ_AAPT_KIND found: --apk works for apps that are not installed"
  else dr_warn "no aapt/aapt2: --apk only accepts a copy of an installed APK"; fi
  if [ -n "$SZ_CHCON" ]; then dr_ok "chcon (overlay files get $SZ_CONTEXT)"
  else dr_warn "chcon missing: overlay files keep the default label (SELinux: $SZ_SELINUX)"; fi
  dr_ok "SELinux: $SZ_SELINUX (this tool never changes it)"
  if [ -n "$SZ_SDK" ] && [ "$SZ_SDK" -ge 28 ]; then
    case $SZ_PRIVPROP in
      enforce) dr_ok "ro.control_privapp_permissions=enforce: unlisted privileged permissions can stop the boot; this tool denies them explicitly" ;;
      disable) dr_warn "ro.control_privapp_permissions=disable: priv-app apps get every privileged permission they request" ;;
      *) dr_ok "ro.control_privapp_permissions=${SZ_PRIVPROP:-unset}" ;;
    esac
  fi
}

sz_doctor_apps() {
  dr_n=0
  for dr_f in "$SZ_STATE"/*.conf; do
    [ -f "$dr_f" ] || continue
    dr_p=${dr_f##*/}; dr_p=${dr_p%.conf}
    dr_n=$((dr_n + 1))
    if ! sz_valid_pkg "$dr_p"; then dr_fail "state file with an invalid name: ${dr_f##*/}"; continue; fi
    if ! sz_state_load "$dr_p"; then dr_fail "$dr_p: state file corrupt (systemizer remove $dr_p --yes)"; continue; fi
    sz_modedir "$dr_p" "$SZ_S_MODE"
    if [ ! -f "$SZ_P_DIR/base.apk" ]; then dr_fail "$dr_p: overlay files missing"; continue; fi
    dr_ok "$dr_p ($SZ_S_MODE, $SZ_S_APKS APK file(s))"
  done
  [ $dr_n -gt 0 ] || dr_ok "no managed apps yet"
  for dr_d in app priv-app; do
    for dr_f in "$SZ_OVL/$dr_d"/*; do
      [ -d "$dr_f" ] || continue
      [ -f "$SZ_STATE/${dr_f##*/}.conf" ] || dr_warn "overlay directory without state: $dr_d/${dr_f##*/} (interrupted run; install again or remove it)"
    done
  done
  for dr_f in "$SZ_OVL"/etc/permissions/privapp-permissions-*.xml; do
    [ -f "$dr_f" ] || continue
    dr_p=${dr_f##*/}; dr_p=${dr_p#privapp-permissions-}; dr_p=${dr_p%.xml}
    [ -f "$SZ_STATE/$dr_p.conf" ] || dr_warn "allowlist file without state: ${dr_f##*/}"
  done
}

cmd_doctor() {
  [ $# -eq 0 ] || { case $1 in -h|--help) usage; exit 0 ;; *) sz_usage_die "doctor takes no arguments" ;; esac; }
  sz_init 0
  dr_nwarn=0 dr_nfail=0
  dr_ok "module $SZ_ID $(sz_kv_get "$SZ_MODDIR/module.prop" version) at $SZ_MODDIR"
  sz_doctor_device
  sz_doctor_apps
  printf '%s failure(s), %s warning(s)\n' "$dr_nfail" "$dr_nwarn"
  [ $dr_nfail -eq 0 ] || exit "$SZ_UNSUPPORTED"
  exit 0
}
