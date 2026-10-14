package com.stalliondz.tool.tiktok;

import android.content.ClipData;
import android.content.ClipboardManager;
import android.content.Context;
import android.app.Instrumentation;
import android.view.ViewGroup;
import android.webkit.WebView;
import android.webkit.WebViewClient;
import android.text.InputType;
import android.view.inputmethod.EditorInfo;
import android.view.inputmethod.InputConnection;
import android.widget.LinearLayout;
import android.widget.Button;
import java.util.concurrent.CountDownLatch;
import java.util.concurrent.TimeUnit;
import java.util.concurrent.atomic.AtomicReference;
import kotlin.Unit;
import androidx.test.platform.app.InstrumentationRegistry;
import androidx.test.ext.junit.runners.AndroidJUnit4;
import androidx.test.rule.ActivityTestRule;
import org.junit.Before;
import org.junit.After;
import org.junit.Rule;
import org.junit.Test;
import org.junit.runner.RunWith;
import static org.junit.Assert.*;

/** Exercises the real Android WebView/clipboard without contacting TikTok. */
@SuppressWarnings("deprecation")
@RunWith(AndroidJUnit4.class)
public class NativeClipboardPasteTest {
    @Rule public ActivityTestRule<MainActivity> activityRule = new ActivityTestRule<>(MainActivity.class);
    private WebView webView;
    private Button otherFocus;
    private boolean stalePasswordConnection;

    private MainActivity getActivity() { return activityRule.getActivity(); }
    private Instrumentation getInstrumentation() { return InstrumentationRegistry.getInstrumentation(); }

    @Before
    public void setUp() throws Exception {
        MainActivity activity = getActivity();
        CountDownLatch loaded = new CountDownLatch(1);
        getInstrumentation().runOnMainSync(() -> {
            LinearLayout layout = new LinearLayout(activity);
            layout.setOrientation(LinearLayout.VERTICAL);
            otherFocus = new Button(activity);
            otherFocus.setText("Other focus");
            otherFocus.setFocusableInTouchMode(true);
            layout.addView(otherFocus);
            webView = new WebView(activity) {
                @Override public InputConnection onCreateInputConnection(EditorInfo info) {
                    InputConnection connection = super.onCreateInputConnection(info);
                    if (stalePasswordConnection) {
                        info.inputType = InputType.TYPE_CLASS_TEXT | InputType.TYPE_TEXT_VARIATION_EMAIL_ADDRESS;
                    }
                    return connection;
                }
            };
            webView.getSettings().setJavaScriptEnabled(true);
            layout.addView(webView, new LinearLayout.LayoutParams(-1, 0, 1));
            activity.addContentView(layout, new ViewGroup.LayoutParams(-1, -1));
            webView.setWebViewClient(new WebViewClient() {
                @Override public void onPageFinished(WebView view, String url) { loaded.countDown(); }
            });
            webView.loadDataWithBaseURL("https://www.tiktok.com/login/phone-or-email/email",
                "<input id='email' name='username'><input id='password' type='password'>" +
                "<input id='otp' autocomplete='one-time-code'>" +
                "<div id='comment' contenteditable='true' data-e2e='comment-input'></div>" +
                "<script>window.inputEvents=0;window.events=[];" +
                "document.addEventListener('input',()=>inputEvents++);" +
                "for(const type of ['keydown','keyup','paste','beforeinput','input','focus','blur'])" +
                "document.addEventListener(type,e=>events.push([e.type,e.target.id,e.isTrusted," +
                "e.ctrlKey,e.clipboardData?.getData('text/plain').length]),true);</script>",
                "text/html", "UTF-8", null);
        });
        assertTrue("Fixture loaded", loaded.await(10, TimeUnit.SECONDS));
    }

    private String evaluate(String script) throws Exception {
        AtomicReference<String> value = new AtomicReference<>();
        CountDownLatch done = new CountDownLatch(1);
        getInstrumentation().runOnMainSync(() -> webView.evaluateJavascript(script, result -> {
            value.set(result);
            done.countDown();
        }));
        assertTrue("JavaScript completed", done.await(5, TimeUnit.SECONDS));
        return value.get();
    }

    private boolean paste(String text, String guard) throws Exception {
        AtomicReference<Boolean> value = new AtomicReference<>();
        CountDownLatch done = new CountDownLatch(1);
        getInstrumentation().runOnMainSync(() -> {
            ClipboardManager clipboard = (ClipboardManager) getActivity().getSystemService(Context.CLIPBOARD_SERVICE);
            clipboard.setPrimaryClip(ClipData.newPlainText("test", text));
            NativeClipboardPaste.INSTANCE.paste(webView, guard, result -> {
                value.set(result);
                done.countDown();
                return Unit.INSTANCE;
            });
        });
        assertTrue("Paste completed", done.await(5, TimeUnit.SECONDS));
        return value.get();
    }

