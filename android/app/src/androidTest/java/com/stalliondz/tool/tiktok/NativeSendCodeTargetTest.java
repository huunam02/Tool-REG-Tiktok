package com.stalliondz.tool.tiktok;

import android.graphics.Rect;
import androidx.test.ext.junit.runners.AndroidJUnit4;
import java.util.Map;
import org.json.JSONObject;
import org.junit.Test;
import org.junit.runner.RunWith;
import static org.junit.Assert.*;

@RunWith(AndroidJUnit4.class)
public class NativeSendCodeTargetTest {
    private JSONObject target(double x, double y, double width, double height) throws Exception {
        return new JSONObject().put("x", x).put("y", y)
            .put("viewportWidth", width).put("viewportHeight", height);
    }

    @Test public void mapsDesktopViewportUsingNativeScreenOffset() throws Exception {
        Map<String, Double> point = NativeSendCodeTarget.INSTANCE.toScreen(
            target(490, 200, 980, 1600), 30, 120, 1080, 1800, new Rect(0, 0, 1080, 1800));
        assertNotNull(point);
        assertEquals(570.0, point.get("x"), 0.001);
        assertEquals(120.0 + 200.0 * 1080 / 980, point.get("y"), 0.001);
    }

    @Test public void usesZoomedViewportWidthAndRejectsKeyboardClipping() throws Exception {
        Map<String, Double> point = NativeSendCodeTarget.INSTANCE.toScreen(
            target(100, 60, 400, 600), 30, 120, 1080, 1800, new Rect(0, 0, 1080, 1800));
        assertNotNull(point);
        assertEquals(300.0, point.get("x"), 0.001);
        assertEquals(282.0, point.get("y"), 0.001);
        assertNull(NativeSendCodeTarget.INSTANCE.toScreen(
            target(100, 400, 400, 600), 30, 120, 1080, 1800, new Rect(0, 0, 1080, 900)));
        assertNull(NativeSendCodeTarget.INSTANCE.toScreen(
            target(-1, 60, 400, 600), 30, 120, 1080, 1800, new Rect(0, 0, 1080, 1800)));
        assertNull(NativeSendCodeTarget.INSTANCE.toScreen(
            target(100, 60, 0, 600), 30, 120, 1080, 1800, new Rect(0, 0, 1080, 1800)));
    }
}
