# Retroid Easy Root - CHECK: writes a root status report (changes nothing).
# Pick THIS file in Settings > Handheld Settings > Advanced > Run script as Root.
# The runner sends each line on its own and cuts it at 255 chars, so the next line starts tools/check.sh.
for d in /storage/emulated/0 /data/media/0 /sdcard; do f=$d/Download/RetroidRoot/tools/check.sh; [ -f $f ] && { /system/bin/sh $f; break; }; done
[ -f /storage/emulated/0/Download/RetroidRoot/tools/check.sh ] || echo tools/check.sh not found > /storage/emulated/0/Download/RetroidRoot/launcher-error.txt
