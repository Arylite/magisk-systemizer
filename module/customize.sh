# Sourced by the Magisk installer (never executed): do not call exit.

[ "${API:-0}" -ge 21 ] || abort "! Android 5.0 (API 21) or newer is required"

# Magisk wipes $MODPATH before this runs. In the app (BOOTMODE) the previous
# version is still in /data/adb/modules until the next reboot, so carry the
# managed apps over. A recovery flash writes straight into the live module dir,
# so there is nothing left to copy.
MODROOT=${NVBASE:-/data/adb}/modules
OLD=$MODROOT/$MODID
if [ "$BOOTMODE" = true ] && [ -d "$OLD" ]; then
  ui_print "- Keeping apps managed by the previous version"
  for d in state system/app system/priv-app system/etc/permissions; do
    [ -d "$OLD/$d" ] || continue
    mkdir -p "$MODPATH/$d" || abort "! Cannot create $d"
    cp -a "$OLD/$d/." "$MODPATH/$d/" || abort "! Cannot copy $d from the previous version"
  done
  for d in system/app system/priv-app system/etc; do
    [ -d "$MODPATH/$d" ] && set_perm_recursive "$MODPATH/$d" 0 0 0755 0644 u:object_r:system_file:s0
  done
elif [ "$BOOTMODE" != true ]; then
  ui_print "- Recovery flash: apps managed by an older version are not kept"
fi

ui_print "- Reboot, then run:  su -c \"systemizer help\""
ui_print "- Before the first reboot:  su -c \"sh $MODROOT/$MODID/system/bin/systemizer help\""
