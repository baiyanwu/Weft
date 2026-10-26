package io.baiyanwu.weft;

import android.os.IBinder;
import android.os.ParcelFileDescriptor;
import android.os.SystemClock;
import android.system.Os;

import java.io.BufferedReader;
import java.io.InputStreamReader;
import java.nio.charset.StandardCharsets;
import java.util.Locale;
import java.util.concurrent.CountDownLatch;
import java.util.concurrent.TimeUnit;

/** Runs as the already-authorized adb shell user. No APK, root, or network listener. */
public final class BridgeAgent {
    private static final String END = "__WEFT_DUMP_END__";

    private ReusableMouse reusableMouse;
    private final MouseButtonMapper buttonMapper = new MouseButtonMapper();
    private volatile DeviceKeyActions keyActions;
    private volatile int mouseId = -1;
    private volatile boolean running = true;
    private volatile boolean active;
    private volatile boolean aligning;
    private volatile long lastCommand = SystemClock.elapsedRealtime();
    private volatile int buttons;
    private volatile long controlEpoch;
    private volatile CursorParser dumpParser;
    private volatile CountDownLatch dumpLatch;
    private final Object observerSignal = new Object();
    private IBinder input;
    private ParcelFileDescriptor dumpRead;
    private ParcelFileDescriptor dumpWrite;

    public static void main(String[] args) {
        Locale.setDefault(Locale.US);
        BridgeAgent agent = new BridgeAgent();
        Runtime.getRuntime().addShutdownHook(new Thread(agent::closeMouse));
        try { agent.run(); }
        catch (Throwable e) { emit("{\"type\":\"error\",\"message\":\"" + escape(e.toString()) + "\"}"); }
        finally { agent.running = false; agent.closeMouse(); }
        System.exit(0);
    }

