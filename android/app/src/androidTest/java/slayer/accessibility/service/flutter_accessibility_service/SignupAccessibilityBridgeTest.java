package slayer.accessibility.service.flutter_accessibility_service;

import android.app.Instrumentation;
import android.app.UiAutomation;
import android.accessibilityservice.GestureDescription;
import android.graphics.Path;
import android.graphics.Rect;
import android.view.ViewGroup;
import android.webkit.WebView;
import android.webkit.WebViewClient;
import android.view.accessibility.AccessibilityNodeInfo;
import androidx.test.ext.junit.runners.AndroidJUnit4;
import androidx.test.platform.app.InstrumentationRegistry;
import androidx.test.rule.ActivityTestRule;
import com.stalliondz.tool.tiktok.SignupFixtureActivity;
import io.flutter.plugin.common.MethodChannel;
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

/** Runs in a local HTML fixture; no network/mailbox/TikTok requests. */
@SuppressWarnings({"deprecation", "unchecked"})
@RunWith(AndroidJUnit4.class)
public class SignupAccessibilityBridgeTest {
    @Rule public ActivityTestRule<SignupFixtureActivity> activity = new ActivityTestRule<>(SignupFixtureActivity.class);
    private WebView web;
    private Instrumentation instrumentation() { return InstrumentationRegistry.getInstrumentation(); }

    @Before public void setup() throws Exception {
        // Instrumentation restarts the host process; reconnect its service and
        // keep UiAutomation from suppressing real Accessibility services.
        UiAutomation automation = instrumentation().getUiAutomation(UiAutomation.FLAG_DONT_SUPPRESS_ACCESSIBILITY_SERVICES);
        automation.executeShellCommand("settings put secure enabled_accessibility_services ''").close();
        Thread.sleep(300);
        automation.executeShellCommand("settings put secure enabled_accessibility_services " +
            instrumentation().getTargetContext().getPackageName() +
            "/slayer.accessibility.service.flutter_accessibility_service.AccessibilityListener").close();
        CountDownLatch loaded = new CountDownLatch(1);
        instrumentation().runOnMainSync(() -> {
            web = new WebView(activity.getActivity());
            web.getSettings().setJavaScriptEnabled(true);
            web.setImportantForAccessibility(android.view.View.IMPORTANT_FOR_ACCESSIBILITY_YES);
            activity.getActivity().setContentView(web, new ViewGroup.LayoutParams(-1, -1));
            web.setWebViewClient(new WebViewClient() {
                @Override public void onPageFinished(WebView view, String url) { loaded.countDown(); }
            });
            web.loadDataWithBaseURL("https://www.tiktok.com/signup", "<html><head>" +
                "<meta name='viewport' content='width=device-width,initial-scale=1'></head><body>" +
                "<h1>Enter 6-digit code</h1><input id='email' type='email' placeholder='Email address'>" +
                "<div style='margin-top:60px' id='slots'>" +
                "<input maxlength='1' style='width:35px'><input maxlength='1' style='width:35px'>" +
                "<input maxlength='1' style='width:35px'><input maxlength='1' style='width:35px'>" +
                "<input maxlength='1' style='width:35px'><input maxlength='1' style='width:35px'></div>" +
                "<select aria-label='Month'><option>Month</option><option>January</option><option>February</option></select>" +
                "<div id='commentFixtureBox' contenteditable='true' role='textbox' aria-placeholder='Add comment...' " +
                "style='display:none;position:fixed;bottom:16px;width:85%;min-height:40px'></div>" +
                "<script>slots.firstElementChild.addEventListener('paste',e=>{" +
                "e.preventDefault();const code=e.clipboardData.getData('text/plain');" +
                "Array.from(slots.children).forEach((el,i)=>el.value=code[i]||'');" +
                "window.trustedPaste=e.isTrusted;});</script></body></html>", "text/html", "UTF-8", null);
        });
        assertTrue(loaded.await(10, TimeUnit.SECONDS));
        long deadline = System.currentTimeMillis()+10000;
        while (System.currentTimeMillis()<deadline) {
            AtomicReference<Map<String,Object>> data = new AtomicReference<>();
            instrumentation().runOnMainSync(() -> data.set(SignupAccessibilityBridge.snapshot()));
            List<Map<String,Object>> nodes = (List<Map<String,Object>>) data.get().get("nodes");
            if (nodes != null && nodes.stream().filter(n -> Boolean.TRUE.equals(n.get("editable"))).count() >= 7) return;
            Thread.sleep(200);
        }
        fail("Accessibility service did not expose the fixture WebView");
    }

