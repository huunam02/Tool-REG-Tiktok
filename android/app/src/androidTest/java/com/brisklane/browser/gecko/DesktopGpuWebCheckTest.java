package com.brisklane.browser.gecko;

import android.graphics.Bitmap;
import android.os.SystemClock;
import androidx.test.platform.app.InstrumentationRegistry;
import androidx.test.rule.ActivityTestRule;
import com.stalliondz.tool.tiktok.SignupFixtureActivity;
import io.flutter.plugin.common.BinaryMessenger;
import io.flutter.plugin.common.MethodCall;
import io.flutter.plugin.common.MethodChannel;
import io.flutter.plugin.common.StandardMethodCodec;
import java.io.File;
import java.io.FileOutputStream;
import java.nio.ByteBuffer;
import java.nio.charset.StandardCharsets;
import java.nio.file.Files;
import java.util.HashMap;
import java.util.Map;
import java.util.concurrent.CountDownLatch;
import java.util.concurrent.TimeUnit;
import java.util.concurrent.atomic.AtomicReference;
import org.json.JSONArray;
import org.json.JSONObject;
import org.junit.Rule;
import org.junit.Test;
import static org.junit.Assert.*;
import static org.junit.Assume.assumeTrue;

/** Opt-in live web check. Serve outputs/firefox-desktop on localhost:8878,
 * adb reverse tcp:8878 tcp:8878, and pass -e gpuWebCheck true to instrumentation.
 * Uses separate browser contexts, without changing saved configurations. */
public class DesktopGpuWebCheckTest {
    @Rule public ActivityTestRule<SignupFixtureActivity> activity =
        new ActivityTestRule<>(SignupFixtureActivity.class);

    @Test public void allGpuProfilesOnProbeAndWhatIsMyBrowser() throws Exception {
        assumeTrue("Live website check is opt-in", "true".equals(
            InstrumentationRegistry.getArguments().getString("gpuWebCheck")));
        JSONArray failures = new JSONArray();
        for (FirefoxDesktopIdentity.Gpu gpu : FirefoxDesktopIdentity.Gpu.values()) {
            JSONObject result = new JSONObject().put("gpuId", gpu.getId());
            try {
                checkGpu(gpu, result);
                result.put("passed", true);
            } catch (Throwable error) {
                result.put("passed", false).put("error", error.toString());
                failures.put(gpu.getId() + ": " + error);
            } finally {
                write(gpu.getId() + "-summary.json", result.toString(2));
            }
        }
        assertEquals(failures.toString(), 0, failures.length());
    }

