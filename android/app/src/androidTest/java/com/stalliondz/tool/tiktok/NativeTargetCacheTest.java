package com.stalliondz.tool.tiktok;

import android.app.Instrumentation;
import android.webkit.WebView;
import android.webkit.WebViewClient;
import android.view.ViewGroup;
import androidx.test.ext.junit.runners.AndroidJUnit4;
import androidx.test.platform.app.InstrumentationRegistry;
import androidx.test.rule.ActivityTestRule;
import java.util.Map;
import java.util.concurrent.CountDownLatch;
import java.util.concurrent.TimeUnit;
import java.util.concurrent.atomic.AtomicReference;
import kotlin.Unit;
import org.junit.After;
import org.junit.Before;
import org.junit.Rule;
import org.junit.Test;
import org.junit.runner.RunWith;
import static org.junit.Assert.*;

@SuppressWarnings("deprecation")
@RunWith(AndroidJUnit4.class)
public class NativeTargetCacheTest {
    @Rule public ActivityTestRule<MainActivity> activityRule = new ActivityTestRule<>(MainActivity.class);
    private WebView view;
    private int geometryReads;

    private Instrumentation instrumentation() { return InstrumentationRegistry.getInstrumentation(); }

    @Before public void setUp() throws Exception {
        CountDownLatch loaded = new CountDownLatch(1);
        instrumentation().runOnMainSync(() -> {
            view = new WebView(activityRule.getActivity()) {
                @Override public void getLocationOnScreen(int[] location) {
                    for (StackTraceElement frame : Thread.currentThread().getStackTrace()) {
                        if (frame.getClassName().equals(NativeSendCodeTarget.class.getName())) {
                            geometryReads++;
                            break;
                        }
                    }
                    super.getLocationOnScreen(location);
                }
            };
            view.getSettings().setJavaScriptEnabled(true);
            activityRule.getActivity().addContentView(view, new ViewGroup.LayoutParams(-1, -1));
            view.setWebViewClient(new WebViewClient() {
                @Override public void onPageFinished(WebView webView, String url) { loaded.countDown(); }
            });
            view.loadDataWithBaseURL("https://www.tiktok.com/", "<body><script>" +
                "window.__flutterAutoLogin={getSendCodeTarget:()=>({x:100,y:100," +
                "viewportWidth:innerWidth,viewportHeight:innerHeight})};</script></body>",
                "text/html", "UTF-8", null);
        });
        assertTrue(loaded.await(10, TimeUnit.SECONDS));
        instrumentation().waitForIdleSync();
    }

    private Map<String, Double> read() throws Exception {
        AtomicReference<Map<String, Double>> result = new AtomicReference<>();
        CountDownLatch done = new CountDownLatch(1);
        instrumentation().runOnMainSync(() -> NativeSendCodeTarget.INSTANCE.read(view, 1, "login", "send-code", point -> {
            result.set(point);
            done.countDown();
            return Unit.INSTANCE;
        }));
        assertTrue(done.await(5, TimeUnit.SECONDS));
        assertNotNull(result.get());
        return result.get();
    }

    @Test public void reusesStablePhysicalGeometry() throws Exception {
        Map<String, Double> first = read();
        int reads = geometryReads;
        assertEquals(first, read());
        assertEquals(reads, geometryReads);
    }

    @Test public void remeasuresAfterTranslationWithoutWaitingForLayout() throws Exception {
        Map<String, Double> first = read();
        int reads = geometryReads;
        instrumentation().runOnMainSync(() -> view.setTranslationY(20));
        Map<String, Double> moved = read();
        assertEquals(first.get("y") + 20, moved.get("y"), 0.01);
        assertTrue(geometryReads > reads);
    }

    @Test public void keepsGeometryAfterAnUnchangedLayoutEvent() throws Exception {
        Map<String, Double> first = read();
        int reads = geometryReads;
        instrumentation().runOnMainSync(() -> view.getViewTreeObserver().dispatchOnGlobalLayout());
        assertEquals(first, read());
        assertEquals(reads, geometryReads);
    }

    @Test public void invalidatesOnlyTheFailedActionAndRemeasuresNextTime() throws Exception {
        read();
        int reads = geometryReads;
        CountDownLatch setup = new CountDownLatch(1);
        instrumentation().runOnMainSync(() -> view.evaluateJavascript(
            "window.__flutterNativeTapTargets=new Map([['login/send-code',{}],['login/continue-otp',{}]]);true",
            result -> setup.countDown()));
        assertTrue(setup.await(5, TimeUnit.SECONDS));
        CountDownLatch invalidated = new CountDownLatch(1);
        instrumentation().runOnMainSync(() -> NativeSendCodeTarget.INSTANCE.invalidate(
            view, "login", "send-code", success -> {
                assertTrue(success);
                invalidated.countDown();
                return Unit.INSTANCE;
            }));
        assertTrue(invalidated.await(5, TimeUnit.SECONDS));
        CountDownLatch checked = new CountDownLatch(1);
        instrumentation().runOnMainSync(() -> view.evaluateJavascript(
            "!window.__flutterNativeTapTargets.has('login/send-code') && window.__flutterNativeTapTargets.has('login/continue-otp')",
            result -> {
                assertEquals("true", result);
                checked.countDown();
            }));
        assertTrue(checked.await(5, TimeUnit.SECONDS));
        read();
        assertEquals(reads + 1, geometryReads);
        read();
        assertEquals(reads + 1, geometryReads);
    }

    @After public void tearDown() {
        if (view != null) instrumentation().runOnMainSync(() -> {
            ((ViewGroup) view.getParent()).removeView(view);
            view.destroy();
        });
    }
}