    private String evaluate(String script) throws Exception {
        AtomicReference<String> value = new AtomicReference<>();
        CountDownLatch done = new CountDownLatch(1);
        instrumentation().runOnMainSync(() -> web.evaluateJavascript(script, result -> {
            value.set(result); done.countDown();
        }));
        assertTrue(done.await(5, TimeUnit.SECONDS)); return value.get();
    }

    private Map<String,Object> paste(String text, String field) throws Exception {
        CountDownLatch done = new CountDownLatch(1);
        AtomicReference<Map<String,Object>> value = new AtomicReference<>();
        instrumentation().runOnMainSync(() -> SignupAccessibilityBridge.paste(text, field, new MethodChannel.Result() {
            @Override public void success(Object result) { value.set((Map<String,Object>)result); done.countDown(); }
            @Override public void error(String code, String message, Object detail) { done.countDown(); }
            @Override public void notImplemented() { done.countDown(); }
        }));
        assertTrue("Paste completed", done.await(10, TimeUnit.SECONDS)); return value.get();
    }

    private void keyboardSuppressed(boolean suppressed) throws Exception {
        CountDownLatch done = new CountDownLatch(1);
        AtomicReference<Object> value = new AtomicReference<>();
        instrumentation().runOnMainSync(() -> SignupAccessibilityBridge.setKeyboardSuppressed(suppressed, new MethodChannel.Result() {
            @Override public void success(Object result) { value.set(result); done.countDown(); }
            @Override public void error(String code, String message, Object detail) { done.countDown(); }
            @Override public void notImplemented() { done.countDown(); }
        }));
        assertTrue(done.await(3, TimeUnit.SECONDS));
        assertEquals(Boolean.TRUE, value.get());
    }

    private void emailForm(String prompt, String switchLabel, boolean extraEditor) throws Exception {
        instrumentation().runOnMainSync(() -> web.requestFocus());
        evaluate("document.body.innerHTML=\"<h1>Sign up</h1><div>" + prompt +
            "</div><input id='missingHintEmail' type='text'>" +
            (extraEditor ? "<input id='unrelated' type='text'>" : "") +
            "<button>" + switchLabel + "</button><button>Send code</button>\";" +
            "missingHintEmail.focus();true");
        Thread.sleep(500);
        tapFocusedEditor();
        Thread.sleep(500);
    }

    @Test public void recognizesSignupEmailWithoutHintAndPreservesDraft() throws Exception {
        emailForm("Enter your email", "Use phone", false);
        AtomicReference<Map<String,Object>> snapshot = new AtomicReference<>();
        instrumentation().runOnMainSync(() -> snapshot.set(SignupAccessibilityBridge.snapshot()));
        List<Map<String,Object>> nodes = (List<Map<String,Object>>) snapshot.get().get("nodes");
        Map<String,Object> editor = nodes.stream().filter(n -> Boolean.TRUE.equals(n.get("editable"))).findFirst().get();
        assertEquals(snapshot.get().toString(), "Email address", editor.get("hint"));
        assertEquals(0, editor.get("length"));
        Map<String,Object> pasted = paste("fixture@example.org", "email");
        assertEquals(pasted.toString() + " DOM=" + evaluate("missingHintEmail.value.length"), Boolean.TRUE, pasted.get("ok"));
        assertEquals("\"fixture@example.org\"", evaluate("missingHintEmail.value"));
        assertEquals("draft-exists", paste("replacement@example.org", "email").get("reason"));
        instrumentation().runOnMainSync(() -> snapshot.set(SignupAccessibilityBridge.snapshot()));
        assertFalse("Inferred hint must not contain field values", snapshot.get().toString().contains("fixture@example.org"));
    }