    private void run() throws Exception {
        input = (IBinder) Class.forName("android.os.ServiceManager")
            .getMethod("getService", String.class).invoke(null, "input");
        if (input == null) throw new IllegalStateException("Input service unavailable");
        ParcelFileDescriptor[] pipe = ParcelFileDescriptor.createPipe();
        dumpRead = pipe[0]; dumpWrite = pipe[1];
        Thread reader = new Thread(this::readDumps, "weft-cursor-reader");
        reader.setDaemon(true); reader.start();
        Thread observer = new Thread(this::observe, "weft-observer");
        observer.setDaemon(true); observer.start();
        Thread watchdog = new Thread(() -> {
            while (running) {
                if (SystemClock.elapsedRealtime() - lastCommand > 3500) {
                    closeMouse(); System.exit(0);
                }
                SystemClock.sleep(300);
            }
        }, "weft-watchdog");
        watchdog.setDaemon(true); watchdog.start();
        ScreenMetrics metrics = ScreenMetrics.read();
        aligning = true;
        try {
            reusableMouse = new ReusableMouse(input, this::sample, this::pointerActionFailed);
            reusableMouse.prepare(metrics.display);
            mouseId = reusableMouse.deviceId();
        } finally { aligning = false; }
        emit("{\"type\":\"ready\",\"protocol\":4,\"pointerMode\":\"absolute\"," + metrics.fields() + ",\"reusable\":true,\"buttonMapping\":true}");
        BufferedReader commands = new BufferedReader(new InputStreamReader(System.in, StandardCharsets.UTF_8));
        String line;
        while (running && (line = commands.readLine()) != null) {
            lastCommand = SystemClock.elapsedRealtime();
            if (line.length() > 256) throw new IllegalArgumentException("Command too long");
            String[] parts = line.trim().split(" +");
            switch (parts[0]) {
            case "ping":
                if (!active) {
                    aligning = true;
                    try {
                        reusableMouse.prepare(displayInfo());
                        mouseId = reusableMouse.deviceId();
                    } finally { aligning = false; }
                }
                break;
            case "map-buttons":
                if (parts.length != 8 || !(parts[2].equals("0") || parts[2].equals("1")))
                    throw new IllegalArgumentException("map-buttons arguments");
                buttonMapper.configure(Long.parseLong(parts[1]), parts[2].equals("1"),
                    java.util.Arrays.copyOfRange(parts, 3, 8));
                break;
            case "enter-abs":
                if (parts.length != 8 || Long.parseLong(parts[2]) != 0)
                    throw new IllegalArgumentException("enter-abs arguments");
                long requestedEpoch = Long.parseLong(parts[1]);
                if (requestedEpoch > controlEpoch) enterAbsolute(requestedEpoch,
                    Integer.parseInt(parts[3]), Integer.parseInt(parts[4]), new int[] {
                        Integer.parseInt(parts[5]), Integer.parseInt(parts[6]), Integer.parseInt(parts[7])});
                break;
            case "pointer-action":
                try {
                    if (parts.length != 4) throw new IllegalArgumentException("pointer-action arguments");
                    reusableMouse.performAction(Long.parseLong(parts[1]), Long.parseLong(parts[2]), parts[3]);
                } catch (Exception error) {
                    pointerActionFailed(controlEpoch, parts.length > 3 ? parts[3] : "unknown", error);
                }
                break;
            case "pointer":
                if (parts.length != 8) throw new IllegalArgumentException("pointer arguments");
                long inputEpoch = Long.parseLong(parts[1]);
                if (active && inputEpoch == controlEpoch) {
                    long inputSequence = Long.parseLong(parts[2]);
                    MouseButtonMapper.Result mapped = buttonMapper.pointer(inputEpoch, inputSequence, Integer.parseInt(parts[5]));
                    if (mapped == null) break;
                    buttons = mapped.buttons;
                    reusableMouse.send(inputEpoch, inputSequence, Integer.parseInt(parts[3]),
                        Integer.parseInt(parts[4]), buttons, Integer.parseInt(parts[6]), Integer.parseInt(parts[7]));
                    for (int key : mapped.keys) {
                        if (keyActions == null) keyActions = new DeviceKeyActions(input);
                        keyActions.press(key);
                        emit("{\"type\":\"mapped\",\"epoch\":" + inputEpoch + ",\"sequence\":" + inputSequence + ",\"keyCode\":" + key + "}");
                    }
                }
                break;
            case "release":
                if (parts.length > 2) throw new IllegalArgumentException("release arguments");
                if (parts.length == 1 || Long.parseLong(parts[1]) == controlEpoch) {
                    active = false; buttons = 0;
                    buttonMapper.release(controlEpoch);
                    if (keyActions != null) keyActions.release();
                    reusableMouse.release();
                    emit("{\"type\":\"released\",\"epoch\":" + controlEpoch + "}");
                }
                break;
            case "probe":
                if (parts.length != 2) throw new IllegalArgumentException("probe arguments");
                if (active && Long.parseLong(parts[1]) == controlEpoch) {
                    Snapshot snap = sample(mouseId);
                    emit("{\"epoch\":" + controlEpoch + "," + snap.json().substring(1));
                }
                break;
            case "quit": running = false; break;
            default: throw new IllegalArgumentException("Unknown command");
            }
        }
    }

    private void enterAbsolute(long requestedEpoch, int x, int y, int[] display) {
        active = false; aligning = true; buttons = 0; controlEpoch = requestedEpoch;
        long started = SystemClock.elapsedRealtime();
        try {
            reusableMouse.enter(controlEpoch, x, y, display);
            buttonMapper.enter(controlEpoch);
            mouseId = reusableMouse.deviceId(); active = true;
            emit("{\"type\":\"entered\",\"epoch\":" + controlEpoch + ",\"x\":" + x + ",\"y\":" + y
                + ",\"width\":" + display[0] + ",\"height\":" + display[1] + ",\"rotation\":" + display[2]
                + ",\"reused\":true,\"pointerMode\":\"absolute\",\"mouseId\":" + mouseId
                + ",\"generation\":" + reusableMouse.generation()
                + ",\"entryMs\":" + (SystemClock.elapsedRealtime() - started) + "}");
        } catch (Exception error) {
            try { reusableMouse.release(); } catch (Exception ignored) { }
            emit("{\"type\":\"entryFailed\",\"epoch\":" + controlEpoch
                + ",\"message\":\"设备鼠标交接失败，已保留 Mac 控制\",\"detail\":\"" + escape(error.toString()) + "\"}");
        } finally {
            aligning = false;
            synchronized (observerSignal) { observerSignal.notifyAll(); }
        }
    }

