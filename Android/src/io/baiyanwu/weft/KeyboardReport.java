package io.baiyanwu.weft;

/** NKRO bitmap: one modifier byte followed by usages 0..223 (28 bytes). */
final class KeyboardReport {
    static final int SIZE = 29;

    static byte[] descriptor() {
        int[] values = {
            0x05,0x01, 0x09,0x06, 0xa1,0x01, // Generic Desktop / Keyboard
            0x05,0x07, 0x19,0xe0, 0x29,0xe7, 0x15,0x00, 0x25,0x01,
            0x75,0x01, 0x95,0x08, 0x81,0x02, // Eight modifiers
            0x19,0x00, 0x29,0xdf, 0x75,0x01, 0x95,0xe0, 0x81,0x02, // Key bitmap
            0x05,0x08, 0x19,0x01, 0x29,0x05, 0x75,0x01, 0x95,0x05, 0x91,0x02, // LEDs
            0x75,0x03, 0x95,0x01, 0x91,0x01, 0xc0
        };
        byte[] result = new byte[values.length];
        for (int i = 0; i < values.length; i++) result[i] = (byte) values[i];
        return result;
    }

    static byte[] decode(int modifiers, String keys) {
        if (modifiers < 0 || modifiers > 255) throw new IllegalArgumentException("Keyboard modifiers");
        byte[] report = new byte[SIZE]; report[0] = (byte) modifiers;
        if (keys.equals("-")) return report;
        if (keys.length() == 0 || keys.length() > 448 || keys.length() % 2 != 0)
            throw new IllegalArgumentException("Keyboard usages");
        for (int i = 0; i < keys.length(); i += 2) {
            int hi = Character.digit(keys.charAt(i), 16), lo = Character.digit(keys.charAt(i + 1), 16);
            int usage = hi * 16 + lo;
            if (hi < 0 || lo < 0 || usage < 4 || usage > 223)
                throw new IllegalArgumentException("Keyboard usage");
            report[1 + usage / 8] |= (byte) (1 << (usage % 8));
        }
        return report;
    }

    static int actionCode(String action) {
        switch (action) {
        case "none": return 0;
        case "back": return 4;
        case "home": return 3;
        case "recents": return 187;
        case "forward": return 125;
        case "notifications": return -1;
        case "quickSettings": return -2;
        case "collapsePanels": return -3;
        case "settings": return 176;
        case "dpadUp": return 19;
        case "dpadDown": return 20;
        case "dpadLeft": return 21;
        case "dpadRight": return 22;
        case "dpadCenter": return 23;
        case "pageUp": return 92;
        case "pageDown": return 93;
        case "volumeUp": return 24;
        case "volumeDown": return 25;
        case "mute": return 164;
        case "playPause": return 85;
        case "nextTrack": return 87;
        case "previousTrack": return 88;
        case "mediaStop": return 86;
        case "screenshot": return 120;
        case "power": return 26;
        case "wake": return 224;
        case "sleep": return 223;
        case "brightnessUp": return 221;
        case "brightnessDown": return 220;
        case "camera": return 27;
        case "search": return 84;
        case "assistant": return 231;
        case "menu": return 82;
        default: throw new IllegalArgumentException("Keyboard action");
        }
    }
}
