package slayer.accessibility.service.flutter_accessibility_service;

import android.app.Instrumentation;
import android.app.UiAutomation;
import android.os.SystemClock;
import android.os.ParcelFileDescriptor;
import android.provider.Settings;
import android.view.MotionEvent;
import android.view.View;
import androidx.test.ext.junit.runners.AndroidJUnit4;
import androidx.test.platform.app.InstrumentationRegistry;
import androidx.test.rule.ActivityTestRule;
import com.stalliondz.tool.tiktok.SignupFixtureActivity;
import io.flutter.plugin.common.MethodChannel;
import java.util.ArrayList;
import java.util.Arrays;
import java.util.HashMap;
import java.util.List;
import java.util.Map;
import java.util.concurrent.CountDownLatch;
import java.util.concurrent.TimeUnit;
import java.util.concurrent.atomic.AtomicReference;
import org.junit.After;
import org.junit.Before;
import org.junit.Rule;
import org.junit.Test;
import org.junit.runner.RunWith;
import static org.junit.Assert.*;

/** Exercises real Accessibility touch injection on a local native view only. */
@RunWith(AndroidJUnit4.class)
public class ContinuousGestureTest {
    @Rule public ActivityTestRule<SignupFixtureActivity> activity =
        new ActivityTestRule<>(SignupFixtureActivity.class);
    private final List<MotionEvent> events = new ArrayList<>();
    private String enabledServices;
    private UiAutomation automation;
    private Instrumentation instrumentation() { return InstrumentationRegistry.getInstrumentation(); }

    private void shell(String command) throws Exception {
        // Drain output before closing: Android 9's UiAutomation repeater can
        // crash on EPIPE if the reader closes while settings is still writing.
        try (ParcelFileDescriptor.AutoCloseInputStream input =
                new ParcelFileDescriptor.AutoCloseInputStream(automation.executeShellCommand(command))) {
            byte[] buffer = new byte[1024];
            while (input.read(buffer) != -1) { }
        }
    }

    @Before public void setup() throws Exception {
        automation = instrumentation().getUiAutomation(UiAutomation.FLAG_DONT_SUPPRESS_ACCESSIBILITY_SERVICES);
        enabledServices = Settings.Secure.getString(
            instrumentation().getTargetContext().getContentResolver(),
            Settings.Secure.ENABLED_ACCESSIBILITY_SERVICES);
        shell("settings delete secure enabled_accessibility_services");
        long deadline = SystemClock.uptimeMillis() + 5000;
        while (AccessibilityListener.currentInstance() != null && SystemClock.uptimeMillis() < deadline) {
            Thread.sleep(50);
        }
        String ownService = instrumentation().getTargetContext().getPackageName() +
            "/slayer.accessibility.service.flutter_accessibility_service.AccessibilityListener";
        shell("settings put secure enabled_accessibility_services " + ownService);
        deadline = SystemClock.uptimeMillis() + 10000;
        while (AccessibilityListener.currentInstance() == null && SystemClock.uptimeMillis() < deadline) {
            Thread.sleep(50);
        }
        assertNotNull("Accessibility service connected", AccessibilityListener.currentInstance());
        instrumentation().runOnMainSync(() -> {
            View target = new View(activity.getActivity());
            target.setOnTouchListener((view, event) -> {
                events.add(MotionEvent.obtain(event));
                return true;
            });
            activity.getActivity().setContentView(target);
        });
        instrumentation().waitForIdleSync();
        Thread.sleep(300);
    }

    @After public void cleanup() throws Exception {
        if (automation != null) {
            // UiAutomation tokenizes this command directly; shell quotes would
            // become part of the setting instead of escaping the value.
            String command = enabledServices == null || enabledServices.isEmpty()
                ? "settings delete secure enabled_accessibility_services"
                : "settings put secure enabled_accessibility_services " + enabledServices;
            shell(command);
        }
        for (MotionEvent event : events) event.recycle();
    }

    private Map<String, Object> segment(int duration, double... xy) {
        List<Object> points = new ArrayList<>();
        for (int i = 0; i < xy.length; i += 2) {
            Map<String, Object> point = new HashMap<>();
            point.put("x", xy[i]);
            point.put("y", xy[i + 1]);
            points.add(point);
        }
        Map<String, Object> segment = new HashMap<>();
        segment.put("path", points);
        segment.put("duration", duration);
        return segment;
    }

    private void dispatch(List<Object> segments) throws Exception {
        CountDownLatch completed = new CountDownLatch(1);
        AtomicReference<Object> result = new AtomicReference<>();
        instrumentation().runOnMainSync(() ->
            AccessibilityListener.performContinuousGesture(segments, new MethodChannel.Result() {
                @Override public void success(Object value) { result.set(value); completed.countDown(); }
                @Override public void error(String code, String message, Object details) {
                    result.set(code); completed.countDown();
                }
                @Override public void notImplemented() { completed.countDown(); }
            }));
        assertTrue("Gesture callback received", completed.await(10, TimeUnit.SECONDS));
        assertEquals("Continuous gesture completed", Boolean.TRUE, result.get());
        instrumentation().waitForIdleSync();
    }

    private void assertSingleTouch(float x, float y, long minimumDuration) {
        assertEquals(1, events.stream().filter(e -> e.getActionMasked() == MotionEvent.ACTION_DOWN).count());
        assertEquals(1, events.stream().filter(e -> e.getActionMasked() == MotionEvent.ACTION_UP).count());
        assertEquals(0, events.stream().filter(e -> e.getActionMasked() == MotionEvent.ACTION_CANCEL).count());
        MotionEvent end = events.get(events.size() - 1);
        assertEquals(x, end.getRawX(), .01f);
        assertEquals(y, end.getRawY(), .01f);
        assertTrue("Requested holds must not finish early",
            end.getEventTime() - events.get(0).getEventTime() >= minimumDuration);
    }

    @Test public void subpixelMovementAndIntermediateHoldKeepOneFingerDown() throws Exception {
        dispatch(Arrays.asList(
            segment(100, 200, 600),
            segment(45, 200, 600, 200.2, 600.1),
            segment(70, 200.2, 600.1),
            segment(300, 200.2, 600.1, 250.4, 600),
            segment(160, 250.4, 600)));
        assertSingleTouch(250, 600, 625);
    }

    @Test public void consecutiveStationarySegmentsPreserveTheirDuration() throws Exception {
        dispatch(Arrays.asList(
            segment(120, 200, 600),
            segment(80, 200, 600),
            segment(180, 200, 600)));
        assertSingleTouch(200, 600, 330);
    }
}
