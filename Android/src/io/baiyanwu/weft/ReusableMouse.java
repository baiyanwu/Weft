package io.baiyanwu.weft;

import android.os.IBinder;
import android.os.SystemClock;
import android.view.InputDevice;

/** One resident absolute mouse. Only connection preparation waits for diagnostics. */
final class ReusableMouse implements AutoCloseable {
    interface Feedback { BridgeAgent.Snapshot sample(int deviceId) throws Exception; }
    private final Object lock = new Object();
    private final Feedback feedback;
    private final PointerVisibility visibility;
    private UhidDevice mouse;
    private AbsoluteMouseReport geometry;
    private int mouseId = -1, generation, x, y;
    private boolean closed, active, awaitingVisibility;
    private long epoch, sequence, enteredAt;
    private final int[] submittedX = new int[256], submittedY = new int[256];
    private int submittedCount;

    ReusableMouse(IBinder input, Feedback feedback) throws Exception {
        this.feedback = feedback;
        visibility = new PointerVisibility(input);
    }

    int deviceId() { synchronized (lock) { return mouseId; } }
    int generation() { synchronized (lock) { return generation; } }
    boolean preparedFor(int[] display) {
        synchronized (lock) { return !closed && mouse != null && geometry != null && geometry.matches(display); }
    }

    void prepare(int[] display) throws Exception {
        if (preparedFor(display)) return;
        destroyDevices();
        long started = SystemClock.elapsedRealtime();
        synchronized (lock) {
            if (closed) throw new IllegalStateException("Mouse session is closed");
            geometry = new AbsoluteMouseReport(display);
            mouse = new UhidDevice("Absolute Mouse", geometry.descriptor());
        }
        try {
            InputDevice device = mouse.awaitRegistration(started + 1800);
            if (!device.supportsSource(InputDevice.SOURCE_MOUSE)
                    || !device.supportsSource(InputDevice.SOURCE_STYLUS)
                    || device.supportsSource(InputDevice.SOURCE_TOUCHSCREEN))
                throw new IllegalStateException("Absolute native mouse is not supported");
            synchronized (lock) {
                mouseId = device.getId();
                x = geometry.width - 1; y = geometry.height - 1;
                mouse.send(geometry.report(x, y, 0, 0, 0));
            }
            long deadline = started + 2400;
            boolean located = false;
            while (SystemClock.elapsedRealtime() < deadline) {
                BridgeAgent.Snapshot snap = feedback.sample(deviceId());
                if (snap != null && snap.valid && Math.abs(snap.x - x) <= 3 && Math.abs(snap.y - y) <= 3) {
                    located = true; break;
                }
                SystemClock.sleep(4);
            }
            if (!located || !geometry.matches(BridgeAgent.displayInfo()))
                throw new IllegalStateException("Absolute mouse preparation failed");
            visibility.hide(deviceId());
            synchronized (lock) { generation++; }
            System.err.println("Absolute mouse prepared: generation=" + generation() + ", mouse=" + deviceId()
                + ", elapsed=" + (SystemClock.elapsedRealtime() - started) + "ms");
        } catch (Exception error) { destroyDevices(); throw error; }
    }

    void enter(long newEpoch, int px, int py, int[] display) throws Exception {
        if (!preparedFor(display) || !java.util.Arrays.equals(display, BridgeAgent.displayInfo()))
            throw new IllegalStateException("Display changed since pointer preparation");
        synchronized (lock) {
            visibility.hideNow(mouseId);
            epoch = newEpoch; sequence = 0; submittedCount = 0;
            x = px; y = py;
            mouse.send(geometry.report(x, y, 0, 0, 0));
            remember(x, y);
            active = true; awaitingVisibility = true; enteredAt = SystemClock.elapsedRealtime();
        }
    }

    void send(long inputEpoch, long inputSequence, int px, int py, int buttons, int wheel, int pan) throws Exception {
        synchronized (lock) {
            if (!active || inputEpoch != epoch || inputSequence <= sequence) return;
            mouse.send(geometry.report(px, py, buttons, wheel, pan));
            x = px; y = py; sequence = inputSequence;
            if (awaitingVisibility) remember(x, y);
        }
    }

    void release() throws Exception {
        synchronized (lock) {
            active = false; awaitingVisibility = false;
            if (mouse == null) return;
            mouse.send(geometry.report(x, y, 0, 0, 0));
            visibility.hideNow(mouseId);
        }
    }

    boolean needsVisibilityConfirmation() { synchronized (lock) { return active && awaitingVisibility; } }

    // Diagnostic work never holds the input lock. Movement and clicks continue while it runs.
    void confirmVisibility() throws Exception {
        final long visit;
        final int id;
        synchronized (lock) {
            if (!active || !awaitingVisibility) return;
            visit = epoch; id = mouseId;
        }
        BridgeAgent.Snapshot snap = feedback.sample(id);
        synchronized (lock) {
            if (!active || epoch != visit || id != mouseId) return;
            if (snap != null && snap.valid) {
                for (int i = 0; i < Math.min(submittedCount, submittedX.length); i++) {
                    if (Math.abs(snap.x - submittedX[i]) <= 3 && Math.abs(snap.y - submittedY[i]) <= 3) {
                        if (visibility.showNow(mouseId)) {
                            awaitingVisibility = false;
                            System.err.println("Absolute pointer visible: epoch=" + epoch + ", confirm="
                                + (SystemClock.elapsedRealtime() - enteredAt) + "ms");
                        }
                        break;
                    }
                }
            }
            if (awaitingVisibility && SystemClock.elapsedRealtime() - enteredAt > 800)
                throw new IllegalStateException("Absolute cursor could not be shown reliably");
        }
    }

    void refreshHidden() throws Exception { visibility.refreshHidden(); }

    private void remember(int px, int py) {
        int slot = submittedCount++ % submittedX.length;
        submittedX[slot] = px; submittedY[slot] = py;
    }

    void destroyDevices() {
        synchronized (lock) {
            active = false; awaitingVisibility = false;
            if (mouse != null) {
                try { mouse.send(geometry.report(x, y, 0, 0, 0)); } catch (Exception ignored) { }
                mouse.close(); mouse = null;
            }
            geometry = null; mouseId = -1;
        }
    }

    @Override public void close() {
        destroyDevices();
        synchronized (lock) { closed = true; }
        visibility.close();
    }
}
