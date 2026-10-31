package com.the412banner.retroideasyroot;

import android.app.Activity;
import android.app.AlertDialog;
import android.app.PendingIntent;
import android.content.ComponentName;
import android.content.Intent;
import android.content.pm.PackageInstaller;
import android.content.pm.PackageManager;
import android.graphics.Typeface;
import android.graphics.drawable.GradientDrawable;
import android.media.MediaScannerConnection;
import android.net.Uri;
import android.os.Build;
import android.os.Bundle;
import android.os.Environment;
import android.os.Handler;
import android.os.Looper;
import android.os.SystemClock;
import android.provider.Settings;
import android.text.format.DateUtils;
import android.text.util.Linkify;
import android.util.TypedValue;
import android.view.View;
import android.widget.Button;
import android.widget.LinearLayout;
import android.widget.ScrollView;
import android.widget.TextView;
import android.widget.Toast;

import java.io.ByteArrayOutputStream;
import java.io.File;
import java.io.FileInputStream;
import java.io.FileOutputStream;
import java.io.IOException;
import java.io.InputStream;
import java.io.OutputStream;
import java.net.HttpURLConnection;
import java.net.URL;
import java.nio.charset.StandardCharsets;
import java.security.MessageDigest;
import java.util.ArrayList;
import java.util.Arrays;
import java.util.Collections;
import java.util.HashMap;
import java.util.List;
import java.util.Locale;
import java.util.Map;
import java.util.concurrent.CountDownLatch;
import java.util.concurrent.ExecutorService;
import java.util.concurrent.Executors;
import java.util.concurrent.TimeUnit;

/**
 * One screen that walks through rooting with the Easy Root scripts. The app itself never has root:
 * Retroid's root runner can only be started by the user (Settings > Run script as Root), so the app
 * prepares the files, opens Retroid Settings and shows the results the scripts write to Download/RetroidRoot.
 */
public class MainActivity extends Activity {
    static final String SUPPORTED_MODEL = "Retroid Pocket Duo";
    static final String MAGISK_VERSION = "31.1";
    static final String MAGISK_FILE = "Magisk-v" + MAGISK_VERSION + ".apk";
    static final String MAGISK_URL =
            "https://github.com/topjohnwu/Magisk/releases/download/v" + MAGISK_VERSION + "/" + MAGISK_FILE;
    // must match MAGISK_KNOWN in scripts/tools/lib.sh (CI checks it)
    static final String MAGISK_SHA256 = "89cefac0a318afa39fb3880c45c87b036c05bc1ebf02a7a715b7f8d7c26ac6e7";
    static final String MAGISK_PKG = "com.topjohnwu.magisk";
    static final String[] TOOL_FILES = {"BACKUP.sh", "ROOT.sh", "UNDO.sh", "CHECK.sh",
            "tools/lib.sh", "tools/backup.sh", "tools/root.sh", "tools/undo.sh", "tools/check.sh"};
    // media-scanned after copying so the Run script as Root picker lists them; tools/ is not scanned on purpose
    static final String[] LAUNCHERS = {"BACKUP.sh", "ROOT.sh", "UNDO.sh", "CHECK.sh"};
    static final String REPO = "https://github.com/The412Banner/Banners-No-PC-Retroid-Overclock";

    static final int GREEN = 0xFF2E7D32, RED = 0xFFC62828, AMBER = 0xFFEF6C00, GREY = 0xFF808080;

    final Handler main = new Handler(Looper.getMainLooper());
    final ExecutorService bg = Executors.newSingleThreadExecutor();
    final Map<String, byte[]> assets = new HashMap<>();
    File download, toolDir;
    boolean supported;

    LinearLayout list;
    Step access, magisk, tools, backup, root, check, app, undo;
    Button allowBtn, downloadBtn, copyBtn, installBtn;
    Button[] settingsBtns, logBtns;

    // Magisk APK check, cached by file size + time so the 10 MB file is hashed only when it changes
    String apkKey;
    Boolean apkOk;
    boolean downloading, copying;
    String downloadText, downloadError, copyError, scanError, installError;

    final Runnable ticker = new Runnable() {
        @Override
        public void run() {
            refresh();
            main.postDelayed(this, 2000);
        }
    };

    final class Step {
        final LinearLayout card, buttons;
        final TextView state, info;

