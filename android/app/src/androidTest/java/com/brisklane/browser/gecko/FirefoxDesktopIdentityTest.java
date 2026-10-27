package com.brisklane.browser.gecko;

import androidx.test.ext.junit.runners.AndroidJUnit4;
import androidx.test.platform.app.InstrumentationRegistry;
import io.flutter.plugin.common.BinaryMessenger;
import io.flutter.plugin.common.MethodCall;
import io.flutter.plugin.common.MethodChannel;
import io.flutter.plugin.common.StandardMethodCodec;
import java.net.ServerSocket;
import java.net.Socket;
import java.nio.ByteBuffer;
import java.nio.charset.StandardCharsets;
import java.util.HashMap;
import java.util.Map;
import java.util.concurrent.ConcurrentHashMap;
import java.util.concurrent.CountDownLatch;
import java.util.concurrent.TimeUnit;
import java.util.concurrent.atomic.AtomicReference;
import org.json.JSONObject;
import org.junit.Test;
import org.junit.runner.RunWith;
import static org.junit.Assert.*;

@RunWith(AndroidJUnit4.class)
public class FirefoxDesktopIdentityTest {
    // Capture values in the first site script, before a later eval can repair
    // them. A strict CSP also checks that the extension needs no inline eval.
    private static final String SNAPSHOT = "JSON.stringify({ua:navigator.userAgent,"
        + "platform:navigator.platform,oscpu:navigator.oscpu,languages:navigator.languages,"
        + "cpu:navigator.hardwareConcurrency,touch:navigator.maxTouchPoints,"
        + "touchEvent:typeof TouchEvent,onTouch:'ontouchstart' in window,"
        + "orientation:'orientation' in window,screenOrientation:screen.orientation.type,"
        + "screen:[screen.width,screen.height,screen.colorDepth],"
        + "outer:[outerWidth,outerHeight],dpr:devicePixelRatio,"
        + "gpu:(()=>{const g=document.createElement('canvas').getContext('webgl');"
        + "if(!g)return null;const e=g.getExtension('WEBGL_debug_renderer_info');"
        + "return e?[g.getParameter(e.UNMASKED_VENDOR_WEBGL),"
        + "g.getParameter(e.UNMASKED_RENDERER_WEBGL)]:null})()})";

