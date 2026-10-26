package io.baiyanwu.weft;

import android.os.SystemClock;
import java.util.Arrays;

/** A keyboard exists only during a keyboard-enabled control visit. */
final class DeviceKeyboard implements AutoCloseable {
    private final UhidDevice device;
    private byte[] lastReport = new byte[KeyboardReport.SIZE];
    private long lastSequence;
    private boolean capsKnown;
    private boolean requestedCaps;
    private boolean closed;

    DeviceKeyboard() throws Exception {
        device = new UhidDevice("Keyboard", KeyboardReport.descriptor(), lastReport);
        try { device.awaitRegistration(SystemClock.elapsedRealtime() + 2500); }
        catch (Exception error) { device.close(); throw error; }
    }

    synchronized boolean send(long sequence, int modifiers, int caps, String keys) throws Exception {
        if (closed || sequence <= lastSequence) return false;
        if (caps != 0 && caps != 1) throw new IllegalArgumentException("Keyboard Caps Lock");
        byte[] report = KeyboardReport.decode(modifiers, keys);
        boolean desired = caps != 0;
        if (!capsKnown || desired != requestedCaps) {
            int leds = device.outputState();
            boolean actual = leds >= 0 ? (leds & 2) != 0 : capsKnown && requestedCaps;
            if (actual != desired) {
                byte[] press = lastReport.clone();
                press[1 + 0x39 / 8] |= (byte) (1 << (0x39 % 8));
                device.send(press); device.send(lastReport);
            }
            requestedCaps = desired; capsKnown = true;
        }
        if (!Arrays.equals(lastReport, report)) { device.send(report); lastReport = report; }
        lastSequence = sequence;
        return true;
    }

    @Override public synchronized void close() {
        if (closed) return;
        closed = true;
        try { device.send(new byte[KeyboardReport.SIZE]); } catch (Exception ignored) { }
        device.close();
    }
}
