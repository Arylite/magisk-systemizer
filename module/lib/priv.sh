# priv.sh - privileged mode: which permissions go in the allowlist.

# No allowlist (system mode, or nothing to list): empty grant / deny plan.
sz_priv_reset() { SZ_XML_NEEDED=0; : > "$SZ_TMP/g.list"; : > "$SZ_TMP/d.list"; }

# Works out the allowlist XML. Sets SZ_XML_NEEDED; writes g.list (granted) and
# d.list (denied) in $SZ_TMP. Grants come only from the caller; the denies are the
# other privileged permissions the app asks for, because from Android 9 an app in
# priv-app with an unlisted privileged permission can stop the device booting.
sz_priv_plan() { # pkg "grants" [lenient]
  sz_priv_reset
  [ -d "$SZ_SYSTEM/priv-app" ] || sz_die "$SZ_UNSUPPORTED" "this device has no $SZ_SYSTEM/priv-app directory"
  [ -n "$SZ_SDK" ] || sz_die "$SZ_UNSUPPORTED" "cannot read the Android version (ro.build.version.sdk)"
  if [ "$SZ_SDK" -lt 26 ]; then
    [ -z "$2" ] || sz_die "$SZ_UNSUPPORTED" "--grant needs Android 8.0+: older versions give priv-app apps every privileged permission they request"
    sz_say "note: Android before 8.0 gives a priv-app app every privileged permission it requests"
    return 0
  fi
  sz_have dumpsys || sz_die "$SZ_UNSUPPORTED" "dumpsys is missing: cannot read the permissions $1 requests"
  sz_priv_load "$1" || sz_die "$SZ_FAIL" "cannot read the permissions of $1 or the permission table (dumpsys / pm)"
  for pl_g in $2; do
    if grep -Fxq -- "$pl_g" "$SZ_TMP/priv.list"; then
      printf '%s\n' "$pl_g" >> "$SZ_TMP/g.list"; continue
    fi
    if [ "$3" = 1 ]; then sz_warn "$pl_g is no longer a privileged permission requested by $1: dropped"; continue; fi
    if grep -Fxq -- "$pl_g" "$SZ_TMP/sig.list"; then
      sz_die "$SZ_UNSUPPORTED" "$pl_g is signature-level: only an app signed with the platform key can hold it, an allowlist cannot grant it"
    elif grep -Fxq -- "$pl_g" "$SZ_TMP/reqperms"; then
      sz_die "$SZ_USAGE" "$pl_g is not a privileged-level permission: no allowlist entry applies"
    fi
    sz_die "$SZ_USAGE" "$1 does not request $pl_g"
  done
  while IFS= read -r pl_p; do
    grep -Fxq -- "$pl_p" "$SZ_TMP/g.list" && continue
    # Android 8 has no deny element, and under enforce an unlisted privileged
    # permission can stop the boot: refuse instead of writing a partial allowlist.
    if [ "$SZ_SDK" -lt 28 ] && [ "$SZ_PRIVPROP" = enforce ]; then
      sz_die "$SZ_REFUSED" "$1 requests $pl_p: Android 8 cannot deny it and this device enforces the allowlist (boot risk). Grant every privileged permission it requests, or use system mode"
    fi
    [ "$SZ_SDK" -lt 28 ] || printf '%s\n' "$pl_p" >> "$SZ_TMP/d.list"
  done < "$SZ_TMP/priv.list"
  if [ -s "$SZ_TMP/g.list" ] || [ -s "$SZ_TMP/d.list" ]; then SZ_XML_NEEDED=1; fi
  sz_say "Privileged permissions requested: $(grep -c '' "$SZ_TMP/priv.list")  granted: $(grep -c '' "$SZ_TMP/g.list")  denied: $(grep -c '' "$SZ_TMP/d.list")"
  sz_list_perms granted "$SZ_TMP/g.list"; sz_list_perms denied "$SZ_TMP/d.list"
  if [ -s "$SZ_TMP/sig.list" ]; then
    sz_say "Signature-only permissions (cannot be granted without the platform key): $(grep -c '' "$SZ_TMP/sig.list")"
    sz_list_perms signature-only "$SZ_TMP/sig.list"
  fi
  if [ "$SZ_PRIVPROP" = disable ]; then
    sz_warn "ro.control_privapp_permissions=disable: this device grants every privileged permission the app requests, whatever the allowlist says"
  fi
}

sz_list_perms() { # label file
  while IFS= read -r lp_p; do [ -z "$lp_p" ] || sz_say "  $1: $lp_p"; done < "$2"
}

# Read the app's requested permissions and the device permission table, then split
# them into priv.list / sig.list. Status 1 when either tool output is unusable.
sz_priv_load() { # pkg
  sz_capture "$SZ_TMP/dump.raw" dumpsys package "$1"
  sz_parse_dump "$SZ_TMP/dump.raw" "$1" || return 1
  sz_capture "$SZ_TMP/perms.raw" pm list permissions -f
  grep -q 'permission:' "$SZ_TMP/perms.raw" || return 1
  # The table has thousands of entries and reading it in a shell loop takes ~30 s on a
  # phone: let grep cut out the few permissions this app requests, then parse only those.
  : > "$SZ_TMP/perms.pat"; : > "$SZ_TMP/perms.sub"
  while IFS= read -r pl_q; do
    printf '%s\n' "+ permission:$pl_q" "permission:$pl_q" "  permission:$pl_q" >> "$SZ_TMP/perms.pat"
  done < "$SZ_TMP/reqperms"
  if [ -s "$SZ_TMP/perms.pat" ]; then
    grep -F -x -A12 -f "$SZ_TMP/perms.pat" "$SZ_TMP/perms.raw" > "$SZ_TMP/perms.sub"
  fi
  sz_parse_perms "$SZ_TMP/perms.sub" "$SZ_TMP/permlevels" # empty when nothing requested matches
  # Fail closed: a defined permission whose level fell outside the grep window would
  # otherwise be missed, left out of the deny list, and could stop the boot.
  pl_have=" "
  while IFS=' ' read -r pl_n pl_l; do pl_have="$pl_have$pl_n "; done < "$SZ_TMP/permlevels"
  while IFS= read -r pl_q; do
    case $pl_have in *" $pl_q "*) continue ;; esac
    grep -Fxq -e "+ permission:$pl_q" -e "permission:$pl_q" -e "  permission:$pl_q" "$SZ_TMP/perms.sub" && return 1
  done < "$SZ_TMP/reqperms"
  sz_priv_scan
}

# Privileged app that now asks for a privileged permission its allowlist does not
# mention: on an enforcing Android 8+ device that can stop the next boot.
sz_priv_drift() { # pkg ; 0 = drift (sets SZ_DRIFT_PERM), 1 = none, 2 = cannot tell
  [ -n "$SZ_SDK" ] || return 2
  [ "$SZ_SDK" -ge 28 ] || { [ "$SZ_SDK" -ge 26 ] && [ "$SZ_PRIVPROP" = enforce ]; } || return 1
  sz_have dumpsys || return 2
  sz_priv_load "$1" || return 2
  while IFS= read -r pd2_p; do
    [ -f "$SZ_P_XML" ] && grep -Fq "\"$pd2_p\"" "$SZ_P_XML" && continue
    SZ_DRIFT_PERM=$pd2_p
    return 0
  done < "$SZ_TMP/priv.list"
  return 1
}
