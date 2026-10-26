package io.baiyanwu.weft;

import android.os.SystemClock;
import android.system.Os;
import android.system.OsConstants;
import android.system.StructPollfd;
import android.view.InputDevice;

import java.io.FileDescriptor;
import java.nio.ByteBuffer;
import java.nio.ByteOrder;
import java.nio.charset.StandardCharsets;

/** One UHID lifetime; keyboard identity stays separate from other input devices. */
final class UhidDevice implements AutoCloseable {
    private final String name;
    private final String role;
    private final String physicalLocation;
    private final String uniqueId;
    private final java.util.Set<Integer> existingDevices;
    private final KeyboardRegistry registry;
    private FileDescriptor fd;
    private volatile boolean closed;
    private volatile boolean kernelStarted;
    private volatile boolean kernelOpened;
    private volatile String readerFailure;
    private volatile byte[] latestReport;
    private volatile int outputState = -1;
    private final StringBuilder eventTypes = new StringBuilder();

    UhidDevice(String role, byte[] descriptor) throws Exception {
        this(role, descriptor, null);
    }

    UhidDevice(String role, byte[] descriptor, byte[] initialReport) throws Exception {
        this.role = role;
        latestReport = initialReport == null ? null : initialReport.clone();
        registry = initialReport == null ? null : new KeyboardRegistry();
        existingDevices = initialReport == null ? null : new java.util.HashSet<Integer>();
        if (existingDevices != null) for (int id : registry.ids()) existingDevices.add(id);
        // Keep the keyboard layout identity stable. InputReader merges devices by
        // bus/vendor/product/version/uniq/phys, ignoring their names and processes.
        // A location per lifetime also prevents a retry merging with a retiring keyboard.
        name = initialReport == null ? "weft " + role + " " + android.os.Process.myPid() + " " + System.nanoTime() : "weft " + role;
        physicalLocation = initialReport == null ? "" : "weft/keyboard/" + android.os.Process.myPid() + "/" + System.nanoTime();
        uniqueId = initialReport == null ? "" : "weft.keyboard.v1";
        fd = Os.open("/dev/uhid", OsConstants.O_RDWR, 0);
        try {
            ByteBuffer create = ByteBuffer.allocate(280 + descriptor.length).order(ByteOrder.LITTLE_ENDIAN);
            create.putInt(11).put(name.getBytes(StandardCharsets.UTF_8)); // UHID_CREATE2
            create.position(132); // phys[64]; leave a terminating zero in the field.
            create.put(physicalLocation.getBytes(StandardCharsets.UTF_8));
            create.position(196); // uniq[64]; stable identity for Android keyboard layouts.
            create.put(uniqueId.getBytes(StandardCharsets.UTF_8));
            create.position(260);
            create.putShort((short) descriptor.length).putShort((short) 6); // BUS_VIRTUAL
            create.putInt(0).putInt(0).putInt(0).putInt(0).put(descriptor);
            Os.write(fd, create.array(), 0, create.position());
            // Some kernels request an initial report before they expose an
            // input device. Always service that channel while registration runs.
            Thread reader = new Thread(this::readEvents, "weft-uhid-" + role.replace(' ', '-'));
            reader.setDaemon(true);
            reader.start();
        } catch (Exception error) {
            close();
            throw error;
        }
    }

    InputDevice awaitRegistration(long deadline) throws Exception {
        String candidates = "";
        while (SystemClock.elapsedRealtime() < deadline) {
            synchronized (this) { requireOpen(); }
            StringBuilder seen = new StringBuilder();
            for (int id : registry == null ? InputDevice.getDeviceIds() : registry.ids()) {
                if (existingDevices != null && existingDevices.contains(id)) continue;
                InputDevice device = registry == null ? InputDevice.getDevice(id) : registry.device(id);
                if (device != null && seen.length() < 400) seen.append(id).append(':').append(device.getName()).append(';');
                if (device != null && name.equals(device.getName())) {
                    System.err.println("Virtual pointer registered: " + role + ", id=" + id + ", " + eventSummary());
                    return device;
                }
            }
            candidates = seen.toString();
            SystemClock.sleep(4);
        }
        // UHID_OPEN describes a driver's users, not Android registration.
        // InputDevice registration plus the caller's position feedback are the
        // readiness checks; a missing OPEN notification alone is not a failure.
        throw new IllegalStateException("Virtual input registration timed out: " + role + ", " + eventSummary() + ", candidates=[" + candidates + "]");
    }

