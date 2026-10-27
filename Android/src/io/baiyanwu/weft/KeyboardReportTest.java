package io.baiyanwu.weft;

public final class KeyboardReportTest {
    public static void main(String[] args) {
        byte[] report = KeyboardReport.decode(1, "0405060708090a0b0c0d");
        check(report.length == 29 && report[0] == 1, "modifier and NKRO report size");
        for (int usage = 4; usage <= 13; usage++)
            check((report[1 + usage / 8] & (1 << (usage % 8))) != 0, "more than six held keys");
        byte[] release = KeyboardReport.decode(0, "-");
        for (byte value : release) check(value == 0, "complete key release");
        reject(-1, "-"); reject(256, "-"); reject(0, "e0"); reject(0, "0"); reject(0, "zz");
        check(KeyboardReport.actionCode("mute") == 164, "volume mute action");
        int inputBits = 0, outputBits = 0, size = 0, count = 0;
        byte[] descriptor = KeyboardReport.descriptor();
        for (int offset = 0; offset < descriptor.length;) {
            int prefix = descriptor[offset++] & 255, length = prefix & 3;
            if (length == 3) length = 4;
            int value = 0;
            for (int i = 0; i < length; i++) value |= (descriptor[offset++] & 255) << (8 * i);
            if (prefix == 0x75) size = value;
            else if (prefix == 0x95) count = value;
            else if (prefix == 0x81) inputBits += size * count;
            else if (prefix == 0x91) outputBits += size * count;
        }
        check(inputBits == KeyboardReport.SIZE * 8 && outputBits == 8, "descriptor matches input and LED reports");
        System.out.println("Keyboard report checks passed");
    }
    private static void reject(int modifiers, String keys) {
        try { KeyboardReport.decode(modifiers, keys); throw new AssertionError("accepted invalid report"); }
        catch (IllegalArgumentException expected) { }
    }
    private static void check(boolean condition, String message) {
        if (!condition) throw new AssertionError(message);
    }
}
