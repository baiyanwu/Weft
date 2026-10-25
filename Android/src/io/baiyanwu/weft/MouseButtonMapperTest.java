package io.baiyanwu.weft;

import java.util.Arrays;

public final class MouseButtonMapperTest {
    private static final String[] ORIGINAL = {"original", "original", "original", "original", "original"};
    private static void check(boolean condition, String message) {
        if (!condition) throw new AssertionError(message);
    }
    private static void result(MouseButtonMapper.Result result, int buttons, int... keys) {
        check(result != null, "input should be accepted");
        check(result.buttons == buttons, "wrong native button mask");
        check(Arrays.equals(result.keys, keys), "wrong mapped actions: " + Arrays.toString(result.keys));
    }
    public static void main(String[] args) {
        MouseButtonMapper mapper = new MouseButtonMapper();
        mapper.configure(1, false, new String[] {"home", "back", "recents", "volumeUp", "volumeDown"});
        mapper.enter(1);
        result(mapper.pointer(1, 1, 31), 31);
        result(mapper.pointer(1, 2, 31), 31);
        mapper.release(1);
        String[] names = {"back", "home", "recents", "volumeUp", "volumeDown"};
        int[] codes = {4, 3, 187, 24, 25};
        long epoch = 1;
        for (int button = 0; button < 5; button++) {
            for (int action = 0; action < names.length; action++) {
                String[] actions = ORIGINAL.clone(); actions[button] = names[action];
                mapper.configure(++epoch, true, actions); mapper.enter(epoch);
                int bit = 1 << button;
                result(mapper.pointer(epoch, 1, bit), 0, codes[action]);
                result(mapper.pointer(epoch, 2, bit), 0);
                result(mapper.pointer(epoch, 3, 0), 0);
                result(mapper.pointer(epoch, 4, bit), 0, codes[action]);
                mapper.release(epoch);
            }
        }
        mapper.configure(++epoch, true, new String[] {"original", "original", "original", "back", "original"});
        mapper.enter(epoch);
        result(mapper.pointer(epoch, 1, 9), 1, 4);
        result(mapper.pointer(epoch, 2, 9), 1);
        result(mapper.pointer(epoch, 3, 1), 1);
        result(mapper.pointer(epoch, 4, 9), 1, 4);
        check(mapper.pointer(epoch, 4, 0) == null, "duplicate sequence");
        check(mapper.pointer(epoch - 1, 100, 0) == null, "stale visit");
        mapper.release(epoch - 1);
        result(mapper.pointer(epoch, 5, 9), 1);
        mapper.configure(epoch + 1, true, new String[] {"original", "original", "original", "home", "original"});
        result(mapper.pointer(epoch, 6, 0), 0);
        result(mapper.pointer(epoch, 7, 8), 0, 4);
        mapper.release(epoch);
        check(mapper.pointer(epoch, 8, 8) == null, "action after release");
        mapper.enter(++epoch);
        result(mapper.pointer(epoch, 1, 8), 0, 3);
        mapper.configure(epoch + 2, true, new String[] {"home", "back", "recents", "volumeUp", "volumeDown"});
        mapper.configure(epoch + 1, true, ORIGINAL);
        mapper.enter(epoch + 2); epoch += 2;
        result(mapper.pointer(epoch, 1, 31), 0, 3, 4, 187, 24, 25);
        mapper.release(epoch); mapper.enter(++epoch);
        result(mapper.pointer(epoch, 1, 31), 31);
        mapper.configure(epoch + 1, true, ORIGINAL); mapper.enter(++epoch);
        result(mapper.pointer(epoch, 1, 31 | 128), 31);
        boolean rejected = false;
        try { mapper.configure(epoch + 1, true, new String[] {"power", "original", "original", "original", "original"}); }
        catch (IllegalArgumentException expected) { rejected = true; }
        check(rejected, "unsupported device action");
        System.out.println("MouseButtonMapperTest passed: all 25 mappings, held buttons, mixed drag, defaults, and visit/sequence fences");
    }
}