        Step(String title, String text) {
            card = new LinearLayout(MainActivity.this);
            card.setOrientation(LinearLayout.VERTICAL);
            int p = dp(14);
            card.setPadding(p, p, p, p);
            GradientDrawable border = new GradientDrawable();
            border.setCornerRadius(dp(10));
            border.setStroke(dp(1), 0x60808080);
            card.setBackground(border);
            LinearLayout.LayoutParams lp = new LinearLayout.LayoutParams(
                    LinearLayout.LayoutParams.MATCH_PARENT, LinearLayout.LayoutParams.WRAP_CONTENT);
            lp.topMargin = dp(10);
            list.addView(card, lp);
            card.addView(label(title, 18, true));
            if (text != null) card.addView(label(text, 14, false));
            state = label("", 15, true);
            card.addView(state);
            info = label("", 13, false);
            info.setVisibility(View.GONE);
            card.addView(info);
            buttons = new LinearLayout(MainActivity.this);
            buttons.setOrientation(LinearLayout.HORIZONTAL);
            card.addView(buttons);
        }

        Button button(String text, View.OnClickListener l) {
            Button b = new Button(MainActivity.this);
            b.setText(text);
            b.setAllCaps(false);
            b.setOnClickListener(l);
            buttons.addView(b);
            return b;
        }

        void set(int color, String s) {
            state.setTextColor(color);
            state.setText(s);
        }

        void info(String s) {
            info.setText(s == null ? "" : s);
            info.setVisibility(s == null || s.isEmpty() ? View.GONE : View.VISIBLE);
        }
    }

    @Override
    protected void onCreate(Bundle savedInstanceState) {
        super.onCreate(savedInstanceState);
        download = Environment.getExternalStoragePublicDirectory(Environment.DIRECTORY_DOWNLOADS);
        toolDir = new File(download, "RetroidRoot");
        supported = SUPPORTED_MODEL.equals(Build.MODEL);
        for (String n : TOOL_FILES) {
            try (InputStream in = getAssets().open(n)) {
                assets.put(n, readAll(in));
            } catch (IOException e) {
                throw new IllegalStateException("missing asset " + n, e);
            }
        }

        ScrollView scroll = new ScrollView(this);
        list = new LinearLayout(this);
        list.setOrientation(LinearLayout.VERTICAL);
        int p = dp(16);
        list.setPadding(p, p, p, dp(32));
        scroll.addView(list);
        setContentView(scroll);

        list.addView(label(getString(R.string.app_name) + " " + versionName(), 24, true));
        list.addView(label("Device: " + Build.MODEL + "\nFirmware: " + Build.DISPLAY
                + "\nAndroid " + Build.VERSION.RELEASE, 14, false));
        TextView sup = label(supported ? "This device is supported."
                : "This device is not supported. Only the " + SUPPORTED_MODEL + " is supported for now.", 15, true);
        sup.setTextColor(supported ? GREEN : RED);
        list.addView(sup);
        list.addView(label("Rooting is your own choice and may void your warranty. The tool backs up your boot "
                + "partitions first, writes only the active slot, checks every step and stops without writing "
                + "if anything looks wrong.", 13, false));

        access = new Step("1. Allow file access",
                "Needed to put the tool files in Download and to read their results.");
        allowBtn = access.button("Allow", v -> startActivity(new Intent(
                Settings.ACTION_MANAGE_APP_ALL_FILES_ACCESS_PERMISSION, Uri.parse("package:" + getPackageName()))));

        magisk = new Step("2. Get Magisk " + MAGISK_VERSION,
                "Downloads " + MAGISK_FILE + " from the official Magisk release on GitHub into Download and checks it.");
        downloadBtn = magisk.button("Download", v -> downloadMagisk());

        tools = new Step("3. Put the tool files in Download",
                "Copies BACKUP.sh, ROOT.sh, UNDO.sh, CHECK.sh and the tools folder to Download/RetroidRoot.");
        copyBtn = tools.button("Copy files", v -> copyTools());

        backup = new Step("4. Back up",
                "Saves your stock boot partitions (both slots) to Download/RetroidRoot/boot-backup and checks "
                        + "every copy. It only reads, it writes no partition. Tap Open Retroid Settings, go to "
                        + "Handheld Settings > Advanced > Run script as Root, and pick Download > RetroidRoot > "
                        + "BACKUP.sh. It takes about a minute. Then copy the boot-backup folder off the device "
                        + "(PC or cloud): it is how you go back to stock.");
        Button s0 = backup.button("Open Retroid Settings", v -> openRetroidSettings());
        Button l0 = backup.button("Show log", v -> showLog("backup-result.txt"));

        root = new Step("5. Root",
                "Run ROOT.sh the same way (Run script as Root > RetroidRoot > ROOT.sh). If there is no backup "
                        + "yet, it makes one first. Then come back here for the result.");
        Button s1 = root.button("Open Retroid Settings", v -> openRetroidSettings());
        Button l1 = root.button("Show log", v -> showLog("root-result.txt"));

        check = new Step("6. Restart, then check",
                "Restart the device. Then run CHECK.sh the same way (Run script as Root > RetroidRoot > CHECK.sh).");
        Button s2 = check.button("Open Retroid Settings", v -> openRetroidSettings());
        Button l2 = check.button("Show log", v -> showLog("check-result.txt"));

        app = new Step("7. Magisk app",
                "Manages root. ROOT.sh installs it for you; if that did not work, install it here. "
                        + "On its first start Magisk may ask for one more restart.");
        installBtn = app.button("Install Magisk app", v -> installMagisk());

        TextView undoTitle = label("Undo", 20, true);
        undoTitle.setPadding(0, dp(20), 0, 0);
        list.addView(undoTitle);
        undo = new Step("Back to stock",
                "Puts your backed-up stock init_boot back (to unroot, or before a firmware update). "
                        + "Run UNDO.sh with Run script as Root, then restart.");
        Button s3 = undo.button("Open Retroid Settings", v -> openRetroidSettings());
        Button l3 = undo.button("Show log", v -> showLog("undo-result.txt"));
        settingsBtns = new Button[]{s0, s1, s2, s3};
        logBtns = new Button[]{l0, l1, l2, l3};

        TextView credits = label("Magisk is made by topjohnwu (GPLv3). This app downloads it from the official "
                + "release and does not include it.\nRetroid Easy Root by The412Banner: " + REPO, 12, false);
        credits.setPadding(0, dp(20), 0, 0);
        Linkify.addLinks(credits, Linkify.WEB_URLS);
        list.addView(credits);
    }

