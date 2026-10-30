# Retroid Easy Root

Root the **Retroid Pocket Duo** with Magisk, with no PC. Each step is one tap in Retroid's own
**Run script as Root** option. You can use the app (it guides you and shows the results) or only the scripts.

**Your own choice and risk. Rooting may void your warranty. Retroid does not support root.**
The tool backs up your boot partitions first, writes only the active slot, checks every step, and stops
without writing if anything looks wrong.

Only the **Retroid Pocket Duo** is supported for now (tested on firmware `RPDuo_V1.0.0.108`, Magisk 31.1).
Other models are refused until someone tests them.

## With the app

1. Install **Retroid Easy Root** (APK from the release) and open it.
2. **Allow file access.**
3. **Download Magisk 31.1.** The app gets it from the official release on GitHub and checks it.
4. **Copy the tool files.** They go to `Download/RetroidRoot`.
5. Tap **Open Retroid Settings**, go to **Handheld Settings > Advanced > Run script as Root**, and pick
   `Download > RetroidRoot > ROOT.sh`. The first run takes about a minute (it makes a backup).
   Then go back to the app and read the result.
6. **Restart** the device. Open the Magisk app (it may ask for one more restart).
7. Run `CHECK.sh` the same way to confirm. The app shows **Rooted**.

## With the scripts only

1. Download `Magisk-v31.1.apk` from https://github.com/topjohnwu/Magisk/releases/tag/v31.1 into `Download`.
2. Unzip the script pack into `Download`, so you have `Download/RetroidRoot/ROOT.sh` and `Download/RetroidRoot/tools/`.
3. Settings > Handheld Settings > Advanced > **Run script as Root** > `Download/RetroidRoot/ROOT.sh`.
4. Read `Download/RetroidRoot/root-result.txt`. The last lines say `RESULT: OK` when it worked.
5. Restart. Open the Magisk app.

| Pick this | What it does | Result file |
|---|---|---|
| `ROOT.sh` | Makes a boot backup if there is none. Checks the Magisk APK against the official release. Patches the stock `init_boot` with Magisk's own patcher (the same settings the Magisk app uses). Checks the patched image. Writes it to the **active slot only** and reads it back; if the read-back does not match, it writes the stock image back. Installs the Magisk app if it is missing. Does not restart. | `root-result.txt` |
| `UNDO.sh` | Writes your stock `init_boot` back (to unroot, or before a firmware update). Only when the backup checks out, was made on the firmware you run now, and the partition holds a Magisk image. | `undo-result.txt` |
| `CHECK.sh` | Changes nothing. Reports whether Magisk runs, what is on `init_boot`, and whether the backup is OK. | `check-result.txt` |

Your backup is in `Download/RetroidRoot/boot-backup/` (boot, init_boot, vendor_boot, dtbo and vbmeta of both
slots, with `SHA256SUMS`). **Copy it off the device too.** After a firmware update, run `ROOT.sh` again: it puts
the old backup aside (`boot-backup-<old firmware>`) and makes a new one.

The patched image is also saved as `Download/RetroidRoot/magisk_patched-init_boot_<slot>.img`.

## If something goes wrong

- A step that **stops** has written nothing; the result file says why.
- If the device does not start after rooting: the other slot is untouched. From a PC with fastboot:
  `fastboot flash init_boot_a init_boot_a.img` (your stock backup), or `fastboot set_active b`.
- Ask on Discord: https://discord.gg/n8S4G2WZQ4 and keep the result files.

## How it works

Retroid's **Run script as Root** (`com.rp.settings`) does not run the picked file as a script. It sends every line
on its own to its root service (`/system/bin/pservice`), which runs it with `popen()` and cuts lines at 255
characters. So `ROOT.sh`, `UNDO.sh` and `CHECK.sh` are one short line each that start the real script in
`tools/` with Android's shell.

`tools/root.sh` unpacks `boot_patch.sh` and its binaries from the Magisk APK and runs them the way the Magisk app
does. On the Duo the result is byte-identical to an image patched in the Magisk app (sha256 `f9baf44c…` from
stock `a872e906…`, firmware 1.0.0.108).

Apps cannot use Retroid's root service themselves (the service is hidden from apps and the Run script screen is
not exported), so the app prepares the files, opens Retroid Settings and reads the results. It never has root.

## Testing

`test/sim-test.sh` runs root/undo/check in test mode against fake partitions (no root needed, 18 cases):
`/system/bin/sh test/sim-test.sh <stock init_boot.img> <Magisk APK> <empty scratch dir>`

## Credits

- **Magisk** by topjohnwu (GPLv3): https://github.com/topjohnwu/Magisk. Not included here. You download the
  official APK, and its own patcher does the patching.
- No-PC Run script as Root method and this tool: The412Banner.
- The original Retroid Pocket 5 root scripts that started this: reddit user shuddertrix.
