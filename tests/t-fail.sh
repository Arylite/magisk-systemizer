# t-fail.sh - failures, interrupted runs, corrupt state, module flags, locking.
T_NAME=failures
. "$(dirname "$0")/harness.sh"
P=com.example.app
app() { t_new; t_app $P 1 1; A=$T_ROOT/data/app/~~r1==/$P-h1==/base.apk; }
clean() { t_eq "$1: work dir is clean" "" "$(ls -A "$MOD/.work" 2>/dev/null)"; }

# ---- unsupported layout
app; rm -rf "$T_ROOT/sys/app"
t_cli install $P; t_rc "no /system/app" 4; t_cli doctor; t_rc "doctor" 4; t_out "doctor says FAIL" "[FAIL]"
app; t_cli doctor; t_rc "doctor on a good device" 0; t_out "doctor summary" "0 failure(s)"
app; t_shim getprop 'exit 0'; t_cli doctor; t_out "no getprop is a warning" "cannot read the Android API level"

# ---- a failed copy changes nothing (transaction)
app; t_shim cp 'exit 1'
if "$T_SH" -c 'cp /dev/null "$0"' "$T_ROOT/cp-probe" 2> /dev/null; then
  echo "SKIP copy failure: $T_SH runs cp as a built-in, a fake cp cannot replace it"
else
  t_cli install $P; t_rc "copy failure" 1; t_nofile "no overlay" "$MOD/system/app/$P"; t_nofile "no state" "$MOD/state/$P.conf"; clean "copy failure"
fi
app; mkdir -p "$MOD/.work/stage.1/x" "$MOD/.work/trash/y"
t_cli install $P; t_rc "leftovers of a killed run" 0; clean "after leftovers"

# ---- SELinux: never disabled, fatal only when enforcing
app; t_shim chcon 'exit 1'
t_cli install $P; t_rc "chcon fails, permissive" 0
app; printf 'Enforcing\n' > "$FAKE/enforce"; t_shim chcon 'exit 1'
t_cli install $P; t_rc "chcon fails, enforcing" 1; t_out "says so" chcon; t_nofile "nothing published" "$MOD/system/app/$P"
app; printf 'Enforcing\n' > "$FAKE/enforce"; t_cli doctor; t_out "never changes SELinux" "never changes it"

# ---- missing APK behind pm path
app; rm "$A"; t_cli install $P; t_rc "APK vanished" 5; t_nofile "nothing published" "$MOD/system/app/$P"

# ---- interrupted install: overlay without state
app; mkdir -p "$MOD/system/app/$P"; echo junk > "$MOD/system/app/$P/base.apk"
t_cli doctor; t_rc "doctor tolerates it" 0; t_out "doctor flags it" "overlay directory without state"
t_cli install $P; t_rc "install repairs" 0; t_out "warns" "incomplete overlay"; t_same "real APK in place" "$(t_ovl $P)" "$A"
t_cli doctor; t_noout "doctor is clean" "without state"

# ---- corrupt state and broken overlay
app; t_cli install $P; printf 'garbage\n' > "$MOD/state/$P.conf"
t_cli install $P; t_rc "corrupt state, install" 1; t_out "explains" corrupt
t_cli status $P; t_rc "corrupt state, status" 1; t_cli doctor; t_rc "corrupt state, doctor" 4
t_cli remove $P; t_rc "remove cleans it" 0; t_nofile "state gone" "$MOD/state/$P.conf"; t_nofile "overlay gone" "$MOD/system/app/$P"
t_cli install $P; t_rc "install after cleanup" 0
rm "$(t_ovl $P)"; t_cli status $P; t_rc "broken overlay" 1; t_out "says BROKEN" BROKEN
t_cli install $P; t_rc "install does not paper over it" 1
t_cli refresh $P; t_rc "refresh repairs it" 0; t_cli status $P; t_rc "healthy again" 0
rm "$FAKE/path.$P"; t_cli refresh $P; t_rc "app not visible to pm" 3

# ---- module flags
app; touch "$MOD/remove"; t_cli install $P; t_rc "module scheduled for removal" 7
app; touch "$MOD/update"; t_cli install $P; t_rc "module update pending" 7; t_out "asks for a reboot" reboot
app; touch "$MOD/disable"; t_cli install $P; t_rc "module disabled" 0; t_out "warns it is inactive" inactive
t_cli status $P; t_out "status says inactive" "module disabled"; t_cli doctor; t_out "doctor sees the flag" "flag file present: disable"

# ---- lock
app; mkdir -p "$MOD/.work"; echo $$ > "$MOD/.work/lock"
t_cli install $P; t_rc "live lock" 1; t_out "names the cause" "another systemizer"; t_nofile "nothing published" "$MOD/system/app/$P"
t_eq "live lock kept" $$ "$(cat "$MOD/.work/lock")"
echo 999999 > "$MOD/.work/lock"; echo 999999 > "$MOD/.work/lock.999999"
t_cli install $P; t_rc "stale lock" 0; clean "stale lock"
app; mkdir -p "$MOD/.work/lock"; echo 999999 > "$MOD/.work/lock/pid"
t_cli install $P; t_rc "v0.1.0 lock directory" 0; clean "v0.1.0 lock directory"

# ---- root ignores the caller's environment: no test hooks, no inherited PATH
app; mkdir -p "$T_ROOT/evil/lib"; printf 'id=arylite.systemizer\n' > "$T_ROOT/evil/module.prop"
printf 'touch "%s"\n' "$T_ROOT/pwned" > "$T_ROOT/evil/lib/core.sh"
SYSTEMIZER_MODDIR=$T_ROOT/evil; CLI_MOD=$MOD/system/bin/systemizer
"$T_SH" "$CLI_MOD" version > /dev/null 2>&1; t_file "control: hooks work for a non-root user" "$T_ROOT/pwned"
rm -f "$T_ROOT/pwned"; t_shim id 'echo 0'; "$T_SH" "$CLI_MOD" version > /dev/null 2>&1
t_nofile "root: SYSTEMIZER_MODDIR is ignored" "$T_ROOT/pwned"
t_shim id 'echo'; "$T_SH" "$CLI_MOD" version > /dev/null 2>&1; t_nofile "unknown uid counts as root" "$T_ROOT/pwned"

# ---- an update of a preinstalled app is never shadowed
app; sed 's/flags=\[ HAS_CODE \]/flags=[ SYSTEM HAS_CODE UPDATED_SYSTEM_APP ]/' "$FAKE/dump.$P" > "$FAKE/d" && mv "$FAKE/d" "$FAKE/dump.$P"
t_cli install $P; t_rc "updated system app" 7; t_out "explains" "preinstalled"; t_nofile "nothing published" "$MOD/system/app/$P"

# ---- another module already ships the package
app; mkdir -p "$T_ROOT/mod2/system/app/$P"; printf 'id=other.module\n' > "$T_ROOT/mod2/module.prop"
t_cli install $P; t_rc "clash" 7; t_out "names the module" mod2; t_nofile "nothing published" "$MOD/system/app/$P"
touch "$T_ROOT/mod2/disable"; t_cli install $P; t_rc "disabled module does not clash" 0
t_done
