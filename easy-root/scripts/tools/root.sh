#!/system/bin/sh
# root.sh - Retroid Easy Root: patches the stock init_boot with Magisk's own patcher and writes it to the ACTIVE slot.
# Start it with ROOT.sh in Run script as Root (Settings > Handheld Settings > Advanced), or: su -c sh root.sh
# Needs the official Magisk APK in Download (see MAGISK_KNOWN in lib.sh). Makes a boot backup first if there is none.
# Stops without writing if a check fails; if the read-back does not match it writes the stock image back.
# Does not restart the device. Result: Download/RetroidRoot/root-result.txt (+ status/root.txt for the app).
# DRYRUN=1 (from a shell): patch and check only, never write the partition or install anything.

. "${0%/*}/lib.sh"
find_base || exit 1
begin root root-result.txt
DRY=${DRYRUN:-0}
[ "$DRY" = 1 ] && log "DRY RUN: nothing will be written to the device"

check_device
prepare_work

find_magisk_apk || stop "No official Magisk APK in Download (found:${FOUND:- nothing}). Get Magisk-v31.1.apk from github.com/topjohnwu/Magisk/releases or with the Retroid Easy Root app."
log "Magisk APK: $APK (version $MAGISK_VER, checked against the official release)"
get_magisk_tools || stop "Could not unpack Magisk's patcher from $APK."

if [ "$DRY" != 1 ] && magisk_running; then
  finish ALREADY 0 "Magisk is already running on this device. Nothing to do."
fi

dd if="$DEV" of="$WORK/cur.img" bs=1048576 2> /dev/null && [ "$(stat -c %s "$WORK/cur.img")" = "$DSIZE" ] || stop "Could not read $DEV."
FW=$(prop ro.build.display.id)
BK=$R/boot-backup

# Same backup as BACKUP.sh when there is none yet (or the firmware changed)
ensure_backup

if ! cmp -s "$WORK/cur.img" "$STOCK"; then
  is_patched "$WORK/cur.img"
  case $? in
    0)
      [ "$DRY" = 1 ] || finish ALREADY 0 "init_boot$SLOT already holds a Magisk-patched image. Restart the device to start Magisk."
      log "init_boot$SLOT is already patched (dry run goes on with the stock backup)"
      ;;
    *) stop "init_boot$SLOT is not the same as your stock backup and is not Magisk-patched. Not touching it." ;;
  esac
else
  log "init_boot$SLOT is stock (same as the backup)"
fi

# Patch: Magisk's boot_patch.sh with the settings the Magisk app would use
cp "$STOCK" "$WORK/stock.img" || stop "Could not copy the stock image."
get_flags
log "patch settings: KEEPVERITY=$KEEPVERITY KEEPFORCEENCRYPT=$KEEPFORCEENCRYPT PATCHVBMETAFLAG=$PATCHVBMETAFLAG RECOVERYMODE=$RECOVERYMODE LEGACYSAR=$LEGACYSAR PREINITDEVICE=$PREINITDEVICE"
[ -n "$PREINITDEVICE" ] || stop "Magisk could not find its pre-init partition (magisk --preinit-device gave nothing)."
log "----- Magisk patcher output"
( cd "$M" && env -i PATH="$PATH" HOME=/ TMPDIR="$WORK" BOOTMODE=true KEEPVERITY=$KEEPVERITY KEEPFORCEENCRYPT=$KEEPFORCEENCRYPT \
    PATCHVBMETAFLAG=$PATCHVBMETAFLAG RECOVERYMODE=$RECOVERYMODE LEGACYSAR=$LEGACYSAR PREINITDEVICE=$PREINITDEVICE \
    ./busybox sh boot_patch.sh "$WORK/stock.img" ) >> "$LOG" 2>&1
rc=$?
log "----- end of patcher output (exit $rc)"
P=$M/new-boot.img
[ "$rc" = 0 ] && [ -f "$P" ] || stop "Magisk's patcher failed (see above). Nothing was written."

# Check the patched image before it goes anywhere near the partition
[ "$(dd if="$P" bs=8 count=1 2> /dev/null)" = "ANDROID!" ] || stop "The patched image is not an Android boot image."
[ "$(hdr "$P")" = "$(hdr "$STOCK")" ] || stop "Header version differs: patched $(hdr "$P"), stock $(hdr "$STOCK")."
PSIZE=$(stat -c %s "$P")
[ "$PSIZE" -gt 4096 ] && [ "$PSIZE" -le "$DSIZE" ] || stop "The patched image ($PSIZE bytes) does not fit the partition ($DSIZE)."
[ $((PSIZE % 4096)) -eq 0 ] && [ $((DSIZE % 4096)) -eq 0 ] || stop "Sizes are not multiples of 4096."
cmp -s "$P" "$STOCK" && stop "The patched image is identical to stock."
is_patched "$P" || stop "The new image does not test as Magisk-patched."
PSHA=$(sha256sum "$P" | cut -d' ' -f1)
cp "$P" "$R/magisk_patched-init_boot$SLOT.img"
log "patched image OK: $PSIZE bytes, sha256 $PSHA (copy: $R/magisk_patched-init_boot$SLOT.img)"

[ "$DRY" = 1 ] && finish DRYRUN 0 "Dry run OK: patched image made and checked (sha256 $PSHA). Nothing was written."

# Write: the partition must still be stock right before writing
cmp -s "$DEV" "$STOCK" || stop "init_boot$SLOT changed during the run. Nothing was written."
[ "$(blockdev --getro "$DEV" 2> /dev/null)" = 1 ] && blockdev --setrw "$DEV"
log "writing the patched image to $DEV ..."
dd if="$P" of="$DEV" bs=4096 conv=notrunc 2> /dev/null
[ "$PSIZE" -lt "$DSIZE" ] && dd if=/dev/zero of="$DEV" bs=4096 seek=$((PSIZE / 4096)) count=$(((DSIZE - PSIZE) / 4096)) conv=notrunc 2> /dev/null
sync
if same_start "$P" "$DEV"; then
  log "read back: matches the patched image"
else
  log "read back: DOES NOT MATCH - writing the stock image back"
  dd if="$STOCK" of="$DEV" bs=1048576 conv=notrunc 2> /dev/null
  sync
  cmp -s "$DEV" "$STOCK" && finish PROBLEM 1 "Writing failed; the stock image was put back and checked, so the device is as before. Ask for help before trying again."
  finish PROBLEM 1 "Writing failed AND putting stock back failed. Do NOT restart. Ask for help (Discord) and keep this file."
fi

# Install the Magisk app from the same APK if it is not there yet
if [ "$T" != 1 ] && [ -z "$(pm path $MAGISK_PKG 2> /dev/null)" ]; then
  cp "$APK" "$WORK/magisk.apk" && chmod 644 "$WORK/magisk.apk"
  if pm install -r "$WORK/magisk.apk" >> "$LOG" 2>&1; then
    log "Magisk app $MAGISK_VER installed"
  else
    log "could not install the Magisk app here; install it by tapping ${APK##*/} in Download"
  fi
fi

finish OK 0 "Done: init_boot$SLOT now holds the Magisk-patched image (checked). Restart the device, then open the Magisk app."
