#!/bin/sh
# device-smoke.sh - run the real CLI on a connected phone, inside a scratch directory.
#   sh tests/device-smoke.sh [adb-serial]
# No root and no system change: the module is pushed to /data/local/tmp/sz-smoke and
# run as the adb shell user (the phone's own mksh + toybox + real pm / dumpsys)
# against a fake /system inside that directory. The directory is deleted at the end.
cd "$(dirname "$0")/.." || exit 1
export MSYS_NO_PATHCONV=1 # Git Bash on Windows would rewrite /data/... into a Windows path
ADB="adb${1:+ -s $1}"
D=/data/local/tmp/sz-smoke
PASS=0 FAIL=0
ok()  { PASS=$((PASS + 1)); }
bad() { FAIL=$((FAIL + 1)); printf 'FAIL %s\n' "$1"; [ -z "$2" ] || printf '%s\n' "$2" | head -n 8; }
dsh() { $ADB shell "$1" | tr -d '\r'; }
run() { # arguments of the CLI -> OUT, RC
  OUT=$(dsh "cd $D && SYSTEMIZER_TESTING=1 SYSTEMIZER_NO_CHCON=1 SYSTEMIZER_MODDIR=$D/mod SYSTEMIZER_SYSTEM=$D/sys sh $D/mod/system/bin/systemizer $* 2>&1; echo RC=\$?")
  RC=${OUT##*RC=}; OUT=${OUT%RC=*}
}
want() { if [ "$RC" = "$2" ]; then ok; else bad "$1: exit $RC, wanted $2" "$OUT"; fi; }
has()  { case $OUT in *"$2"*) ok ;; *) bad "$1: output lacks [$2]" "$OUT" ;; esac; }

$ADB get-state > /dev/null 2>&1 || { echo "no device"; exit 2; }
echo "device: $(dsh 'getprop ro.product.model; getprop ro.build.version.release; echo shell=$0; id -u' | tr '\n' ' ')"
dsh "rm -rf $D; mkdir -p $D/sys/app $D/sys/priv-app $D/sys/etc/permissions" > /dev/null
$ADB push module $D/mod > /dev/null 2>&1 || { echo "push failed"; exit 2; }
trap 'dsh "rm -rf $D" > /dev/null' EXIT

# One single-APK app, one split app, one more single-APK app, all user-installed.
PICK=$(dsh 'for p in $(pm list packages -3 | cut -d: -f2); do echo "$(pm path $p | wc -l) $p"; done')
A1=$(printf '%s\n' "$PICK" | awk '$1 == 1 {print $2; exit}')
A3=$(printf '%s\n' "$PICK" | awk '$1 == 1 {print $2}' | sed -n 2p)
A2=$(printf '%s\n' "$PICK" | awk '$1 > 1 {print $2; exit}')
echo "apps: single=$A1 split=$A2 other=$A3"
[ -n "$A1" ] && [ -n "$A2" ] && [ -n "$A3" ] || { echo "need two single-APK apps and one split app"; exit 2; }

run version; want version 0
run doctor; want doctor 0; has "doctor summary" "0 failure(s)"
run list; want list 0; has "list shows the app" "$A1"
run install bad_name; want "invalid name" 2
run install no.such.package; want "unknown package" 3
run install "$A1" --dry-run; want "dry run" 0
run status "$A1"; want "dry run left nothing" 3
run install "$A1"; want install 0
OV=$D/mod/system/app/$A1/base.apk
dsh "cmp $OV \$(pm path $A1 | cut -d: -f2) && echo SAME" | grep -q SAME && ok || bad "overlay APK is not byte-identical to the installed one"
run install "$A1"; want "install again" 0; has "idempotent" "Nothing to do"
run status "$A1"; want status 0; has "status text" "up to date"
run list --managed; has "managed list" "$A1"
run install "$A2"; want "split app" 0
N=$(dsh "pm path $A2 | wc -l"); M=$(dsh "ls $D/mod/system/app/$A2 | wc -l")
[ "$N" = "$M" ] && ok || bad "split app: $N installed APK files but $M copied"
run status "$A2"; want "split status" 0
run install "$A3" --mode privileged --dry-run; want "privileged plan on real dumpsys/pm output" 0
has "real permission table parsed" "Privileged permissions requested:"
echo "privileged plan for $A3: $(printf '%s' "$OUT" | grep 'requested:')"
run install "$A3" --mode privileged --grant android.permission.NO_SUCH_THING --dry-run; want "grant of an unrequested permission" 2
# An installed app that really requests privileged permissions (found with dumpsys), if any.
PA=$(dsh 'for p in $(pm list packages -3 | cut -d: -f2); do dumpsys package $p | grep -q -E "^      android.permission.(WRITE_SECURE_SETTINGS|MANAGE_USERS|MODIFY_PHONE_STATE|INSTALL_PACKAGES|DELETE_PACKAGES|DUMP|READ_LOGS)\$" && { echo $p; break; }; done')
if [ -n "$PA" ]; then
  X=$D/mod/system/etc/permissions/privapp-permissions-$PA.xml
  run install "$PA" --mode privileged; want "privileged install of $PA" 0
  dsh "test -f $D/mod/system/priv-app/$PA/base.apk && echo yes" | grep -q yes && ok || bad "APK not in priv-app"
  G=$(dsh "grep deny-permission $X | head -n 1 | cut -d'\"' -f2")
  [ -n "$G" ] && ok || bad "no deny-permission entry in the allowlist" "$(dsh "cat $X")"
  run remove "$PA"; want "remove privileged app" 0
  dsh "test -e $X && echo left" | grep -q left && bad "allowlist left behind after remove" || ok
  run install "$PA" --mode privileged --grant "$G"; want "explicit grant $G" 0
  dsh "grep -c '<permission name=\"$G\"/>' $X" | grep -q 1 && ok || bad "grant not written as <permission>" "$(dsh "cat $X")"
  run status "$PA"; want "status of the privileged app" 0
  echo "privileged app tested: $PA, granted $G"
  run remove "$PA"; want "remove the privileged app again" 0
else echo "SKIP: no installed app requests a privileged permission"; fi
run remove "$A1"; want remove 0
run remove "$A2"; want "remove split app" 0
run list --managed; has "nothing managed any more" "No managed apps"
run doctor; want "doctor after cleanup" 0
printf 'device smoke: %s passed, %s failed\n' "$PASS" "$FAIL"
[ $FAIL -eq 0 ]
