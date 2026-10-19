package com.stalliondz.tool.tiktok;

import com.brisklane.browser.MainActivity;

import android.provider.Settings;
import android.webkit.JavascriptInterface;
import android.webkit.WebView;
import androidx.test.ext.junit.runners.AndroidJUnit4;
import androidx.test.platform.app.InstrumentationRegistry;
import androidx.test.rule.ActivityTestRule;
import androidx.webkit.WebViewCompat;
import androidx.webkit.WebViewFeature;
import java.io.BufferedReader;
import java.io.InputStreamReader;
import java.nio.charset.StandardCharsets;
import java.util.Collections;
import java.util.TimeZone;
import java.util.concurrent.CountDownLatch;
import java.util.concurrent.TimeUnit;
import java.util.concurrent.atomic.AtomicReference;
import org.json.JSONObject;
import org.junit.Test;
import org.junit.runner.RunWith;
import static org.junit.Assert.*;
import static org.junit.Assume.assumeTrue;

@SuppressWarnings("deprecation")
@RunWith(AndroidJUnit4.class)
public class WebViewTimeZoneTest {
    @org.junit.Rule public ActivityTestRule<MainActivity> activity = new ActivityTestRule<>(MainActivity.class);

    @Test public void proxyZonesApplyBeforeFirstScriptInPageAndFrameWithoutSystemChange() throws Exception {
        assumeTrue(WebViewFeature.isFeatureSupported(WebViewFeature.DOCUMENT_START_SCRIPT));
        String originalZone = TimeZone.getDefault().getID();
        int originalAuto = Settings.Global.getInt(activity.getActivity().getContentResolver(), Settings.Global.AUTO_TIME_ZONE, 1);
        StringBuilder template = new StringBuilder();
        try (BufferedReader reader = new BufferedReader(new InputStreamReader(
                InstrumentationRegistry.getInstrumentation().getContext().getAssets().open("webview_timezone.js"), StandardCharsets.UTF_8))) {
            String line;
            while ((line = reader.readLine()) != null) template.append(line).append('\n');
        }
        for (String zone : new String[]{"America/New_York", "Asia/Tokyo"}) {
            String script = template.toString().replace("__PROXY_TIME_ZONE__", JSONObject.quote(zone));
            String probe = "function probe(){return {zone:Intl.DateTimeFormat().resolvedOptions().timeZone," +
                "winter:new Date('2026-01-15T12:00:00Z').getTimezoneOffset()," +
                "summer:new Date('2026-07-15T12:00:00Z').getTimezoneOffset()," +
                "text:new Date('2026-07-15T12:00:00Z').toString()," +
                "local:new Date(2026,6,15,12).toISOString()," +
                "explicit:Intl.DateTimeFormat('en-US',{timeZone:'UTC'}).resolvedOptions().timeZone," +
                "utc:new Date('2026-07-15T12:00:00Z').toISOString()};}";
            String html = "<!doctype html><script>" + probe +
                "const first=probe();function frameReady(frame){TimeZoneTest.receive(JSON.stringify({first,frame}));}" +
                "</script><iframe srcdoc=\"<script>" + probe + "parent.frameReady(probe());</script>\"></iframe>";
            AtomicReference<WebView> view = new AtomicReference<>();
            AtomicReference<String> captured = new AtomicReference<>();
            CountDownLatch done = new CountDownLatch(1);
            try {
                InstrumentationRegistry.getInstrumentation().runOnMainSync(() -> {
                    WebView webView = new WebView(activity.getActivity());
                    view.set(webView);
                    webView.getSettings().setJavaScriptEnabled(true);
                    webView.addJavascriptInterface(new Object() {
                        @JavascriptInterface public void receive(String value) { captured.set(value); done.countDown(); }
                    }, "TimeZoneTest");
                    WebViewCompat.addDocumentStartJavaScript(webView, script, Collections.singleton("*"));
                    webView.loadDataWithBaseURL("https://timezone.test/", html, "text/html", "UTF-8", null);
                });
                assertTrue("Page and frame completed", done.await(15, TimeUnit.SECONDS));
                JSONObject result = new JSONObject(captured.get());
                boolean east = zone.equals("America/New_York");
                for (String scope : new String[]{"first", "frame"}) {
                    JSONObject snapshot = result.getJSONObject(scope);
                    assertEquals(zone, snapshot.getString("zone"));
                    assertEquals(east ? 300 : -540, snapshot.getInt("winter"));
                    assertEquals(east ? 240 : -540, snapshot.getInt("summer"));
                    assertTrue(snapshot.getString("text").contains(east ? "GMT-0400" : "GMT+0900"));
                    assertEquals(east ? "2026-07-15T16:00:00.000Z" : "2026-07-15T03:00:00.000Z", snapshot.getString("local"));
                    assertEquals("UTC", snapshot.getString("explicit"));
                    assertEquals("2026-07-15T12:00:00.000Z", snapshot.getString("utc"));
                }
            } finally {
                InstrumentationRegistry.getInstrumentation().runOnMainSync(() -> { if (view.get() != null) view.get().destroy(); });
            }
        }
        assertEquals(originalZone, TimeZone.getDefault().getID());
        assertEquals(originalAuto, Settings.Global.getInt(activity.getActivity().getContentResolver(), Settings.Global.AUTO_TIME_ZONE, 1));
    }
}
