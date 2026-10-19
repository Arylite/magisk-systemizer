# t-unit.sh - unit tests of the pure shell logic (validation, state, XML, parsers).
T_NAME=unit
. "$(dirname "$0")/harness.sh"
t_new
for l in core state parse xml fs; do . "$REPO/module/lib/$l.sh"; done
SZ_STATE=$MOD/state SZ_OVL=$MOD/system SZ_WORK=$MOD/.work SZ_TMP=$T_ROOT/tmp SZ_CMP=1
mkdir -p "$SZ_STATE" "$SZ_TMP" "$SZ_WORK"
FX=$HERE/fixtures

# ---- package and permission names
for n in com.example.app a.b com.example.app_2 Com.Example.X; do
  t_status "pkg ok: $n" 0 sz_valid_pkg "$n"; done
long=a.b; while [ ${#long} -lt 256 ]; do long=${long}bb; done
for n in '' com .com.x com..x com.x. 1com.x com.1x com.ex-ample 'com.ex ample' 'com.x;rm' '../x.y' \
  'com.example
rm' "$long"; do
  t_status "pkg rejected: $n" 1 sz_valid_pkg "$n"; done
t_status "perm ok" 0 sz_valid_perm android.permission.INTERNET
for n in '' x 'a b' 'a.b"/><c' 'a.b<' 'android.permission.X&y'; do
  t_status "perm rejected: $n" 1 sz_valid_perm "$n"; done

# ---- state files
st_case() { # name want key value : a good file with one key overridden
  { for k in schema:1 package:com.x.y mode:system source:installed apks:1 versioncode:7 grants:; do
      kk=${k%%:*} vv=${k#*:}; [ "$kk" != "$3" ] || vv=$4; printf '%s=%s\n' "$kk" "$vv"; done
  } > "$SZ_STATE/com.x.y.conf"
  sz_state_load com.x.y; t_eq "state $1" "$2" "$?"
}
st_case good 0 mode system
st_case "mode root" 2 mode root
st_case "schema 2" 2 schema 2
st_case "other package" 2 package com.other.z
st_case "apks 0" 2 apks 0
st_case "apks text" 2 apks x
st_case "apks 99" 2 apks 99
st_case "source url" 2 source url
st_case "versioncode junk" 2 versioncode 1x
st_case "grants glob" 2 grants 'a.b*C'
st_case "grants ok" 0 grants 'a.b.C,d.e.F'
t_eq "grant list" " a.b.C d.e.F" "$SZ_S_GRANTLIST"
rm "$SZ_STATE/com.x.y.conf"; sz_state_load com.x.y; t_eq "state missing" 1 "$?"
sz_state_write com.x.y privileged installed 3 42 a.b.C; sz_state_load com.x.y
t_eq "state roundtrip" "privileged 3 42" "$SZ_S_MODE $SZ_S_APKS $SZ_S_VCODE"
t_status "same set" 0 sz_same_set "a b" "b a"
t_status "different set" 1 sz_same_set "a b" "a c"
printf 'x.y.A\n\nx.y.B\n' > "$T_ROOT/l"; t_eq "join comma" "x.y.A,x.y.B" "$(sz_join_comma "$T_ROOT/l")"

# ---- allowlist XML
printf 'a.b.C\n' > "$T_ROOT/g"; printf 'd.e.F\ng.h.I\n' > "$T_ROOT/d"
sz_gen_xml com.x.y "$T_ROOT/g" "$T_ROOT/d" "$T_ROOT/x.xml"
t_status "xml valid" 0 sz_xml_ok "$T_ROOT/x.xml" com.x.y
t_grep "xml grant" '<permission name="a.b.C"/>' "$T_ROOT/x.xml"
t_grep "xml deny" '<deny-permission name="g.h.I"/>' "$T_ROOT/x.xml"
t_status "xml wrong package" 1 sz_xml_ok "$T_ROOT/x.xml" com.other.z
: > "$T_ROOT/none"; sz_gen_xml com.x.y "$T_ROOT/none" "$T_ROOT/none" "$T_ROOT/e.xml"
t_status "xml without entries is rejected" 1 sz_xml_ok "$T_ROOT/e.xml" com.x.y
{ head -n 4 "$T_ROOT/x.xml"; printf '        <permission name="a.b&c"/>\n    </privapp-permissions>\n</permissions>\n'; } > "$T_ROOT/b.xml"
t_status "xml bad name" 1 sz_xml_ok "$T_ROOT/b.xml" com.x.y
{ cat "$T_ROOT/x.xml"; printf '<extra/>\n'; } > "$T_ROOT/b2.xml"
t_status "xml extra line" 1 sz_xml_ok "$T_ROOT/b2.xml" com.x.y
head -n 5 "$T_ROOT/x.xml" > "$T_ROOT/b3.xml"
t_status "xml truncated" 1 sz_xml_ok "$T_ROOT/b3.xml" com.x.y

# ---- parsers (real Android 16 capture, package renamed)
t_status "dump parsed" 0 sz_parse_dump "$FX/dump-android16.txt" com.example.real
t_eq "dump version" "701046282" "$SZ_D_VCODE"
t_eq "dump version name" "10.39.34.995726622.4-release" "$SZ_D_VNAME"
t_eq "dump permission count" 22 "$(grep -c '' "$SZ_TMP/reqperms")"
t_grep "dump permission" android.permission.RECORD_AUDIO "$SZ_TMP/reqperms"
t_status "dump unknown package" 1 sz_parse_dump "$FX/dump-android16.txt" com.other.pkg
{ printf 'Packages:\n  Package [p.q.r] (1):\n    versionCode=5 minSdk=1\n    requested permissions:\n'
  printf '      android.permission.READ_SMS: restricted=true\n'
  printf 'Hidden system packages:\n  Package [p.q.r] (1):\n    versionCode=3 minSdk=1\n'; } > "$T_ROOT/h.txt"
sz_parse_dump "$T_ROOT/h.txt" p.q.r; t_eq "first block only" 5 "$SZ_D_VCODE"
t_grep "restricted suffix stripped" android.permission.READ_SMS "$SZ_TMP/reqperms"
t_nogrep "no suffix left" restricted "$SZ_TMP/reqperms"
t_status "permission table" 0 sz_parse_perms "$FX/permissions.txt" "$SZ_TMP/permlevels"
t_eq "permission count" 7 "$(grep -c '' "$SZ_TMP/permlevels")"
t_grep "level kept" 'android.permission.INTERNET normal|instant' "$SZ_TMP/permlevels"
printf 'x.y.V signature|vendorPrivileged\nx.y.S signatureOrSystem\nx.y.D dangerous\n' >> "$SZ_TMP/permlevels"
printf 'android.permission.INSTALL_PACKAGES\nandroid.permission.BIND_ACCESSIBILITY_SERVICE\nx.y.V\nx.y.S\nx.y.D\nno.such.Perm\n' > "$SZ_TMP/reqperms"
sz_priv_scan
t_eq "privileged-level" "android.permission.INSTALL_PACKAGES x.y.S" "$(tr '\n' ' ' < "$SZ_TMP/priv.list" | sed 's/ $//')"
t_eq "signature-only" "android.permission.BIND_ACCESSIBILITY_SERVICE x.y.V" "$(tr '\n' ' ' < "$SZ_TMP/sig.list" | sed 's/ $//')"

# ---- byte comparison without cmp (cksum fallback)
printf 'same\n' > "$T_ROOT/f1"; printf 'same\n' > "$T_ROOT/f2"; printf 'diff\n' > "$T_ROOT/f3"
SZ_CMP=; t_status "cksum: equal files" 0 sz_same "$T_ROOT/f1" "$T_ROOT/f2"
t_status "cksum: different files" 1 sz_same "$T_ROOT/f1" "$T_ROOT/f3"; SZ_CMP=1

# ---- deletion guard
for p in "$SZ_WORK/../x" /tmp/foo "$SZ_OVL/app" "$SZ_OVL/app/" "$SZ_OVL/etc" "$SZ_STATE/.conf" ""; do
  t_status "safe_rm refuses [$p]" 1 sz_safe_rm "$p"; done
mkdir -p "$SZ_OVL/app/com.x.y"; t_status "safe_rm accepts own entry" 0 sz_safe_rm "$SZ_OVL/app/com.x.y"
t_nofile "safe_rm deleted it" "$SZ_OVL/app/com.x.y"
t_done
