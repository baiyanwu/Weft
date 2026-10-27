package io.baiyanwu.weft;

import android.os.IBinder;
import android.os.SystemClock;
import android.view.InputDevice;
import android.view.InputEvent;
import android.view.KeyCharacterMap;
import android.view.KeyEvent;

import java.lang.reflect.Method;

/** Complete system-action presses for mouse and keyboard mappings. */
final class DeviceKeyActions {
    private final Object input;
    private final Method inject;
    private final boolean targeted;
    private volatile KeyEvent pendingRelease;

    DeviceKeyActions(IBinder binder) throws Exception {
        Class<?> type = Class.forName("android.hardware.input.IInputManager");
        input = Class.forName("android.hardware.input.IInputManager$Stub")
            .getMethod("asInterface", IBinder.class).invoke(null, binder);
        Method method;
        boolean target;
        try {
            method = type.getMethod("injectInputEventToTarget", InputEvent.class, int.class, int.class);
            target = true;
        } catch (NoSuchMethodException legacy) {
            method = type.getMethod("injectInputEvent", InputEvent.class, int.class);
            target = false;
        }
        inject = method; targeted = target;
    }

    void press(int code) throws Exception {
        if (pendingRelease != null) {
            release();
            if (pendingRelease != null) throw new IllegalStateException("Previous device key is still pressed");
        }
        switch (code) {
        case KeyEvent.KEYCODE_BACK: case KeyEvent.KEYCODE_HOME: case KeyEvent.KEYCODE_APP_SWITCH:
        case KeyEvent.KEYCODE_FORWARD: case KeyEvent.KEYCODE_SETTINGS:
        case KeyEvent.KEYCODE_DPAD_UP: case KeyEvent.KEYCODE_DPAD_DOWN:
        case KeyEvent.KEYCODE_DPAD_LEFT: case KeyEvent.KEYCODE_DPAD_RIGHT: case KeyEvent.KEYCODE_DPAD_CENTER:
        case KeyEvent.KEYCODE_PAGE_UP: case KeyEvent.KEYCODE_PAGE_DOWN:
        case KeyEvent.KEYCODE_VOLUME_UP: case KeyEvent.KEYCODE_VOLUME_DOWN: case KeyEvent.KEYCODE_VOLUME_MUTE:
        case KeyEvent.KEYCODE_MEDIA_PLAY_PAUSE: case KeyEvent.KEYCODE_MEDIA_NEXT:
        case KeyEvent.KEYCODE_MEDIA_PREVIOUS: case KeyEvent.KEYCODE_MEDIA_STOP:
        case KeyEvent.KEYCODE_SYSRQ: case KeyEvent.KEYCODE_POWER: case KeyEvent.KEYCODE_WAKEUP:
        case KeyEvent.KEYCODE_SLEEP: case KeyEvent.KEYCODE_BRIGHTNESS_UP: case KeyEvent.KEYCODE_BRIGHTNESS_DOWN:
        case KeyEvent.KEYCODE_CAMERA: case KeyEvent.KEYCODE_SEARCH: case KeyEvent.KEYCODE_VOICE_ASSIST:
        case KeyEvent.KEYCODE_MENU: break;
        default: throw new IllegalArgumentException("Unsupported device key");
        }
        long downTime = SystemClock.uptimeMillis();
        KeyEvent release = new KeyEvent(downTime, downTime, KeyEvent.ACTION_UP, code, 0, 0,
            KeyCharacterMap.VIRTUAL_KEYBOARD, 0, 0, InputDevice.SOURCE_KEYBOARD);
        pendingRelease = release;
        try {
            send(new KeyEvent(downTime, downTime, KeyEvent.ACTION_DOWN, code, 0, 0,
                KeyCharacterMap.VIRTUAL_KEYBOARD, 0, 0, InputDevice.SOURCE_KEYBOARD), 2);
        } finally {
            send(KeyEvent.changeTimeRepeat(release, SystemClock.uptimeMillis(), 0), 2);
            if (pendingRelease == release) pendingRelease = null;
        }
    }

    void release() {
        KeyEvent event = pendingRelease;
        if (event == null) return;
        try {
            // Cleanup must not wait for an unresponsive app while the watchdog is exiting.
            send(KeyEvent.changeTimeRepeat(event, SystemClock.uptimeMillis(), 0), 0);
            if (pendingRelease == event) pendingRelease = null;
        } catch (Exception failure) { System.err.println("Device key release failed: " + failure); }
    }

    private void send(KeyEvent event, int mode) throws Exception {
        // WAIT_FOR_FINISH keeps down/up and the next input in order. -1 targets the current window.
        Object accepted = targeted ? inject.invoke(input, event, mode, -1) : inject.invoke(input, event, mode);
        if (!Boolean.TRUE.equals(accepted)) throw new IllegalStateException("Device key injection rejected");
    }
}
