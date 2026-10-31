# lib.sh - shared parts of the Retroid Easy Root scripts (root.sh, undo.sh, check.sh source this file).
# The scripts run as root: started by the short launchers (ROOT.sh, UNDO.sh, CHECK.sh) through
# Settings > Handheld Settings > Advanced > Run script as Root, or on any rooted device with: su -c sh <script>
# Retroid's runner sends every line of the picked file on its own to its root service and cuts lines at
# 255 characters, which is why the launchers are one short line and the real work is done here.

export PATH=/system/bin:/system/xbin:/vendor/bin
EASYROOT_VERSION=0.1.0
MAGISK_PKG=com.topjohnwu.magisk
# Magisk APKs this version knows: <sha256 of the official file from github.com/topjohnwu/Magisk/releases>=<version>
MAGISK_KNOWN="89cefac0a318afa39fb3880c45c87b036c05bc1ebf02a7a715b7f8d7c26ac6e7=31.1"

# Test mode (EASYROOT_TEST=1 from a shell; the Retroid runner cannot set it): fake properties, partitions and
# storage, so the scripts can be tested without root. EASYROOT_PROP_ro_product_model=... overrides getprop.
T=${EASYROOT_TEST:-0}
DEVDIR=/dev/block/by-name
WORK=/data/local/tmp/retroid-easyroot
BASES="/storage/emulated/0 /data/media/0 /sdcard"
if [ "$T" = 1 ]; then
  DEVDIR=${EASYROOT_DEVDIR:-$DEVDIR}
  WORK=${EASYROOT_WORK:-$WORK}
  BASES=${EASYROOT_BASE:-$BASES}
fi

prop() {
  if [ "$T" = 1 ]; then
    eval "v=\${EASYROOT_PROP_$(echo "$1" | tr '.' '_')}"
    [ -n "$v" ] && { echo "$v"; return 0; }
  fi
  getprop "$1"
}

# find_base: first storage path we can write to -> B (storage root), R (Download/RetroidRoot)
find_base() {
  for d in $BASES; do
    mkdir -p "$d/Download/RetroidRoot/status" 2>/dev/null || continue
    echo ok > "$d/Download/RetroidRoot/status/.probe" 2>/dev/null || continue
    rm -f "$d/Download/RetroidRoot/status/.probe"
    B=$d
    R=$d/Download/RetroidRoot
    return 0
  done
  return 1
}

log() { echo "$*" >> "$LOG"; }

# set_status RESULT message: the small status file the app reads (status/<step>.txt), written in one go
set_status() {
  f=$R/status/$STEP.txt
  {
    echo "STEP=$STEP"
    echo "RESULT=$1"
    echo "MESSAGE=$2"
    echo "TIME=$(date +%s)"
    echo "VERSION=$EASYROOT_VERSION"
    if [ -n "$STATUS_EXTRA" ]; then printf '%s\n' "$STATUS_EXTRA"; fi
  } > "$f.tmp" && mv -f "$f.tmp" "$f"
}

# begin <step> <result file>: start a fresh result file
begin() {
  STEP=$1
  LOG=$R/$2
  : > "$LOG"
  log "===== Retroid Easy Root $EASYROOT_VERSION - $STEP - $(date)"
  log "model: $(prop ro.product.model)  firmware: $(prop ro.build.display.id)  slot: $(prop ro.boot.slot_suffix)"
  log "runner: $(id)  context: $(cat /proc/self/attr/current 2>/dev/null)"
  set_status RUNNING "started"
}

# tidy: remove the work folder, make the results readable for apps, tell the media scanner
tidy() {
  case "$WORK" in */retroid-easyroot) rm -rf "$WORK" ;; esac
  if [ "$B" = /data/media/0 ]; then
    chown -R "$(stat -c %u:%g /data/media/0/Download)" "$R" 2>/dev/null
    chmod -R ug+rwX,o+rX "$R" 2>/dev/null
  fi
  [ "$T" = 1 ] || am broadcast -a android.intent.action.MEDIA_SCANNER_SCAN_FILE -d "file:///storage/emulated/0/Download/RetroidRoot/${LOG##*/}" > /dev/null 2>&1
}

# finish RESULT exitcode message
finish() {
  log ""
  log "RESULT: $1 - $3"
  log "===== END $(date)"
  set_status "$1" "$3"
  tidy
  exit "$2"
}
stop() { finish STOPPED 1 "$*"; }