    private void focusDomOnly(String id) throws Exception {
        getInstrumentation().runOnMainSync(() -> otherFocus.requestFocus());
        evaluate("(() => {const e=document.getElementById('" + id + "');e.focus();" +
            "if(e.isContentEditable){const r=document.createRange();r.selectNodeContents(e);" +
            "const s=window.getSelection();s.removeAllRanges();s.addRange(r);}else{e.select();}return true;})()");
        assertEquals("\"" + id + "\"", evaluate("document.activeElement.id"));
    }

    @Test public void testPastesCredentialsWithoutTouchOrKeyboard() throws Exception {
        String[] ids = {"email", "password", "otp"};
        String[] values = {"test@example.com", "test-secret", "012345"};
        for (int i = 0; i < ids.length; i++) {
            String id = ids[i];
            focusDomOnly(id);
            assertTrue("Native paste accepted for " + id, paste(values[i],
                "document.activeElement.id === '" + id + "' && !document.hidden"));
            awaitValue(id, values[i]);
        }
        assertEquals("3", evaluate("window.inputEvents"));
    }

    @Test public void testPastesUnicodeComment() throws Exception {
        focusDomOnly("comment");
        assertTrue(paste("Xin chào 👋", "document.activeElement.id === 'comment' && !document.hidden"));
        awaitValue("comment", "Xin chào 👋");
        assertEquals("1", evaluate("window.inputEvents"));
    }

    @Test public void testRejectsCancelledOrWrongField() throws Exception {
        focusDomOnly("email");
        assertFalse(paste("test-secret", "document.activeElement.id === 'password'"));
        assertFalse(paste("test@example.com", "false"));
        assertEquals("\"\"", evaluate("document.getElementById('email').value"));
        assertEquals("0", evaluate("window.inputEvents"));
    }

    @Test public void testDoesNotPastePasswordIntoStaleOtpConnection() throws Exception {
        focusDomOnly("password");
        stalePasswordConnection = true;
        assertFalse(paste("test-secret", "document.activeElement.id === 'password' && !document.hidden"));
        assertEquals("\"\"", evaluate("document.getElementById('password').value"));
        assertEquals("0", evaluate("window.inputEvents"));
        stalePasswordConnection = false;
        assertTrue(paste("test-secret", "document.activeElement.id === 'password' && !document.hidden"));
        awaitValue("password", "test-secret");
        assertEquals("1", evaluate("window.inputEvents"));
    }

    @Test public void testRechecksCancellationAfterNativeFocus() throws Exception {
        focusDomOnly("email");
        evaluate("window.cancelled=false;true");
        getInstrumentation().runOnMainSync(() -> webView.setOnFocusChangeListener((view, focused) -> {
            if (focused) webView.evaluateJavascript("window.cancelled=true", null);
        }));
        assertFalse(paste("test@example.com",
            "!window.cancelled && document.activeElement.id === 'email'"));
        assertEquals("\"\"", evaluate("document.getElementById('email').value"));
        assertEquals("0", evaluate("window.inputEvents"));
    }

    @Test public void testRechecksCancellationWhileWaitingForNativeEditor() throws Exception {
        focusDomOnly("password");
        evaluate("window.cancelled=false;true");
        getInstrumentation().runOnMainSync(() -> webView.setOnFocusChangeListener((view, focused) -> {
            if (focused) webView.evaluateJavascript("setTimeout(()=>window.cancelled=true,50)", null);
        }));
        assertFalse(paste("test-secret",
            "!window.cancelled && document.activeElement.id === 'password'"));
        assertEquals("\"\"", evaluate("document.getElementById('password').value"));
        assertEquals("0", evaluate("window.inputEvents"));
    }

    private void awaitValue(String id, String expected) throws Exception {
        String script = "(() => {const e=document.getElementById('" + id + "');return " +
            "(e.value === undefined ? e.textContent : e.value) === " +
            org.json.JSONObject.quote(expected) + ";})()";
        long deadline = System.currentTimeMillis() + 3000;
        while (System.currentTimeMillis() < deadline) {
            if ("true".equals(evaluate(script))) return;
            Thread.sleep(50);
        }
        fail("Clipboard text reached " + id + ": " + evaluate("JSON.stringify({focused:document.hasFocus(),active:document.activeElement.id,events})"));
    }

    @After
    public void tearDown() throws Exception {
        if (webView != null) getInstrumentation().runOnMainSync(() -> {
            ((ViewGroup) webView.getParent()).removeView(webView);
            webView.destroy();
        });
    }
}
