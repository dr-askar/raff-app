package com.raffapp.installcheck;

import android.app.Activity;
import android.app.AlertDialog;
import android.app.PendingIntent;
import android.content.BroadcastReceiver;
import android.content.ClipData;
import android.content.ClipboardManager;
import android.content.Context;
import android.content.Intent;
import android.content.IntentFilter;
import android.content.SharedPreferences;
import android.content.pm.PackageInfo;
import android.content.pm.PackageInstaller;
import android.content.pm.PackageManager;
import android.graphics.Color;
import android.graphics.Typeface;
import android.graphics.drawable.GradientDrawable;
import android.net.Uri;
import android.os.Build;
import android.os.Bundle;
import android.provider.Settings;
import android.view.Gravity;
import android.view.View;
import android.widget.Button;
import android.widget.LinearLayout;
import android.widget.ScrollView;
import android.widget.TextView;
import java.io.File;
import java.io.FileOutputStream;
import java.io.InputStream;
import java.io.OutputStream;
import java.security.MessageDigest;
import java.util.Locale;

public final class MainActivity extends Activity {
    static final String RAFF = "com.raffapp.raff";
    static final String EXPECTED = ReleaseInfo.HASH;
    private TextView title, details, device;
    private Button install, open;
    private boolean visible;
    private final BroadcastReceiver refresh = new BroadcastReceiver() {
        @Override public void onReceive(Context c, Intent i) { render(); showConfirmation(); }
    };

    @Override public void onCreate(Bundle state) {
        super.onCreate(state);
        ScrollView scroll = new ScrollView(this);
        scroll.setFillViewport(true);
        scroll.setBackgroundColor(Color.rgb(241, 245, 250));
        LinearLayout root = new LinearLayout(this);
        root.setOrientation(LinearLayout.VERTICAL);
        root.setPadding(dp(24), dp(36), dp(24), dp(28));
        root.setLayoutDirection(View.LAYOUT_DIRECTION_RTL);
        scroll.addView(root);
        TextView heading = text("مساعد تثبيت رفّ", 27, true);
        root.addView(heading);
        root.addView(text("نسخة رفّ " + ReleaseInfo.VERSION + " موجودة داخل الأداة. اضغط الزر ثم وافق على نافذة أندرويد. إذا رفض الهاتف، ستظهر رسالة السبب هنا.", 18, false));
        root.addView(text("هذه أداة منفصلة للتثبيت والفحص. لا تحذف رفّ ولا تمسح بياناته، ولا تحتاج إنترنت أو كمبيوتر.", 15, false));
        install = new Button(this);
        install.setId(1001);
        install.setText("تثبيت رفّ وإظهار النتيجة");
        install.setTextSize(18);
        install.setTextColor(Color.WHITE);
        install.setBackgroundTintList(android.content.res.ColorStateList.valueOf(Color.rgb(49, 106, 145)));
        root.addView(install, new LinearLayout.LayoutParams(-1, dp(64)));
        install.setOnClickListener(v -> requestInstall());
        title = text("جاهز", 22, true); title.setId(1002); root.addView(title);
        details = text("", 15, false); details.setId(1003);
        details.setTextIsSelectable(true);
        details.setPadding(dp(14), dp(14), dp(14), dp(14));
        GradientDrawable card = new GradientDrawable();
        card.setColor(Color.WHITE); card.setCornerRadius(dp(14));
        details.setBackground(card); root.addView(details);
        open = new Button(this); open.setId(1004); open.setText("فتح رفّ");
        open.setOnClickListener(v -> {
            Intent intent = getPackageManager().getLaunchIntentForPackage(RAFF);
            if (intent != null) startActivity(intent);
        });
        root.addView(open);
        Button copy = new Button(this); copy.setText("نسخ نتيجة الفحص");
        copy.setOnClickListener(v -> ((ClipboardManager)getSystemService(CLIPBOARD_SERVICE))
            .setPrimaryClip(ClipData.newPlainText("Raff install result", report())));
        root.addView(copy);
        device = text("", 13, false); root.addView(device);
        setContentView(scroll);
        if (Build.VERSION.SDK_INT >= 33) registerReceiver(refresh, new IntentFilter(InstallState.REFRESH), Context.RECEIVER_NOT_EXPORTED);
        else registerReceiver(refresh, new IntentFilter(InstallState.REFRESH));
        SharedPreferences prior = InstallState.prefs(this);
        if (prior.getBoolean("active", false)) {
            int id = prior.getInt("session", -1);
            if (id >= 0 && getPackageManager().getPackageInstaller().getSessionInfo(id) != null) {
                InstallState.result(this, -1, "توجد محاولة سابقة؛ اضغط متابعة لاستئناف موافقة أندرويد.", 0);
            } else {
                InstallState.result(this, -100, "توقفت المحاولة السابقة قبل وصول نتيجة أندرويد. يمكنك بدء محاولة جديدة.", 0);
            }
        }
    }