    @Test public void missingHintDoesNotTurnPhoneOrAmbiguousFieldsIntoEmail() throws Exception {
        for (String[] scenario : new String[][] {
                {"Enter your phone", "Use email", "false"},
                {"Enter your email", "Use email", "false"},
                {"Enter your email", "Use phone", "true"}}) {
            emailForm(scenario[0], scenario[1], Boolean.parseBoolean(scenario[2]));
            AtomicReference<Map<String,Object>> snapshot = new AtomicReference<>();
            instrumentation().runOnMainSync(() -> snapshot.set(SignupAccessibilityBridge.snapshot()));
            List<Map<String,Object>> nodes = (List<Map<String,Object>>) snapshot.get().get("nodes");
            assertFalse(nodes.stream().anyMatch(n -> Boolean.TRUE.equals(n.get("editable")) &&
                "Email address".equals(n.get("hint"))));
            assertEquals("wrong-email-field", paste("fixture@example.org", "email").get("reason"));
            assertEquals("\"\"", evaluate("missingHintEmail.value"));
        }
    }

    private void loginForm(boolean extraEditor, boolean phone) throws Exception {
        instrumentation().runOnMainSync(() -> web.requestFocus());
        evaluate("document.body.innerHTML=\"<div role='dialog' aria-modal='true' style='position:fixed;top:25%;left:10%;width:80%'><div>Log in</div>" +
            "<button>Phone</button><button>Username or email</button>" +
            "<div style='margin-top:20px'><input style='font-size:18px' id='missingHintLogin' type='" + (phone ? "tel" : "text") + "'></div>" +
            "<div style='margin-top:20px'><input style='font-size:18px' type='password'></div>" +
            (extraEditor ? "<input type='text'>" : "") +
            "<button>Continue</button></div>\";missingHintLogin.focus();true");
        Thread.sleep(500);
        tapFocusedEditor();
        Thread.sleep(500);
    }

    @Test public void recognizesLoginUsernameWithoutHintAndPreservesDraft() throws Exception {
        loginForm(false, false);
        AtomicReference<Map<String,Object>> snapshot = new AtomicReference<>();
        instrumentation().runOnMainSync(() -> snapshot.set(SignupAccessibilityBridge.snapshot()));
        List<Map<String,Object>> nodes = (List<Map<String,Object>>) snapshot.get().get("nodes");
        assertEquals(snapshot.get().toString(), 1, nodes.stream().filter(n -> Boolean.TRUE.equals(n.get("editable")) &&
            "Username or email".equals(n.get("hint"))).count());
        Map<String,Object> pasted = paste("fixture@example.org", "email");
        assertEquals(pasted.toString(), Boolean.TRUE, pasted.get("ok"));
        assertEquals("\"fixture@example.org\"", evaluate("missingHintLogin.value"));
        assertEquals("draft-exists", paste("replacement@example.org", "email").get("reason"));
        instrumentation().runOnMainSync(() -> snapshot.set(SignupAccessibilityBridge.snapshot()));
        assertFalse(snapshot.get().toString().contains("fixture@example.org"));
    }

    @Test public void missingLoginHintRejectsAmbiguousAndPhoneFields() throws Exception {
        for (boolean phone : new boolean[] {false, true}) {
            loginForm(!phone, phone);
            AtomicReference<Map<String,Object>> snapshot = new AtomicReference<>();
            instrumentation().runOnMainSync(() -> snapshot.set(SignupAccessibilityBridge.snapshot()));
            List<Map<String,Object>> nodes = (List<Map<String,Object>>) snapshot.get().get("nodes");
            assertFalse(nodes.stream().anyMatch(n -> Boolean.TRUE.equals(n.get("editable")) &&
                "Username or email".equals(n.get("hint"))));
            assertEquals("wrong-email-field", paste("fixture@example.org", "email").get("reason"));
            assertEquals("\"\"", evaluate("missingHintLogin.value"));
        }
    }

