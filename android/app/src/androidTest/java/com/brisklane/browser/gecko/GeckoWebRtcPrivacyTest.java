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
public class GeckoWebRtcPrivacyTest {
    // WebRTC stays available like on the reference PC, but ICE must never
    // produce a candidate: no Local IP, and no STUN/UDP outside the proxy.
    // A same-origin about:blank frame gets no document-start script, so it
    // is checked too.
    private static final String PAGE = "<!doctype html><body><script>"
        + "const gather=(w)=>new Promise((done)=>{const out={api:typeof w.RTCPeerConnection,candidates:[]};"
        + "try{const pc=new w.RTCPeerConnection({iceServers:[{urls:'stun:stun.l.google.com:19302'}]});"
        + "pc.createDataChannel('x');pc.onicecandidate=(e)=>{if(e.candidate)out.candidates.push(e.candidate.candidate)};"
        + "pc.createOffer().then((o)=>pc.setLocalDescription(o));"
        + "setTimeout(()=>{out.sdp=pc.localDescription?pc.localDescription.sdp:'';pc.close();done(out)},4000)}"
        + "catch(e){out.error=String(e);done(out)}});"
        + "const f=document.createElement('iframe');document.body.appendChild(f);"
        + "Promise.all([gather(window),gather(f.contentWindow)]).then((r)=>{"
        + "window.rtcRead=JSON.stringify({top:r[0],frame:r[1]});location.hash='done'});"
        + "</script>";

    @Test public void iceGathersNoAddressInPageOrDynamicFrame() throws Exception {
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
                        boolean worker = false;
                        String body = path.equals("/") ? PAGE : "";
                        byte[] bytes = body.getBytes(StandardCharsets.UTF_8);
                        String response = "HTTP/1.1 200 OK\r\nContent-Type: "
                            + (worker ? "application/javascript" : "text/html")
                            + "; charset=utf-8\r\n"
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
                args.put("contextId", "webrtc-privacy-test");
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
                args.put("source", "window.wrappedJSObject.rtcRead");
                view.get().onMethodCall(new MethodCall("evaluateJavascript", args),
                    new Reply(value, evaluated));
            });
            assertTrue("Readout timed out", evaluated.await(10, TimeUnit.SECONDS));
            JSONObject result = new JSONObject(String.valueOf(value.get()));
            java.util.regex.Pattern address = java.util.regex.Pattern.compile(
                "\\b\\d{1,3}(\\.\\d{1,3}){3}\\b|[0-9a-f]{1,4}(:[0-9a-f]{0,4}){2,7}|\\.local\\b",
                java.util.regex.Pattern.CASE_INSENSITIVE);
            for (String key : new String[]{"top", "frame"}) {
                JSONObject readout = result.getJSONObject(key);
                assertEquals(key, "function", readout.getString("api"));
                assertFalse(key + " " + readout, readout.has("error"));
                assertEquals(key + " candidates " + readout.getJSONArray("candidates"),
                    0, readout.getJSONArray("candidates").length());
                for (String line : readout.getString("sdp").split("\\r?\\n")) {
                    assertFalse(key + " SDP candidate: " + line, line.startsWith("a=candidate"));
                    if (line.startsWith("c=") || line.startsWith("a=rtcp:")) continue;
                    assertFalse(key + " SDP address: " + line, address.matcher(line).find()
                        && !line.startsWith("o=") && !line.startsWith("a=fingerprint"));
                }
            }
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
