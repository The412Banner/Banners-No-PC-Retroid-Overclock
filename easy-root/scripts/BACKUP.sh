# Retroid Easy Root - BACKUP: saves your stock boot partitions to Download/RetroidRoot/boot-backup (writes no partition).
# Pick THIS file in Settings > Handheld Settings > Advanced > Run script as Root.
# The runner sends each line on its own and cuts it at 255 chars, so the next line starts tools/backup.sh.
for d in /storage/emulated/0 /data/media/0 /sdcard; do f=$d/Download/RetroidRoot/tools/backup.sh; [ -f $f ] && { /system/bin/sh $f; break; }; done
[ -f /storage/emulated/0/Download/RetroidRoot/tools/backup.sh ] || echo tools/backup.sh not found > /storage/emulated/0/Download/RetroidRoot/launcher-error.txt
