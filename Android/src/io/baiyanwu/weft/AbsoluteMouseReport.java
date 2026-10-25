package io.baiyanwu.weft;

import java.nio.ByteBuffer;
import java.nio.ByteOrder;
import java.util.Arrays;

/** One puck carries absolute position, five mouse buttons and both relative wheels. */
final class AbsoluteMouseReport {
    final int width, height, rotation;

    AbsoluteMouseReport(int[] display) {
        width = display[0]; height = display[1]; rotation = display[2];
        if (width < 2 || height < 2 || width > 65536 || height > 65536 || rotation < 0 || rotation > 3)
            throw new IllegalArgumentException("Unsupported mouse geometry");
    }

    boolean matches(int[] display) {
        return width == display[0] && height == display[1] && rotation == display[2];
    }

    byte[] descriptor() {
        ByteBuffer data = ByteBuffer.allocate(180).order(ByteOrder.LITTLE_ENDIAN);
        data.put(bytes(0x05,0x0D, 0x09,0x01, 0xA1,0x01,
            // Linux 6.1 ignores a generic Digitizer application on its own.
            // A real enclosing Pointer collection makes it an input application,
            // while the inner Puck/Pen collections retain their existing mapping.
            0x05,0x01, 0x09,0x01, 0xA1,0x00, 0x05,0x0D,
            0x09,0x21, 0xA1,0x00, 0x85,0x01,
            0x15,0x00, 0x25,0x01, 0x75,0x01, 0x95,0x02,
            0x09,0x32, 0x09,0x42, 0x81,0x02,
            0x75,0x06, 0x95,0x01, 0x81,0x03,
            // Linux maps Button usages by their nearest Physical collection.
            // Puck would produce BTN_0..4 (keyboard/stylus buttons), whereas
            // Pointer produces BTN_LEFT..EXTRA in this same absolute report.
            0x05,0x01, 0x09,0x01, 0xA1,0x00,
            0x05,0x09, 0x19,0x01, 0x29,0x05, 0x15,0x00, 0x25,0x01,
            0x75,0x01, 0x95,0x05, 0x81,0x02,
            0x75,0x03, 0x95,0x01, 0x81,0x03, 0xC0,
            0x05,0x01, 0x09,0x30, 0x15,0x00, 0x26));
        data.putShort((short) (width - 1));
        data.put(bytes(0x75,0x10, 0x95,0x01, 0x81,0x02, 0x09,0x31, 0x26));
        data.putShort((short) (height - 1));
        data.put(bytes(0x81,0x02,
            0x09,0x38, 0x15,0x81, 0x25,0x7F, 0x75,0x08, 0x95,0x01, 0x81,0x06,
            0x05,0x0C, 0x0A,0x38,0x02, 0x81,0x06, 0xC0,
            // Inactive pen capability defers the registration-time default cursor.
            0x05,0x0D, 0x09,0x20, 0xA1,0x00, 0x85,0x02,
            0x09,0x32, 0x15,0x00, 0x25,0x01, 0x75,0x01, 0x95,0x01, 0x81,0x02,
            0x75,0x07, 0x81,0x03, 0xC0,0xC0,0xC0));
        return Arrays.copyOf(data.array(), data.position());
    }

    byte[] report(int x, int y, int buttons, int wheel, int pan) {
        if (x < 0 || x >= width || y < 0 || y >= height)
            throw new IllegalArgumentException("Mouse position outside display");
        return ByteBuffer.allocate(9).order(ByteOrder.LITTLE_ENDIAN)
            .put((byte) 1).put((byte) 3).put((byte) (buttons & 31))
            .putShort((short) x).putShort((short) y)
            .put((byte) Math.max(-127, Math.min(127, wheel)))
            .put((byte) Math.max(-127, Math.min(127, pan))).array();
    }

    private static byte[] bytes(int... values) {
        byte[] data = new byte[values.length];
        for (int i = 0; i < values.length; i++) data[i] = (byte) values[i];
        return data;
    }
}
