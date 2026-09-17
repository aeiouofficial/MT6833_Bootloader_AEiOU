package com.aeiou.goldenprovisioner;

import android.Manifest;
import android.app.PendingIntent;
import android.app.job.JobInfo;
import android.app.job.JobParameters;
import android.app.job.JobScheduler;
import android.app.job.JobService;
import android.content.ComponentName;
import android.content.Context;
import android.content.Intent;
import android.content.SharedPreferences;
import android.content.pm.PackageInfo;
import android.content.pm.PackageInstaller;
import android.content.pm.PackageManager;
import android.content.pm.Signature;
import android.os.Build;
import android.util.Log;

import org.json.JSONArray;
import org.json.JSONObject;

import java.io.File;
import java.io.FileInputStream;
import java.io.InputStream;
import java.io.OutputStream;
import java.nio.charset.StandardCharsets;
import java.security.MessageDigest;

public final class ProvisionJobService extends JobService {
    static final String TAG = "AEiOUGolden";
    static final String PREFS = "golden_state";
    static final String MANIFEST = "/product/etc/aeiou-golden/apps.json";
    static final String PAYLOAD_ROOT = "/product/etc/aeiou-golden/apks";
    static final int JOB_ID = 0x4145494F;
    static final int MAX_RETRIES = 3;

    static void schedule(Context context, long latencyMs) {
        JobScheduler js = context.getSystemService(JobScheduler.class);
        if (js == null) return;
        JobInfo job = new JobInfo.Builder(JOB_ID,
                new ComponentName(context, ProvisionJobService.class))
                .setMinimumLatency(latencyMs)
                .setOverrideDeadline(Math.max(latencyMs + 45_000L, 60_000L))
                .build();
        js.schedule(job);
    }

    static SharedPreferences prefs(Context context) {
        return context.createDeviceProtectedStorageContext()
                .getSharedPreferences(PREFS, Context.MODE_PRIVATE);
    }

    @Override
    public boolean onStartJob(JobParameters params) {
        new Thread(() -> {
            try {
                provisionOnce();
            } catch (Throwable t) {
                Log.e(TAG, "Provisioning failed closed", t);
                prefs(this).edit().putString("lastError", t.toString()).apply();
            } finally {
                jobFinished(params, false);
            }
        }, "aeiou-golden-provision").start();
        return true;
    }

    @Override
    public boolean onStopJob(JobParameters params) {
        return true;
    }

    private void provisionOnce() throws Exception {
        if (checkSelfPermission(Manifest.permission.INSTALL_PACKAGES)
                != PackageManager.PERMISSION_GRANTED) {
            throw new SecurityException("INSTALL_PACKAGES was not granted to privileged provisioner");
        }
        JSONObject manifest = new JSONObject(readUtf8(new File(MANIFEST)));
        String buildId = manifest.getString("buildId");
        SharedPreferences p = prefs(this);
        if (buildId.equals(p.getString("completeBuildId", ""))) return;

        String pendingPackage = p.getString("pendingPackage", "");
        int pendingSession = p.getInt("pendingSession", -1);
        if (!pendingPackage.isEmpty() && pendingSession >= 0) {
            PackageInstaller.SessionInfo info = getPackageManager().getPackageInstaller()
                    .getSessionInfo(pendingSession);
            if (info != null && info.isActive()) return;
            p.edit().remove("pendingPackage").remove("pendingSession").apply();
        }

        JSONArray apps = manifest.getJSONArray("apps");
        for (int i = 0; i < apps.length(); i++) {
            JSONObject app = apps.getJSONObject(i);
            String mode = app.getString("mode");
            String pkg = app.getString("package");
            String version = app.getString("version");
            if ("system".equals(mode)) {
                assertInstalled(pkg, version, null);
                continue;
            }
            if (!"provision".equals(mode)) throw new IllegalStateException("Unknown mode: " + mode);

            File apk = new File(PAYLOAD_ROOT, app.getString("file"));
            String expectedSha = app.getString("sha256").toLowerCase();
            if (!expectedSha.equals(sha256(apk))) throw new SecurityException("SHA-256 mismatch: " + apk);
            PackageInfo archive = getPackageManager().getPackageArchiveInfo(
                    apk.getAbsolutePath(), PackageManager.GET_SIGNING_CERTIFICATES);
            if (archive == null || !pkg.equals(archive.packageName)
                    || !version.equals(archive.versionName)) {
                throw new SecurityException("APK identity mismatch: " + apk);
            }
            String signer = signerSha256(archive);
            if (isInstalledExact(pkg, version, signer)) continue;

            int retries = p.getInt("retry_" + pkg, 0);
            if (retries >= MAX_RETRIES) {
                throw new IllegalStateException("Retry limit reached for " + pkg);
            }
            beginInstall(apk, pkg, buildId, retries + 1);
            return;
        }
        p.edit().putString("completeBuildId", buildId).remove("lastError").apply();
        Log.i(TAG, "Golden provisioning complete for " + buildId);
    }

