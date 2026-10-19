package com.brisklane.browser;

import android.util.Log;
import android.webkit.WebView;
import androidx.test.ext.junit.runners.AndroidJUnit4;
import androidx.test.platform.app.InstrumentationRegistry;
import androidx.test.rule.ActivityTestRule;
import androidx.webkit.WebViewFeature;
import com.stalliondz.tool.tiktok.SignupFixtureActivity;
import java.io.BufferedReader;
import java.io.InputStreamReader;
import java.net.ServerSocket;
import java.net.Socket;
import java.nio.charset.StandardCharsets;
import java.util.Arrays;
import java.util.HashMap;
import java.util.Map;
import java.util.concurrent.ConcurrentHashMap;
import java.util.concurrent.CountDownLatch;
import java.util.concurrent.TimeUnit;
import java.util.concurrent.atomic.AtomicReference;
import org.junit.Rule;
import org.junit.Test;
import org.junit.runner.RunWith;
import static org.junit.Assert.*;
import static org.junit.Assume.assumeTrue;

/** Measures bytes received by a local HTTP server; no external sites or accounts. */
@RunWith(AndroidJUnit4.class)
public class WebViewHeaderPrivacyTest {
    @Rule public ActivityTestRule<SignupFixtureActivity> activity =
        new ActivityTestRule<>(SignupFixtureActivity.class);

    @Test public void masksPackageForNavigationPostFramesRedirectsAndServiceWorkers() throws Exception {
        assumeTrue(WebViewFeature.isFeatureSupported(WebViewFeature.CUSTOM_REQUEST_HEADERS));
        assumeTrue(WebViewFeature.isFeatureSupported(WebViewFeature.MULTI_PROFILE));
        Map<String, Request> requests = new ConcurrentHashMap<>();
        AtomicReference<Throwable> failure = new AtomicReference<>();
        AtomicReference<WebView> web = new AtomicReference<>();
        String[] expected = {"GET /", "GET /get", "POST /post", "GET /frame",
            "GET /redirect", "GET /redirected", "GET /sw.js", "GET /worker", "POST /cors"};
        CountDownLatch received = new CountDownLatch(expected.length);
        try (ServerSocket server = new ServerSocket(0)) {
            Thread worker = new Thread(() -> {
                while (!server.isClosed()) {
                    try (Socket socket = server.accept()) {
                        socket.setSoTimeout(5000);
                        BufferedReader reader = new BufferedReader(new InputStreamReader(
                            socket.getInputStream(), StandardCharsets.UTF_8));
                        String first = reader.readLine();
                        if (first == null) continue;
                        String key = first.substring(0, first.lastIndexOf(' '));
                        Map<String, String> headers = new HashMap<>();
                        String line;
                        while ((line = reader.readLine()) != null && !line.isEmpty()) {
                            int colon = line.indexOf(':');
                            if (colon > 0) headers.put(line.substring(0, colon).toLowerCase(java.util.Locale.ROOT),
                                line.substring(colon + 1).trim());
                        }
                        int length = Integer.parseInt(headers.getOrDefault("content-length", "0"));
                        char[] body = new char[length];
                        int offset = 0;
                        while (offset < length) {
                            int read = reader.read(body, offset, length - offset);
                            if (read < 0) break;
                            offset += read;
                        }
                        Request old = requests.put(key, new Request(headers, new String(body)));
                        if (old == null && Arrays.asList(expected).contains(key)) received.countDown();
                        String content = "ok";
                        String type = "text/html";
                        String status = "200 OK";
                        String extra = "Access-Control-Allow-Origin: *\r\n"
                            + "Access-Control-Allow-Methods: GET,POST,OPTIONS\r\n"
                            + "Access-Control-Allow-Headers: X-Probe\r\n";
                        if (key.equals("GET /")) {
                            extra += "Set-Cookie: header_probe=kept; Path=/; SameSite=Lax\r\n";
                            content = "<html><body><iframe src='/frame'></iframe><script>"
                                + "fetch('/get');fetch('/post',{method:'POST',body:'post-body-kept'});"
                                + "fetch('/redirect');"
                                + "fetch('http://localhost:" + server.getLocalPort()
                                + "/cors',{method:'POST',headers:{'X-Probe':'1'},body:'cors-body-kept'});"
                                + "navigator.serviceWorker.register('/sw.js');</script></body></html>";
                        } else if (key.equals("GET /sw.js")) {
                            type = "application/javascript";
                            content = "self.addEventListener('install',e=>self.skipWaiting());"
                                + "self.addEventListener('activate',e=>e.waitUntil("
                                + "clients.claim().then(()=>fetch('/worker'))));";
                        } else if (key.equals("GET /redirect")) {
                            status = "302 Found";
                            extra += "Location: /redirected\r\n";
                        }
                        byte[] bytes = content.getBytes(StandardCharsets.UTF_8);
                        socket.getOutputStream().write(("HTTP/1.1 " + status + "\r\n" + extra
                            + "Content-Type: " + type + "\r\nContent-Length: " + bytes.length
                            + "\r\nConnection: close\r\n\r\n").getBytes(StandardCharsets.UTF_8));
                        socket.getOutputStream().write(bytes);
                    } catch (Throwable error) {
                        if (!server.isClosed()) failure.compareAndSet(null, error);
                    }
                }
            }, "header-privacy-fixture");
            worker.setDaemon(true);
            worker.start();
            try {
                InstrumentationRegistry.getInstrumentation().runOnMainSync(() -> {
                    WebView view = new WebView(activity.getActivity());
                    web.set(view);
                    activity.getActivity().setContentView(view);
                    view.getSettings().setJavaScriptEnabled(true);
                    assertTrue(WebViewHeaderPrivacy.maskPackageName(view));
                    // A second configure must not append duplicate header values.
                    assertTrue(WebViewHeaderPrivacy.maskPackageName(view));
                    view.loadUrl("http://127.0.0.1:" + server.getLocalPort() + "/");
                });
                assertTrue("Missing requests: " + requests.keySet(), received.await(20, TimeUnit.SECONDS));
                assertNull("Local server error", failure.get());
                for (String key : expected) {
                    assertEquals(key + " uses the replacement header value", "XMLHttpRequest",
                        requests.get(key).headers.get("x-requested-with"));
                }
                assertEquals("post-body-kept", requests.get("POST /post").body);
                assertEquals("cors-body-kept", requests.get("POST /cors").body);
                assertTrue("Cookies still use WebView's normal network stack",
                    requests.get("GET /get").headers.getOrDefault("cookie", "").contains("header_probe=kept"));
                // Known provider limitation: custom headers do not apply to preflight.
                assertNotNull("Cross-origin POST exercised CORS preflight", requests.get("OPTIONS /cors"));
                Log.i("BrowserIdentity", "Header privacy fixture CORS OPTIONS X-Requested-With="
                    + requests.get("OPTIONS /cors").headers.get("x-requested-with"));
            } finally {
                InstrumentationRegistry.getInstrumentation().runOnMainSync(() -> {
                    if (web.get() != null) web.get().destroy();
                });
            }
        }
    }

    private static final class Request {
        final Map<String, String> headers;
        final String body;
        Request(Map<String, String> headers, String body) { this.headers = headers; this.body = body; }
    }
}
