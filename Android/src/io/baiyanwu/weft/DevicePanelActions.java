package io.baiyanwu.weft;

import android.os.IBinder;

/** Status-bar operations run in the keyboard process under its adb shell identity. */
final class DevicePanelActions {
    private final Class<?> type;
    private final Object service;

    DevicePanelActions() throws Exception {
        IBinder binder = (IBinder) Class.forName("android.os.ServiceManager")
            .getMethod("getService", String.class).invoke(null, "statusbar");
        if (binder == null) throw new IllegalStateException("Status bar service unavailable");
        type = Class.forName("com.android.internal.statusbar.IStatusBarService");
        service = Class.forName("com.android.internal.statusbar.IStatusBarService$Stub")
            .getMethod("asInterface", IBinder.class).invoke(null, binder);
    }

    void perform(int action) throws Exception {
        switch (action) {
        case -1: type.getMethod("expandNotificationsPanel").invoke(service); break;
        case -2: type.getMethod("expandSettingsPanel", String.class).invoke(service, (Object) null); break;
        case -3: type.getMethod("collapsePanels").invoke(service); break;
        default: throw new IllegalArgumentException("Unsupported panel action");
        }
    }
}
