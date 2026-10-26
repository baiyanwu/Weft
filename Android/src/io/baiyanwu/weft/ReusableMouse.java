package io.baiyanwu.weft;

import android.os.IBinder;
import android.os.SystemClock;
import android.view.InputDevice;
import android.view.ViewConfiguration;

import java.util.concurrent.Executors;
import java.util.concurrent.ScheduledExecutorService;
import java.util.concurrent.TimeUnit;

/** One resident absolute mouse. Only connection preparation waits for diagnostics. */
final class ReusableMouse implements AutoCloseable {
    interface Feedback { BridgeAgent.Snapshot sample(int deviceId) throws Exception; }
    interface ActionFailure { void report(long epoch, String action, Exception error); }
    private final Object lock = new Object();
    private final Feedback feedback;
    private final PointerVisibility visibility;
    private final ActionFailure actionFailure;
    private final ScheduledExecutorService actionQueue = Executors.newSingleThreadScheduledExecutor(task -> {
        Thread worker = new Thread(task, "weft-pointer-actions");
        worker.setDaemon(true);
        return worker;
    });
    private UhidDevice mouse;
    private AbsoluteMouseReport geometry;
    private int mouseId = -1, generation, x, y;
    private boolean closed, active, awaitingVisibility;
    private long epoch, sequence, enteredAt;
    private long actionGeneration;
    private int physicalButtons, mappedButtons;
    private final int[] submittedX = new int[256], submittedY = new int[256];
    private int submittedCount;

    ReusableMouse(IBinder input, Feedback feedback, ActionFailure actionFailure) throws Exception {
        this.feedback = feedback;
        this.actionFailure = actionFailure;
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
            cancelMappedLocked(); physicalButtons = 0;
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
            physicalButtons = buttons;
            mouse.send(geometry.report(px, py, physicalButtons | mappedButtons, wheel, pan));
            x = px; y = py; sequence = inputSequence;
            if (awaitingVisibility) remember(x, y);
        }
    }

    void release() throws Exception {
        synchronized (lock) {
            active = false; awaitingVisibility = false;
            cancelMappedLocked(); physicalButtons = 0;
            if (mouse == null) return;
            mouse.send(geometry.report(x, y, 0, 0, 0));
            visibility.hideNow(mouseId);
        }
    }

    // Mapped clicks bypass physical button mappings but preserve any physical drag.
    // Timed releases use a separate worker, so cursor diagnostics cannot turn a click into a long press.
    void performAction(long inputEpoch, long inputSequence, String action) throws Exception {
        synchronized (lock) {
            if (!active || inputEpoch != epoch || inputSequence <= sequence) return;
            int button = 0, wheel = 0, pan = 0;
            long hold = 35;
            boolean twice = false;
            switch (action) {
            case "cancel":
                sequence = inputSequence; cancelMappedLocked(); writeStateLocked(0, 0); return;
            case "click": button = 1; break;
            case "doubleClick": button = 1; twice = true; break;
            case "longClick": button = 1; hold = ViewConfiguration.getLongPressTimeout() + 100L; break;
            case "rightClick": button = 2; break;
            case "middleClick": button = 4; break;
            case "scrollUp": wheel = 1; break;
            case "scrollDown": wheel = -1; break;
            case "scrollLeft": pan = -1; break;
            case "scrollRight": pan = 1; break;
            default: throw new IllegalArgumentException("Unsupported pointer action: " + action);
            }
            sequence = inputSequence;
            if (wheel != 0 || pan != 0) { writeStateLocked(wheel, pan); return; }
            if (mappedButtons != 0 || (physicalButtons & button) != 0) return;
            long token = ++actionGeneration;
            mappedButtons = button;
            try {
                writeStateLocked(0, 0);
                scheduleStep(inputEpoch, token, action, button, false, hold);
                if (twice) {
                    scheduleStep(inputEpoch, token, action, button, true, 140);
                    scheduleStep(inputEpoch, token, action, button, false, 175);
                }
            } catch (Exception error) {
                cancelMappedLocked();
                try { writeStateLocked(0, 0); } catch (Exception ignored) { }
                throw error;
            }
        }
    }

    private void scheduleStep(long visit, long token, String action, int button, boolean down, long delay) {
        actionQueue.schedule(() -> {
            Exception failure = null;
            synchronized (lock) {
                if (closed || !active || visit != epoch || token != actionGeneration) return;
                // A physical press that started between double-click pulses owns its own release.
                if (down && (physicalButtons & button) != 0) { cancelMappedLocked(); return; }
                mappedButtons = down ? button : 0;
                try { writeStateLocked(0, 0); }
                catch (Exception error) {
                    cancelMappedLocked(); failure = error;
                    try { writeStateLocked(0, 0); } catch (Exception ignored) { }
                }
            }
            if (failure != null) actionFailure.report(visit, action, failure);
        }, delay, TimeUnit.MILLISECONDS);
    }

    private void writeStateLocked(int wheel, int pan) throws Exception {
        mouse.send(geometry.report(x, y, physicalButtons | mappedButtons, wheel, pan));
    }

    private void cancelMappedLocked() { actionGeneration++; mappedButtons = 0; }

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
            cancelMappedLocked(); physicalButtons = 0;
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
        actionQueue.shutdownNow();
        visibility.close();
    }
}
