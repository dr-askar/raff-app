package com.raffapp.installcheck;

import android.content.Context;
import android.content.SharedPreferences;
import android.content.pm.PackageInstaller;

final class InstallState {
    static final String ACTION = "com.raffapp.installcheck.INSTALL_STATUS";
    static final String REFRESH = "com.raffapp.installcheck.REFRESH";
    static SharedPreferences prefs(Context c) {
        return c.getSharedPreferences("install-result", Context.MODE_PRIVATE);
    }
    static void result(Context c, int status, String message, int legacy) {
        prefs(c).edit().putInt("status", status).putString("message", message)
            .putInt("legacy", legacy).putBoolean("active", status == -1).commit();
    }
    static String title(int status) {
        switch (status) {
            case PackageInstaller.STATUS_SUCCESS: return "تم تثبيت رفّ بنجاح";
            case PackageInstaller.STATUS_PENDING_USER_ACTION: return "بانتظار موافقة أندرويد";
            case PackageInstaller.STATUS_FAILURE_BLOCKED: return "أندرويد منع التثبيت";
            case PackageInstaller.STATUS_FAILURE_ABORTED: return "أُلغيت محاولة التثبيت";
            case PackageInstaller.STATUS_FAILURE_INVALID: return "أندرويد رفض ملف التطبيق";
            case PackageInstaller.STATUS_FAILURE_CONFLICT: return "يوجد تعارض في الحزمة أو التوقيع";
            case PackageInstaller.STATUS_FAILURE_STORAGE: return "مشكلة في مساحة التخزين";
            case PackageInstaller.STATUS_FAILURE_INCOMPATIBLE: return "عدم توافق مع الهاتف";
            case 8: return "انتهت مهلة التثبيت";
            case -100: return "تعذر إكمال المحاولة";
            case -2: return "جارٍ التحقق من نسخة رفّ";
            default: return "تعذر التثبيت؛ تفاصيل أندرويد أدناه";
        }
    }
}
