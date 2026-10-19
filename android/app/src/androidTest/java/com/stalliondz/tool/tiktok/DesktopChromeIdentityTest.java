package com.stalliondz.tool.tiktok;

import com.brisklane.browser.MainActivity;

import android.app.Instrumentation;
import android.webkit.WebView;
import android.webkit.WebSettings;
import android.webkit.JavascriptInterface;
import android.webkit.WebViewClient;
import android.view.ViewGroup;
import androidx.test.ext.junit.runners.AndroidJUnit4;
import androidx.test.platform.app.InstrumentationRegistry;
import androidx.test.rule.ActivityTestRule;
import androidx.webkit.WebViewFeature;
import java.io.BufferedReader;
import java.io.InputStreamReader;
import java.net.ServerSocket;
import java.net.Socket;
import java.nio.charset.StandardCharsets;
import java.util.HashMap;
import java.util.Locale;
import java.util.Map;
import java.util.concurrent.CountDownLatch;
import java.util.concurrent.TimeUnit;
import java.util.concurrent.atomic.AtomicReference;
import java.util.regex.Matcher;
import java.util.regex.Pattern;
import org.json.JSONArray;
import org.json.JSONObject;
import org.junit.Test;
import org.junit.runner.RunWith;
import static org.junit.Assert.*;
import static org.junit.Assume.assumeTrue;

/** Verifies real HTTP headers and JavaScript before contacting any website. */
@SuppressWarnings("deprecation")
@RunWith(AndroidJUnit4.class)
public class DesktopChromeIdentityTest {
    @org.junit.Rule public ActivityTestRule<MainActivity> activity = new ActivityTestRule<>(MainActivity.class);

    @Test public void firstRequestAndJavaScriptUseTheSameDesktopChromeProfile() throws Exception {
        assertDesktopIdentity(null);
    }

    @Test public void staleWindowsUaIsReplacedByTheInstalledEngineProfile() throws Exception {
        assertDesktopIdentity("Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 " +
            "(KHTML, like Gecko) Chrome/140.0.0.0 Safari/537.36");
    }

    @Test public void staleMacUaIsReplacedByTheInstalledEngineProfile() throws Exception {
        assertDesktopIdentity("Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 " +
            "(KHTML, like Gecko) Chrome/139.0.0.0 Safari/537.36");
    }

    @Test public void configuredChrome155ControlsTheFirstRequestAndClientHints() throws Exception {
        assertDesktopIdentity(null, "155.0.8059.79");
    }

    @Test public void selectedRecentChrome151IsNotForcedToChrome155() throws Exception {
        assertDesktopIdentity(null, "151.0.7922.173");
    }

    private static final String MIUI_AGENT = "Mozilla/5.0 (X11; Linux x86_64) AppleWebKit/537.36 " +
        "(KHTML, like Gecko) Chrome/135.0.7049.79 Safari/537.36 XiaoMi/MiuiBrowser/14.65.0-gn";

    @Test public void miuiHasDesktopIdentityAndLayoutFromFirstRequest() throws Exception {
        assertDesktopIdentity(null, "135.0.7049.79", true);
    }

    @Test public void windowsChromeHasMatchingHeadersJavaScriptAndDesktopLayout() throws Exception {
        assertDesktopIdentity(null, "155.0.8059.79", false, true);
    }

    @Test public void engineCompatibilityUsesInstalledVersionAndNativeHardware() throws Exception {
        assertDesktopIdentity(null, null, false, false, false);
    }

    private void assertDesktopIdentity(String configuredAgent) throws Exception {
        assertDesktopIdentity(configuredAgent, null);
    }

    private void assertDesktopIdentity(String configuredAgent, String requestedFullVersion) throws Exception {
        assertDesktopIdentity(configuredAgent, requestedFullVersion, false);
    }

    private void assertDesktopIdentity(String configuredAgent, String requestedFullVersion, boolean isMiui) throws Exception {
        assertDesktopIdentity(configuredAgent, requestedFullVersion, isMiui, false);
    }

    private void assertDesktopIdentity(String configuredAgent, String requestedFullVersion, boolean isMiui, boolean isWindows) throws Exception {
        assertDesktopIdentity(configuredAgent, requestedFullVersion, isMiui, isWindows, true);
    }

