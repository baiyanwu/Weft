package io.baiyanwu.weft;

import java.util.regex.Matcher;
import java.util.regex.Pattern;

/** Parses only this helper's mouse coordinates. App/window names are never retained. */
public final class CursorParser {
    private static final Pattern DEVICE = Pattern.compile("(?:mDeviceStates=|^\\s*)(\\d+):\\[");
    private static final Pattern POINT = Pattern.compile("(?:hovering|touching)Pointers=\\[Pointer\\(id=\\d+, MOUSE\\) at \\(([-+.0-9]+), ([-+.0-9]+)\\)");
    private final int deviceId;
    public double x = Double.NaN;
    public double y = Double.NaN;

    public CursorParser(int deviceId) { this.deviceId = deviceId; }

    public void accept(String line) {
        Matcher device = DEVICE.matcher(line);
        if (!device.find() || Integer.parseInt(device.group(1)) != deviceId) return;
        Matcher point = POINT.matcher(line.substring(device.end()));
        if (point.find()) {
            x = Double.parseDouble(point.group(1));
            y = Double.parseDouble(point.group(2));
        }
    }

    public boolean valid() { return Double.isFinite(x) && Double.isFinite(y); }

    // InputDispatcher's device state is in the display's unrotated input space.
    // Match the display transform printed by Android, then clamp the far edge.
    public double[] logical(int width, int height, int rotation) {
        double lx = x, ly = y;
        if (rotation == 1) { lx = y; ly = height - x; }
        if (rotation == 2) { lx = width - x; ly = height - y; }
        if (rotation == 3) { lx = width - y; ly = x; }
        return new double[] { Math.max(0, Math.min(width - 1, lx)), Math.max(0, Math.min(height - 1, ly)) };
    }
}
