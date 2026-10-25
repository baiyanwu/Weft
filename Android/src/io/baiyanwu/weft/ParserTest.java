package io.baiyanwu.weft;

public final class ParserTest {
    public static void main(String[] args) {
        CursorParser parser = new CursorParser(42);
        parser.accept("    16:[touchingPointers=[], hoveringPointers=[Pointer(id=0, MOUSE) at (1, 2)]]");
        require(!parser.valid(), "must ignore other input devices");
        parser.accept("    42:[touchingPointers=[], hoveringPointers=[Pointer(id=0, MOUSE) at (2334.96, 2225.88)], pilferingPointerIds=<none>]");
        require(parser.valid() && parser.x == 2334.96 && parser.y == 2225.88, "continuation line");
        parser = new CursorParser(42);
        parser.accept("name='some window', mDeviceStates=42:[touchingPointers=[], hoveringPointers=[Pointer(id=0, MOUSE) at (0, 2399.0)]]");
        require(parser.valid() && parser.x == 0 && parser.y == 2399, "inline state and edge coordinates");
        parser = new CursorParser(42);
        parser.accept("42:[touchingPointers=[], hoveringPointers=[]]");
        require(!parser.valid(), "missing cursor is not zero");
        parser.x = 2108.51; parser.y = 1877.7;
        double[] rotated = parser.logical(3392, 2400, 1);
        require(Math.abs(rotated[0] - 1877.7) < .001 && Math.abs(rotated[1] - 291.49) < .001, "landscape input-to-display transform");
        parser.x = 2400; parser.y = 3392;
        rotated = parser.logical(3392, 2400, 1);
        require(rotated[0] == 3391 && rotated[1] == 0, "far edge clamps");
        parser = new CursorParser(42);
        parser.accept("42:[touchingPointers=[Pointer(id=0, MOUSE) at (32, 64)], hoveringPointers=[]]");
        require(parser.valid() && parser.x == 32 && parser.y == 64, "a held mouse button still confirms position");
        System.out.println("CursorParser: 7 checks passed");
    }

    private static void require(boolean condition, String message) {
        if (!condition) throw new AssertionError(message);
    }
}