    @Override protected void onResume() {
        super.onResume(); visible = true; render(); showConfirmation();
    }
    @Override protected void onPause() { visible = false; super.onPause(); }
    @Override protected void onDestroy() { unregisterReceiver(refresh); super.onDestroy(); }

    private TextView text(String value, int size, boolean bold) {
        TextView t = new TextView(this);
        t.setText(value); t.setTextSize(size); t.setTextColor(Color.rgb(37, 55, 73));
        t.setPadding(0, dp(10), 0, dp(14));
        t.setGravity(Gravity.START);
        if (bold) t.setTypeface(null, Typeface.BOLD);
        return t;
    }
    private int dp(int value) { return Math.round(value * getResources().getDisplayMetrics().density); }

    private String installed() {
        try {
            PackageInfo p = getPackageManager().getPackageInfo(RAFF, 0);
            return "نسخة رفّ الظاهرة لهذا المستخدم: " + p.versionName + " (" + p.versionCode + ")";
        } catch (PackageManager.NameNotFoundException e) {
            return "رفّ غير مثبت لهذا المستخدم.";
        }
    }
    private String environment() {
        return "Android " + Build.VERSION.RELEASE + " / API " + Build.VERSION.SDK_INT
            + "\n" + Build.MANUFACTURER + " " + Build.MODEL
            + "\nABI: " + android.text.TextUtils.join(", ", Build.SUPPORTED_ABIS) + "\n" + installed();
    }
    private String report() {
        SharedPreferences p = InstallState.prefs(this);
        return "Raff installer helper " + ReleaseInfo.HELPER + "\nRaff " + ReleaseInfo.VERSION + " / code " + ReleaseInfo.CODE + "\nSHA256: " + EXPECTED
            + "\n" + environment() + "\nStatus: " + p.getInt("status", -9)
            + "\nLegacy: " + p.getInt("legacy", 0) + "\n" + p.getString("message", "");
    }
    private void render() {
        SharedPreferences p = InstallState.prefs(this);
        boolean hasResult = p.contains("status");
        int status = p.getInt("status", -9);
        title.setText(hasResult ? InstallState.title(status) : "جاهز للتثبيت");
        String message = p.getString("message", "");
        details.setText(hasResult ? "رمز أندرويد: " + status + "\nLegacy: " + p.getInt("legacy", 0)
            + "\n\n" + (message.isEmpty() ? (status == 0 ? "نجحت عملية التثبيت." : "لا توجد تفاصيل إضافية من أندرويد حتى الآن.") : message)
            : "النسخة المضمّنة هي رفّ " + ReleaseInfo.VERSION + ". لا يبدأ التثبيت إلا بضغطك على الزر.");
        device.setText(environment());
        open.setVisibility(status == 0 ? View.VISIBLE : View.GONE);
        install.setEnabled(!p.getBoolean("active", false) || status == -1);
        install.setText(status == -1 ? "متابعة موافقة أندرويد" : "تثبيت رفّ وإظهار النتيجة");
    }
    private void requestInstall() {
        if (Build.VERSION.SDK_INT >= 26 && !getPackageManager().canRequestPackageInstalls()) {
            new AlertDialog.Builder(this).setTitle("سماح تثبيت رفّ من هذه الأداة")
                .setMessage("أندرويد يحتاج سماح التثبيت لهذا المساعد. فعّل السماح في الصفحة التالية ثم ارجع واضغط زر التثبيت. لا تحتاج تعطيل حماية الهاتف.")
                .setPositiveButton("فتح إعداد السماح", (d, w) -> {
                    try { startActivity(new Intent(Settings.ACTION_MANAGE_UNKNOWN_APP_SOURCES, Uri.parse("package:" + getPackageName()))); }
                    catch (RuntimeException e) { fail("تعذر فتح إعداد السماح: " + e.getMessage()); }
                }).setNegativeButton("إلغاء", null).show();
            return;
        }
        if (InstallState.prefs(this).getInt("status", -9) == -1) {
            if (InstallResultReceiver.confirmation != null) { showConfirmation(); return; }
            int id = InstallState.prefs(this).getInt("session", -1);
            try (PackageInstaller.Session session = getPackageManager().getPackageInstaller().openSession(id)) {
                commit(session, id);
            } catch (Exception e) { fail("تعذر استئناف المحاولة: " + e.getMessage()); }
            return;
        }
        InstallState.prefs(this).edit().putBoolean("active", true).putInt("status", -2)
            .putString("message", "جارٍ مطابقة الملف ثم إرساله إلى مثبّت أندرويد…").remove("session").commit();
        render();
        new Thread(this::prepare, "raff-installer").start();
    }
    private void prepare() {
        int sessionId = -1;
        File apk = new File(getCacheDir(), "raff-app.apk");
        PackageInstaller installer = getPackageManager().getPackageInstaller();
        try {
            MessageDigest digest = MessageDigest.getInstance("SHA-256");
            byte[] buffer = new byte[65536];
            try (InputStream input = getAssets().open("raff-app.apk"); OutputStream out = new FileOutputStream(apk)) {
                int n; while ((n = input.read(buffer)) != -1) { out.write(buffer, 0, n); digest.update(buffer, 0, n); }
            }
            StringBuilder hex = new StringBuilder();
            for (byte b : digest.digest()) hex.append(String.format(Locale.ROOT, "%02x", b & 255));
            if (!EXPECTED.equals(hex.toString())) throw new SecurityException("بصمة نسخة رفّ المضمّنة غير مطابقة؛ لم يبدأ التثبيت.");
            PackageInfo info = getPackageManager().getPackageArchiveInfo(apk.getPath(), 0);
            if (info == null || !RAFF.equals(info.packageName) || info.versionCode != ReleaseInfo.CODE)
                throw new SecurityException("تعذر التحقق من هوية رفّ " + ReleaseInfo.VERSION + "؛ لم يبدأ التثبيت.");
            PackageInstaller.SessionParams params = new PackageInstaller.SessionParams(PackageInstaller.SessionParams.MODE_FULL_INSTALL);
            params.setAppPackageName(RAFF); params.setAppLabel("رفّ"); params.setSize(apk.length());
            if (Build.VERSION.SDK_INT >= 31) params.setRequireUserAction(PackageInstaller.SessionParams.USER_ACTION_REQUIRED);
            sessionId = installer.createSession(params);
            InstallState.prefs(this).edit().putInt("session", sessionId).commit();
            try (PackageInstaller.Session session = installer.openSession(sessionId)) {
                try (InputStream in = new java.io.FileInputStream(apk); OutputStream out = session.openWrite("base.apk", 0, apk.length())) {
                    int n; while ((n = in.read(buffer)) != -1) out.write(buffer, 0, n);
                    session.fsync(out);
                }
                commit(session, sessionId);
            }
        } catch (Exception e) {
            if (sessionId >= 0) try { installer.abandonSession(sessionId); } catch (RuntimeException ignored) { }
            fail(e.getClass().getSimpleName() + ": " + e.getMessage());
        } finally { apk.delete(); }
    }
    private void commit(PackageInstaller.Session session, int id) {
        Intent intent = new Intent(this, InstallResultReceiver.class).setAction(InstallState.ACTION);
        int flags = PendingIntent.FLAG_UPDATE_CURRENT;
        if (Build.VERSION.SDK_INT >= 31) flags |= PendingIntent.FLAG_MUTABLE;
        PendingIntent pending = PendingIntent.getBroadcast(this, id, intent, flags);
        session.commit(pending.getIntentSender());
    }
    private void showConfirmation() {
        if (!visible || InstallResultReceiver.confirmation == null) return;
        Intent confirmation = InstallResultReceiver.confirmation;
        InstallResultReceiver.confirmation = null;
        try { startActivity(confirmation); }
        catch (RuntimeException e) { fail("تعذر فتح موافقة أندرويد: " + e.getMessage()); }
    }
    private void fail(String message) {
        InstallState.result(this, -100, message, 0);
        runOnUiThread(this::render);
    }
}
