#!/system/bin/sh
# check.sh - Retroid Easy Root: read-only status report (is Magisk running, what is on init_boot, is the backup OK).
# Start it with CHECK.sh in Run script as Root, or: su -c sh check.sh
# Changes nothing on the device. Result: Download/RetroidRoot/check-result.txt (+ status/check.txt for the app).

. "${0%/*}/lib.sh"
find_base || exit 1
begin check check-result.txt

check_device
prepare_work
FW=$(prop ro.build.display.id)

# Magisk running?
MAGISK=none
if magisk_running; then
  MAGISK=running
  for m in /debug_ramdisk/magisk /product/bin/magisk /system/bin/magisk /sbin/magisk; do
    [ -x "$m" ] && { MAGISK=$("$m" -v 2> /dev/null); break; }
  done
  [ -n "$MAGISK" ] || MAGISK=running
fi
log "Magisk: $MAGISK"

# Magisk app
APP=$(dumpsys package $MAGISK_PKG 2> /dev/null | sed -n 's/^ *versionName=//p' | head -1)
[ "$T" = 1 ] && APP=$EASYROOT_APP
[ -n "$APP" ] || APP=none
log "Magisk app: $APP"

# Backup
BK=$R/boot-backup
if [ ! -f "$BK/init_boot$SLOT.img" ]; then
  BACKUP=missing
elif ! check_backup "$BK"; then
  BACKUP=bad
elif [ "$(backup_fw "$BK")" != "$FW" ]; then
  BACKUP=old-firmware
else
  BACKUP=ok
fi
log "backup: $BACKUP"

# What is on init_boot now
dd if="$DEV" of="$WORK/cur.img" bs=1048576 2> /dev/null
if [ "$BACKUP" != missing ] && cmp -s "$WORK/cur.img" "$BK/init_boot$SLOT.img"; then
  PART=stock
elif [ -f "$R/magisk_patched-init_boot$SLOT.img" ] && same_start "$R/magisk_patched-init_boot$SLOT.img" "$WORK/cur.img"; then
  PART=patched
else
  if [ -x /data/adb/magisk/magiskboot ]; then
    MB=/data/adb/magisk/magiskboot
  elif find_magisk_apk && get_magisk_tools; then
    :
  fi
  is_patched "$WORK/cur.img"
  case $? in 0) PART=patched ;; 1) PART=not-patched ;; *) PART=unknown ;; esac
fi
log "init_boot$SLOT: $PART (sha256 $(sha256sum "$WORK/cur.img" | cut -d' ' -f1))"
log "other slot init_boot: sha256 $(head -c "$DSIZE" "$DEVDIR/init_boot$([ "$SLOT" = _a ] && echo _b || echo _a)" 2> /dev/null | sha256sum | cut -d' ' -f1)"
log "SELinux: $(getenforce 2> /dev/null)  verified boot: $(prop ro.boot.verifiedbootstate)"

if [ "$MAGISK" != none ]; then
  STATE=ROOTED
  MSG="Rooted: Magisk $MAGISK is running."
elif [ "$PART" = patched ]; then
  STATE=FLASHED
  MSG="Magisk is written to init_boot$SLOT but not running yet. Restart the device."
elif [ "$PART" = stock ] || [ "$PART" = not-patched ]; then
  STATE=STOCK
  MSG="Not rooted: init_boot$SLOT is stock."
else
  STATE=UNKNOWN
  MSG="Could not tell what is on init_boot$SLOT."
fi
[ "$BACKUP" = ok ] || MSG="$MSG Backup: $BACKUP."

STATUS_EXTRA="STATE=$STATE
MAGISK=$MAGISK
MAGISK_APP=$APP
PARTITION=$PART
BACKUP=$BACKUP
FIRMWARE=$FW
SLOT=$SLOT"
finish OK 0 "$MSG"