    private void checkGpu(FirefoxDesktopIdentity.Gpu gpu, JSONObject result) throws Exception {
        AtomicReference<GeckoPlatformView> view = new AtomicReference<>();
        AtomicReference<CountDownLatch> loaded = new AtomicReference<>(new CountDownLatch(1));
        BinaryMessenger messenger = new BinaryMessenger() {
            @Override public void send(String channel, ByteBuffer message) {
                send(channel, message, null);
            }
            @Override public void send(String channel, ByteBuffer message, BinaryReply reply) {
                message.flip();
                MethodCall call = StandardMethodCodec.INSTANCE.decodeMethodCall(message);
                if ("event".equals(call.method)) {
                    Map<?, ?> event = (Map<?, ?>) call.arguments;
                    if ("loadStop".equals(event.get("type"))) loaded.get().countDown();
                }
                if (reply != null) reply.reply(null);
            }
            @Override public void setMessageHandler(String channel, BinaryMessageHandler handler) {}
        };
        try {
            onMain(() -> {
                Map<String, Object> args = new HashMap<>();
                args.put("initialUrl", "http://127.0.0.1:8878/do-dau-hieu-thiet-bi-v2.html");
                args.put("contextId", "gpu-web-check-" + gpu.getId() + "-" + System.currentTimeMillis());
                args.put("desktopGpu", gpu.getId());
                GeckoPlatformView platform = new GeckoPlatformView(activity.getActivity(), messenger, 9500, args);
                view.set(platform);
                GeckoRuntimeHolder.INSTANCE.runtime(activity.getActivity()).getSettings().setConsoleOutputEnabled(true);
                activity.getActivity().setContentView(platform.getView());
                platform.onMethodCall(new MethodCall("start", null), new Reply(null, null));
            });
            assertTrue("Probe page did not load", loaded.get().await(45, TimeUnit.SECONDS));
            JSONObject probe = waitForProbe(view.get());
            write(gpu.getId() + "-probe.json", probe.toString(2));
            result.put("probe", probe);
            screenshot(gpu.getId() + "-probe.png");
            JSONArray precisionSemantics = new JSONArray(String.valueOf(evaluate(view.get(),
                "JSON.stringify(['webgl','webgl2'].map(api=>{const g=document.createElement('canvas').getContext(api);"
                + "const f=g.getShaderPrecisionFormat(g.FRAGMENT_SHADER,g.MEDIUM_FLOAT);"
                + "const getter=Object.getOwnPropertyDescriptor(WebGLShaderPrecisionFormat.prototype,'precision').get;"
                + "let illegalReceiverThrows=false;try{getter.call({})}catch(e){illegalReceiverThrows=e instanceof TypeError}"
                + "const invalid=g.getShaderPrecisionFormat(0,g.MEDIUM_FLOAT);"
                + "return {api,nativeInstance:f instanceof WebGLShaderPrecisionFormat,"
                + "noOwnProperties:Object.keys(f).length===0,illegalReceiverThrows,"
                + "invalidReturnsNull:invalid===null,invalidEnum:g.getError()===g.INVALID_ENUM}}))")));
            result.put("precisionSemantics", precisionSemantics);
            for (int i = 0; i < precisionSemantics.length(); i++) {
                JSONObject check = precisionSemantics.getJSONObject(i);
                for (String key : new String[]{"nativeInstance", "noOwnProperties", "illegalReceiverThrows",
                        "invalidReturnsNull", "invalidEnum"}) {
                    assertTrue(check.getString("api") + " " + key, check.getBoolean(key));
                }
            }
            JSONObject nativeWebgpu = new JSONObject(String.valueOf(evaluate(view.get(),
                "Promise.race([(async()=>{try{"
                + "if(!navigator.gpu)return JSON.stringify({adapterAvailable:false});"
                + "let a=await navigator.gpu.requestAdapter();const defaultAdapterAvailable=!!a;"
                + "if(!a)a=await navigator.gpu.requestAdapter({forceFallbackAdapter:true});"
                + "if(!a)return JSON.stringify({adapterAvailable:false});"
                + "const info={adapterAvailable:true,defaultAdapterAvailable,features:Array.from(a.features).sort(),"
                + "maxTex:a.limits.maxTextureDimension2D};"
                + "const d=await a.requestDevice();info.deviceCreated=true;"
                + "const output=d.createBuffer({size:4,usage:GPUBufferUsage.STORAGE|GPUBufferUsage.COPY_SRC});"
                + "const read=d.createBuffer({size:4,usage:GPUBufferUsage.COPY_DST|GPUBufferUsage.MAP_READ});"
                + "const module=d.createShaderModule({code:'@group(0) @binding(0) var<storage,read_write> out:array<u32>; @compute @workgroup_size(1) fn main(){out[0]=42u;}'});"
                + "const p=d.createComputePipeline({layout:'auto',compute:{module,entryPoint:'main'}});"
                + "const group=d.createBindGroup({layout:p.getBindGroupLayout(0),entries:[{binding:0,resource:{buffer:output}}]});"
                + "const encoder=d.createCommandEncoder();const pass=encoder.beginComputePass();"
                + "pass.setPipeline(p);pass.setBindGroup(0,group);pass.dispatchWorkgroups(1);pass.end();"
                + "encoder.copyBufferToBuffer(output,0,read,0,4);d.queue.submit([encoder.finish()]);"
                + "await read.mapAsync(GPUMapMode.READ);info.computeResult=new Uint32Array(read.getMappedRange())[0];"
                + "read.unmap();output.destroy();read.destroy();d.destroy();return JSON.stringify(info);"
                + "}catch(e){return JSON.stringify({error:String(e)})}})(),"
                + "new Promise(resolve=>setTimeout(()=>resolve(JSON.stringify({error:'timeout'})),7000))])")));
            result.put("nativeWebgpu", nativeWebgpu);
            if (nativeWebgpu.optBoolean("adapterAvailable")) {
                assertEquals("Native WebGPU compute result", 42, nativeWebgpu.getInt("computeResult"));
            }

            loaded.set(new CountDownLatch(1));
            onMain(() -> view.get().onMethodCall(new MethodCall("loadUrl",
                arguments("url", "https://www.whatismybrowser.com/")), new Reply(null, null)));
            assertTrue("WhatIsMyBrowser did not load", loaded.get().await(60, TimeUnit.SECONDS));
            JSONObject website = waitForWebsite(view.get(), false);
            screenshot(gpu.getId() + "-whatismybrowser-top.png");
            evaluate(view.get(), "(()=>{const link=Array.from(document.querySelectorAll('a'))"
                + ".find(a=>a.textContent.trim()==='How did you find out all this?');"
                + "if(link){link.click();return true}return false})()");
            website = waitForWebsite(view.get(), true);
            write(gpu.getId() + "-whatismybrowser.json", website.toString(2));
            result.put("website", website);
            screenshot(gpu.getId() + "-whatismybrowser.png");

            assertEquals(FirefoxDesktopIdentity.USER_AGENT, probe.getJSONObject("basics").getString("userAgent"));
            assertEquals("Win32", probe.getJSONObject("basics").getString("platform"));
            assertEquals(0, probe.getJSONObject("basics").getInt("maxTouchPoints"));
            JSONArray screen = probe.getJSONObject("basics").getJSONArray("screen");
            assertEquals(1920, screen.getInt(0));
            assertEquals(1080, screen.getInt(1));
            for (String api : new String[]{"webgl", "webgl2"}) {
                JSONObject precision = probe.getJSONObject(api).getJSONObject("precision");
                for (String shader : new String[]{"VERTEX_SHADER", "FRAGMENT_SHADER"}) {
                    for (String type : new String[]{"HIGH_FLOAT", "MEDIUM_FLOAT", "LOW_FLOAT", "HIGH_INT"}) {
                        assertEquals(api + " " + shader + "." + type,
                            "HIGH_INT".equals(type) ? "[31,30,0]" : "[127,127,23]",
                            precision.getJSONArray(shader + "." + type).toString());
                    }
                }
                JSONObject params = probe.getJSONObject(api).getJSONObject("params");
                assertEquals(gpu.getVendor(), params.getString("UNMASKED_VENDOR"));
                assertEquals(gpu.getRenderer(), params.getString("UNMASKED_RENDERER"));
                assertEquals(gpu.getRenderer(), params.getString("RENDERER"));
            }
            assertEquals(gpu == FirefoxDesktopIdentity.Gpu.AMD_R9_200 ? 8 : 16,
                probe.getJSONObject("webgl2").getJSONObject("params").getInt("MAX_SAMPLES"));
            assertEquals(FirefoxDesktopIdentity.USER_AGENT, website.getString("userAgent"));
            assertEquals(gpu.getRenderer(), website.getJSONObject("webgl").getString("renderer"));
            assertEquals(gpu.getVendor(), website.getJSONObject("webgl").getString("vendor"));
            assertTrue("Website did not identify Windows Firefox", website.getString("body").contains("Firefox 158"));
            assertTrue("Website did not identify Windows", website.getString("body").contains("Windows 10"));
            assertTrue("Website technical details did not show selected GPU",
                website.getString("body").contains(gpu.getRenderer()));
        } finally {
            if (view.get() != null) onMain(() -> {
                activity.getActivity().setContentView(new android.widget.FrameLayout(activity.getActivity()));
                view.get().dispose();
            });
        }
    }

