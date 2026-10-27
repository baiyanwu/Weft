package io.baiyanwu.weft;

import java.util.Arrays;

/** Maps physical button edges, while fencing configurations and inputs by control visit. */
final class MouseButtonMapper {
    static final int BACK = 4, HOME = 3, RECENTS = 187, VOLUME_UP = 24, VOLUME_DOWN = 25;
    private static final int[] ORIGINAL = new int[5];
    private long epoch, sequence, pendingEpoch;
    private boolean active, enabled, pendingEnabled;
    private int held;
    private int[] actions = ORIGINAL, pendingActions = ORIGINAL;

    synchronized void configure(long visit, boolean enabled, String[] names) {
        if (names.length != 5) throw new IllegalArgumentException("Five button actions required");
        int[] parsed = new int[5];
        for (int i = 0; i < 5; i++) parsed[i] = keyCode(names[i]);
        if (visit <= epoch || visit < pendingEpoch) return;
        pendingEpoch = visit; pendingEnabled = enabled; pendingActions = parsed;
    }

    synchronized void enter(long visit) {
        if (visit <= epoch) return;
        enabled = pendingEpoch == visit && pendingEnabled;
        actions = pendingEpoch == visit ? pendingActions : ORIGINAL;
        epoch = visit; sequence = 0; held = 0; active = true;
        if (pendingEpoch <= visit) { pendingEpoch = 0; pendingActions = ORIGINAL; pendingEnabled = false; }
    }

    synchronized Result pointer(long visit, long inputSequence, int physicalButtons) {
        if (!active || visit != epoch || inputSequence <= sequence) return null;
        sequence = inputSequence;
        int raw = physicalButtons & 31, pressed = raw & ~held;
        held = raw;
        int nativeButtons = raw, count = 0;
        int[] keys = new int[5];
        if (enabled) {
            for (int i = 0; i < 5; i++) {
                int bit = 1 << i;
                if (actions[i] == 0) continue;
                nativeButtons &= ~bit;
                if ((pressed & bit) != 0) keys[count++] = actions[i];
            }
        }
        return new Result(nativeButtons, Arrays.copyOf(keys, count));
    }

    synchronized void release(long visit) {
        if (visit != epoch) return;
        active = false; held = 0; enabled = false; actions = ORIGINAL;
    }

    static int keyCode(String name) {
        switch (name) {
        case "original": return 0;
        case "back": return BACK;
        case "home": return HOME;
        case "recents": return RECENTS;
        case "volumeUp": return VOLUME_UP;
        case "volumeDown": return VOLUME_DOWN;
        default: throw new IllegalArgumentException("Unsupported button action: " + name);
        }
    }

    static final class Result {
        final int buttons;
        final int[] keys;
        Result(int buttons, int[] keys) { this.buttons = buttons; this.keys = keys; }
    }
}
