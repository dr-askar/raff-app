package com.raffapp.installcheck;

import android.content.BroadcastReceiver;
import android.content.Context;
import android.content.Intent;
import android.content.pm.PackageInstaller;

public final class InstallResultReceiver extends BroadcastReceiver {
    static volatile Intent confirmation;
    @Override public void onReceive(Context context, Intent intent) {
        if (!InstallState.ACTION.equals(intent.getAction())) return;
        int session = intent.getIntExtra(PackageInstaller.EXTRA_SESSION_ID, -1);
        if (session < 0 || session != InstallState.prefs(context).getInt("session", -2)) return;
        int status = intent.getIntExtra(PackageInstaller.EXTRA_STATUS, -100);
        String message = intent.getStringExtra(PackageInstaller.EXTRA_STATUS_MESSAGE);
        int legacy = intent.getIntExtra("android.content.pm.extra.LEGACY_STATUS", 0);
        if (status == PackageInstaller.STATUS_PENDING_USER_ACTION) {
            confirmation = intent.getParcelableExtra(Intent.EXTRA_INTENT);
        } else {
            confirmation = null;
        }
        InstallState.result(context, status, message == null ? "" : message, legacy);
        context.sendBroadcast(new Intent(InstallState.REFRESH).setPackage(context.getPackageName()));
    }
}
