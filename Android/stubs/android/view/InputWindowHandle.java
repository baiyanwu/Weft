package android.view;

import android.os.IBinder;

/** Compile-only Android 16 hidden API declaration. Never packaged into the agent. */
public final class InputWindowHandle {
    public IBinder token;
    public int displayId;
}
