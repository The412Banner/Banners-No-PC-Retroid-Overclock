#!/system/bin/sh
# sim-test.sh - runs backup.sh / root.sh / undo.sh / check.sh in test mode (EASYROOT_TEST=1) against fake partitions.
# No root needed, nothing on the device is touched. Run it with Android's shell (the scripts target mksh/toybox):
#   /system/bin/sh sim-test.sh <stock init_boot.img> <official Magisk APK> <empty scratch dir>
# The fake init_boot partitions are copies of the real stock image, so Magisk's patcher runs for real.

STOCK_IMG=$1
MAGISK_APK=$2
SIM=$3
[ -f "$STOCK_IMG" ] && [ -f "$MAGISK_APK" ] && [ -n "$SIM" ] || { echo "usage: sim-test.sh <stock init_boot.img> <Magisk APK> <scratch dir>"; exit 2; }
SRC=$(cd "${0%/*}/../scripts" && pwd)
ulimit -f 1048576 2> /dev/null   # 512 MB cap on any file written
PASS=0
FAIL=0

setup() {
  rm -rf "$SIM"
  mkdir -p "$SIM/dev" "$SIM/storage/Download/RetroidRoot" "$SIM/work"
  cp -r "$SRC"/* "$SIM/storage/Download/RetroidRoot/"
  cp "$STOCK_IMG" "$SIM/dev/init_boot_a"
  cp "$STOCK_IMG" "$SIM/dev/init_boot_b"
  for p in boot vendor_boot dtbo vbmeta; do
    for s in _a _b; do head -c 1048576 /dev/urandom > "$SIM/dev/$p$s"; done
  done
  cp "$MAGISK_APK" "$SIM/storage/Download/Magisk-v31.1.apk"
  export EASYROOT_TEST=1 EASYROOT_DEVDIR=$SIM/dev EASYROOT_BASE=$SIM/storage EASYROOT_WORK=$SIM/work/retroid-easyroot
  export EASYROOT_PROP_ro_product_model="Retroid Pocket Duo" EASYROOT_PROP_ro_boot_slot_suffix=_a
  export EASYROOT_PROP_ro_build_display_id=FW1 EASYROOT_PROP_ro_crypto_state=encrypted EASYROOT_PREINIT=sda12
  export EASYROOT_MAGISKD=0 EASYROOT_APP=31.1
  unset DRYRUN
}

R() { echo "$SIM/storage/Download/RetroidRoot"; }
run() { /system/bin/sh "$(R)/tools/$1.sh"; }
field() { sed -n "s/^$2=//p" "$(R)/status/$1.txt"; }
sha() { sha256sum "$1" | cut -d' ' -f1; }
STOCK_SHA=$(sha "$STOCK_IMG")

# expect <name> <step> <RESULT> [file sha-wanted]...
expect() {
  name=$1 step=$2 want=$3
  shift 3
  got=$(field "$step" RESULT)
  ok=1
  [ "$got" = "$want" ] || { ok=0; echo "    RESULT $got, wanted $want: $(field "$step" MESSAGE)"; }
  while [ $# -ge 2 ]; do
    [ "$(sha "$1")" = "$2" ] || { ok=0; echo "    $1: sha $(sha "$1"), wanted $2"; }
    shift 2
  done
  if [ $ok = 1 ]; then PASS=$((PASS + 1)); echo "ok   $name ($got: $(field "$step" MESSAGE))"
  else FAIL=$((FAIL + 1)); echo "FAIL $name"; fi
}

setup
rm "$SIM/storage/Download/Magisk-v31.1.apk"
run root
expect "no Magisk APK -> stop" root STOPPED "$SIM/dev/init_boot_a" "$STOCK_SHA"

setup
rm "$SIM/storage/Download/Magisk-v31.1.apk"
head -c 4096 /dev/urandom > "$SIM/storage/Download/Magisk-v99.apk"
run root
expect "unknown Magisk APK -> stop" root STOPPED "$SIM/dev/init_boot_a" "$STOCK_SHA"

setup
env EASYROOT_PROP_ro_product_model="Retroid Pocket 5" /system/bin/sh "$(R)/tools/root.sh"
expect "unsupported model -> stop" root STOPPED "$SIM/dev/init_boot_a" "$STOCK_SHA"

setup
env DRYRUN=1 /system/bin/sh "$(R)/tools/root.sh"
expect "dry run -> nothing written" root DRYRUN "$SIM/dev/init_boot_a" "$STOCK_SHA"
[ -f "$(R)/boot-backup/SHA256SUMS" ] && echo "     (dry run made the backup: $(wc -l < "$(R)/boot-backup/SHA256SUMS") images)"

setup
run root
PATCHED_SHA=$(sha "$(R)/magisk_patched-init_boot_a.img")
expect "root, no backup yet -> backup + flash" root OK "$SIM/dev/init_boot_a" "$PATCHED_SHA" "$SIM/dev/init_boot_b" "$STOCK_SHA" "$(R)/boot-backup/init_boot_a.img" "$STOCK_SHA"
echo "     patched sha256 $PATCHED_SHA"
(cd "$(R)/boot-backup" && sha256sum -c SHA256SUMS > /dev/null 2>&1) && echo "     backup SHA256SUMS check OK ($(wc -l < "$(R)/boot-backup/SHA256SUMS") images)" || { FAIL=$((FAIL + 1)); echo "FAIL backup SHA256SUMS"; }

run root
expect "root again -> already flashed" root ALREADY "$SIM/dev/init_boot_a" "$PATCHED_SHA"
run check
expect "check after flash" check OK
[ "$(field check STATE)" = FLASHED ] && echo "     STATE=FLASHED" || { FAIL=$((FAIL + 1)); echo "FAIL check STATE $(field check STATE), wanted FLASHED"; }
env EASYROOT_MAGISKD=1 /system/bin/sh "$(R)/tools/check.sh"
[ "$(field check STATE)" = ROOTED ] && { PASS=$((PASS + 1)); echo "ok   check with Magisk running -> ROOTED"; } || { FAIL=$((FAIL + 1)); echo "FAIL check STATE $(field check STATE), wanted ROOTED"; }
env EASYROOT_MAGISKD=1 /system/bin/sh "$(R)/tools/root.sh"
expect "root with Magisk running -> already" root ALREADY "$SIM/dev/init_boot_a" "$PATCHED_SHA"

env EASYROOT_PROP_ro_build_display_id=FW3 /system/bin/sh "$(R)/tools/undo.sh"
expect "undo with backup from other firmware -> stop" undo STOPPED "$SIM/dev/init_boot_a" "$PATCHED_SHA"
run undo
expect "undo -> stock" undo OK "$SIM/dev/init_boot_a" "$STOCK_SHA" "$SIM/dev/init_boot_b" "$STOCK_SHA"
run undo
expect "undo again -> already stock" undo ALREADY "$SIM/dev/init_boot_a" "$STOCK_SHA"
run check
[ "$(field check STATE)" = STOCK ] && { PASS=$((PASS + 1)); echo "ok   check after undo -> STOCK"; } || { FAIL=$((FAIL + 1)); echo "FAIL check STATE $(field check STATE), wanted STOCK"; }

# patched image made by the Magisk app (not our copy): undo must recognise it with magiskboot
cp "$(R)/magisk_patched-init_boot_a.img" "$SIM/other-patched.img"
rm "$(R)/magisk_patched-init_boot_a.img"
dd if="$SIM/other-patched.img" of="$SIM/dev/init_boot_a" conv=notrunc 2> /dev/null
run undo
expect "undo of a patch not made by the tool" undo OK "$SIM/dev/init_boot_a" "$STOCK_SHA"

# unknown content on the partition (same firmware): root and undo must not touch it
head -c 8388608 /dev/urandom > "$SIM/dev/init_boot_a"
JUNK_SHA=$(sha "$SIM/dev/init_boot_a")
run root
expect "root with unknown partition content -> stop" root STOPPED "$SIM/dev/init_boot_a" "$JUNK_SHA"
run undo
expect "undo with unknown partition content -> stop" undo STOPPED "$SIM/dev/init_boot_a" "$JUNK_SHA"

# firmware update: new stock image (one changed byte near the end), new firmware name -> old backup set aside
setup
run root > /dev/null
cp "$STOCK_IMG" "$SIM/dev/init_boot_a"
printf 'X' | dd of="$SIM/dev/init_boot_a" bs=1 seek=8000000 conv=notrunc 2> /dev/null
NEW_SHA=$(sha "$SIM/dev/init_boot_a")
env EASYROOT_PROP_ro_build_display_id=FW2 /system/bin/sh "$(R)/tools/root.sh"
expect "root after firmware update -> new backup + flash" root OK "$(R)/boot-backup/init_boot_a.img" "$NEW_SHA" "$(R)/boot-backup-FW1/init_boot_a.img" "$STOCK_SHA"

# patched partition and no backup: must not save a patched image as "stock"
setup
run root > /dev/null
rm -rf "$(R)/boot-backup"
run root
expect "patched partition, no backup -> stop" root STOPPED
[ -d "$(R)/boot-backup" ] && { FAIL=$((FAIL + 1)); echo "FAIL a backup of a patched partition was made"; }

# BACKUP.sh: reads partitions only; checks an existing backup instead of replacing it
check_field() {
  if [ "$(field "$1" "$2")" = "$3" ]; then PASS=$((PASS + 1)); echo "ok   $4 ($2=$3)"
  else FAIL=$((FAIL + 1)); echo "FAIL $4: $2=$(field "$1" "$2"), wanted $3"; fi
}
setup
rm "$SIM/storage/Download/Magisk-v31.1.apk"
run backup
expect "backup, no Magisk APK -> stop" backup STOPPED "$SIM/dev/init_boot_a" "$STOCK_SHA"
[ -d "$(R)/boot-backup" ] && { FAIL=$((FAIL + 1)); echo "FAIL backup folder made without a stock check"; }

setup
env EASYROOT_PROP_ro_product_model="Retroid Pocket 5" /system/bin/sh "$(R)/tools/backup.sh"
expect "backup on unsupported model -> stop" backup STOPPED

setup
run backup
expect "backup -> made + checked" backup OK "$SIM/dev/init_boot_a" "$STOCK_SHA" "$(R)/boot-backup/init_boot_a.img" "$STOCK_SHA" \
  "$(R)/boot-backup/vendor_boot_b.img" "$(sha "$SIM/dev/vendor_boot_b")" "$(R)/boot-backup/dtbo_a.img" "$(sha "$SIM/dev/dtbo_a")"
check_field backup IMAGES 10 "backup has every partition of both slots"
run backup
expect "backup again -> already there, checked" backup ALREADY
printf 'X' | dd of="$(R)/boot-backup/vendor_boot_b.img" bs=1 seek=100 conv=notrunc 2> /dev/null
run backup
expect "backup with a damaged image -> stop" backup STOPPED

setup
run backup > /dev/null
run root
expect "root after BACKUP.sh -> uses that backup" root OK "$SIM/dev/init_boot_a" "$PATCHED_SHA"
grep -q "no boot backup yet" "$(R)/root-result.txt" && { FAIL=$((FAIL + 1)); echo "FAIL root made a second backup"; }
run backup
expect "backup when rooted, backup there -> already" backup ALREADY "$SIM/dev/init_boot_a" "$PATCHED_SHA"
rm -rf "$(R)/boot-backup"
run backup
expect "backup of a patched partition, no backup -> stop" backup STOPPED "$SIM/dev/init_boot_a" "$PATCHED_SHA"
[ -d "$(R)/boot-backup" ] && { FAIL=$((FAIL + 1)); echo "FAIL a backup of a patched partition was made"; }

setup
run backup > /dev/null
cp "$STOCK_IMG" "$SIM/dev/init_boot_a"
printf 'X' | dd of="$SIM/dev/init_boot_a" bs=1 seek=8000000 conv=notrunc 2> /dev/null
NEW_SHA=$(sha "$SIM/dev/init_boot_a")
env EASYROOT_PROP_ro_build_display_id=FW2 /system/bin/sh "$(R)/tools/backup.sh"
expect "backup after firmware update -> old set aside, new made" backup OK "$(R)/boot-backup/init_boot_a.img" "$NEW_SHA" "$(R)/boot-backup-FW1/init_boot_a.img" "$STOCK_SHA" "$SIM/dev/init_boot_a" "$NEW_SHA"

echo
echo "passed $PASS, failed $FAIL"
[ $FAIL = 0 ]
