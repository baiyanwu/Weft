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

/** One UHID lifetime; names distinguish it from devices still being removed. */
final class UhidDevice implements AutoCloseable {
    private final String name;
    private final String role;
    private FileDescriptor fd;
    private volatile boolean closed;
    private volatile boolean kernelStarted;
    private volatile boolean kernelOpened;
    private volatile String readerFailure;
    private final StringBuilder eventTypes = new StringBuilder();

    UhidDevice(String role, byte[] descriptor) throws Exception {
        this.role = role;
        name = "weft " + role + " " + android.os.Process.myPid() + " " + System.nanoTime();
        fd = Os.open("/dev/uhid", OsConstants.O_RDWR, 0);
        try {
            ByteBuffer create = ByteBuffer.allocate(280 + descriptor.length).order(ByteOrder.LITTLE_ENDIAN);
            create.putInt(11).put(name.getBytes(StandardCharsets.UTF_8)); // UHID_CREATE2
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
        while (SystemClock.elapsedRealtime() < deadline) {
            synchronized (this) { requireOpen(); }
            for (int id : InputDevice.getDeviceIds()) {
                InputDevice device = InputDevice.getDevice(id);
                if (device != null && name.equals(device.getName())) {
                    System.err.println("Virtual pointer registered: " + role + ", id=" + id + ", " + eventSummary());
                    return device;
                }
            }
            SystemClock.sleep(4);
        }
        // UHID_OPEN describes a driver's users, not Android registration.
        // InputDevice registration plus the caller's position feedback are the
        // readiness checks; a missing OPEN notification alone is not a failure.
        throw new IllegalStateException("Virtual pointer registration timed out: " + role + ", " + eventSummary());
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
                case 9: // UHID_GET_REPORT
                case 13: // UHID_SET_REPORT
                    if (count < 8) throw new IllegalStateException("Incomplete UHID report request");
                    // Our descriptors advertise input reports only. Reply with
                    // EIO for unsupported control reports instead of leaving
                    // the kernel synchronously blocked waiting for a response.
                    int request = message.getInt();
                    ByteBuffer reply = ByteBuffer.allocate(type == 9 ? 12 : 10).order(ByteOrder.LITTLE_ENDIAN);
                    reply.putInt(type == 9 ? 10 : 14).putInt(request).putShort((short) OsConstants.EIO);
                    if (type == 9) reply.putShort((short) 0);
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
        return "started=" + kernelStarted + ", opened=" + kernelOpened + ", events=[" + eventTypes.toString().trim() + "]";
    }

    private synchronized void writeEvent(byte[] event) throws Exception {
        Os.write(requireOpen(), event, 0, event.length);
    }

    synchronized void send(byte[] report) throws Exception {
        ByteBuffer packet = ByteBuffer.allocate(6 + report.length).order(ByteOrder.LITTLE_ENDIAN);
        packet.putInt(12).putShort((short) report.length).put(report); // UHID_INPUT2
        Os.write(requireOpen(), packet.array(), 0, packet.position());
    }

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
