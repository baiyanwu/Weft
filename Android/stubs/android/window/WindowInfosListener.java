package android.window;

import android.util.Pair;
import android.view.InputWindowHandle;

/** Compile-only Android 16 hidden API declaration. The implementation is provided by Android. */
public abstract class WindowInfosListener {
    public WindowInfosListener() { }
    public abstract void onWindowInfosChanged(InputWindowHandle[] windows, DisplayInfo[] displays);
    public Pair<InputWindowHandle[], DisplayInfo[]> register() { throw new UnsupportedOperationException(); }
    public void unregister() { throw new UnsupportedOperationException(); }
    public static final class DisplayInfo { }
}