    @Test public void labelsSelectedBirthdaySpinnersWithoutHints() throws Exception {
        // Actual WebView 155 Accessibility recording: selected year has no hint.
        String json;
        try (java.io.InputStream input = instrumentation().getContext().getAssets().open("signup-birthday-missing-hints.json")) {
            json = new String(input.readAllBytes(), java.nio.charset.StandardCharsets.UTF_8);
        }
        org.json.JSONArray raw = new org.json.JSONObject(json).getJSONArray("nodes");
        List<Map<String,Object>> nodes = new java.util.ArrayList<>();
        for (int i = 0; i < raw.length(); i++) {
            org.json.JSONObject node = raw.getJSONObject(i);
            Map<String,Object> values = new java.util.HashMap<>();
            values.put("text", node.optString("text"));
            values.put("hint", node.optString("hint"));
            values.put("className", node.optString("className"));
            org.json.JSONArray bounds = node.getJSONArray("bounds");
            values.put("bounds", java.util.Arrays.asList(bounds.getInt(0), bounds.getInt(1), bounds.getInt(2), bounds.getInt(3)));
            nodes.add(values);
        }
        SignupAccessibilityBridge.labelSignupBirthdayFields(nodes);
        for (String[] field : new String[][] {{"Month", "Month"}, {"Day", "Day"}, {"Year", "1991"}}) {
            assertTrue(nodes.toString(), nodes.stream().anyMatch(n ->
                "android.widget.Spinner".equals(n.get("className")) && field[0].equals(n.get("hint")) && field[1].equals(n.get("text"))));
        }
        nodes.removeIf(n -> "When’s your birthday?*".equals(n.get("text")));
        for (Map<String,Object> node : nodes) node.put("hint", "");
        SignupAccessibilityBridge.labelSignupBirthdayFields(nodes);
        assertFalse("Unrelated dropdowns must not be relabeled", nodes.stream().anyMatch(n -> !"".equals(n.get("hint"))));
    }

    @Test public void treatsOnlyCommentEdgeFillersAsEmpty() {
        assertEquals("", SignupAccessibilityBridge.comparableComment("\n\u200B\u200E\uFEFF\u00A0"));
        assertEquals("draft text", SignupAccessibilityBridge.comparableComment("\u200B draft text\n"));
        assertEquals("a  b", SignupAccessibilityBridge.comparableComment(" a  b "));
        assertEquals("👩‍💻", SignupAccessibilityBridge.comparableComment(" 👩‍💻\n"));
    }

    @Test public void pastesIntoEmptyContenteditableWithInvisibleFillerAndPreservesRealDraft() throws Exception {
        instrumentation().runOnMainSync(() -> web.requestFocus());
        keyboardSuppressed(true);
        evaluate("email.style.display='none';slots.style.display='none';" +
            "commentFixtureBox.style.display='block';commentFixtureBox.textContent='\\u200B';" +
            "commentFixtureBox.addEventListener('paste',e=>window.commentPasteTrusted=e.isTrusted);" +
            "commentFixtureBox.focus();true");
        Thread.sleep(500);
        tapFocusedEditor();
        Thread.sleep(500);
        AtomicReference<Map<String,Object>> state = new AtomicReference<>();
        instrumentation().runOnMainSync(() -> state.set(SignupAccessibilityBridge.snapshot()));
        List<Map<String,Object>> nodes = (List<Map<String,Object>>) state.get().get("nodes");
        Map<String,Object> editor = nodes.stream().filter(n -> Boolean.TRUE.equals(n.get("editable")) &&
            String.valueOf(n.get("hint")).contains("comment")).findFirst().get();
        assertEquals(0, editor.get("length"));
        assertEquals(Boolean.TRUE, editor.get("focused"));
        Map<String,Object> result = paste("Video đẹp quá!", "comment");
        assertEquals(result.toString(), Boolean.TRUE, result.get("ok"));
        assertEquals("true", evaluate("window.commentPasteTrusted"));
        assertEquals("\"Video đẹp quá!\"", evaluate("commentFixtureBox.textContent.replace(/\\u200B/g,'').trim()"));
        assertEquals(Boolean.FALSE, paste("Replacement", "comment").get("ok"));
        assertEquals("\"Video đẹp quá!\"", evaluate("commentFixtureBox.textContent.replace(/\\u200B/g,'').trim()"));
        keyboardSuppressed(false);
    }

