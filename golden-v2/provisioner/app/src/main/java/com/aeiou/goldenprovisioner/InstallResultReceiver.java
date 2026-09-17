package com.aeiou.goldenprovisioner;

import android.content.BroadcastReceiver;
import android.content.Context;
import android.content.Intent;
import android.content.SharedPreferences;
import android.content.pm.PackageInstaller;
import android.util.Log;

public final class InstallResultReceiver extends BroadcastReceiver {
    @Override
    public void onReceive(Context context, Intent intent) {
        SharedPreferences p = ProvisionJobService.prefs(context);
        int status = intent.getIntExtra(PackageInstaller.EXTRA_STATUS,
                PackageInstaller.STATUS_FAILURE);
        String expected = intent.getStringExtra("expectedPackage");
        String message = intent.getStringExtra(PackageInstaller.EXTRA_STATUS_MESSAGE);
        SharedPreferences.Editor e = p.edit()
                .remove("pendingPackage")
                .remove("pendingSession");
        if (status == PackageInstaller.STATUS_SUCCESS) {
            e.remove("lastError");
            Log.i(ProvisionJobService.TAG, "Installed " + expected);
        } else {
            e.putString("lastError", "install status=" + status + " package="
                    + expected + " message=" + String.valueOf(message));
            Log.e(ProvisionJobService.TAG, "Install failed for " + expected
                    + " status=" + status + " message=" + message);
        }
        e.apply();
        ProvisionJobService.schedule(context, status == PackageInstaller.STATUS_SUCCESS
                ? 2_000L : 30_000L);
    }
}