# check_device: root, supported model, active slot -> MODEL SLOT DEV DSIZE
check_device() {
  [ "$T" = 1 ] || [ "$(id -u)" = 0 ] || stop "Not running as root. Start it with Run script as Root (Settings > Handheld Settings > Advanced)."
  MODEL=$(prop ro.product.model)
  case "$MODEL" in
    "Retroid Pocket Duo") ;;
    *) stop "This device ($MODEL) is not supported yet. Supported: Retroid Pocket Duo." ;;
  esac
  SLOT=$(prop ro.boot.slot_suffix)
  case "$SLOT" in _a|_b) ;; *) stop "Active slot unknown ('$SLOT')." ;; esac
  DEV=$DEVDIR/init_boot$SLOT
  [ -e "$DEV" ] || stop "$DEV does not exist."
  [ -b "$DEV" ] || [ "$T" = 1 ] || stop "$DEV is not a block device."
  DSIZE=$(blockdev --getsize64 "$DEV" 2>/dev/null)
  [ -n "$DSIZE" ] || DSIZE=$(stat -c %s "$DEV")
  log "active slot: $SLOT -> $DEV ($DSIZE bytes); only this slot is ever written"
}

prepare_work() {
  case "$WORK" in */retroid-easyroot) rm -rf "$WORK" ;; esac
  mkdir -p "$WORK" && chmod 700 "$WORK" || stop "Cannot create the work folder $WORK."
}

magisk_running() {
  if [ "$T" = 1 ]; then [ "$EASYROOT_MAGISKD" = 1 ]; return; fi
  pidof magiskd > /dev/null 2>&1 || ps -A 2>/dev/null | grep -q '[m]agiskd'
}

# find_magisk_apk: newest Magisk*.apk in Download whose sha256 is in MAGISK_KNOWN -> APK MAGISK_VER; others -> FOUND
find_magisk_apk() {
  APK=
  MAGISK_VER=
  FOUND=
  ls -t "$B"/Download/Magisk*.apk 2>/dev/null > "$WORK/apks.txt"
  while IFS= read -r f; do
    s=$(sha256sum "$f" | cut -d' ' -f1)
    for k in $MAGISK_KNOWN; do
      [ "${k%%=*}" = "$s" ] && { APK=$f; MAGISK_VER=${k#*=}; return 0; }
    done
    FOUND="$FOUND ${f##*/}"
  done < "$WORK/apks.txt"
  return 1
}

# get_magisk_tools: unpack Magisk's own patcher from the APK into $WORK/m (the same files the Magisk app uses)
get_magisk_tools() {
  M=$WORK/m
  rm -rf "$M"
  mkdir -p "$M/x" || return 1
  unzip -o -q -d "$M/x" "$APK" assets/boot_patch.sh assets/util_functions.sh \
    lib/arm64-v8a/libmagiskboot.so lib/arm64-v8a/libmagiskinit.so lib/arm64-v8a/libmagisk.so \
    lib/arm64-v8a/libinit-ld.so lib/arm64-v8a/libbusybox.so > /dev/null 2>&1
  cp "$M/x/assets/boot_patch.sh" "$M/x/assets/util_functions.sh" "$M/" || return 1
  for n in magiskboot magiskinit magisk init-ld busybox; do
    cp "$M/x/lib/arm64-v8a/lib$n.so" "$M/$n" || return 1
  done
  rm -rf "$M/x"
  # named files, no glob: if Run script as Root is pointed at this file, each line runs alone with $M empty
  chmod 755 "$M/boot_patch.sh" "$M/util_functions.sh" "$M/magiskboot" "$M/magiskinit" "$M/magisk" "$M/init-ld" "$M/busybox"
  MB=$M/magiskboot
}

# is_patched <image>: 0 = Magisk-patched ramdisk, 1 = not Magisk-patched, 2 = cannot tell. Needs MB (magiskboot).
is_patched() {
  [ -n "$MB" ] && [ -x "$MB" ] || return 2
  c=$WORK/chk
  rm -rf "$c"
  mkdir -p "$c"
  ( cd "$c" && "$MB" unpack "$1" > /dev/null 2>&1 ) || { rm -rf "$c"; return 2; }
  [ -f "$c/ramdisk.cpio" ] || { rm -rf "$c"; return 1; }
  ( cd "$c" && "$MB" cpio ramdisk.cpio test > /dev/null 2>&1 )
  r=$?
  rm -rf "$c"
  # magiskboot cpio test: 0 = stock, 1 = Magisk, 2 = another root method
  case $r in 0) return 1 ;; 1) return 0 ;; *) return 2 ;; esac
}

# same_start <file> <device>: the device starts with exactly the file's bytes
same_start() {
  [ "$(head -c "$(stat -c %s "$1")" "$2" | sha256sum | cut -d' ' -f1)" = "$(sha256sum "$1" | cut -d' ' -f1)" ]
}