    private void beginInstall(File apk, String pkg, String buildId, int retry) throws Exception {
        PackageInstaller installer = getPackageManager().getPackageInstaller();
        PackageInstaller.SessionParams sp = new PackageInstaller.SessionParams(
                PackageInstaller.SessionParams.MODE_FULL_INSTALL);
        sp.setAppPackageName(pkg);
        sp.setSize(apk.length());
        sp.setInstallReason(PackageManager.INSTALL_REASON_DEVICE_RESTORE);
        if (Build.VERSION.SDK_INT >= 31) {
            sp.setInstallScenario(PackageManager.INSTALL_SCENARIO_DEVICE_RESTORE);
        }
        int sessionId = installer.createSession(sp);
        SharedPreferences p = prefs(this);
        p.edit().putString("pendingPackage", pkg).putInt("pendingSession", sessionId)
                .putInt("retry_" + pkg, retry).apply();
        try (PackageInstaller.Session session = installer.openSession(sessionId);
             InputStream in = new FileInputStream(apk);
             OutputStream out = session.openWrite("base.apk", 0, apk.length())) {
            byte[] buffer = new byte[1024 * 1024];
            int n;
            while ((n = in.read(buffer)) >= 0) out.write(buffer, 0, n);
            session.fsync(out);
            Intent status = new Intent(this, InstallResultReceiver.class)
                    .setAction("com.aeiou.goldenprovisioner.INSTALL_RESULT")
                    .putExtra("expectedPackage", pkg)
                    .putExtra("buildId", buildId);
            PendingIntent pi = PendingIntent.getBroadcast(this, sessionId, status,
                    PendingIntent.FLAG_UPDATE_CURRENT | PendingIntent.FLAG_MUTABLE);
            session.commit(pi.getIntentSender());
        } catch (Throwable t) {
            p.edit().remove("pendingPackage").remove("pendingSession").apply();
            try { installer.abandonSession(sessionId); } catch (Throwable ignored) { }
            throw t;
        }
    }

    private boolean isInstalledExact(String pkg, String version, String signer) {
        try {
            PackageInfo current = getPackageManager().getPackageInfo(
                    pkg, PackageManager.GET_SIGNING_CERTIFICATES);
            return version.equals(current.versionName) && signer.equals(signerSha256(current));
        } catch (Exception ignored) {
            return false;
        }
    }

    private void assertInstalled(String pkg, String version, String signer) throws Exception {
        PackageInfo current = getPackageManager().getPackageInfo(
                pkg, PackageManager.GET_SIGNING_CERTIFICATES);
        if (!version.equals(current.versionName)) {
            throw new IllegalStateException("System package version mismatch: " + pkg);
        }
        if (signer != null && !signer.equals(signerSha256(current))) {
            throw new SecurityException("System package signer mismatch: " + pkg);
        }
    }

    static String signerSha256(PackageInfo info) throws Exception {
        if (info.signingInfo == null) throw new SecurityException("Missing signing info: " + info.packageName);
        Signature[] signatures = info.signingInfo.getApkContentsSigners();
        if (signatures == null || signatures.length == 0) throw new SecurityException("Missing signer: " + info.packageName);
        MessageDigest md = MessageDigest.getInstance("SHA-256");
        return hex(md.digest(signatures[0].toByteArray()));
    }

    static String sha256(File file) throws Exception {
        MessageDigest md = MessageDigest.getInstance("SHA-256");
        try (InputStream in = new FileInputStream(file)) {
            byte[] buffer = new byte[1024 * 1024];
            int n;
            while ((n = in.read(buffer)) >= 0) md.update(buffer, 0, n);
        }
        return hex(md.digest());
    }

    private static String readUtf8(File file) throws Exception {
        try (InputStream in = new FileInputStream(file)) {
            byte[] data = new byte[(int) file.length()];
            int off = 0;
            while (off < data.length) {
                int n = in.read(data, off, data.length - off);
                if (n < 0) break;
                off += n;
            }
            if (off != data.length) throw new IllegalStateException("Short read: " + file);
            return new String(data, StandardCharsets.UTF_8);
        }
    }

    private static String hex(byte[] bytes) {
        StringBuilder out = new StringBuilder(bytes.length * 2);
        for (byte b : bytes) out.append(String.format("%02x", b & 0xff));
        return out.toString();
    }
}
