package com.stalliondz.tool.tiktok;

import com.brisklane.browser.MainActivity;

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

    // A page can build a same-origin about:blank frame and use its fresh
    // globals before any document-start script runs there; that must not
    // yield WebRTC or any ICE candidate (Local IP) either.
    @Test public void dynamicFramesCannotGatherLocalIp() throws Exception {
        assumeTrue(WebViewFeature.isFeatureSupported(WebViewFeature.DOCUMENT_START_SCRIPT));
        String script = readPrivacyScript("disable_webrtc.js");
        String html = "<!doctype html><body><iframe></iframe><script>" +
            "window.report={};window.found=[];" +
            "const check=(name,win)=>{let PC;try{PC=win&&win.RTCPeerConnection}catch(e){}" +
            "report[name]=typeof PC;if(typeof PC==='function')found.push(PC);};" +
            "check('parser',frames[0]);</script><script>(async()=>{" +
            "const candidates=[];" +
            "const appended=document.createElement('iframe');document.body.appendChild(appended);" +
            "check('contentWindow',appended.contentWindow);" +
            "check('contentDocument',appended.contentDocument.defaultView);" +
            "document.body.append(document.createElement('iframe'));" +
            "check('frames',frames[frames.length-1]);" +
            "document.body.insertAdjacentHTML('beforeend','<iframe></iframe>');" +
            "check('html',frames[frames.length-1]);" +
            "const box=document.createElement('div');document.body.appendChild(box);" +
            "box.innerHTML='<iframe></iframe>';check('innerHTML',frames[frames.length-1]);" +
            "const inner=appended.contentDocument.createElement('iframe');" +
            "appended.contentDocument.body.appendChild(inner);check('nested',inner.contentWindow);" +
            "appended.contentDocument.write('<iframe></iframe>');" +
            "check('write',appended.contentWindow.frames[appended.contentWindow.length-1]);" +
            "let popup=null;try{popup=window.open('about:blank')}catch(e){}" +
            "report.popup=popup?(()=>{try{return typeof popup.RTCPeerConnection}catch(e){return 'blocked'}})():'undefined';" +
            "for(const PC of found){try{const pc=new PC({iceServers:[]});pc.createDataChannel('probe');" +
            "pc.onicecandidate=e=>{if(e.candidate)candidates.push(e.candidate.candidate)};" +
            "await pc.setLocalDescription(await pc.createOffer());" +
            "await new Promise(r=>setTimeout(r,2000));pc.close();}catch(e){report.error=String(e)}}" +
            "report.candidates=candidates;GpuPrivacyTest.receive(JSON.stringify(report));" +
            "})()</script></body>";
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
            assertTrue("Dynamic frame probes completed", received.await(20, TimeUnit.SECONDS));
            JSONObject report = new JSONObject(snapshot.get());
            for (String access : new String[]{"parser", "contentWindow", "contentDocument", "frames",
                    "html", "innerHTML", "nested", "write", "popup"}) {
                assertEquals("WebRTC is disabled via " + access + " in " + report,
                    "undefined", report.getString(access));
            }
            assertEquals("No ICE candidate in " + report, 0, report.getJSONArray("candidates").length());
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

    // WebRTC is always blocked, so no page or frame can read any Local IP.
    @Test public void firstPageAndFrameHideLocalIpWhileWebGlStillRenders() throws Exception {
        assumeTrue(WebViewFeature.isFeatureSupported(WebViewFeature.DOCUMENT_START_SCRIPT));
        String script = readPrivacyScript("pixel_gpu_info.js") +
            readPrivacyScript("disable_webrtc.js");
        String probe = "async function probe(){const results=[];" +
            "for(const type of ['webgl','webgl2']){" +
            "const canvas=document.createElement('canvas');canvas.width=2;canvas.height=2;" +
            "const gl=canvas.getContext(type);if(!gl)continue;" +
            "const debug=gl.getExtension('WEBGL_debug_renderer_info');" +
            "const vendor=gl.getParameter(gl.VENDOR),renderer=gl.getParameter(gl.RENDERER);" +
            "const unmasked=gl.getParameter(0x9246),error=gl.getError();" +
            "gl.clearColor(1,0,0,1);gl.clear(gl.COLOR_BUFFER_BIT);" +
            "const pixels=new Uint8Array(4);gl.readPixels(0,0,1,1,gl.RGBA,gl.UNSIGNED_BYTE,pixels);" +
            "const unmaskedVendor=debug?gl.getParameter(debug.UNMASKED_VENDOR_WEBGL):null;" +
            "results.push({type,debug:!!debug,vendor,renderer,unmasked,unmaskedVendor,error,pixels:Array.from(pixels)," +
            "debugListed:gl.getSupportedExtensions().includes('WEBGL_debug_renderer_info')});}" +
            "return {webgpu:typeof navigator.gpu,rtc:typeof RTCPeerConnection," +
            "webkitRtc:typeof webkitRTCPeerConnection,mozRtc:typeof mozRTCPeerConnection," +
            "iceGatherer:typeof RTCIceGatherer,iceTransport:typeof RTCIceTransport,results};}";
        String html = "<!doctype html><script>" + probe +
            "const first=probe();function frameReady(frame){first.then(first=>GpuPrivacyTest.receive(JSON.stringify({first,frame})));}" +
            "</script><iframe srcdoc=\"<script>" + probe +
            "probe().then(frame=>parent.frameReady(frame));</script>\"></iframe>";
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
                for (String api : new String[]{"rtc", "webkitRtc", "mozRtc"}) {
                    assertEquals("WebRTC is disabled in " + scope, "undefined", document.getString(api));
                }
                for (String api : new String[]{"iceGatherer", "iceTransport"}) {
                    assertEquals("Native ICE is disabled", "undefined", document.getString(api));
                }
                JSONArray results = document.getJSONArray("results");
                assertTrue("Emulator provides a working WebGL context", results.length() > 0);
                for (int i = 0; i < results.length(); i++) {
                    JSONObject gl = results.getJSONObject(i);
                    assertTrue("Native renderer extension is available", gl.getBoolean("debug"));
                    assertTrue(gl.getBoolean("debugListed"));
                    assertEquals("WebKit", gl.getString("vendor"));
                    assertEquals("WebKit WebGL", gl.getString("renderer"));
                    assertEquals("Google Inc. (ARM)", gl.getString("unmaskedVendor"));
                    assertEquals("ANGLE (ARM, Mali-G715, OpenGL ES 3.2)", gl.getString("unmasked"));
                    assertEquals(0, gl.getInt("error"));
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
