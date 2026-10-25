package io.baiyanwu.weft;

import java.nio.ByteBuffer;
import java.nio.ByteOrder;
import java.util.ArrayList;
import java.util.Arrays;
import java.util.List;

public final class AbsoluteMouseReportTest {
    public static void main(String[] args) {
        AbsoluteMouseReport mouse = new AbsoluteMouseReport(new int[] {3392, 2400, 1});
        byte[] report = mouse.report(3391, 2399, 31, -2, 3);
        ByteBuffer values = ByteBuffer.wrap(report).order(ByteOrder.LITTLE_ENDIAN);
        check(report.length == 9 && values.get() == 1 && values.get() == 3, "one native mouse report");
        check(values.get() == 31, "all five buttons preserved");
        check((values.getShort() & 65535) == 3391 && (values.getShort() & 65535) == 2399, "landscape coordinates are not rotated twice");
        check(values.get() == -2 && values.get() == 3, "independent signed vertical and horizontal wheels");
        check(mouse.report(0, 0, 0, 0, 0)[2] == 0, "release buttons without removing device");
        check(mouse.report(0, 0, 0, 1000, -1000)[7] == 127 && mouse.report(0, 0, 0, 1000, -1000)[8] == -127, "wheel range");
        try { mouse.report(3392, 0, 0, 0, 0); throw new AssertionError("outside position accepted"); }
        catch (IllegalArgumentException expected) { }
        int size = 0, count = 0, id = 0, bits = 0;
        int usagePage = 0, usage = 0, minimumUsage = 0, maximumUsage = 0;
        int collections = 0, applications = 0;
        List<int[]> collectionStack = new ArrayList<>();
        List<Integer> mouseButtonCodes = new ArrayList<>();
        boolean relativePosition = false;
        boolean legacyInputCollection = false;
        byte[] descriptor = mouse.descriptor();
        for (int i = 0; i < descriptor.length;) {
            int prefix = descriptor[i++] & 255;
            int length = prefix & 3; if (length == 3) length = 4;
            int value = 0;
            for (int j = 0; j < length; j++) value |= (descriptor[i++] & 255) << (j * 8);
            if (prefix == 0x05) usagePage = value;
            if (prefix == 0x09) usage = value;
            if (prefix == 0x19) minimumUsage = value;
            if (prefix == 0x29) maximumUsage = value;
            if (prefix == 0xa1) {
                collections++;
                if (value == 1) applications++;
                int fullUsage = (usagePage << 16) | usage;
                collectionStack.add(new int[] {value, fullUsage});
                if ((value == 0 || value == 1)
                        && ((fullUsage >= 0x10000 && fullUsage <= 0x10008)
                            || (fullUsage >= 0xd0002 && fullUsage <= 0xd0006)))
                    legacyInputCollection = true;
            }
            if (prefix == 0xc0) {
                collections--;
                collectionStack.remove(collectionStack.size() - 1);
            }
            if (prefix == 0x75) size = value;
            if (prefix == 0x95) count = value;
            if (prefix == 0x85) id = value;
            if ((prefix & 0xfc) == 0x80 && id == 1) {
                bits += size * count;
                if ((value & 1) == 0 && usagePage == 9) {
                    // Match Linux hidinput_configure_usage: application first,
                    // then the innermost Physical collection for button usages.
                    int application = 0, physical = 0;
                    for (int[] collection : collectionStack) {
                        if (collection[0] == 1) application = collection[1];
                        if (collection[0] == 0) physical = collection[1];
                    }
                    int base = application == 0x10001 || application == 0x10002
                            || physical == 0x10001 || physical == 0x10002 ? 0x110 : 0x100;
                    for (int button = minimumUsage; button <= maximumUsage; button++)
                        mouseButtonCodes.add(base + button - 1);
                }
                if ((value & 1) == 0 && usagePage == 1 && (usage == 0x30 || usage == 0x31))
                    relativePosition |= (value & 4) != 0;
            }
            // HID local items belong to one Main item only.
            if ((prefix & 0x0c) == 0) { usage = 0; minimumUsage = 0; maximumUsage = 0; }
        }
        check(bits == (report.length - 1) * 8, "HID descriptor matches wire report size");
        check(legacyInputCollection, "Linux 6.1 must recognize an input collection before registering events");
        check(collections == 0 && applications == 1, "compatibility wrapper keeps one application and balanced collections");
        check(mouseButtonCodes.equals(Arrays.asList(0x110, 0x111, 0x112, 0x113, 0x114)),
            "five buttons must map to BTN_LEFT/RIGHT/MIDDLE/SIDE/EXTRA, not keyboard buttons");
        check(!relativePosition, "button fix must keep absolute X/Y without a second relative cursor mapper");
        System.out.println("Absolute mouse report: 12 checks passed");
    }
    private static void check(boolean condition, String label) { if (!condition) throw new AssertionError(label); }
}
