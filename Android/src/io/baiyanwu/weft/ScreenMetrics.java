package io.baiyanwu.weft;

/** Display dimensions for the layout, read from the same oriented display snapshot. */
final class ScreenMetrics {
    final int[] display;
    final double widthMM, heightMM;
    final boolean estimated;

    private ScreenMetrics(int[] display, double widthMM, double heightMM, boolean estimated) {
        this.display = display; this.widthMM = widthMM; this.heightMM = heightMM; this.estimated = estimated;
    }

    static ScreenMetrics read() throws Exception {
        Object info = BridgeAgent.displayInfoObject();
        int width = info.getClass().getField("logicalWidth").getInt(info);
        int height = info.getClass().getField("logicalHeight").getInt(info);
        int rotation = info.getClass().getField("rotation").getInt(info);
        double xdpi = field(info, "physicalXDpi", 0), ydpi = field(info, "physicalYDpi", 0);
        boolean estimated = !validDpi(xdpi) || !validDpi(ydpi);
        if (estimated) {
            double density = field(info, "logicalDensityDpi", 160);
            xdpi = ydpi = validDpi(density) ? density : 160;
        }
        // Android rotates logicalWidth/Height but keeps physical X/Y DPI in
        // the natural orientation. Swap the DPI axes, not the pixel dimensions.
        boolean rotated = rotation == 1 || rotation == 3;
        return new ScreenMetrics(new int[] {width, height, rotation},
            width * 25.4 / (rotated ? ydpi : xdpi), height * 25.4 / (rotated ? xdpi : ydpi), estimated);
    }

    String fields() {
        return "\"width\":" + display[0] + ",\"height\":" + display[1] + ",\"rotation\":" + display[2]
            + ",\"layoutWidthMM\":" + widthMM + ",\"layoutHeightMM\":" + heightMM
            + ",\"estimatedSize\":" + estimated;
    }

    private static double field(Object info, String name, double fallback) {
        try { return ((Number) info.getClass().getField(name).get(info)).doubleValue(); }
        catch (ReflectiveOperationException error) { return fallback; }
    }
    private static boolean validDpi(double value) { return Double.isFinite(value) && value >= 30 && value <= 2000; }
}
