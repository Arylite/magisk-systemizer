# t-cli.sh - argument validation and the install / status / refresh / remove cycle.
T_NAME=cli
. "$(dirname "$0")/harness.sh"
P=com.example.app
DATA=
t_new

# ---- usage errors exit 2
t_cli help; t_rc help 0; t_out "help text" "Usage: systemizer"
t_cli version; t_rc version 0; t_out "version" "systemizer v"
for a in "bogus" "install" "install bad_name" "install com" "install ../../x.y" "install com.a.b com.c.d" \
  "install com.a.b --package com.c.d" "install com.a.b --mode root" "install com.a.b --nope" \
  "install --mode" "install com.a.b --grant android.permission.X" "install com.a.b --grant bad;x --mode privileged" \
  "remove" "remove bad_name" "refresh" "refresh --all com.a.b" "status bad_name"; do
  t_cli $a; t_rc "usage: $a" 2
done
t_cli install com.a.b; t_rc "not installed" 3
t_cli status com.a.b; t_rc "status of unmanaged" 3
t_cli remove com.a.b; t_rc "remove of unmanaged is a no-op" 0
t_cli refresh com.a.b; t_rc "refresh of unmanaged" 3

# ---- install, idempotence, status
t_new; t_app $P 100 1; A=$T_ROOT/data/app/~~r1==/$P-h1==/base.apk
t_cli install --dry-run $P; t_rc "dry run" 0; t_nofile "dry run leaves no overlay" "$MOD/system/app/$P"
t_nofile "dry run leaves no state" "$MOD/state/$P.conf"
t_cli install $P; t_rc install 0; t_out "reboot hint" Reboot
t_noout "no stray shell errors" "No such file"; t_noout "no stray shell errors (2)" "line "
t_same "APK copied byte for byte" "$(t_ovl $P)" "$A"
t_grep "state: mode" mode=system "$MOD/state/$P.conf"; t_grep "state: version" versioncode=100 "$MOD/state/$P.conf"
t_cli install $P; t_rc "install again" 0; t_out "second run is a no-op" "Nothing to do"
t_cli install $P --mode privileged; t_rc "mode change is refused" 7
t_cli status $P; t_rc "status fresh" 0; t_out "status text" "up to date"; t_out "pending reboot" "pending reboot"
mkdir -p "$T_ROOT/sys/app/$P"; t_cli status $P; t_out "active once mounted" "Active:     yes"
t_cli list --managed; t_out "managed list" "$P  [managed, system]"
t_cli list; t_out "user list" "$P  [managed]"

# ---- an update makes the overlay stale; refresh fixes it
t_app $P 101 1
t_cli status $P; t_rc "stale status" 6; t_out "stale text" STALE
t_cli install $P; t_rc "install on stale" 6; t_out "points to refresh" "systemizer refresh"
t_cli refresh --dry-run $P; t_rc "refresh dry run" 0; t_grep "dry run kept old APK" v100 "$(t_ovl $P)"
t_cli refresh $P; t_rc refresh 0; t_same "overlay updated" "$(t_ovl $P)" "$A"; t_grep "state version" versioncode=101 "$MOD/state/$P.conf"
t_cli refresh $P; t_rc "refresh again" 0; t_out "up to date" "up to date"
t_cli status; t_rc "summary" 0; t_out "summary line" "$P  system  up to date"
t_cli refresh --all; t_rc "refresh --all" 0

# ---- split APKs and odd paths
t_app com.example.split 7 3; t_cli install com.example.split; t_rc "split install" 0
for f in base.apk split_2.apk split_3.apk; do t_file "split file $f" "$MOD/system/app/com.example.split/$f"; done
t_same "split content" "$MOD/system/app/com.example.split/split_2.apk" "$T_ROOT/data/app/~~r1==/com.example.split-h1==/split_config.x2.apk"
t_grep "state counts splits" apks=3 "$MOD/state/com.example.split.conf"
t_app com.example.split 8 2; t_cli status com.example.split; t_rc "split set changed" 6
t_cli refresh com.example.split; t_rc "split refresh" 0; t_nofile "dropped split is gone" "$MOD/system/app/com.example.split/split_3.apk"
T_SPACE=1; t_app com.example.space 1 2; T_SPACE=
t_cli install com.example.space; t_rc "paths with spaces" 0; t_file "spaced copy" "$MOD/system/app/com.example.space/split_2.apk"

# ---- remove and reinstall
t_cli remove $P; t_rc remove 0; t_nofile "overlay gone" "$MOD/system/app/$P"; t_nofile "state gone" "$MOD/state/$P.conf"
t_cli remove $P; t_rc "remove twice" 0; t_out "remove twice text" "Nothing to do"
t_cli install $P; t_rc reinstall 0; t_file "reinstalled" "$(t_ovl $P)"
printf 'package:/system/app/%s/base.apk\n' $P > "$FAKE/path.$P"
t_cli remove $P; t_rc "no user copy needs consent" 2; t_file "still there" "$(t_ovl $P)"
t_cli remove --yes $P; t_rc "consent given" 0; t_nofile "removed" "$MOD/system/app/$P"

# ---- apps that are already system apps
printf 'package:/system/app/Foo/Foo.apk\n' > "$FAKE/path.com.example.sys"
t_cli install com.example.sys; t_rc "unmanaged system app" 7; t_out "says why" "already a system app"
printf 'package:/data/app/x/base.apk\npackage:/system/app/y/y.apk\n' > "$FAKE/path.com.example.mix"
t_cli install com.example.mix; t_rc "mixed locations" 5
t_done