    private JSONObject waitForProbe(GeckoPlatformView view) throws Exception {
        long deadline = SystemClock.elapsedRealtime() + 45000;
        while (SystemClock.elapsedRealtime() < deadline) {
            try {
                String raw = String.valueOf(evaluate(view,
                    "document.getElementById('raw') && document.getElementById('raw').value"));
                if (raw.startsWith("{")) return new JSONObject(raw);
            } catch (Exception ignored) { }
            SystemClock.sleep(500);
        }
        throw new AssertionError("Probe did not finish producing JSON");
    }

    private JSONObject waitForWebsite(GeckoPlatformView view, boolean technical) throws Exception {
        long deadline = SystemClock.elapsedRealtime() + 45000;
        JSONObject last = null;
        while (SystemClock.elapsedRealtime() < deadline) {
            try {
                last = new JSONObject(String.valueOf(evaluate(view,
                    "JSON.stringify({url:location.href,title:document.title,"
                    + "userAgent:navigator.userAgent,platform:navigator.platform,"
                    + "screen:[screen.width,screen.height,devicePixelRatio],"
                    + "cpu:navigator.hardwareConcurrency,touch:navigator.maxTouchPoints,"
                    + "webgl:(()=>{const g=document.createElement('canvas').getContext('webgl');"
                    + "if(!g)return null;const e=g.getExtension('WEBGL_debug_renderer_info');"
                    + "return e?{vendor:g.getParameter(e.UNMASKED_VENDOR_WEBGL),"
                    + "renderer:g.getParameter(e.UNMASKED_RENDERER_WEBGL)}:null})(),"
                    + "body:document.body.innerText.replace(/\\b(?:\\d{1,3}\\.){3}\\d{1,3}\\b/g,'[IP]')})")));
                String body = last.getString("body");
                if (body.contains("Firefox 158") && body.contains("Windows 10")
                    && (!technical || body.contains("WebGL Renderer"))) return last;
            } catch (Exception ignored) { }
            SystemClock.sleep(1000);
        }
        if (last != null) return last;
        throw new AssertionError("Cannot read WhatIsMyBrowser page");
    }

