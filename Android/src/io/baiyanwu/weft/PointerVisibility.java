package io.baiyanwu.weft;

import android.os.IBinder;
import android.os.Parcel;
import android.os.SystemClock;
import android.util.Pair;
import android.view.InputWindowHandle;
import android.view.PointerIcon;
import android.window.WindowInfosListener;

import java.lang.reflect.Method;
import java.util.ArrayList;
import java.util.concurrent.CountDownLatch;

/** Changes only the cursor icon for our mouse; no app focus, overlays or screen capture. */
final class PointerVisibility implements AutoCloseable {
    private final Object input;
    private final Method setIcon;
    private final PointerIcon hiddenIcon = systemIcon(PointerIcon.TYPE_NULL);
    private final PointerIcon visibleIcon = systemIcon(PointerIcon.TYPE_DEFAULT);
    private final WindowInfosListener listener;
    private final CountDownLatch initialWindowsReady = new CountDownLatch(1);
    private volatile IBinder[] windowTokens = new IBinder[0];
    private volatile long windowRevision;
    private IBinder lastToken;
    private int lastDeviceId = -1;
    private int hiddenDeviceId = -1;
    private long lastAppliedAt;
    private long appliedRevision = -1;
    private volatile boolean closed;

    PointerVisibility(IBinder inputBinder) throws Exception {
        Class<?> type = Class.forName("android.hardware.input.IInputManager");
        input = Class.forName("android.hardware.input.IInputManager$Stub")
            .getMethod("asInterface", IBinder.class).invoke(null, inputBinder);
        setIcon = type.getMethod("setPointerIcon", PointerIcon.class, int.class, int.class,
            int.class, IBinder.class);
        listener = new WindowInfosListener() {
            @Override public void onWindowInfosChanged(InputWindowHandle[] windows, DisplayInfo[] displays) {
                try { initialWindowsReady.await(); }
                catch (InterruptedException interrupted) { Thread.currentThread().interrupt(); return; }
                if (closed) return;
                rememberTokens(windows);
            }
        };
        // AOSP explicitly permits this listener for shell (ACCESS_SURFACE_FLINGER).
        // Retain only input tokens for display 0, never window names or content.
        try {
            Pair<InputWindowHandle[], WindowInfosListener.DisplayInfo[]> initial = listener.register();
            if (initial != null) rememberTokens(initial.first);
        } finally { initialWindowsReady.countDown(); }
    }

    private void rememberTokens(InputWindowHandle[] windows) {
        ArrayList<IBinder> tokens = new ArrayList<>();
        if (windows != null) {
            for (InputWindowHandle window : windows) {
                if (window.displayId == 0 && window.token != null && !tokens.contains(window.token))
                    tokens.add(window.token);
            }
        }
        windowTokens = tokens.toArray(new IBinder[0]);
        windowRevision++;
    }

    synchronized void hide(int deviceId) throws Exception {
        requireIcon(hiddenIcon, deviceId);
        hiddenDeviceId = deviceId;
    }

    synchronized void show(int deviceId) throws Exception {
        hiddenDeviceId = -1;
        requireIcon(visibleIcon, deviceId);
    }

    synchronized void hideNow(int deviceId) throws Exception {
        hiddenDeviceId = deviceId;
        appliedRevision = -1; lastAppliedAt = 0;
        apply(hiddenIcon, deviceId, true);
    }

    synchronized boolean showNow(int deviceId) throws Exception {
        if (!apply(visibleIcon, deviceId, true)) return false;
        hiddenDeviceId = -1;
        return true;
    }

    synchronized void refreshHidden() throws Exception {
        if (closed || hiddenDeviceId < 0) return;
        long now = SystemClock.elapsedRealtime();
        if (windowRevision == appliedRevision && now - lastAppliedAt < 250) return;
        // A newly exposed window may replace the icon while our mouse is idle.
        // Reassert TYPE_NULL without sending mouse movement or taking focus.
        apply(hiddenIcon, hiddenDeviceId, windowRevision != appliedRevision);
        lastAppliedAt = now;
    }

    private void requireIcon(PointerIcon icon, int deviceId) throws Exception {
        if (closed || deviceId < 0) throw new IllegalStateException("Pointer visibility is unavailable");
        long deadline = SystemClock.elapsedRealtime() + 250;
        do {
            if (apply(icon, deviceId, true)) return;
            SystemClock.sleep(8);
        } while (SystemClock.elapsedRealtime() < deadline);
        throw new IllegalStateException("No current hover window accepted the pointer icon");
    }

    private boolean apply(PointerIcon icon, int deviceId, boolean findWindow) throws Exception {
        if (lastToken != null && lastDeviceId == deviceId && set(icon, deviceId, lastToken)) {
            lastAppliedAt = SystemClock.elapsedRealtime();
            appliedRevision = windowRevision;
            return true;
        }
        if (!findWindow) return false;
        for (IBinder token : windowTokens) {
            if (token == lastToken && lastDeviceId == deviceId) continue;
            // Android validates that this specific device/pointer is in the window.
            if (set(icon, deviceId, token)) {
                lastToken = token; lastDeviceId = deviceId;
                lastAppliedAt = SystemClock.elapsedRealtime();
                appliedRevision = windowRevision;
                return true;
            }
        }
        return false;
    }

    private boolean set(PointerIcon icon, int deviceId, IBinder token) throws Exception {
        return Boolean.TRUE.equals(setIcon.invoke(input, icon, 0, deviceId, 0, token));
    }

    private static PointerIcon systemIcon(int type) {
        // A system icon's parcel contains its type only; Android resolves resources.
        Parcel parcel = Parcel.obtain();
        try {
            parcel.writeInt(type); parcel.setDataPosition(0);
            return PointerIcon.CREATOR.createFromParcel(parcel);
        } finally { parcel.recycle(); }
    }

    @Override public synchronized void close() {
        if (closed) return;
        closed = true; hiddenDeviceId = -1; lastToken = null;
        listener.unregister();
        windowTokens = new IBinder[0];
    }
}