    @Override
    protected void onResume() {
        super.onResume();
        main.removeCallbacks(ticker);
        main.post(ticker);
    }

    @Override
    protected void onPause() {
        super.onPause();
        main.removeCallbacks(ticker);
    }

    @Override
    protected void onDestroy() {
        super.onDestroy();
        bg.shutdown();
    }

    void refresh() {
        boolean files = Environment.isExternalStorageManager();
        boolean go = files && supported;

        if (files) access.set(GREEN, "✓ Allowed");
        else access.set(AMBER, "Not allowed yet");
        allowBtn.setEnabled(!files);

        // 2. Magisk APK
        File apk = new File(download, MAGISK_FILE);
        if (!files) {
            magisk.set(GREY, "Needs file access first");
        } else if (downloading) {
            magisk.set(AMBER, downloadText == null ? "Downloading…" : downloadText);
        } else if (!apk.exists()) {
            apkKey = null;
            apkOk = null;
            magisk.set(AMBER, "Not downloaded yet");
        } else {
            String key = apk.length() + ":" + apk.lastModified();
            if (!key.equals(apkKey)) {
                apkKey = key;
                apkOk = null;
                hashApk(apk, key);
            }
            if (apkOk == null) magisk.set(AMBER, "Checking the file…");
            else if (apkOk) magisk.set(GREEN, "✓ " + MAGISK_FILE + " is in Download (checked)");
            else magisk.set(RED, MAGISK_FILE + " in Download is not the official file. Download it again.");
        }
        magisk.info(downloadError == null ? null : "Download failed: " + downloadError);
        downloadBtn.setEnabled(go && !downloading && !Boolean.TRUE.equals(apkOk));

        // 3. tool files
        if (!files) {
            tools.set(GREY, "Needs file access first");
        } else if (copying) {
            tools.set(AMBER, "Copying…");
        } else {
            int missing = 0, old = 0;
            for (String n : TOOL_FILES) {
                File f = new File(toolDir, n);
                if (!f.exists()) missing++;
                else if (!Arrays.equals(readFile(f), assets.get(n))) old++;
            }
            if (missing == 0 && old == 0) tools.set(GREEN, "✓ Up to date in Download/RetroidRoot");
            else if (missing == TOOL_FILES.length) tools.set(AMBER, "Not copied yet");
            else tools.set(AMBER, (missing + old) + " file(s) missing or out of date. Copy again.");
        }
        tools.info(copyError != null ? "Copy failed: " + copyError : scanError);
        copyBtn.setEnabled(go && !copying);

        // 4. backup, 5. root, 6. check, undo: results the scripts wrote
        showResult(backup, "backup", files);
        showResult(root, "root", files);
        showResult(undo, "undo", files);
        showCheck(files);
        for (Button b : settingsBtns) b.setEnabled(supported);
        for (Button b : logBtns) b.setEnabled(files);

        // 6. Magisk app
        String v = installedVersion(MAGISK_PKG);
        if (v != null) app.set(GREEN, "✓ Magisk app " + v + " is installed");
        else app.set(AMBER, "Not installed");
        app.info(installError == null ? null : "Install failed: " + installError);
        installBtn.setEnabled(go && v == null && Boolean.TRUE.equals(apkOk));
    }

