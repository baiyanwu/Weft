package io.baiyanwu.weft;

import android.os.IBinder;
import android.os.SystemClock;
import java.io.BufferedReader;
import java.io.InputStreamReader;
import java.nio.charset.StandardCharsets;

/** A separate adb shell process: keyboard failures cannot stop or block the mouse agent. */
public final class KeyboardAgent {
    private volatile boolean running = true;
    private volatile long lastCommand = SystemClock.elapsedRealtime();
    private volatile long epoch;
    private volatile DeviceKeyboard keyboard;
    private volatile DeviceKeyActions actions;
    private DevicePanelActions panels;
    private IBinder input;

    public static void main(String[] args) {
        KeyboardAgent agent = new KeyboardAgent();
        Runtime.getRuntime().addShutdownHook(new Thread(agent::release));
        try { agent.run(); }
        catch (Throwable error) { agent.error("键盘连接失败，鼠标可继续使用", error); }
        finally { agent.running = false; agent.release(); }
        System.exit(0);
    }

    private void run() throws Exception {
        input = (IBinder) Class.forName("android.os.ServiceManager")
            .getMethod("getService", String.class).invoke(null, "input");
        if (input == null) throw new IllegalStateException("Input service unavailable");
        Thread health = new Thread(() -> {
            while (running) {
                if (SystemClock.elapsedRealtime() - lastCommand > 3500) { release(); System.exit(0); }
                emit("{\"type\":\"heartbeat\"}");
                SystemClock.sleep(450);
            }
        }, "weft-keyboard-health");
        health.setDaemon(true); health.start();
        emit("{\"type\":\"ready\",\"protocol\":1}");
        BufferedReader commands = new BufferedReader(new InputStreamReader(System.in, StandardCharsets.UTF_8));
        String line;
        while (running && (line = commands.readLine()) != null) {
            lastCommand = SystemClock.elapsedRealtime();
            if (line.length() > 1024) throw new IllegalArgumentException("Keyboard command too long");
            String[] parts = line.trim().split(" +");
            switch (parts[0]) {
            case "ping": break;
            case "enter":
                if (parts.length != 2) throw new IllegalArgumentException("Keyboard enter arguments");
                long requested = Long.parseLong(parts[1]);
                if (requested <= epoch) break;
                release(); epoch = requested;
                try {
                    keyboard = new DeviceKeyboard();
                    emit("{\"type\":\"entered\",\"epoch\":" + epoch + "}");
                } catch (Exception error) {
                    release(); error("键盘初始化失败，鼠标可继续使用", error);
                }
                break;
            case "keyboard":
                if (parts.length != 7) throw new IllegalArgumentException("Keyboard frame arguments");
                if (Long.parseLong(parts[1]) != epoch || keyboard == null) break;
                try {
                    if (keyboard.send(Long.parseLong(parts[2]), Integer.parseInt(parts[3]), Integer.parseInt(parts[4]), parts[6]))
                        performAction(parts[5]);
                } catch (Exception error) {
                    release(); error("键盘输入失败，鼠标可继续使用", error);
                }
                break;
            case "release":
                if (parts.length == 1 || (parts.length == 2 && Long.parseLong(parts[1]) == epoch)) release();
                break;
            case "quit": running = false; break;
            default: throw new IllegalArgumentException("Unknown keyboard command");
            }
        }
    }

    private void performAction(String name) {
        try {
            int action = KeyboardReport.actionCode(name);
            if (action < 0) {
                if (panels == null) panels = new DevicePanelActions();
                panels.perform(action);
            } else if (action != 0) {
                if (actions == null) actions = new DeviceKeyActions(input);
                actions.press(action);
            }
        } catch (Exception error) {
            // An unsupported OEM/system operation must not tear down keyboard or pointer input.
            if (actions != null) actions.release();
            Throwable cause = error.getCause() == null ? error : error.getCause();
            emit("{\"type\":\"action-error\",\"epoch\":" + epoch + ",\"action\":\"" + escape(name)
                + "\",\"detail\":\"" + escape(cause.toString()) + "\"}");
        }
    }

    private synchronized void release() {
        DeviceKeyboard current = keyboard; keyboard = null;
        if (current != null) current.close();
        if (actions != null) actions.release();
    }
    private void error(String message, Throwable error) {
        emit("{\"type\":\"keyboard-error\",\"epoch\":" + epoch + ",\"message\":\"" + message
            + "\",\"detail\":\"" + escape(error.toString()) + "\"}");
    }
    private static synchronized void emit(String json) { System.out.println(json); System.out.flush(); }
    private static String escape(String value) {
        return value.replace("\\", "\\\\").replace("\"", "\\\"").replace("\n", " ").replace("\r", " ");
    }
}
