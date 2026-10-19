# t-module.sh - the Magisk side: customize.sh upgrade path and the ZIP itself.
T_NAME=module
. "$(dirname "$0")/harness.sh"
t_new

# ---- customize.sh with the Magisk helpers stubbed out
ui_print() { echo "$1" >> "$T_ROOT/log"; }
abort() { echo "$1" >> "$T_ROOT/abort"; }
set_perm_recursive() { echo "$*" >> "$T_ROOT/perm"; }
OLD=$T_ROOT/adb/modules/arylite.systemizer
mkdir -p "$OLD/state" "$OLD/system/app/com.x.y" "$OLD/system/priv-app/com.p.q" "$OLD/system/etc/permissions"
echo 'schema=1' > "$OLD/state/com.x.y.conf"; echo apk > "$OLD/system/app/com.x.y/base.apk"
echo apk > "$OLD/system/priv-app/com.p.q/base.apk"; echo xml > "$OLD/system/etc/permissions/privapp-permissions-com.p.q.xml"
run_customize() { # BOOTMODE API
  rm -rf "$T_ROOT/new" "$T_ROOT/log" "$T_ROOT/abort" "$T_ROOT/perm"; mkdir -p "$T_ROOT/new"
  MODPATH=$T_ROOT/new MODID=arylite.systemizer NVBASE=$T_ROOT/adb BOOTMODE=$1 API=$2
  . "$REPO/module/customize.sh"
}
run_customize true 33
t_file "state carried over" "$T_ROOT/new/state/com.x.y.conf"
t_file "app overlay carried over" "$T_ROOT/new/system/app/com.x.y/base.apk"
t_file "priv-app carried over" "$T_ROOT/new/system/priv-app/com.p.q/base.apk"
t_file "allowlist carried over" "$T_ROOT/new/system/etc/permissions/privapp-permissions-com.p.q.xml"
t_nofile "no abort on a normal upgrade" "$T_ROOT/abort"; t_grep "labels restored" system_file "$T_ROOT/perm"
t_grep "tells where the CLI is" "systemizer help" "$T_ROOT/log"
run_customize false 33; t_nofile "recovery flash copies nothing" "$T_ROOT/new/state"; t_grep "recovery warning" "not kept" "$T_ROOT/log"
run_customize true 20; t_file "Android 4.4 is refused" "$T_ROOT/abort"
rm -rf "$OLD"; run_customize true 33; t_nofile "first install has nothing to carry" "$T_ROOT/new/state"; t_nofile "no abort on first install" "$T_ROOT/abort"

# ---- the ZIP (needs python 3; skipped otherwise)
PY=; for c in python3 python; do "$c" -c 'import zipfile' > /dev/null 2>&1 && { PY=$c; break; }; done
if [ -z "$PY" ]; then echo "SKIP zip checks: python 3 not found"; t_done; exit $?; fi
Z=$T_ROOT/out/arylite.systemizer-v0.1.0.zip
"$PY" "$REPO/build.py" --out "$T_ROOT/out" > /dev/null; t_eq "build" 0 "$?"; t_file "zip exists" "$Z"
"$PY" "$REPO/build.py" --out "$T_ROOT/out2" > /dev/null; t_same "reproducible build" "$Z" "$T_ROOT/out2/arylite.systemizer-v0.1.0.zip"
zl() { "$PY" -c 'import sys,zipfile; sys.stdout.buffer.write(chr(10).join(zipfile.ZipFile(sys.argv[1]).namelist()).encode())' "$Z"; }
zp() { "$PY" -c 'import sys,zipfile; sys.stdout.buffer.write(zipfile.ZipFile(sys.argv[1]).read(sys.argv[2]))' "$Z" "$1"; }
L=$(zl); case $L in *\\*) t_bad "forward slashes only" "$L" ;; *) t_pass ;; esac
for f in module.prop customize.sh system/bin/systemizer lib/core.sh META-INF/com/google/android/update-binary; do
  case "
$L
" in *"
$f
"*) t_pass ;; *) t_bad "zip contains $f" ;; esac; done
case $L in *state/*|*.work*|*tests*) t_bad "no runtime or dev files in the zip" "$L" ;; *) t_pass ;; esac
t_eq "updater-script" "#MAGISK" "$(zp META-INF/com/google/android/updater-script)"
t_eq "module id" "id=arylite.systemizer" "$(zp module.prop | head -n 1)"
# the build refuses bad input
bad() { rm -rf "$T_ROOT/b"; cp -R "$REPO/module" "$T_ROOT/b"; }
bad; printf 'x\r\n' >> "$T_ROOT/b/lib/core.sh"; "$PY" "$REPO/build.py" --src "$T_ROOT/b" --out "$T_ROOT/o3" > /dev/null 2>&1; t_eq "CR is refused" 1 "$?"
bad; printf '# caf\303\251\n' >> "$T_ROOT/b/lib/core.sh"; "$PY" "$REPO/build.py" --src "$T_ROOT/b" --out "$T_ROOT/o3" > /dev/null 2>&1; t_eq "non-ASCII is refused" 1 "$?"
bad; rm "$T_ROOT/b/customize.sh"; "$PY" "$REPO/build.py" --src "$T_ROOT/b" --out "$T_ROOT/o3" > /dev/null 2>&1; t_eq "missing file is refused" 1 "$?"
bad; sed 's/^id=.*/id=1bad id/' "$REPO/module/module.prop" > "$T_ROOT/b/module.prop"; "$PY" "$REPO/build.py" --src "$T_ROOT/b" --out "$T_ROOT/o3" > /dev/null 2>&1; t_eq "bad id is refused" 1 "$?"
t_done