    void showResult(Step s, String step, boolean files) {
        if (!files) {
            s.set(GREY, "Needs file access first");
            s.info(null);
            return;
        }
        Map<String, String> st = readStatus(step);
        if (st == null) {
            s.set(GREY, "Not run yet");
            s.info(null);
            return;
        }
        String r = st.containsKey("RESULT") ? st.get("RESULT") : "";
        long t = parseLong(st.get("TIME")) * 1000;
        int color;
        String head;
        switch (r) {
            case "OK":
                color = GREEN;
                head = "✓ Done";
                break;
            case "ALREADY":
                color = GREEN;
                head = "backup".equals(step) ? "✓ Backup is there and checks out" : "✓ Nothing to do";
                break;
            case "DRYRUN":
                color = GREEN;
                head = "✓ Dry run";
                break;
            case "RUNNING":
                boolean stale = System.currentTimeMillis() - t > 15 * 60 * 1000;
                color = stale ? RED : AMBER;
                head = stale ? "Started but did not finish" : "Running…";
                break;
            case "STOPPED":
                color = AMBER;
                head = "Stopped";
                break;
            case "PROBLEM":
                color = RED;
                head = "Problem";
                break;
            default:
                color = GREY;
                head = r;
        }
        s.set(color, head + when(t));
        s.info(st.get("MESSAGE"));
    }

    void showCheck(boolean files) {
        Map<String, String> st = files ? readStatus("check") : null;
        if (st == null || !"OK".equals(st.get("RESULT"))) {
            showResult(check, "check", files);
            return;
        }
        String state = st.containsKey("STATE") ? st.get("STATE") : "";
        long t = parseLong(st.get("TIME")) * 1000;
        switch (state) {
            case "ROOTED":
                check.set(GREEN, "✓ Rooted" + when(t));
                break;
            case "FLASHED":
                check.set(AMBER, "Written, restart needed" + when(t));
                break;
            case "STOCK":
                check.set(GREY, "Not rooted" + when(t));
                break;
            default:
                check.set(RED, "Unknown state" + when(t));
        }
        check.info(st.get("MESSAGE"));
    }

    static String when(long t) {
        if (t <= 0) return "";
        return " (" + DateUtils.getRelativeTimeSpanString(t, System.currentTimeMillis(),
                DateUtils.MINUTE_IN_MILLIS) + ")";
    }

    void hashApk(File f, String key) {
        bg.execute(() -> {
            String sha = sha256(f);
            main.post(() -> {
                if (key.equals(apkKey)) {
                    apkOk = MAGISK_SHA256.equals(sha);
                    refresh();
                }
            });
        });
    }

