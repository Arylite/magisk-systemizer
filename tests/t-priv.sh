# t-priv.sh - privileged mode: allowlist contents, refusals, drift, per-Android-version rules.
T_NAME=privileged
. "$(dirname "$0")/harness.sh"
P=com.example.priv
IP=android.permission.INSTALL_PACKAGES MU=android.permission.MANAGE_USERS
WS=android.permission.WRITE_SECURE_SETTINGS BA=android.permission.BIND_ACCESSIBILITY_SERVICE
DP=android.permission.DELETE_PACKAGES NET=android.permission.INTERNET
priv() { t_new; t_app $P 1 1 "$@"; X=$MOD/system/etc/permissions/privapp-permissions-$P.xml; }

# ---- nothing granted: every requested privileged permission is denied explicitly
priv $IP $MU $NET $BA
t_cli install $P --mode privileged; t_rc install 0; t_out "plan" "granted: 0  denied: 2"; t_out "signature note" "Signature-only"
t_out "names are listed" "  denied: $IP"; t_out "signature-only is named" "  signature-only: $BA"
t_file "app in priv-app" "$MOD/system/priv-app/$P/base.apk"; t_nofile "not in app" "$MOD/system/app/$P"
t_grep "deny 1" "<deny-permission name=\"$IP\"/>" "$X"; t_grep "deny 2" "<deny-permission name=\"$MU\"/>" "$X"
t_nogrep "no grant" "<permission name=" "$X"; t_nogrep "normal permission left out" "$NET" "$X"
t_nogrep "signature permission left out" "$BA" "$X"; t_grep "state mode" mode=privileged "$MOD/state/$P.conf"
t_cli install $P; t_rc "mode downgrade is refused" 7
t_cli install $P --mode privileged; t_rc "same request again" 0; t_out "no-op" "Nothing to do"
t_cli install $P --mode privileged --grant $IP; t_rc "other grants are refused" 7

# ---- one explicit grant (given twice), the rest denied
priv $IP $MU
t_cli install $P --mode privileged --grant $IP --grant $IP; t_rc "grant" 0
t_grep "granted" "<permission name=\"$IP\"/>" "$X"; t_grep "other denied" "<deny-permission name=\"$MU\"/>" "$X"
t_eq "listed once" 1 "$(grep -c "name=\"$IP\"" "$X")"; t_grep "state keeps the grant" "grants=$IP" "$MOD/state/$P.conf"
t_cli status $P; t_rc "status" 0; t_out "granted shown" "Granted:"
t_cli remove $P; t_rc remove 0; t_nofile "priv-app gone" "$MOD/system/priv-app/$P"; t_nofile "allowlist gone" "$X"

# ---- refused grants leave nothing behind
priv $IP $BA $NET
t_cli install $P --mode privileged --grant $BA; t_rc "signature-level" 4; t_out "explains" "platform key"
t_cli install $P --mode privileged --grant $DP; t_rc "not requested" 2
t_cli install $P --mode privileged --grant $NET; t_rc "not privileged-level" 2
t_nofile "nothing published" "$MOD/system/priv-app/$P"; t_nofile "no state" "$MOD/state/$P.conf"; t_nofile "no allowlist" "$X"

# ---- Android version rules
priv $IP; t_prop ro.build.version.sdk 25
t_cli install $P --mode privileged --grant $IP; t_rc "grant before Android 8" 4
t_cli install $P --mode privileged; t_rc "plain priv-app before Android 8" 0; t_nofile "no allowlist mechanism" "$X"
priv $IP $MU; t_prop ro.build.version.sdk 27
t_cli install $P --mode privileged --grant $IP; t_rc "Android 8.1" 0
t_grep "grant written" "<permission name=\"$IP\"/>" "$X"; t_nogrep "no deny element before Android 9" deny-permission "$X"
priv $NET; t_cli install $P --mode privileged; t_rc "no privileged permission asked" 0; t_nofile "no allowlist needed" "$X"

# ---- environment problems
priv $IP; rm -rf "$T_ROOT/sys/priv-app"; t_cli install $P --mode privileged; t_rc "no priv-app directory" 4
priv $IP; t_shim dumpsys 'exit 0'; t_cli install $P --mode privileged; t_rc "dumpsys gives nothing" 1
priv $IP; : > "$FAKE/permissions"; t_cli install $P --mode privileged; t_rc "empty permission table" 1
t_nofile "failed install leaves no overlay" "$MOD/system/priv-app/$P"
priv $IP; t_prop ro.control_privapp_permissions disable; t_cli install $P --mode privileged; t_rc "allowlist ignored by device" 0
t_out "warns" "grants every privileged permission"

# ---- the app changes after install: drift is reported and refresh repairs it
priv $IP; t_cli install $P --mode privileged; t_dump $P 1 $IP $WS
t_cli status $P; t_rc "drift" 6; t_out "names the permission" "$WS"; t_out "boot warning" "boot risk"
t_cli refresh $P; t_rc "refresh repairs the allowlist" 0; t_grep "new permission denied" "<deny-permission name=\"$WS\"/>" "$X"
t_cli status $P; t_rc "clean again" 0
t_app $P 2 1 $NET; t_cli refresh $P; t_rc "update drops its privileged permissions" 0
t_nofile "allowlist removed when not needed" "$X"; t_file "app updated" "$MOD/system/priv-app/$P/base.apk"
t_done
