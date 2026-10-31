Retroid Easy Root @VERSION@ - manual pack (no app needed)
=========================================================

Roots the Retroid Pocket Duo with Magisk @MAGISK@, with no PC. You run each step yourself with Retroid's own
"Run script as Root" option. The Retroid Easy Root app uses the same scripts and guides you through them,
if you would rather use that.

Your own choice and risk. Rooting may void your warranty. Retroid does not support root.
Only the Retroid Pocket Duo is supported (tested on firmware RPDuo_V1.0.0.108). The scripts refuse other models.


What is in this zip
-------------------
  README-FIRST.txt         this file
  Magisk-v@MAGISK@.apk         the official Magisk app, unchanged (see Credits)
  Magisk-LICENSE.txt       Magisk's licence (GPLv3)
  RetroidRoot/
    BACKUP.sh              part 2: saves your stock boot partitions
    ROOT.sh                part 3: roots the device
    CHECK.sh               part 4: tells you whether it worked (changes nothing)
    UNDO.sh                puts stock back (to unroot, or before a firmware update)
    tools/                 the real scripts that the four files above start. Never pick these.


1. Put the files in Download
----------------------------
Unzip the zip into the Download folder, so that you end up with:

  Download/Magisk-v@MAGISK@.apk
  Download/RetroidRoot/BACKUP.sh   (and ROOT.sh, CHECK.sh, UNDO.sh and the tools folder)

With the Files app that comes with the Duo: tap the zip to open it, select everything inside it,
tap the menu (three dots) > Copy to..., open Download and tap Copy.
If your file manager unzips into a new folder instead (for example Download/RetroidEasyRoot-manual-...),
move the RetroidRoot folder and the Magisk APK from that folder into Download.

The scripts only look in Download/RetroidRoot. Do not rename that folder.


How to run a step
-----------------
Settings > Handheld Settings > Advanced > Run script as Root, then pick the file:
Download > RetroidRoot > (the file).

Nothing shows on screen while it runs. Give it a minute, then open the result file in Download/RetroidRoot
with any text viewer. Its last lines say RESULT: ... and why. Each run replaces the old result file.

  RESULT: OK        it worked
  RESULT: ALREADY   nothing needed doing
  RESULT: STOPPED   it stopped before writing anything; the line says why
  RESULT: PROBLEM   read the whole file and ask for help (see below) before you restart


2. Back up - BACKUP.sh
----------------------
Pick Download > RetroidRoot > BACKUP.sh. It takes about a minute.

It saves boot, init_boot, vendor_boot, dtbo and vbmeta of both slots to Download/RetroidRoot/boot-backup,
compares every copy with its partition, and writes a SHA256SUMS file. It only reads partitions; it
writes none. If you already have a backup, it checks it instead of making a new one.

Result file: backup-result.txt.

Then COPY the whole boot-backup folder off the device (PC, cloud, another SD card) and keep it.
It is how you go back to stock.


3. Root - ROOT.sh
-----------------
Pick Download > RetroidRoot > ROOT.sh.

It checks the Magisk APK against the official release, patches your stock init_boot with Magisk's own
patcher (the same settings the Magisk app uses), checks the patched image, writes it to the active slot
only and reads it back. If the read-back does not match, it writes the stock image back. It also installs
the Magisk app. If you skipped part 2, it makes the backup first. It does not restart the device.

Result file: root-result.txt.


4. Restart, then check - CHECK.sh
---------------------------------
Restart the device. Open the Magisk app; it may ask for one more restart.
If the Magisk app is missing, tap Download/Magisk-v@MAGISK@.apk to install it.

Then pick Download > RetroidRoot > CHECK.sh. It changes nothing.
Result file: check-result.txt. "Rooted: Magisk ... is running." means you are done.


Undo - UNDO.sh
--------------
To unroot, or before you install a firmware update: pick Download > RetroidRoot > UNDO.sh, then restart.
It only writes when your backup checks out, was made on the firmware you run now, and init_boot holds a
Magisk image. Result file: undo-result.txt.

After a firmware update, run BACKUP.sh again (it moves the old backup to boot-backup-<old firmware> and
makes a new one), then ROOT.sh.


If something goes wrong
-----------------------
- A step that says STOPPED has written nothing. The result file says why.
- Run script as Root does not list the files: check that they are in Download/RetroidRoot (not in a
  folder inside it), then copy them there again with the Files app as described in part 1.
- The device does not start after ROOT.sh: the other slot is untouched. With a PC and fastboot:
  fastboot flash init_boot_a init_boot_a.img (from your backup; use _b if slot b was active),
  or fastboot set_active b.
- Ask on Discord: https://discord.gg/n8S4G2WZQ4 and keep the result files.


Credits
-------
- Magisk by topjohnwu, GPLv3 (see Magisk-LICENSE.txt). The APK in this zip is the unchanged official
  release file (sha256 @MAGISK_SHA@).
  Source code: https://github.com/topjohnwu/Magisk/tree/v@MAGISK@
- Retroid Easy Root and the no-PC Run script as Root method: The412Banner
  https://github.com/The412Banner/Banners-No-PC-Retroid-Overclock
- The original Retroid Pocket 5 root scripts that started this: reddit user shuddertrix.
