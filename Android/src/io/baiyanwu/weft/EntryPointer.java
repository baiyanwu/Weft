package io.baiyanwu.weft;

import java.nio.ByteBuffer;
import java.nio.ByteOrder;
import java.util.Arrays;

/** Absolute, hover-only entry in the current logical display orientation. */
final class EntryPointer {
    final int width, height, rotation, x, y, outwardX, outwardY;

    EntryPointer(int[] display, String side, double fraction) {
        this(display, side, fraction, false);
    }

    static EntryPointer atPixel(int[] display, String side, double pixel) {
        int length = side.equals("above") || side.equals("below") ? display[0] : display[1];
        if (!Double.isFinite(pixel) || pixel < 0 || pixel > length - 1)
            throw new IllegalArgumentException("Entry pixel outside display");
        return new EntryPointer(display, side, pixel, true);
    }

    private EntryPointer(int[] display, String side, double value, boolean exactPixel) {
        width = display[0]; height = display[1]; rotation = display[2];
        if (width < 2 || height < 2 || width > 65536 || height > 65536 || rotation < 0 || rotation > 3)
            throw new IllegalArgumentException("Unsupported display geometry");
        if (!Double.isFinite(value)) throw new IllegalArgumentException("Invalid coordinate");
        double f = Math.min(1, Math.max(0, value));
        int tx = exactPixel ? (int) Math.round(value) : alongEdge(width, f);
        int ty = exactPixel ? (int) Math.round(value) : alongEdge(height, f);
        int dx = 0, dy = 0;
        switch (side) {
        case "below": ty = 0; dy = -1; break;
        case "above": ty = height - 1; dy = 1; break;
        case "left": tx = width - 1; dx = 1; break;
        case "right": tx = 0; dx = -1; break;
        default: throw new IllegalArgumentException("Unknown direction");
        }
        x = tx; y = ty; outwardX = dx; outwardY = dy;
    }

    private static int alongEdge(int length, double fraction) {
        double margin = Math.min(24, (length - 1) / 2.0);
        return (int) Math.round(margin + fraction * (length - 1 - 2 * margin));
    }

    boolean matches(int[] display) {
        return width == display[0] && height == display[1] && rotation == display[2];
    }

    byte[] descriptor() {
        ByteBuffer report = ByteBuffer.allocate(128).order(ByteOrder.LITTLE_ENDIAN);
        // A pointer digitizer, not a direct touchscreen. The puck reports tool
        // MOUSE and absolute X/Y. No mouse-button usages are present, so the
        // in-range/tip bits produce hover, never a click (Android absolute mice).
        report.put(bytes(
            0x05,0x0D, 0x09,0x01, 0xA1,0x01, // Digitizer application
            0x09,0x21, 0xA1,0x00, 0x85,0x01, // Puck, report 1
            0x15,0x00, 0x25,0x01, 0x75,0x01, 0x95,0x02,
            0x09,0x32, 0x09,0x42, 0x81,0x02, // In Range, Tip Switch
            0x75,0x06, 0x95,0x01, 0x81,0x03,
            0x05,0x01, 0x09,0x30, 0x15,0x00, 0x26));
        report.putShort((short) (width - 1));
        report.put(bytes(0x75,0x10, 0x95,0x01, 0x81,0x02, 0x09,0x31, 0x26));
        report.putShort((short) (height - 1));
        report.put(bytes(0x81,0x02, 0xC0));
        // Advertise an inactive pen in the SAME application/input device.
        // Android then exposes SOURCE_MOUSE | SOURCE_STYLUS and waits for the
        // first tool event to show a cursor, instead of showing a new mouse at
        // its default center. We only send puck report 1: its full X/Y reaches
        // PointerChoreographer before unfade. Report 2 is never sent.
        report.put(bytes(
            0x05,0x0D, 0x09,0x20, 0xA1,0x00, 0x85,0x02,
            0x09,0x32, 0x15,0x00, 0x25,0x01, 0x75,0x01, 0x95,0x01, 0x81,0x02,
            0x75,0x07, 0x81,0x03, 0xC0,0xC0));
        return Arrays.copyOf(report.array(), report.position());
    }

    byte[] hoverReport() {
        // DisplayInfo already supplies rotated logical width/height. POINTER
        // digitizers are not orientation-aware; Android handles the conversion
        // to its unrotated input space. Rotating here again breaks landscape.
        return ByteBuffer.allocate(6).order(ByteOrder.LITTLE_ENDIAN)
            .put((byte) 1).put((byte) 3).putShort((short) x).putShort((short) y).array();
    }

    byte[] liftReport() {
        // Keep X/Y on lift: Android's final hover-exit carries this position.
        return ByteBuffer.allocate(6).order(ByteOrder.LITTLE_ENDIAN)
            .put((byte) 1).put((byte) 0).putShort((short) x).putShort((short) y).array();
    }

    private static byte[] bytes(int... values) {
        byte[] result = new byte[values.length];
        for (int i = 0; i < values.length; i++) result[i] = (byte) values[i];
        return result;
    }
}