    void downloadMagisk() {
        if (downloading) return;
        downloading = true;
        downloadText = null;
        downloadError = null;
        refresh();
        bg.execute(() -> {
            File part = new File(download, MAGISK_FILE + ".part");
            File out = new File(download, MAGISK_FILE);
            String err = null;
            try {
                HttpURLConnection c = (HttpURLConnection) new URL(MAGISK_URL).openConnection();
                c.setConnectTimeout(20000);
                c.setReadTimeout(30000);
                c.setInstanceFollowRedirects(true);
                int code = c.getResponseCode();
                if (code != HttpURLConnection.HTTP_OK) throw new IOException("server answered " + code);
                long total = c.getContentLengthLong();
                MessageDigest md = MessageDigest.getInstance("SHA-256");
                try (InputStream in = c.getInputStream(); OutputStream os = new FileOutputStream(part)) {
                    byte[] buf = new byte[65536];
                    long done = 0, lastUi = 0;
                    int n;
                    while ((n = in.read(buf)) > 0) {
                        os.write(buf, 0, n);
                        md.update(buf, 0, n);
                        done += n;
                        long now = SystemClock.uptimeMillis();
                        if (now - lastUi > 300) {
                            lastUi = now;
                            String text = String.format(Locale.ROOT, "Downloading… %.1f / %.1f MB",
                                    done / 1048576.0, total / 1048576.0);
                            main.post(() -> {
                                downloadText = text;
                                refresh();
                            });
                        }
                    }
                } finally {
                    c.disconnect();
                }
                String sha = hex(md.digest());
                if (!MAGISK_SHA256.equals(sha))
                    throw new IOException("the file does not match the official release (sha256 " + sha + ")");
                if (out.exists() && !out.delete()) throw new IOException("cannot replace " + out);
                if (!part.renameTo(out)) throw new IOException("cannot rename the download");
            } catch (Exception e) {
                err = e.getMessage() == null ? e.toString() : e.getMessage();
            }
            part.delete();
            String fe = err;
            main.post(() -> {
                downloading = false;
                downloadError = fe;
                apkKey = null;
                refresh();
            });
        });
    }

    void copyTools() {
        if (copying) return;
        copying = true;
        copyError = null;
        scanError = null;
        refresh();
        bg.execute(() -> {
            String err = null, scan = null;
            try {
                for (String n : TOOL_FILES) {
                    File f = new File(toolDir, n);
                    File dir = f.getParentFile();
                    if (!dir.isDirectory() && !dir.mkdirs()) throw new IOException("cannot create " + dir);
                    try (FileOutputStream os = new FileOutputStream(f)) {
                        os.write(assets.get(n));
                    }
                }
                scan = scanLaunchers();
            } catch (IOException e) {
                err = e.getMessage();
            }
            String fe = err, fs = scan;
            main.post(() -> {
                copying = false;
                copyError = fe;
                scanError = fs;
                refresh();
            });
        });
    }

    // Files written through /sdcard can stay "pending" in Android's media index, and other apps' file
    // pickers (Run script as Root too) do not list pending files. A scan clears it. Runs on the bg thread.
    String scanLaunchers() {
        String[] paths = new String[LAUNCHERS.length];
        for (int i = 0; i < paths.length; i++) paths[i] = new File(toolDir, LAUNCHERS[i]).getPath();
        CountDownLatch done = new CountDownLatch(paths.length);
        List<String> failed = Collections.synchronizedList(new ArrayList<>());
        MediaScannerConnection.scanFile(this, paths, null, (path, uri) -> {
            if (uri == null) failed.add(new File(path).getName());
            done.countDown();
        });
        try {
            if (!done.await(30, TimeUnit.SECONDS)) return "Files copied, but Android's media scan did not finish. "
                    + "If Run script as Root does not list them, restart the device.";
        } catch (InterruptedException e) {
            return "Files copied, but the media scan was interrupted.";
        }
        if (failed.isEmpty()) return null;
        return "Files copied, but Android did not index " + String.join(", ", failed)
                + ". Run script as Root may not list it. Restarting the device usually fixes this.";
    }

    void openRetroidSettings() {
        Intent i = new Intent(Intent.ACTION_MAIN)
                .setComponent(new ComponentName("com.rp.settings", "com.ro.settings.activity.MainSettingsActivity"))
                .addFlags(Intent.FLAG_ACTIVITY_NEW_TASK);
        try {
            startActivity(i);
            return;
        } catch (Exception ignored) {
        }
        Intent l = getPackageManager().getLaunchIntentForPackage("com.rp.settings");
        try {
            startActivity(l != null ? l : new Intent(Settings.ACTION_SETTINGS));
        } catch (Exception e) {
            Toast.makeText(this, "Could not open Settings: " + e.getMessage(), Toast.LENGTH_LONG).show();
        }
    }

    void showLog(String name) {
        File f = new File(toolDir, name);
        byte[] b = readFile(f);
        TextView tv = new TextView(this);
        tv.setText(b == null ? "No log yet (" + f + ")" : new String(b, StandardCharsets.UTF_8));
        tv.setTypeface(Typeface.MONOSPACE);
        tv.setTextSize(TypedValue.COMPLEX_UNIT_SP, 12);
        tv.setTextIsSelectable(true);
        int p = dp(12);
        tv.setPadding(p, p, p, p);
        ScrollView sv = new ScrollView(this);
        sv.addView(tv);
        new AlertDialog.Builder(this).setTitle(name).setView(sv).setPositiveButton("Close", null).show();
    }

