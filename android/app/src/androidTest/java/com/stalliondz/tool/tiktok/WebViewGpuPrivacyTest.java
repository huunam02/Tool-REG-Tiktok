package com.stalliondz.tool.tiktok;

import android.webkit.WebView;
import android.webkit.JavascriptInterface;
import android.view.ViewGroup;
import androidx.test.ext.junit.runners.AndroidJUnit4;
import androidx.test.platform.app.InstrumentationRegistry;
import androidx.test.rule.ActivityTestRule;
import androidx.webkit.WebViewCompat;
import androidx.webkit.WebViewFeature;
import java.io.BufferedReader;
import java.io.InputStreamReader;
import java.nio.charset.StandardCharsets;
import java.util.Collections;
import java.util.concurrent.CountDownLatch;
import java.util.concurrent.TimeUnit;
import java.util.concurrent.atomic.AtomicReference;
import org.json.JSONArray;
import org.json.JSONObject;
import org.junit.Test;
import org.junit.runner.RunWith;
import static org.junit.Assert.*;
import static org.junit.Assume.assumeTrue;

@SuppressWarnings("deprecation")
@RunWith(AndroidJUnit4.class)
public class WebViewGpuPrivacyTest {
    @org.junit.Rule public ActivityTestRule<MainActivity> activity = new ActivityTestRule<>(MainActivity.class);

    private String readPrivacyScript(String filename) throws Exception {
        StringBuilder script = new StringBuilder();
        try (BufferedReader reader = new BufferedReader(new InputStreamReader(
                InstrumentationRegistry.getInstrumentation().getContext().getAssets().open(filename),
                StandardCharsets.UTF_8))) {
            String line;
            while ((line = reader.readLine()) != null) script.append(line).append('\n');
        }
        return script.toString();
    }

    @Test public void firstPageAndFrameHideGpuAndWebRtcWhileWebGlStillRenders() throws Exception {
        assumeTrue(WebViewFeature.isFeatureSupported(WebViewFeature.DOCUMENT_START_SCRIPT));
        String script = readPrivacyScript("hide_gpu_info.js") + readPrivacyScript("disable_webrtc.js");
        String probe = "function probe(){const results=[];" +
            "for(const type of ['webgl','webgl2']){" +
            "const canvas=document.createElement('canvas');canvas.width=2;canvas.height=2;" +
            "const gl=canvas.getContext(type);if(!gl)continue;" +
            "const debug=gl.getExtension('WEBGL_debug_renderer_info');" +
            "const vendor=gl.getParameter(gl.VENDOR),renderer=gl.getParameter(gl.RENDERER);" +
            "const unmasked=gl.getParameter(0x9246),error=gl.getError();" +
            "gl.clearColor(1,0,0,1);gl.clear(gl.COLOR_BUFFER_BIT);" +
            "const pixels=new Uint8Array(4);gl.readPixels(0,0,1,1,gl.RGBA,gl.UNSIGNED_BYTE,pixels);" +
            "results.push({type,debug,vendor,renderer,unmasked,error,pixels:Array.from(pixels)," +
            "debugListed:gl.getSupportedExtensions().includes('WEBGL_debug_renderer_info')});}" +
            "return {webgpu:typeof navigator.gpu,rtc:typeof RTCPeerConnection," +
            "webkitRtc:typeof webkitRTCPeerConnection,mozRtc:typeof mozRTCPeerConnection," +
            "iceGatherer:typeof RTCIceGatherer,iceTransport:typeof RTCIceTransport,results};}";
        String html = "<!doctype html><script>" + probe +
            "const first=probe();function frameReady(frame){GpuPrivacyTest.receive(JSON.stringify({first,frame}));}" +
            "</script><iframe srcdoc=\"<script>" + probe +
            "parent.frameReady(probe());</script>\"></iframe>";
        AtomicReference<WebView> view = new AtomicReference<>();
        AtomicReference<String> snapshot = new AtomicReference<>();
        CountDownLatch received = new CountDownLatch(1);
        try {
            InstrumentationRegistry.getInstrumentation().runOnMainSync(() -> {
                WebView webView = new WebView(activity.getActivity());
                view.set(webView);
                webView.getSettings().setJavaScriptEnabled(true);
                activity.getActivity().addContentView(webView, new ViewGroup.LayoutParams(-1, -1));
                webView.addJavascriptInterface(new Object() {
                    @JavascriptInterface public void receive(String value) {
                        snapshot.set(value); received.countDown();
                    }
                }, "GpuPrivacyTest");
                WebViewCompat.addDocumentStartJavaScript(webView, script, Collections.singleton("*"));
                webView.loadDataWithBaseURL("https://privacy.test/", html, "text/html", "UTF-8", null);
            });
            assertTrue("Parent and frame GPU probes completed", received.await(15, TimeUnit.SECONDS));
            JSONObject captured = new JSONObject(snapshot.get());
            for (String scope : new String[]{"first", "frame"}) {
                JSONObject document = captured.getJSONObject(scope);
                assertEquals("undefined", document.getString("webgpu"));
                for (String api : new String[]{"rtc", "webkitRtc", "mozRtc", "iceGatherer", "iceTransport"}) {
                    assertEquals("WebRTC is unavailable in " + scope, "undefined", document.getString(api));
                }
                JSONArray results = document.getJSONArray("results");
                assertTrue("Emulator provides a working WebGL context", results.length() > 0);
                for (int i = 0; i < results.length(); i++) {
                    JSONObject gl = results.getJSONObject(i);
                    assertTrue(gl.isNull("debug"));
                    assertFalse(gl.getBoolean("debugListed"));
                    assertEquals("", gl.getString("vendor"));
                    assertEquals("", gl.getString("renderer"));
                    assertTrue(gl.isNull("unmasked"));
                    assertEquals(0x0500, gl.getInt("error"));
                    assertEquals("[255,0,0,255]", gl.getJSONArray("pixels").toString());
                }
            }
            assertFalse(snapshot.get().contains("Android Emulator"));
            assertFalse(snapshot.get().contains("Apple M1"));
        } finally {
            InstrumentationRegistry.getInstrumentation().runOnMainSync(() -> {
                WebView webView = view.get();
                if (webView != null) {
                    if (webView.getParent() instanceof ViewGroup) ((ViewGroup) webView.getParent()).removeView(webView);
                    webView.destroy();
                }
            });
        }
    }
}
