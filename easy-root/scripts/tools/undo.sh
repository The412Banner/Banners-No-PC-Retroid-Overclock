#!/system/bin/sh
# undo.sh - Retroid Easy Root: writes the stock init_boot from your backup back to the ACTIVE slot (unroot,
# or before a firmware update). Start it with UNDO.sh in Run script as Root, or: su -c sh undo.sh
# Only writes when the backup checks out, was made on the firmware the device runs now, and the partition
# holds a Magisk-patched image. Does not restart. Result: Download/RetroidRoot/undo-result.txt (+ status/undo.txt).

. "${0%/*}/lib.sh"
find_base || exit 1
begin undo undo-result.txt

check_device
prepare_work

BK=$R/boot-backup
[ -f "$BK/init_boot$SLOT.img" ] || stop "No stock backup ($BK/init_boot$SLOT.img). Nothing was written."
check_backup "$BK" || stop "Your stock backup in $BK does not check out. Nothing was written."
FW=$(prop ro.build.display.id)
[ "$(backup_fw "$BK")" = "$FW" ] || stop "Your backup was made on firmware $(backup_fw "$BK"), but the device runs $FW. Writing it could stop the device from starting. Nothing was written."

dd if="$DEV" of="$WORK/cur.img" bs=1048576 2> /dev/null && [ "$(stat -c %s "$WORK/cur.img")" = "$DSIZE" ] || stop "Could not read $DEV."
cmp -s "$WORK/cur.img" "$STOCK" && finish ALREADY 0 "init_boot$SLOT is already stock. Nothing to do."

# What is on the partition now must be Magisk, not something unknown
if [ -f "$R/magisk_patched-init_boot$SLOT.img" ] && same_start "$R/magisk_patched-init_boot$SLOT.img" "$WORK/cur.img"; then
  log "init_boot$SLOT holds the image Retroid Easy Root wrote"
else
  if [ -x /data/adb/magisk/magiskboot ]; then
    MB=/data/adb/magisk/magiskboot
  elif find_magisk_apk && get_magisk_tools; then
    :
  fi
  is_patched "$WORK/cur.img"
  case $? in
    0) log "init_boot$SLOT holds a Magisk-patched image" ;;
    1) stop "init_boot$SLOT is not stock and not Magisk-patched. Not touching it." ;;
    *)
      [ -n "$MB" ] && stop "init_boot$SLOT is not stock and not a boot image Magisk can read. Not touching it."
      stop "Cannot tell what is on init_boot$SLOT (no magiskboot: put the Magisk APK in Download). Nothing was written."
      ;;
  esac
fi

[ "$(blockdev --getro "$DEV" 2> /dev/null)" = 1 ] && blockdev --setrw "$DEV"
for try in 1 2; do
  log "writing the stock backup to $DEV (try $try) ..."
  dd if="$STOCK" of="$DEV" bs=1048576 conv=notrunc 2> /dev/null
  sync
  if cmp -s "$DEV" "$STOCK"; then
    finish OK 0 "Done: init_boot$SLOT is stock again (checked). Restart the device. The Magisk app stays installed; uninstall it after the restart if you like."
  fi
  log "read back does not match the backup"
done
finish PROBLEM 1 "init_boot$SLOT does not match the backup after writing twice. Do NOT restart. Ask for help (Discord) and keep this file."