    void installMagisk() {
        if (!getPackageManager().canRequestPackageInstalls()) {
            Toast.makeText(this, "Allow this app to install apps, then tap Install again.", Toast.LENGTH_LONG).show();
            startActivity(new Intent(Settings.ACTION_MANAGE_UNKNOWN_APP_SOURCES, Uri.parse("package:" + getPackageName())));
            return;
        }
        installError = null;
        File apk = new File(download, MAGISK_FILE);
        bg.execute(() -> {
            String err = null;
            try {
                if (!MAGISK_SHA256.equals(sha256(apk))) throw new IOException(MAGISK_FILE + " is not the official file");
                PackageInstaller pi = getPackageManager().getPackageInstaller();
                int id = pi.createSession(new PackageInstaller.SessionParams(
                        PackageInstaller.SessionParams.MODE_FULL_INSTALL));
                try (PackageInstaller.Session s = pi.openSession(id)) {
                    try (InputStream in = new FileInputStream(apk);
                         OutputStream out = s.openWrite("base.apk", 0, apk.length())) {
                        byte[] buf = new byte[65536];
                        int n;
                        while ((n = in.read(buf)) > 0) out.write(buf, 0, n);
                        s.fsync(out);
                    }
                    Intent cb = new Intent(this, InstallResultReceiver.class);
                    PendingIntent pend = PendingIntent.getBroadcast(this, id, cb,
                            PendingIntent.FLAG_UPDATE_CURRENT | PendingIntent.FLAG_MUTABLE);
                    s.commit(pend.getIntentSender());
                }
            } catch (Exception e) {
                err = e.getMessage() == null ? e.toString() : e.getMessage();
            }
            String fe = err;
            main.post(() -> {
                installError = fe;
                refresh();
            });
        });
    }

    String installedVersion(String pkg) {
        try {
            return getPackageManager().getPackageInfo(pkg, 0).versionName;
        } catch (PackageManager.NameNotFoundException e) {
            return null;
        }
    }

    String versionName() {
        String v = installedVersion(getPackageName());
        return v == null ? "" : v;
    }

    Map<String, String> readStatus(String step) {
        byte[] b = readFile(new File(toolDir, "status/" + step + ".txt"));
        if (b == null) return null;
        Map<String, String> m = new HashMap<>();
        for (String line : new String(b, StandardCharsets.UTF_8).split("\n")) {
            int e = line.indexOf('=');
            if (e > 0) m.put(line.substring(0, e), line.substring(e + 1));
        }
        return m;
    }

    TextView label(String s, float sp, boolean bold) {
        TextView t = new TextView(this);
        t.setText(s);
        t.setTextSize(TypedValue.COMPLEX_UNIT_SP, sp);
        if (bold) t.setTypeface(Typeface.DEFAULT_BOLD);
        t.setPadding(0, dp(3), 0, dp(3));
        return t;
    }

    int dp(int v) {
        return Math.round(v * getResources().getDisplayMetrics().density);
    }

    static long parseLong(String s) {
        try {
            return s == null ? 0 : Long.parseLong(s.trim());
        } catch (NumberFormatException e) {
            return 0;
        }
    }

    static byte[] readFile(File f) {
        try (InputStream in = new FileInputStream(f)) {
            return readAll(in);
        } catch (IOException e) {
            return null;
        }
    }

    static byte[] readAll(InputStream in) throws IOException {
        ByteArrayOutputStream o = new ByteArrayOutputStream();
        byte[] buf = new byte[8192];
        int n;
        while ((n = in.read(buf)) > 0) o.write(buf, 0, n);
        return o.toByteArray();
    }

    static String sha256(File f) {
        try (InputStream in = new FileInputStream(f)) {
            MessageDigest md = MessageDigest.getInstance("SHA-256");
            byte[] buf = new byte[65536];
            int n;
            while ((n = in.read(buf)) > 0) md.update(buf, 0, n);
            return hex(md.digest());
        } catch (Exception e) {
            return "";
        }
    }

    static String hex(byte[] b) {
        StringBuilder sb = new StringBuilder();
        for (byte x : b) sb.append(String.format(Locale.ROOT, "%02x", x));
        return sb.toString();
    }
}