    private void assertDesktopIdentity(String configuredAgent, String requestedFullVersion, boolean isMiui, boolean isWindows, boolean emulateHardware) throws Exception {
        String platformToken = isWindows ? "Windows NT 10.0; Win64; x64" : "X11; Linux x86_64";
        assumeTrue(WebViewFeature.isFeatureSupported(WebViewFeature.USER_AGENT_METADATA));
        assertTrue("Updated WebView supports desktop form factors", WebViewFeature.isFeatureSupported(WebViewFeature.USER_AGENT_METADATA_FORM_FACTORS));
        Instrumentation instrumentation = InstrumentationRegistry.getInstrumentation();
        ServerSocket server = new ServerSocket(0);
        AtomicReference<Map<String, String>> headers = new AtomicReference<>();
        AtomicReference<Throwable> serverFailure = new AtomicReference<>();
        CountDownLatch served = new CountDownLatch(1);
        CountDownLatch loaded = new CountDownLatch(1);
        AtomicReference<WebView> view = new AtomicReference<>();
        AtomicReference<String> userAgent = new AtomicReference<>();
        CountDownLatch entropyReceived = new CountDownLatch(1);
        AtomicReference<String> entropy = new AtomicReference<>();
        Thread worker = new Thread(() -> {
            try (Socket socket = server.accept()) {
                BufferedReader reader = new BufferedReader(new InputStreamReader(socket.getInputStream(), StandardCharsets.UTF_8));
                reader.readLine();
                Map<String, String> received = new HashMap<>();
                String line;
                while ((line = reader.readLine()) != null && !line.isEmpty()) {
                    int colon = line.indexOf(':');
                    if (colon > 0) received.put(line.substring(0, colon).toLowerCase(Locale.ROOT), line.substring(colon + 1).trim());
                }
                headers.set(received);
                byte[] body = ("<!doctype html><meta name='viewport' content='width=device-width,initial-scale=1,maximum-scale=1,user-scalable=no'>" +
                    "<script>window.firstDesktopMetrics={width:innerWidth,dpr:devicePixelRatio,screenWidth:screen.width,touch:navigator.maxTouchPoints,cpu:navigator.hardwareConcurrency,memory:navigator.deviceMemory};</script>" +
                    "<title>Desktop identity test</title><p>Local fixture</p><iframe srcdoc=\"<script>window.firstPixel={cpu:navigator.hardwareConcurrency,memory:navigator.deviceMemory,touch:navigator.maxTouchPoints};</script>\"></iframe>" +
                    "<script>document.querySelector('meta').content='width=device-width,initial-scale=1';" +
                    "const replacement=document.createElement('meta');replacement.name='viewport';" +
                    "replacement.content='width=device-width,maximum-scale=1,user-scalable=no';" +
                    "document.querySelector('meta').replaceWith(replacement);</script>").getBytes(StandardCharsets.UTF_8);
                socket.getOutputStream().write(("HTTP/1.1 200 OK\r\nContent-Type: text/html; charset=utf-8\r\nContent-Length: " + body.length + "\r\nConnection: close\r\n\r\n").getBytes(StandardCharsets.UTF_8));
                socket.getOutputStream().write(body);
            } catch (Throwable error) {
                serverFailure.set(error);
            } finally {
                served.countDown();
            }
        });
        worker.start();
        try {
            instrumentation.runOnMainSync(() -> {
                WebView webView = new WebView(activity.getActivity());
                view.set(webView);
                webView.getSettings().setJavaScriptEnabled(true);
                webView.addJavascriptInterface(new Object() {
                    @JavascriptInterface public void receive(String json) {
                        entropy.set(json);
                        entropyReceived.countDown();
                    }
                }, "IdentityTest");
                activity.getActivity().addContentView(webView, new ViewGroup.LayoutParams(-1, -1));
                webView.setWebViewClient(new WebViewClient() {
                    @Override public void onPageFinished(WebView webView, String url) { loaded.countDown(); }
                });
                if (configuredAgent != null) webView.getSettings().setUserAgentString(configuredAgent);
                if (requestedFullVersion != null) {
                    userAgent.set(DesktopChromeIdentity.INSTANCE.configure(webView,
                        isMiui ? MIUI_AGENT : "Mozilla/5.0 (" + platformToken + ") AppleWebKit/537.36 " +
                        "(KHTML, like Gecko) Chrome/" + requestedFullVersion.split("\\.")[0] +
                        ".0.0.0 Safari/537.36", requestedFullVersion));
                } else {
                    userAgent.set(DesktopChromeIdentity.INSTANCE.configure(webView, null, null, emulateHardware));
                }
                webView.loadUrl("http://127.0.0.1:" + server.getLocalPort() + "/");
            });
            assertTrue("HTTP fixture served", served.await(10, TimeUnit.SECONDS));
            assertNull(serverFailure.get());
            assertTrue("Page loaded", loaded.await(10, TimeUnit.SECONDS));
            Map<String, String> request = headers.get();
            Matcher nativeVersion = Pattern.compile("Chrome/(\\d+(?:\\.\\d+){3})")
                .matcher(WebSettings.getDefaultUserAgent(activity.getActivity()));
            assertTrue(nativeVersion.find());
            String expectedVersion = requestedFullVersion != null ? requestedFullVersion : nativeVersion.group(1);
            assertEquals(isMiui ? MIUI_AGENT : "Mozilla/5.0 (" + platformToken + ") AppleWebKit/537.36 " +
                "(KHTML, like Gecko) Chrome/" + expectedVersion.split("\\.")[0] +
                ".0.0.0 Safari/537.36", userAgent.get());
            assertEquals(userAgent.get(), request.get("user-agent"));
            assertEquals("?0", request.get("sec-ch-ua-mobile"));
            assertEquals(isWindows ? "\"Windows\"" : "\"Linux\"", request.get("sec-ch-ua-platform"));
            assertTrue(request.get("sec-ch-ua").contains(isMiui ? "\"Miui Browser\"" : "\"Google Chrome\""));
            assertFalse(request.get("sec-ch-ua").contains("Android WebView"));
            if (WebViewFeature.isFeatureSupported(WebViewFeature.CUSTOM_REQUEST_HEADERS)
                    && WebViewFeature.isFeatureSupported(WebViewFeature.MULTI_PROFILE)) {
                assertEquals("Package is replaced, but the header remains present", "XMLHttpRequest", request.get("x-requested-with"));
            }
            Matcher major = Pattern.compile("Chrome/(\\d+)\\.").matcher(userAgent.get());
            assertTrue(major.find());
            assertTrue(request.get("sec-ch-ua").contains("v=\"" + major.group(1) + "\""));

            CountDownLatch evaluated = new CountDownLatch(1);
            AtomicReference<String> snapshot = new AtomicReference<>();
            instrumentation.runOnMainSync(() -> view.get().evaluateJavascript(
                "JSON.stringify({ua:navigator.userAgent,platform:navigator.platform,data:navigator.userAgentData.toJSON(),cpu:navigator.hardwareConcurrency,memory:navigator.deviceMemory,frame:document.querySelector('iframe').contentWindow.firstPixel,touch:navigator.maxTouchPoints,width:innerWidth,dpr:devicePixelRatio,scale:visualViewport.scale,visualWidth:visualViewport.width,first:firstDesktopMetrics,desktopLayout:matchMedia('(min-width: 900px)').matches,viewport:document.querySelector('meta[name=viewport]').content})",
                result -> { snapshot.set(result); evaluated.countDown(); }));
            assertTrue(evaluated.await(5, TimeUnit.SECONDS));
            JSONObject identity = new JSONObject(new JSONArray("[" + snapshot.get() + "]").getString(0));
            assertEquals(userAgent.get(), identity.getString("ua"));
            assertEquals(isWindows ? "Win32" : "Linux armv8l", identity.getString("platform"));
            assertEquals(isWindows ? "Windows" : "Linux", identity.getJSONObject("data").getString("platform"));
            assertFalse(identity.getJSONObject("data").getBoolean("mobile"));
            if (emulateHardware) {
                assertEquals("Pixel CPU cores", 8, identity.getInt("cpu"));
                assertEquals("Android Chrome memory bucket", 8, identity.getInt("memory"));
            } else {
                assertTrue("Native CPU remains available", identity.getInt("cpu") > 0);
                assertTrue("Native memory remains available", identity.getInt("memory") > 0);
            }
            assertTrue("Native phone touch points are retained", identity.getInt("touch") > 0);
            JSONObject frame = identity.getJSONObject("frame");
            assertEquals("Iframe hardware matches the page", identity.getInt("cpu"), frame.getInt("cpu"));
            assertEquals(identity.getInt("memory"), frame.getInt("memory"));
            assertEquals(identity.getInt("touch"), frame.getInt("touch"));
            double density = activity.getActivity().getResources().getDisplayMetrics().density;
            assertEquals("Phone DPR is native, not a fixed desktop value", density, identity.getDouble("dpr"), 0.01);
            JSONObject first = identity.getJSONObject("first");
            assertTrue("First website script already uses desktop layout", first.getInt("width") >= 980);
            assertEquals("First script has native DPR", density, first.getDouble("dpr"), 0.01);
            assertEquals("First script sees consistent CPU", identity.getInt("cpu"), first.getInt("cpu"));
            assertEquals("First script sees consistent memory", identity.getInt("memory"), first.getInt("memory"));
            assertEquals("First script retains native touch", identity.getInt("touch"), first.getInt("touch"));
            double viewWidth = view.get().getWidth() / density;
            assertTrue("Initial overview shows the whole desktop viewport", identity.getDouble("visualWidth") >= 978);
            assertEquals("Initial scale fits desktop layout to phone width", viewWidth / identity.getDouble("width"),
                identity.getDouble("scale"), 0.02);
            assertEquals("Overview fits the phone's actual width", viewWidth,
                identity.getDouble("visualWidth") * identity.getDouble("scale"), 2.0);
            assertTrue("Desktop viewport", identity.getInt("width") >= 980);
            assertTrue("Mobile viewport cannot force responsive phone layout", identity.getBoolean("desktopLayout"));
            assertEquals("Replaced viewport allows zoom", "width=980", identity.getString("viewport"));
            instrumentation.runOnMainSync(() -> view.get().evaluateJavascript(
                "navigator.userAgentData.getHighEntropyValues(['architecture','bitness','model','platformVersion','fullVersionList','formFactors']).then(v=>IdentityTest.receive(JSON.stringify(v)))", null));
            assertTrue("High entropy Client Hints received", entropyReceived.await(5, TimeUnit.SECONDS));
            JSONObject hints = new JSONObject(entropy.get());
            assertEquals("x86", hints.getString("architecture"));
            assertEquals("64", hints.getString("bitness"));
            assertEquals("", hints.getString("model"));
            assertEquals(isWindows ? "10.0.0" : "", hints.getString("platformVersion"));
            assertTrue("Full Client Hints version matches the requested identity",
                hints.getJSONArray("fullVersionList").toString().contains(expectedVersion));
            assertEquals("[\"Desktop\"]", hints.getJSONArray("formFactors").toString());
            assertFalse(hints.getJSONArray("fullVersionList").toString().contains("Android WebView"));

            // A site removing viewport directives must not restore phone layout.
            CountDownLatch removed = new CountDownLatch(1);
            instrumentation.runOnMainSync(() -> view.get().evaluateJavascript(
                "document.querySelectorAll('meta[name=viewport]').forEach(meta=>meta.remove());", result -> removed.countDown()));
            assertTrue(removed.await(5, TimeUnit.SECONDS));
            CountDownLatch checked = new CountDownLatch(1);
            AtomicReference<String> repaired = new AtomicReference<>();
            instrumentation.runOnMainSync(() -> view.get().evaluateJavascript(
                "JSON.stringify({width:innerWidth,viewport:document.querySelector('meta[name=viewport]').content})",
                result -> { repaired.set(result); checked.countDown(); }));
            assertTrue(checked.await(5, TimeUnit.SECONDS));
            JSONObject restored = new JSONObject(new JSONArray("[" + repaired.get() + "]").getString(0));
            assertEquals("width=980", restored.getString("viewport"));
            assertTrue(restored.getInt("width") >= 980);
        } finally {
            server.close();
            worker.join(1000);
            instrumentation.runOnMainSync(() -> {
                WebView webView = view.get();
                if (webView != null) {
                    if (webView.getParent() instanceof ViewGroup) ((ViewGroup) webView.getParent()).removeView(webView);
                    webView.destroy();
                }
            });
        }
    }
}
