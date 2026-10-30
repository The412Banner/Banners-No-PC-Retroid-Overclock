# Retroid Easy Root - ROOT: roots the device (patches init_boot with Magisk, active slot only).
# Pick THIS file in Settings > Handheld Settings > Advanced > Run script as Root.
# The runner sends each line on its own and cuts it at 255 chars, so the next line starts tools/root.sh.
for d in /storage/emulated/0 /data/media/0 /sdcard; do f=$d/Download/RetroidRoot/tools/root.sh; [ -f $f ] && { /system/bin/sh $f; break; }; done
[ -f /storage/emulated/0/Download/RetroidRoot/tools/root.sh ] || echo tools/root.sh not found > /storage/emulated/0/Download/RetroidRoot/launcher-error.txt
