# t-apk.sh - --apk: identity is proven, never guessed from names.
T_NAME=apk
. "$(dirname "$0")/harness.sh"
P=com.example.app N=com.example.new
app() { t_new; t_app $P 5 1; A=$T_ROOT/data/app/~~r1==/$P-h1==/base.apk
        cp "$A" "$T_ROOT/copy.apk"; printf 'other bytes\n' > "$T_ROOT/other.apk"; }
aapt() { t_shim aapt2 'printf "%s\n" "$AAPT_NAME"'; SYSTEMIZER_AAPT=$T_ROOT/bin/aapt2 AAPT_NAME=$1
         export SYSTEMIZER_AAPT AAPT_NAME; }

# ---- no aapt: only a byte-identical copy of an installed APK is accepted
app
t_cli install --apk "$T_ROOT/copy.apk"; t_rc "name unknown" 4; t_out "explains" "no aapt"
t_cli install --apk "$T_ROOT/other.apk" --package $P; t_rc "different build" 5; t_out "signature" "signature"
t_cli install --apk "$T_ROOT/missing.apk" --package $P; t_rc "missing file" 3
cp "$T_ROOT/copy.apk" "$T_ROOT/copy.bin"; t_cli install --apk "$T_ROOT/copy.bin" --package $P; t_rc "not an .apk" 2
t_cli install --apk "$T_ROOT/copy.apk" --package $N; t_rc "wrong package for the bytes" 4
t_cli install --apk "$T_ROOT/other.apk" --package $N; t_rc "unknown app, no aapt" 4
t_nofile "nothing published so far" "$MOD/system/app/$P"
t_cli install --apk "$T_ROOT/copy.apk" --package $P; t_rc "identical copy" 0
t_grep "treated as the installed app" source=installed "$MOD/state/$P.conf"; t_same "overlay" "$(t_ovl $P)" "$A"
t_cli install --apk "$T_ROOT/copy.apk" --package $P; t_rc "repeat" 0
app; ( cd "$T_ROOT" && "$T_SH" "$CLI" install --apk copy.apk --package $P > /dev/null 2>&1 ); t_eq "relative path" 0 "$?"
app; t_app com.example.sp 1 2; cp "$T_ROOT/data/app/~~r1==/com.example.sp-h1==/base.apk" "$T_ROOT/sp.apk"
t_cli install --apk "$T_ROOT/sp.apk" --package com.example.sp; t_rc "split app" 5; t_out "says split" split

# ---- with aapt: an app that is not installed can be systemized from a file
app; aapt $N
t_cli install --apk "$T_ROOT/other.apk"; t_rc "from a file" 0; t_out "source" "Source:   file"
t_grep "state source" source=file "$MOD/state/$N.conf"; t_same "overlay" "$MOD/system/app/$N/base.apk" "$T_ROOT/other.apk"
t_cli refresh $N; t_rc "file apps are not refreshed" 7
t_cli install --apk "$T_ROOT/other.apk" --package $P; t_rc "name mismatch" 5; t_out "both names" "$N"
t_cli install --apk "$T_ROOT/other.apk" $P; t_rc "positional mismatch" 5
app; aapt 'bad name'; t_cli install --apk "$T_ROOT/other.apk"; t_rc "unreadable name" 4
app; aapt $N; t_cli install --apk "$T_ROOT/other.apk" --mode privileged; t_rc "privileged needs the app installed" 4
app; aapt $P; t_cli install --apk "$T_ROOT/other.apk"; t_rc "aapt says installed app, other bytes" 5
t_cli install --apk "$T_ROOT/copy.apk"; t_rc "aapt, identical bytes" 0

# ---- the file is swapped by another app after it was checked (shared storage race)
app; aapt $N; cp "$T_ROOT/other.apk" "$T_ROOT/orig.apk"
t_shim aapt2 'printf "%s\n" "$AAPT_NAME"; printf "evil\n" > "$SWAP"'; SWAP=$T_ROOT/other.apk; export SWAP
t_cli install --apk "$T_ROOT/other.apk"; t_rc "swapped after the check" 0
t_same "the overlay holds the checked bytes" "$MOD/system/app/$N/base.apk" "$T_ROOT/orig.apk"

# ---- without cmp, the forgeable cksum never proves identity
app; SYSTEMIZER_NO_CMP=1; export SYSTEMIZER_NO_CMP
t_cli install --apk "$T_ROOT/copy.apk" --package $P; t_rc "no cmp: identity unproven" 4; t_out "explains" "cmp is missing"
t_nofile "nothing published" "$MOD/system/app/$P"; unset SYSTEMIZER_NO_CMP
t_done