    @Test public void pastesUnicodeCommentThroughAccessibilityAndKeepsExistingDraft() throws Exception {
        instrumentation().runOnMainSync(() -> web.requestFocus());
        keyboardSuppressed(true);
        evaluate("email.type='text';email.placeholder='Add comment...';email.style.position='fixed';email.style.bottom='8px';email.focus();true");
        Thread.sleep(500);
        tapFocusedEditor();
        Thread.sleep(500);
        AtomicReference<Map<String,Object>> state = new AtomicReference<>();
        instrumentation().runOnMainSync(() -> state.set(SignupAccessibilityBridge.snapshot()));
        assertEquals(Boolean.FALSE, state.get().get("keyboardVisible"));
        Map<String,Object> result = paste("Video đẹp quá!", "comment");
        if (!Boolean.TRUE.equals(result.get("ok"))) {
            fail(result.toString() + " snapshot=" + state.get());
        }
        assertEquals(result.toString(), Boolean.TRUE, result.get("ok"));
        assertEquals("\"Video đẹp quá!\"", evaluate("email.value"));
        result = paste("Replacement", "comment");
        assertEquals(Boolean.FALSE, result.get("ok"));
        assertEquals("draft-exists", result.get("reason"));
        assertEquals("\"Video đẹp quá!\"", evaluate("email.value"));
        keyboardSuppressed(false);
        assertEquals(android.accessibilityservice.AccessibilityService.SHOW_MODE_AUTO,
            AccessibilityListener.currentInstance().getSoftKeyboardController().getShowMode());
    }

    @Test public void revealsDisabledPostWithoutEnteringOrSubmittingText() throws Exception {
        evaluate("document.body.innerHTML='<div style=\"position:fixed;bottom:30px;left:10px\">" +
            "<input id=\"draft\">" +
            "<button disabled onclick=\"window.posted=true\">Post</button></div>';true");
        Map<String,Object> result = null;
        long until = System.currentTimeMillis() + 5000;
        do {
            Thread.sleep(200);
            AtomicReference<Map<String,Object>> value = new AtomicReference<>();
            instrumentation().runOnMainSync(() -> {
                List<Map<String,Object>> nodes = (List<Map<String,Object>>) SignupAccessibilityBridge.snapshot().get("nodes");
                Map<String,Object> editor = nodes.stream().filter(n -> Boolean.TRUE.equals(n.get("editable"))).findFirst().orElse(null);
                if (editor == null) {
                    value.set(java.util.Collections.singletonMap("ok", false));
                } else {
                    value.set(SignupAccessibilityBridge.revealCommentPost((String) editor.get("id"),
                        (List<Integer>) editor.get("bounds")));
                }
            });
            result = value.get();
        } while (!Boolean.TRUE.equals(result.get("ok")) && System.currentTimeMillis() < until);
        AtomicReference<Map<String,Object>> state = new AtomicReference<>();
        instrumentation().runOnMainSync(() -> state.set(SignupAccessibilityBridge.snapshot()));
        assertEquals(result.toString() + " snapshot=" + state.get(), Boolean.TRUE, result.get("ok"));
        assertEquals("post-visible", result.get("reason"));
        assertEquals("\"\"", evaluate("draft.value"));
        assertEquals("false", evaluate("window.posted===true"));
    }