    private void readEvents() {
        byte[] event = new byte[4380];
        try {
            StructPollfd ready = new StructPollfd();
            synchronized (this) { ready.fd = requireOpen(); }
            ready.events = (short) OsConstants.POLLIN;
            while (!closed) {
                if (Os.poll(new StructPollfd[] {ready}, 50) == 0) continue;
                if (closed) return;
                if ((ready.revents & OsConstants.POLLIN) == 0)
                    throw new IllegalStateException("UHID event stream unavailable");
                int count = Os.read(ready.fd, event, 0, event.length);
                if (count < 4) throw new IllegalStateException("UHID event stream closed");
                ByteBuffer message = ByteBuffer.wrap(event, 0, count).order(ByteOrder.LITTLE_ENDIAN);
                int type = message.getInt();
                synchronized (this) {
                    if (eventTypes.length() < 120) eventTypes.append(type).append(' ');
                }
                switch (type) {
                case 2: kernelStarted = true; break; // UHID_START
                case 3: throw new IllegalStateException("Kernel stopped the virtual pointer"); // UHID_STOP
                case 4: kernelOpened = true; break; // UHID_OPEN
                case 5: kernelOpened = false; break; // UHID_CLOSE
                case 6: // UHID_OUTPUT: data[4096], size, report type.
                    if (latestReport != null && count >= 4103 && (event[4102] & 255) == 1
                            && (message.getShort(4100) & 65535) > 0) outputState = event[4] & 255;
                    break;
                case 9: // UHID_GET_REPORT
                case 13: // UHID_SET_REPORT
                    if (count < 10) throw new IllegalStateException("Incomplete UHID report request");
                    int request = message.getInt();
                    int number = message.get() & 255, reportType = message.get() & 255;
                    byte[] payload = null;
                    int error = OsConstants.EIO;
                    if (latestReport != null && number == 0) {
                        if (type == 9 && reportType == 2) { payload = latestReport; error = 0; }
                        else if (type == 9 && reportType == 1) { payload = new byte[] {(byte) Math.max(0, outputState)}; error = 0; }
                        else if (type == 13 && reportType == 1 && count >= 13) {
                            int length = message.getShort() & 65535;
                            if (length > 0 && count >= 12 + length) { outputState = event[12] & 255; error = 0; }
                        }
                    }
                    int size = payload == null ? 0 : payload.length;
                    ByteBuffer reply = ByteBuffer.allocate(type == 9 ? 12 + size : 10).order(ByteOrder.LITTLE_ENDIAN);
                    reply.putInt(type == 9 ? 10 : 14).putInt(request).putShort((short) error);
                    if (type == 9) { reply.putShort((short) size); if (payload != null) reply.put(payload); }
                    writeEvent(reply.array());
                    break;
                default: break;
                }
            }
        } catch (Exception error) {
            if (!closed) {
                readerFailure = error.toString();
                System.err.println("Virtual pointer reader failed: " + role + ", " + eventSummary() + ", " + error);
            }
        }
    }

    private synchronized String eventSummary() {
        return "started=" + kernelStarted + ", opened=" + kernelOpened + ", events=[" + eventTypes.toString().trim()
            + "], phys=" + physicalLocation + ", uniq=" + uniqueId;
    }

    private synchronized void writeEvent(byte[] event) throws Exception {
        Os.write(requireOpen(), event, 0, event.length);
    }

    synchronized void send(byte[] report) throws Exception {
        ByteBuffer packet = ByteBuffer.allocate(6 + report.length).order(ByteOrder.LITTLE_ENDIAN);
        packet.putInt(12).putShort((short) report.length).put(report); // UHID_INPUT2
        Os.write(requireOpen(), packet.array(), 0, packet.position());
        if (latestReport != null) latestReport = report.clone();
    }

    int outputState() { return outputState; }

    private FileDescriptor requireOpen() {
        if (fd == null) throw new IllegalStateException("Virtual pointer is closed");
        if (readerFailure != null) throw new IllegalStateException("Virtual pointer transport failed: " + role + ", " + readerFailure);
        return fd;
    }

    @Override public synchronized void close() {
        closed = true;
        if (fd == null) return;
        try { Os.close(fd); } catch (Exception ignored) { }
        fd = null;
    }
}