    @Test public void firstScriptFramesAndRequestHeadersUseWindowsFirefox() throws Exception {
        CountDownLatch loaded = new CountDownLatch(1);
        AtomicReference<GeckoPlatformView> view = new AtomicReference<>();
        Map<String, String> requests = new ConcurrentHashMap<>();
        try (ServerSocket server = new ServerSocket(0)) {
            Thread http = new Thread(() -> {
                while (!server.isClosed()) {
                    try (Socket socket = server.accept()) {
                        var reader = new java.io.BufferedReader(new java.io.InputStreamReader(
                            socket.getInputStream(), StandardCharsets.UTF_8));
                        String first = reader.readLine();
                        if (first == null) continue;
                        String path = first.split(" ")[1];
                        StringBuilder headers = new StringBuilder();
                        String line;
                        while ((line = reader.readLine()) != null && !line.isEmpty()) {
                            headers.append(line).append("\n");
                        }
                        requests.put(path, headers.toString());
                        boolean worker = path.equals("/worker.js");
                        String body = worker
                            ? "postMessage(JSON.stringify({ua:navigator.userAgent,"
                                + "platform:navigator.platform,languages:navigator.languages,"
                                + "cpu:navigator.hardwareConcurrency}));"
                            : "<!doctype html><script nonce='probe'>window.firstRead=" + SNAPSHOT
                                + ";</script>" + (path.equals("/frame") ? ""
                                : "<iframe src='/frame'></iframe><script nonce='probe'>"
                                    + "const worker=new Worker('/worker.js');"
                                    + "worker.onmessage=e=>{window.workerRead=e.data;"
                                    + "if(document.readyState==='complete')location.hash='done';"
                                    + "else window.addEventListener('load',()=>location.hash='done');"
                                    + "worker.terminate()};</script>");
                        byte[] bytes = body.getBytes(StandardCharsets.UTF_8);
                        String response = "HTTP/1.1 200 OK\r\nContent-Type: "
                            + (worker ? "application/javascript" : "text/html")
                            + "; charset=utf-8\r\nContent-Security-Policy: "
                            + "script-src 'nonce-probe' 'self'; worker-src 'self'\r\n"
                            + "Content-Length: " + bytes.length + "\r\nConnection: close\r\n\r\n";
                        socket.getOutputStream().write(response.getBytes(StandardCharsets.UTF_8));
                        socket.getOutputStream().write(bytes);
                    } catch (java.io.IOException error) {
                        if (!server.isClosed()) throw new RuntimeException(error);
                    }
                }
            }, "desktop-identity-http");
            http.setDaemon(true);
            http.start();

            BinaryMessenger messenger = new BinaryMessenger() {
                @Override public void send(String channel, ByteBuffer message) {
                    send(channel, message, null);
                }
                @Override public void send(String channel, ByteBuffer message, BinaryReply reply) {
                    message.flip();
                    MethodCall call = StandardMethodCodec.INSTANCE.decodeMethodCall(message);
                    if (call.method.equals("event")) {
                        Map<?, ?> event = (Map<?, ?>) call.arguments;
                        if (String.valueOf(event.get("url")).endsWith("#done")) loaded.countDown();
                    }
                    if (reply != null) reply.reply(null);
                }
                @Override public void setMessageHandler(String channel, BinaryMessageHandler handler) {}
            };
            InstrumentationRegistry.getInstrumentation().runOnMainSync(() -> {
                Map<String, Object> args = new HashMap<>();
                args.put("initialUrl", "http://127.0.0.1:" + server.getLocalPort() + "/");
                args.put("contextId", "desktop-identity-test");
                GeckoPlatformView platform = new GeckoPlatformView(
                    InstrumentationRegistry.getInstrumentation().getTargetContext(), messenger, 9042, args);
                view.set(platform);
                platform.onMethodCall(new MethodCall("start", null), new Reply(null, null));
            });
            assertTrue("Test page did not finish loading", loaded.await(45, TimeUnit.SECONDS));
            CountDownLatch evaluated = new CountDownLatch(1);
            AtomicReference<Object> value = new AtomicReference<>();
            InstrumentationRegistry.getInstrumentation().runOnMainSync(() -> {
                Map<String, Object> args = new HashMap<>();
                args.put("source", "JSON.stringify({top:JSON.parse(window.wrappedJSObject.firstRead),"
                    + "frame:JSON.parse(window.wrappedJSObject.frames[0].firstRead),"
                    + "worker:JSON.parse(window.wrappedJSObject.workerRead)})");
                view.get().onMethodCall(new MethodCall("evaluateJavascript", args),
                    new Reply(value, evaluated));
            });
            assertTrue("Readout timed out", evaluated.await(10, TimeUnit.SECONDS));
            JSONObject result = new JSONObject(String.valueOf(value.get()));
            for (String key : new String[]{"top", "frame"}) {
                JSONObject readout = result.getJSONObject(key);
                assertEquals(FirefoxDesktopIdentity.USER_AGENT, readout.getString("ua"));
                assertEquals("Win32", readout.getString("platform"));
                assertEquals("Windows NT 10.0; Win64; x64", readout.getString("oscpu"));
                assertEquals("en-US", readout.getJSONArray("languages").getString(0));
                // Workers cannot be patched, so the window keeps the native count.
                assertEquals(result.getJSONObject("worker").getInt("cpu"), readout.getInt("cpu"));
                assertEquals("undefined", readout.getString("touchEvent"));
                assertFalse(readout.getBoolean("onTouch"));
                assertFalse(readout.getBoolean("orientation"));
                assertEquals("landscape-primary", readout.getString("screenOrientation"));
                assertEquals(0, readout.getInt("touch"));
                assertEquals("[1536,864,24]", readout.getJSONArray("screen").toString());
                assertEquals("[1550,830]", readout.getJSONArray("outer").toString());
                assertEquals(1.0, readout.getDouble("dpr"), 0.0);
                assertEquals(FirefoxDesktopIdentity.WEBGL_VENDOR, readout.getJSONArray("gpu").getString(0));
                assertEquals(FirefoxDesktopIdentity.WEBGL_RENDERER, readout.getJSONArray("gpu").getString(1));
            }
            assertEquals(FirefoxDesktopIdentity.USER_AGENT, result.getJSONObject("worker").getString("ua"));
            assertEquals("Win32", result.getJSONObject("worker").getString("platform"));
            assertTrue(requests.get("/").contains(FirefoxDesktopIdentity.USER_AGENT));
            assertTrue(requests.get("/").toLowerCase().contains("accept-language: en-us"));
        } finally {
            if (view.get() != null) {
                InstrumentationRegistry.getInstrumentation().runOnMainSync(() -> view.get().dispose());
            }
        }
    }

    private static class Reply implements MethodChannel.Result {
        private final AtomicReference<Object> value;
        private final CountDownLatch done;
        Reply(AtomicReference<Object> value, CountDownLatch done) { this.value = value; this.done = done; }
        @Override public void success(Object result) {
            if (value != null) value.set(result);
            if (done != null) done.countDown();
        }
        @Override public void error(String code, String message, Object details) {
            success("ERROR " + code + ": " + message);
        }
        @Override public void notImplemented() { error("not_implemented", "", null); }
    }
}