    @Test public void rejectsCommentInputIntoLoginEmail() throws Exception {
        instrumentation().runOnMainSync(() -> web.requestFocus());
        evaluate("email.focus();true");
        Thread.sleep(500);
        tapFocusedEditor();
        Thread.sleep(500);
        Map<String,Object> result = paste("Configured comment", "comment");
        assertEquals(Boolean.FALSE, result.get("ok"));
        assertEquals("wrong-comment-field", result.get("reason"));
        assertEquals("\"\"", evaluate("email.value"));
    }

    @Test public void confirmsNumericOtpWhenInputImmediatelyReplacesEditor() throws Exception {
        instrumentation().runOnMainSync(() -> web.requestFocus());
        evaluate("document.body.innerHTML='<h1>Enter code</h1><input id=\"otp\" type=\"number\" placeholder=\"6-digit code\">';" +
            "otp.addEventListener('input',e=>{window.trustedOtpInput=e.isTrusted;" +
            "if(otp.value==='123456')" +
            "document.body.innerHTML='<nav><a href=\"/messages\">Messages</a><a href=\"/profile\">Profile</a></nav>';});" +
            "otp.focus();true");
        Thread.sleep(500);
        tapFocusedEditor();
        Thread.sleep(500);
        assertEquals("\"\"", evaluate("otp.value"));
        AtomicReference<Map<String,Object>> editorState = new AtomicReference<>();
        instrumentation().runOnMainSync(() -> {
            List<Map<String,Object>> nodes = (List<Map<String,Object>>) SignupAccessibilityBridge.snapshot().get("nodes");
            editorState.set(nodes.stream().filter(n -> Boolean.TRUE.equals(n.get("editable"))).findFirst().get());
        });
        assertEquals(0, editorState.get().get("length"));
        assertEquals("6-digit code", editorState.get().get("hint"));
        Map<String,Object> result = paste("123456", "otp");
        assertEquals(result.toString(), Boolean.TRUE, result.get("ok"));
        assertEquals("otp-view-replaced", result.get("reason"));
        assertEquals("0", evaluate("document.querySelectorAll('input').length"));
        assertEquals("true", evaluate("window.trustedOtpInput"));
    }

    @Test public void pastesThroughRealMenuIntoSixOtpSlots() throws Exception {
        // Focus is fixture preparation. All paste input is the service's gesture/menu path.
        instrumentation().runOnMainSync(() -> web.requestFocus());
        evaluate("email.style.visibility='hidden';slots.firstElementChild.focus();true");
        Thread.sleep(500);
        tapFocusedEditor();
        Thread.sleep(500);
        Map<String,Object> result = paste("123456", "otp");
        if (!Boolean.TRUE.equals(result.get("ok"))) {
            android.graphics.Bitmap screenshot = instrumentation().getUiAutomation(UiAutomation.FLAG_DONT_SUPPRESS_ACCESSIBILITY_SERVICES).takeScreenshot();
            try (java.io.FileOutputStream file = new java.io.FileOutputStream(new java.io.File(activity.getActivity().getFilesDir(), "signup-test-menu.png"))) {
                screenshot.compress(android.graphics.Bitmap.CompressFormat.PNG, 100, file);
            }
        }
        String windows = "";
        if (!Boolean.TRUE.equals(result.get("ok"))) {
            for (android.view.accessibility.AccessibilityWindowInfo window : AccessibilityListener.currentInstance().getWindows()) {
                windows += "\nWINDOW " + window.getType() + fixtureTree(window.getRoot(),0);
            }
        }
        assertEquals(result.toString() + windows, Boolean.TRUE, result.get("ok"));
        assertEquals("\"123456\"", evaluate("Array.from(slots.children).map(el=>el.value).join('')"));
        assertEquals("true", evaluate("window.trustedPaste"));
    }