    private void observe() {
        long lastHeartbeat = 0;
        while (running) {
            long now = SystemClock.elapsedRealtime();
            try {
                if (reusableMouse != null && !aligning) {
                    if (active && reusableMouse.needsVisibilityConfirmation()) reusableMouse.confirmVisibility();
                    else if (!active) reusableMouse.refreshHidden();
                }
                if (now - lastHeartbeat > 450) {
                    emit("{\"type\":\"heartbeat\"," + ScreenMetrics.read().fields() + "}");
                    lastHeartbeat = now;
                }
                synchronized (observerSignal) {
                    observerSignal.wait(reusableMouse != null && reusableMouse.needsVisibilityConfirmation() ? 4 : 120);
                }
            } catch (Throwable e) {
                if (running) emit("{\"type\":\"error\",\"message\":\"" + escape(e.toString()) + "\"}");
                active = false; closeMouse();
            }
        }
    }

    private synchronized Snapshot sample(int id) throws Exception {
        if (id < 0) return null;
        CursorParser parser = new CursorParser(id);
        CountDownLatch latch = new CountDownLatch(1);
        dumpParser = parser; dumpLatch = latch;
        long start = SystemClock.elapsedRealtime();
        input.dump(dumpWrite.getFileDescriptor(), new String[0]);
        byte[] end = (END + "\n").getBytes(StandardCharsets.UTF_8);
        Os.write(dumpWrite.getFileDescriptor(), end, 0, end.length);
        if (!latch.await(600, TimeUnit.MILLISECONDS)) throw new IllegalStateException("Cursor read timeout");
        int[] d = displayInfo();
        double[] point = parser.logical(d[0], d[1], d[2]);
        return new Snapshot(parser.valid(), point[0], point[1], d[0], d[1], d[2], SystemClock.elapsedRealtime() - start);
    }

    private void readDumps() {
        try (BufferedReader reader = new BufferedReader(new InputStreamReader(
                new ParcelFileDescriptor.AutoCloseInputStream(dumpRead), StandardCharsets.UTF_8), 32768)) {
            String line;
            while (running && (line = reader.readLine()) != null) {
                if (line.equals(END)) {
                    CountDownLatch latch = dumpLatch;
                    if (latch != null) latch.countDown();
                } else {
                    CursorParser parser = dumpParser;
                    if (parser != null) parser.accept(line);
                }
            }
        } catch (Exception ignored) { }
    }

    private synchronized void closeMouse() {
        active = false; mouseId = -1; buttons = 0;
        buttonMapper.release(controlEpoch);
        if (keyActions != null) keyActions.release();
        if (reusableMouse != null) reusableMouse.close();
    }

    static int[] displayInfo() throws Exception {
        Object info = displayInfoObject();
        return new int[] {
            info.getClass().getField("logicalWidth").getInt(info),
            info.getClass().getField("logicalHeight").getInt(info),
            info.getClass().getField("rotation").getInt(info)
        };
    }

    static Object displayInfoObject() throws Exception {
        Class<?> type = Class.forName("android.hardware.display.DisplayManagerGlobal");
        Object manager = type.getMethod("getInstance").invoke(null);
        Object info = type.getMethod("getDisplayInfo", int.class).invoke(manager, 0);
        if (info == null) throw new IllegalStateException("Display unavailable");
        return info;
    }

    private void pointerActionFailed(long epoch, String action, Exception error) {
        emit("{\"type\":\"pointer-action-error\",\"epoch\":" + epoch + ",\"action\":\"" + escape(action)
            + "\",\"detail\":\"" + escape(error.toString()) + "\"}");
    }

    private static synchronized void emit(String json) { System.out.println(json); System.out.flush(); }
    private static String escape(String s) { return s.replace("\\", "\\\\").replace("\"", "\\\"").replace("\n", " ").replace("\r", " "); }
    private static byte[] bytes(int... values) {
        byte[] result = new byte[values.length];
        for (int i = 0; i < values.length; i++) result[i] = (byte) values[i];
        return result;
    }

    static final class Snapshot {
        final boolean valid;
        final double x, y;
        final int width, height, rotation;
        final long dumpMs;
        Snapshot(boolean valid, double x, double y, int width, int height, int rotation, long dumpMs) {
            this.valid = valid; this.x = x; this.y = y; this.width = width;
            this.height = height; this.rotation = rotation; this.dumpMs = dumpMs;
        }
        String json() {
            return "{\"type\":\"cursor\",\"valid\":" + valid + ",\"x\":" + (valid ? x : 0)
                + ",\"y\":" + (valid ? y : 0) + ",\"width\":" + width + ",\"height\":" + height
                + ",\"rotation\":" + rotation + ",\"dumpMs\":" + dumpMs + "}";
        }
    }
}
