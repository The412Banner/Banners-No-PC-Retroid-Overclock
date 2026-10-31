#!/system/bin/sh
# backup.sh - Retroid Easy Root: saves your stock boot partitions (both slots) to Download/RetroidRoot/boot-backup.
# Start it with BACKUP.sh in Run script as Root, or: su -c sh backup.sh
# Only reads partitions, never writes one. A backup that is already there is checked, not replaced.
# ROOT.sh makes the same backup when there is none; this lets you make it and copy it off the device first.
# Result: Download/RetroidRoot/backup-result.txt (+ status/backup.txt for the app).

. "${0%/*}/lib.sh"
find_base || exit 1
begin backup backup-result.txt

check_device
prepare_work
FW=$(prop ro.build.display.id)
BK=$R/boot-backup

dd if="$DEV" of="$WORK/cur.img" bs=1048576 2> /dev/null && [ "$(stat -c %s "$WORK/cur.img")" = "$DSIZE" ] || stop "Could not read $DEV."
ensure_backup

# every image, not only init_boot
( cd "$BK" && sha256sum -c SHA256SUMS ) > "$WORK/sums.txt" 2>&1
rc=$?
cat "$WORK/sums.txt" >> "$LOG"
[ "$rc" = 0 ] || stop "Some files in $BK do not match its SHA256SUMS (see above). Keep the folder as it is and ask for help."
n=$(wc -l < "$BK/SHA256SUMS" | tr -d ' ')
log "$n images in $BK match SHA256SUMS"

STATUS_EXTRA="IMAGES=$n
FIRMWARE=$(backup_fw "$BK")"
[ "$BK_NEW" = 1 ] && finish OK 0 "Backup made: $n partition images in Download/RetroidRoot/boot-backup, all checked. Copy that folder off the device (PC or cloud) and keep it."
finish ALREADY 0 "You already have a backup (firmware $(backup_fw "$BK"), $n images, all checked). Copy Download/RetroidRoot/boot-backup off the device if you have not yet."