    private Object evaluate(GeckoPlatformView view, String source) throws Exception {
        CountDownLatch done = new CountDownLatch(1);
        AtomicReference<Object> value = new AtomicReference<>();
        onMain(() -> view.onMethodCall(new MethodCall("evaluateJavascript",
            arguments("source", source, "pageWorld", true, "timeoutMs", 10000)), new Reply(value, done)));
        assertTrue("JavaScript readout timed out", done.await(12, TimeUnit.SECONDS));
        if (String.valueOf(value.get()).startsWith("ERROR ")) throw new Exception(String.valueOf(value.get()));
        return value.get();
    }

    private void screenshot(String name) throws Exception {
        Bitmap image = InstrumentationRegistry.getInstrumentation().getUiAutomation().takeScreenshot();
        assertNotNull(image);
        try (FileOutputStream output = new FileOutputStream(file(name))) {
            image.compress(Bitmap.CompressFormat.PNG, 100, output);
        } finally { image.recycle(); }
    }

    private File file(String name) {
        return new File(InstrumentationRegistry.getInstrumentation().getTargetContext().getCodeCacheDir(),
            "gpu-web-check-" + name);
    }

    private void write(String name, String data) throws Exception {
        Files.write(file(name).toPath(), data.getBytes(StandardCharsets.UTF_8));
    }

    private void onMain(Runnable task) {
        InstrumentationRegistry.getInstrumentation().runOnMainSync(task);
    }

    private static Map<String, Object> arguments(Object... pairs) {
        Map<String, Object> result = new HashMap<>();
        for (int i = 0; i < pairs.length; i += 2) result.put((String) pairs[i], pairs[i + 1]);
        return result;
    }

    private static class Reply implements MethodChannel.Result {
        private final AtomicReference<Object> value;
        private final CountDownLatch done;
        Reply(AtomicReference<Object> value, CountDownLatch done) { this.value = value; this.done = done; }
        @Override public void success(Object result) {
            if (value != null) value.set(result);
            if (done != null) done.countDown();
        }
        @Override public void error(String code, String message, Object details) { success("ERROR " + code + ": " + message); }
        @Override public void notImplemented() { error("not_implemented", "", null); }
    }
}