# hdr <image>: boot image header version
hdr() { dd if="$1" bs=1 skip=40 count=4 2>/dev/null | od -An -tu4 | tr -d ' '; }

backup_fw() {
  cat "$1/firmware.txt" 2>/dev/null || sed -n 's/^firmware: //p' "$1/info.txt" 2>/dev/null | head -1
}

# check_backup <dir>: the stock init_boot copy for the active slot matches SHA256SUMS -> STOCK
check_backup() {
  STOCK=$1/init_boot$SLOT.img
  [ -f "$STOCK" ] || return 1
  want=$(grep " init_boot$SLOT.img\$" "$1/SHA256SUMS" 2>/dev/null | cut -d' ' -f1)
  have=$(sha256sum "$STOCK" | cut -d' ' -f1)
  [ -n "$want" ] && [ "$want" = "$have" ] || { log "stock backup check failed (SHA256SUMS: '$want', file: '$have')"; return 1; }
  [ "$(stat -c %s "$STOCK")" = "$DSIZE" ] || { log "stock backup size $(stat -c %s "$STOCK") is not the partition size $DSIZE"; return 1; }
  log "stock backup OK: $STOCK (sha256 $have, firmware $(backup_fw "$1"))"
}

# make_backup <dir>: copy the boot partitions of both slots, check every copy, write SHA256SUMS, info.txt, firmware.txt
make_backup() {
  d=$1
  mkdir -p "$d" || return 1
  need=0
  for p in boot init_boot vendor_boot vendor_kernel_boot dtbo vbmeta; do
    for s in _a _b; do
      [ -e "$DEVDIR/$p$s" ] || continue
      z=$(blockdev --getsize64 "$DEVDIR/$p$s" 2>/dev/null)
      [ -n "$z" ] || z=$(stat -c %s "$DEVDIR/$p$s")
      need=$((need + z / 1024))
    done
  done
  set -- $(df -k "$B" 2>/dev/null | tail -1)
  free=$4
  log "backup needs $((need / 1024)) MB, free $((free / 1024)) MB"
  [ -n "$free" ] && [ "$free" -gt $((need + 102400)) ] || { log "not enough free space for the backup"; return 1; }
  for p in boot init_boot vendor_boot vendor_kernel_boot dtbo vbmeta; do
    for s in _a _b; do
      src=$DEVDIR/$p$s
      [ -e "$src" ] || continue
      dd if="$src" of="$d/$p$s.img" bs=1048576 2> /dev/null
      cmp -s "$src" "$d/$p$s.img" || { log "backup: $p$s copy does not match the partition"; return 1; }
      log "backup: $p$s saved + checked"
    done
  done
  ( cd "$d" && sha256sum *.img > SHA256SUMS ) || return 1
  prop ro.build.display.id > "$d/firmware.txt"
  {
    echo "Retroid Easy Root $EASYROOT_VERSION boot backup - $(date)"
    echo "model: $(prop ro.product.model) / $(prop ro.product.device)"
    echo "firmware: $(prop ro.build.display.id)"
    echo "build: $(prop ro.build.fingerprint)"
    echo "active slot: $(prop ro.boot.slot_suffix)"
    echo "Keep this folder: it is how you go back to stock (and get firmware updates) later."
  } > "$d/info.txt"
  log "backup written to $d"
}

# get_flags: the same patch settings the Magisk app works out (app_functions.sh: mount_partitions + get_flags)
get_flags() {
  SYSTEM_AS_ROOT=false
  grep ' / ' /proc/mounts | grep -qv 'rootfs' && SYSTEM_AS_ROOT=true
  LEGACYSAR=false
  grep ' / ' /proc/mounts | grep -q '/dev/root' && LEGACYSAR=true
  KEEPVERITY=$SYSTEM_AS_ROOT
  KEEPFORCEENCRYPT=false
  [ "$(prop ro.crypto.state)" = encrypted ] && KEEPFORCEENCRYPT=true
  if [ -n "$(prop ro.boot.vbmeta.device)" ] || [ -n "$(prop ro.boot.vbmeta.size)" ]; then
    PATCHVBMETAFLAG=false
  elif prop ro.product.ab_ota_partitions | grep -wq vbmeta; then
    PATCHVBMETAFLAG=false
  else
    PATCHVBMETAFLAG=true
  fi
  RECOVERYMODE=false
  PREINITDEVICE=$("$M/magisk" --preinit-device 2> /dev/null)
  [ "$T" = 1 ] && [ -n "$EASYROOT_PREINIT" ] && PREINITDEVICE=$EASYROOT_PREINIT
}
