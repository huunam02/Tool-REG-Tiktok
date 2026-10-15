package com.stalliondz.tool.tiktok;

import android.content.Context;
import androidx.test.ext.junit.runners.AndroidJUnit4;
import androidx.test.platform.app.InstrumentationRegistry;
import io.flutter.embedding.engine.FlutterEngine;
import io.flutter.embedding.engine.FlutterEngineCache;
import java.lang.reflect.Field;
import org.junit.Test;
import org.junit.runner.RunWith;
import slayer.accessibility.service.flutter_accessibility_service.AccessibilityListener;
import slayer.accessibility.service.flutter_accessibility_service.FlutterAccessibilityServicePlugin;
import static org.junit.Assert.*;

@RunWith(AndroidJUnit4.class)
public class AccessibilityStartupTest {
    private static class ProbeListener extends AccessibilityListener {
        void connect(Context context) {
            attachBaseContext(context);
            super.onServiceConnected();
        }
    }

    @Test public void connectsBeforeTheOptionalFlutterOverlayEngineExists() throws Exception {
        // Save/restore plugin globals synchronously on the UI thread so this
        // isolated service test cannot change the user's running service.
        Field instance = AccessibilityListener.class.getDeclaredField("instance");
        Field overlay = AccessibilityListener.class.getDeclaredField("mOverlayView");
        Field manager = AccessibilityListener.class.getDeclaredField("mWindowManager");
        instance.setAccessible(true);
        overlay.setAccessible(true);
        manager.setAccessible(true);
        InstrumentationRegistry.getInstrumentation().runOnMainSync(() -> {
            String tag = FlutterAccessibilityServicePlugin.CACHED_TAG;
            FlutterEngine engine = FlutterEngineCache.getInstance().get(tag);
            try {
                Object oldInstance = instance.get(null);
                Object oldOverlay = overlay.get(null);
                Object oldManager = manager.get(null);
                try {
                    FlutterEngineCache.getInstance().remove(tag);
                    overlay.set(null, null);
                    ProbeListener service = new ProbeListener();
                    service.connect(InstrumentationRegistry.getInstrumentation().getTargetContext());
                    assertSame(service, instance.get(null));
                    assertNull(overlay.get(null));
                } finally {
                    instance.set(null, oldInstance);
                    overlay.set(null, oldOverlay);
                    manager.set(null, oldManager);
                }
            } catch (IllegalAccessException error) {
                throw new AssertionError(error);
            } finally {
                if (engine != null) FlutterEngineCache.getInstance().put(tag, engine);
            }
        });
    }
}
