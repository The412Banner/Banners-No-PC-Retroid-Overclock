# Retroid Easy Root - UNDO: puts the stock init_boot back (unroot).
# Pick THIS file in Settings > Handheld Settings > Advanced > Run script as Root.
# The runner sends each line on its own and cuts it at 255 chars, so the next line starts tools/undo.sh.
for d in /storage/emulated/0 /data/media/0 /sdcard; do f=$d/Download/RetroidRoot/tools/undo.sh; [ -f $f ] && { /system/bin/sh $f; break; }; done
[ -f /storage/emulated/0/Download/RetroidRoot/tools/undo.sh ] || echo tools/undo.sh not found > /storage/emulated/0/Download/RetroidRoot/launcher-error.txt
