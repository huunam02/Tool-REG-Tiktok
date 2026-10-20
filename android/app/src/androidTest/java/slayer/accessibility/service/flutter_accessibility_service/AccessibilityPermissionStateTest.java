package slayer.accessibility.service.flutter_accessibility_service;

import android.content.ComponentName;
import androidx.test.ext.junit.runners.AndroidJUnit4;
import org.junit.Test;
import org.junit.runner.RunWith;
import static org.junit.Assert.*;

@RunWith(AndroidJUnit4.class)
public class AccessibilityPermissionStateTest {
    private final ComponentName service = new ComponentName("example.app", "example.app.Listener");

    @Test public void recognizesFullAndShortComponentNames() {
        assertTrue(Utils.containsEnabledService("example.app/example.app.Listener", service));
        assertTrue(Utils.containsEnabledService("example.app/.Listener", service));
        assertTrue(Utils.containsEnabledService("other.app/.Service: example.app/.Listener ", service));
    }

    @Test public void doesNotConfuseOtherServicesWithOurGrant() {
        assertFalse(Utils.containsEnabledService(null, service));
        assertFalse(Utils.containsEnabledService("", service));
        assertFalse(Utils.containsEnabledService("invalid:other.app/.Listener", service));
        assertFalse(Utils.containsEnabledService("example.app/.OtherListener", service));
    }
}
