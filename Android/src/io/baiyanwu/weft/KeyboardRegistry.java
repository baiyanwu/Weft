package io.baiyanwu.weft;

import android.os.IBinder;
import android.view.InputDevice;
import java.lang.reflect.Method;

/** Fresh service queries avoid InputManagerGlobal's application-process device cache. */
final class KeyboardRegistry {
    private final Object service;
    private final Method ids;
    private final Method device;

    KeyboardRegistry() throws Exception {
        IBinder binder = (IBinder) Class.forName("android.os.ServiceManager")
            .getMethod("getService", String.class).invoke(null, "input");
        if (binder == null) throw new IllegalStateException("Input service unavailable");
        Class<?> type = Class.forName("android.hardware.input.IInputManager");
        service = Class.forName("android.hardware.input.IInputManager$Stub")
            .getMethod("asInterface", IBinder.class).invoke(null, binder);
        ids = type.getMethod("getInputDeviceIds");
        device = type.getMethod("getInputDevice", int.class);
    }

    int[] ids() throws Exception { return (int[]) ids.invoke(service); }
    InputDevice device(int id) throws Exception { return (InputDevice) device.invoke(service, id); }
}