    private void tapFocusedEditor() throws Exception {
        CountDownLatch done = new CountDownLatch(1);
        instrumentation().runOnMainSync(() -> {
            AccessibilityListener service = AccessibilityListener.currentInstance();
            AccessibilityNodeInfo editor = SignupAccessibilityBridge.webRoot(service).findFocus(AccessibilityNodeInfo.FOCUS_INPUT);
            Rect bounds = new Rect(); editor.getBoundsInScreen(bounds);
            Path path = new Path(); path.moveTo(bounds.exactCenterX(), bounds.exactCenterY());
            service.dispatchGesture(new GestureDescription.Builder().addStroke(new GestureDescription.StrokeDescription(path,0,140)).build(),
                new android.accessibilityservice.AccessibilityService.GestureResultCallback() {
                    @Override public void onCompleted(GestureDescription gesture) { done.countDown(); }
                }, null);
        });
        assertTrue(done.await(3, TimeUnit.SECONDS));
    }

    @Test public void exposesNativeBirthdayOptions() throws Exception {
        CountDownLatch done = new CountDownLatch(1);
        instrumentation().runOnMainSync(() -> {
            AccessibilityListener service = AccessibilityListener.currentInstance();
            AccessibilityNodeInfo spinner = SignupAccessibilityBridge.webRoot(service)
                .findAccessibilityNodeInfosByText("Month").stream()
                .filter(n -> "android.widget.Spinner".contentEquals(n.getClassName())).findFirst().get();
            Rect bounds = new Rect(); spinner.getBoundsInScreen(bounds);
            Path path = new Path(); path.moveTo(bounds.exactCenterX(), bounds.exactCenterY());
            service.dispatchGesture(new GestureDescription.Builder().addStroke(new GestureDescription.StrokeDescription(path,0,140)).build(),
                new android.accessibilityservice.AccessibilityService.GestureResultCallback() {
                    @Override public void onCompleted(GestureDescription gesture) { done.countDown(); }
                }, null);
        });
        assertTrue(done.await(3, TimeUnit.SECONDS));
        long deadline = System.currentTimeMillis()+5000;
        while(System.currentTimeMillis()<deadline) {
            AtomicReference<Map<String,Object>> data = new AtomicReference<>();
            instrumentation().runOnMainSync(() -> data.set(SignupAccessibilityBridge.snapshot()));
            List<Map<String,Object>> nodes = (List<Map<String,Object>>)data.get().get("nodes");
            if(nodes != null && nodes.stream().anyMatch(n -> Boolean.TRUE.equals(n.get("picker")) && "February".equals(n.get("text")))) return;
            Thread.sleep(200);
        }
        fail("Native birthday options were not exposed");
    }

    private String fixtureTree(AccessibilityNodeInfo node, int depth) {
        if (node == null || depth > 15) return "";
        String value = "\n" + node.getPackageName() + ":" + node.getClassName() + ":" + node.getText() + ":" + node.getContentDescription();
        for (int i=0; i<node.getChildCount(); i++) value += fixtureTree(node.getChild(i), depth+1);
        return value;
    }

    @Test public void pastesEmailAndPreservesDraft() throws Exception {
        instrumentation().runOnMainSync(() -> web.requestFocus());
        evaluate("email.focus();true");
        Thread.sleep(500);
        assertEquals(Boolean.TRUE, paste("fixture@example.org", "email").get("ok"));
        assertEquals(Boolean.FALSE, paste("other@example.org", "email").get("ok"));
        assertEquals("\"fixture@example.org\"", evaluate("email.value"));
    }

    @After public void cleanup() {
        instrumentation().runOnMainSync(() -> {
            SignupAccessibilityBridge.cancelPaste();
            if (web != null) { ((ViewGroup)web.getParent()).removeView(web); web.destroy(); }
        });
    }
}
