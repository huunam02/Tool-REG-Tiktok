package slayer.accessibility.service.flutter_accessibility_service;

import android.content.ClipData;
import android.content.ClipboardManager;
import android.content.Context;
import android.accessibilityservice.GestureDescription;
import android.graphics.Path;
import android.graphics.Rect;
import android.os.Build;
import android.os.Bundle;
import android.os.Handler;
import android.os.Looper;
import android.os.PersistableBundle;
import android.text.InputType;
import android.view.ViewConfiguration;
import android.view.accessibility.AccessibilityNodeInfo;
import android.view.accessibility.AccessibilityWindowInfo;
import java.util.ArrayList;
import java.util.HashMap;
import java.util.List;
import java.util.Map;
import io.flutter.plugin.common.MethodChannel;

/** Accessibility-only snapshots and field input, restricted to the host app's WebView. */
final class SignupAccessibilityBridge {
    private static final java.util.regex.Pattern PLACEHOLDER_LETTER = java.util.regex.Pattern.compile("[\\p{L}&&[^eE]]");
    private static boolean pasting;
    private static boolean pasteCancelled;

    // GeckoView acknowledges ACTION_PASTE but may read the clipboard seconds
    // later (the first paste of a session took over 2s). Restoring the
    // user's clip right after a failed check let that late paste insert the
    // user's own clipboard, so the restore waits while our text stays put.
    private static final int PASTE_EMPTY_RETRIES = 79;
    private static final long FAILED_RESTORE_DELAY_MS = 10000;
    private static final Handler clipboardHandler = new Handler(Looper.getMainLooper());
    private static ClipboardManager deferredClipboard;
    private static ClipData deferredClip;
    private static String deferredText;
    private static final Runnable deferredRestore = () -> {
        if (deferredClipboard != null) restoreClipboard(deferredClipboard, deferredClip, deferredText);
        deferredClipboard = null; deferredClip = null; deferredText = null;
    };

    private static AccessibilityListener keyboardOwner;
    private static final Handler keyboardHandler = new Handler(Looper.getMainLooper());
    private static final Runnable keyboardExpiry = () -> restoreKeyboard();

    private static void restoreKeyboard() {
        keyboardHandler.removeCallbacks(keyboardExpiry);
        if (keyboardOwner != null) {
            keyboardOwner.getSoftKeyboardController().setShowMode(android.accessibilityservice.AccessibilityService.SHOW_MODE_AUTO);
            keyboardOwner = null;
        }
    }

    static void cancelPaste() { pasteCancelled = true; restoreKeyboard(); }

    static void setKeyboardSuppressed(boolean suppress, MethodChannel.Result result) {
        AccessibilityListener service = AccessibilityListener.currentInstance();
        if (!suppress) { restoreKeyboard(); result.success(true); return; }
        if (service == null || webRoot(service) == null) { result.success(false); return; }
        boolean hidden = service.getSoftKeyboardController().setShowMode(android.accessibilityservice.AccessibilityService.SHOW_MODE_HIDDEN);
        if (hidden) {
            keyboardOwner = service;
            keyboardHandler.removeCallbacks(keyboardExpiry);
            // Lease bounds cancellation/crash recovery; a comment input is short.
            keyboardHandler.postDelayed(keyboardExpiry, 10000);
        }
        keyboardHandler.postDelayed(() -> result.success(hidden), 300);
    }

    static AccessibilityNodeInfo webRoot(AccessibilityListener service) {
        if (service == null) return null;
        // GeckoView can leave prefetched descendants from the previous feed
        // item in Android's cache even after clearCache(). Read nodes without
        // caching/prefetching so text, visibility and bounds match the screen.
        if (Build.VERSION.SDK_INT >= 33 && service.isCacheEnabled()) {
            service.setCacheEnabled(false);
        }
        AccessibilityNodeInfo root = service.getRootInActiveWindow();
        AccessibilityNodeInfo web = findWeb(root, service.getPackageName(), 0);
        if (web != null) return web;
        for (AccessibilityWindowInfo window : service.getWindows()) {
            web = findWeb(window.getRoot(), service.getPackageName(), 0);
            if (web != null) return web;
        }
        return null;
    }

    private static AccessibilityNodeInfo findWeb(AccessibilityNodeInfo node, String pkg, int depth) {
        if (node == null || depth > 40 || !pkg.contentEquals(node.getPackageName() == null ? "" : node.getPackageName())) return null;
        // During GeckoView startup/rotation Android 9 can expose nodes whose
        // class name is still null. Keep walking until the web root is ready.
        if (isWebClass(node.getClassName()) && node.isVisibleToUser()) return node;
        for (int i = 0; i < node.getChildCount(); i++) {
            AccessibilityNodeInfo found = findWeb(node.getChild(i), pkg, depth + 1);
            if (found != null) return found;
        }
        return null;
    }

    static boolean isWebClass(CharSequence className) {
        return className != null && "android.webkit.WebView".contentEquals(className);
    }

    /**
     * Why no WebView was found, for a device that cannot be debugged over ADB:
     * the active window, the app's windows and every WebView/Gecko node there,
     * read without the package filter findWeb applies.
     */
    static String diagnoseMissingWeb() {
        try {
            return diagnoseMissingWeb(AccessibilityListener.currentInstance());
        } catch (RuntimeException error) {
            return "diag-error " + error.getClass().getSimpleName();
        }
    }

    private static String diagnoseMissingWeb(AccessibilityListener service) {
        if (service == null) return "svc=null";
        String pkg = service.getPackageName();
        StringBuilder out = new StringBuilder();
        AccessibilityNodeInfo active = service.getRootInActiveWindow();
        out.append("active=").append(active == null ? "null"
            : pkg.contentEquals(active.getPackageName() == null ? "" : active.getPackageName()) ? "app"
            : String.valueOf(active.getPackageName()));
        List<AccessibilityWindowInfo> windows = service.getWindows();
        out.append(" win=").append(windows.size());
        int[] counts = new int[2]; // nodes in app windows, nodes of another package
        List<String> found = new ArrayList<>();
        int appWindows = 0;
        for (AccessibilityWindowInfo window : windows) {
            AccessibilityNodeInfo root = window.getRoot();
            if (root == null || !pkg.contentEquals(root.getPackageName() == null ? "" : root.getPackageName())) continue;
            appWindows++;
            describeWeb(root, pkg, 0, counts, found);
        }
        out.append(" app=").append(appWindows).append(" n=").append(counts[0])
            .append(" foreign=").append(counts[1]);
        out.append(" web=").append(found.isEmpty() ? "none" : String.join(";", found));
        return out.toString();
    }

    private static void describeWeb(AccessibilityNodeInfo node, String pkg, int depth,
            int[] counts, List<String> found) {
        if (node == null || depth > 60 || counts[0] > 3000) return;
        counts[0]++;
        CharSequence nodePkg = node.getPackageName();
        if (!pkg.contentEquals(nodePkg == null ? "" : nodePkg)) counts[1]++;
        String cls = node.getClassName() == null ? "" : node.getClassName().toString();
        if ((cls.contains("WebView") || cls.contains("Gecko")) && found.size() < 4) {
            Rect r = new Rect(); node.getBoundsInScreen(r);
            found.add(cls.substring(cls.lastIndexOf('.') + 1) + " v" + (node.isVisibleToUser() ? 1 : 0)
                + " c" + node.getChildCount() + " d" + depth + " " + r.width() + "x" + r.height());
        }
        for (int i = 0; i < node.getChildCount(); i++) {
            describeWeb(node.getChild(i), pkg, depth + 1, counts, found);
        }
    }

    static Map<String, Object> snapshot() {
        AccessibilityListener service = AccessibilityListener.currentInstance();
        AccessibilityNodeInfo web = webRoot(service);
        Map<String, Object> result = new HashMap<>();
        result.put("ready", web != null);
        // Android can list the service as enabled while it is not bound
        // (Samsung after an app update shows it "not working").
        result.put("serviceConnected", service != null);
        result.put("keyboardVisible", keyboardVisible(service));
        if (web == null) return result;
        Rect rect = new Rect();
        web.getBoundsInScreen(rect);
        // GeckoView reports its document root at the unzoomed desktop layout
        // size; the platform view hosting it bounds the visible viewport.
        AccessibilityNodeInfo host = web.getParent();
        if (host != null) {
            Rect hostRect = new Rect();
            host.getBoundsInScreen(hostRect);
            rect.intersect(hostRect);
        }
        result.put("webBounds", bounds(rect));
        List<Map<String, Object>> nodes = new ArrayList<>();
        // Nodes present but not visible (e.g. a video clock faded out with its
        // controls). Kept apart so callers reading "nodes" are unaffected.
        List<Map<String, Object>> hidden = new ArrayList<>();
        collect(web, "0", nodes, hidden, 0, web);
        labelSignupBirthdayFields(nodes);
        // HTML select opens a native list outside the WebView subtree.
        java.util.Set<Integer> windows = new java.util.HashSet<>();
        AccessibilityNodeInfo active = service.getRootInActiveWindow();
        if (active != null) {
            windows.add(active.getWindowId());
            collectPickers(active, service.getPackageName(), "picker.active", nodes, 0);
        }
        for (AccessibilityWindowInfo window : service.getWindows()) {
            AccessibilityNodeInfo root = window.getRoot();
            if (root != null && windows.add(root.getWindowId())) {
                collectPickers(root, service.getPackageName(), "picker." + root.getWindowId(), nodes, 0);
            }
        }
        result.put("nodes", nodes);
        result.put("hidden", hidden);
        return result;
    }

    static void labelSignupBirthdayFields(List<Map<String, Object>> nodes) {
        boolean birthdayForm = false;
        List<Map<String, Object>> fields = new ArrayList<>();
        for (Map<String, Object> node : nodes) {
            String text = String.valueOf(node.get("text"));
            if (text.equals("When’s your birthday?*") || text.equals("When's your birthday?*") ||
                    text.equals("When’s your birthday?") || text.equals("When's your birthday?")) birthdayForm = true;
            if ("android.widget.Spinner".equals(node.get("className"))) fields.add(node);
        }
        if (!birthdayForm || fields.size() != 3) return;
        fields.sort((a, b) -> Integer.compare(((List<Integer>) a.get("bounds")).get(0),
            ((List<Integer>) b.get("bounds")).get(0)));
        String[] labels = {"Month", "Day", "Year"};
        List<Integer> first = (List<Integer>) fields.get(0).get("bounds");
        for (Map<String, Object> field : fields) {
            List<Integer> rect = (List<Integer>) field.get("bounds");
            if (rect.get(1) >= first.get(3) || first.get(1) >= rect.get(3)) return;
        }
        for (int i = 0; i < labels.length; i++) {
            if ("".equals(fields.get(i).get("hint"))) fields.get(i).put("hint", labels[i]);
        }
    }

    private static void collectPickers(AccessibilityNodeInfo node, String pkg, String path,
            List<Map<String,Object>> nodes, int depth) {
        if (node == null || depth > 40 || !pkg.contentEquals(node.getPackageName() == null ? "" : node.getPackageName())) return;
        String type = String.valueOf(node.getClassName());
        if (node.isVisibleToUser() && (type.equals("android.widget.ListView") || type.equals("android.widget.NumberPicker"))) {
            int start = nodes.size();
            collect(node, path, nodes, new ArrayList<>(), 0, null);
            for (int i=start; i<nodes.size(); i++) nodes.get(i).put("picker", true);
            return;
        }
        if (type.equals("android.webkit.WebView")) return;
        for (int i=0; i<node.getChildCount(); i++) collectPickers(node.getChild(i),pkg,path+"."+i,nodes,depth+1);
    }

    private static boolean keyboardVisible(AccessibilityListener service) {
        if (service == null) return false;
        for (AccessibilityWindowInfo window : service.getWindows()) {
            if (window.getType() == AccessibilityWindowInfo.TYPE_INPUT_METHOD) return true;
        }
        return false;
    }

    static void dismissKeyboard(MethodChannel.Result result) {
        AccessibilityListener service = AccessibilityListener.currentInstance();
        AccessibilityNodeInfo web = webRoot(service);
        if (web == null) { result.success(false); return; }
        AccessibilityNodeInfo focused = web.findFocus(AccessibilityNodeInfo.FOCUS_INPUT);
        if (focused != null) focused.performAction(AccessibilityNodeInfo.ACTION_CLEAR_FOCUS);
        if (!keyboardVisible(service)) { result.success(true); return; }
        // GLOBAL_ACTION_BACK can pop Flutter's route instead of consuming IME.
        // Hide only the soft keyboard. GeckoView ignores ACTION_CLEAR_FOCUS, so
        // its editor keeps input focus and restoring AUTO at once reopens the
        // IME (it flickers). Hold it hidden on the lease long enough to submit.
        boolean hidden = service.getSoftKeyboardController().setShowMode(android.accessibilityservice.AccessibilityService.SHOW_MODE_HIDDEN);
        if (hidden) {
            keyboardOwner = service;
            keyboardHandler.removeCallbacks(keyboardExpiry);
            keyboardHandler.postDelayed(keyboardExpiry, 10000);
        }
        keyboardHandler.postDelayed(() -> result.success(hidden), 300);
    }

    private static List<Integer> bounds(Rect rect) {
        List<Integer> values = new ArrayList<>();
        values.add(rect.left); values.add(rect.top); values.add(rect.right); values.add(rect.bottom);
        return values;
    }

    private static String safe(CharSequence text) {
        if (text == null) return "";
        return text.toString().replaceAll("[A-Za-z0-9.!#$%&'*+/=?^_`{|}~-]+@[A-Za-z0-9.-]+", "[email]")
            .replaceAll("\\b[0-9]{6}\\b", "[code]");
    }

    private static CharSequence editorValue(AccessibilityNodeInfo editor) {
        // Chromium may expose the placeholder as getText() on empty editors.
        // A hint is not a draft and must not contribute to entered length.
        if ((Build.VERSION.SDK_INT >= 26 && editor.isShowingHintText()) || numericPlaceholder(editor)) return null;
        CharSequence value = editor.getText();
        // TikTok's empty contenteditable can expose a newline/zero-width filler
        // instead of null. This is neither a draft nor entered comment content.
        if (isCommentEditor(editor) && comparableComment(value).isEmpty()) return null;
        return value;
    }

    private static boolean isCommentEditor(AccessibilityNodeInfo editor) {
        CharSequence raw = editorHint(editor);
        String hint = raw == null ? "" : raw.toString().toLowerCase(java.util.Locale.ROOT);
        return !editor.isPassword() && (hint.contains("comment") || hint.contains("bình luận"));
    }

    static String comparableComment(CharSequence value) {
        if (value == null) return "";
        // Normalize only the edges; preserve meaningful internal whitespace and
        // emoji joiners. Login/password values must never use this normalization.
        String text = value.toString();
        int start = 0, end = text.length();
        while (start < end && commentFiller(text.codePointAt(start))) start += Character.charCount(text.codePointAt(start));
        while (end > start && commentFiller(text.codePointBefore(end))) end -= Character.charCount(text.codePointBefore(end));
        return text.substring(start, end);
    }

    private static boolean commentFiller(int codePoint) {
        return Character.isWhitespace(codePoint) || Character.isSpaceChar(codePoint) ||
            (Character.getType(codePoint) == Character.FORMAT && codePoint != 0x200C && codePoint != 0x200D);
    }

    private static boolean numericPlaceholder(AccessibilityNodeInfo editor) {
        int inputClass = editor.getInputType() & InputType.TYPE_MASK_CLASS;
        // WebView 134 omits both hintText and showingHintText for number inputs.
        // Letters other than exponent e/E cannot be an HTML number value.
        return !editor.isPassword() &&
            inputClass == InputType.TYPE_CLASS_NUMBER &&
            editor.getText() != null && PLACEHOLDER_LETTER.matcher(editor.getText()).find();
    }

    private static CharSequence editorHint(AccessibilityNodeInfo editor) {
        CharSequence hint = Build.VERSION.SDK_INT >= 26 ? editor.getHintText() : null;
        if (hint != null && hint.length() > 0) return hint;
        return numericPlaceholder(editor) ? editor.getText() : null;
    }

    private static void collect(AccessibilityNodeInfo node, String path, List<Map<String, Object>> nodes,
            List<Map<String, Object>> hidden, int depth, AccessibilityNodeInfo web) {
        if (node == null || depth > 40 || nodes.size() >= 1200) return;
        // Older Android versions cannot disable the accessibility cache.
        if (Build.VERSION.SDK_INT < 33 && !node.refresh()) return;
        if (!node.isVisibleToUser() && hidden.size() < 600) {
            Rect rect = new Rect(); node.getBoundsInScreen(rect);
            Map<String, Object> item = new HashMap<>();
            item.put("id", path);
            item.put("className", String.valueOf(node.getClassName()));
            item.put("bounds", bounds(rect));
            item.put("editable", node.isEditable());
            item.put("focused", node.isFocused());
            // Preserve draft detection when Gecko marks an unfocused editor
            // hidden. Only the length is exposed, never its input text.
            CharSequence hiddenValue = node.isEditable() ? editorValue(node) : null;
            item.put("length", hiddenValue == null ? 0 : hiddenValue.length());
            item.put("text", node.isEditable() || node.isPassword() ? "" : safe(node.getText()));
            item.put("description", node.isEditable() || node.isPassword() ? "" : safe(node.getContentDescription()));
            item.put("hint", node.isEditable() ? safe(editorHint(node)) : "");
            hidden.add(item);
        }
        if (node.isVisibleToUser()) {
            Rect rect = new Rect(); node.getBoundsInScreen(rect);
            Map<String, Object> item = new HashMap<>();
            item.put("id", path);
            item.put("className", String.valueOf(node.getClassName()));
            item.put("bounds", bounds(rect));
            item.put("enabled", node.isEnabled());
            item.put("clickable", node.isClickable());
            item.put("scrollable", node.isScrollable());
            item.put("editable", node.isEditable());
            item.put("password", node.isPassword());
            item.put("focused", node.isFocused());
            item.put("selected", node.isSelected());
            item.put("inputType", node.getInputType());
            CharSequence value = node.isEditable() ? editorValue(node) : null;
            item.put("length", value == null ? 0 : value.length());
            // Field values must never reach calibration files or debug logs.
            item.put("text", node.isEditable() || node.isPassword() ? "" : safe(node.getText()));
            item.put("description", node.isEditable() || node.isPassword() ? "" : safe(node.getContentDescription()));
            String hint = node.isEditable() ? safe(editorHint(node)) : Build.VERSION.SDK_INT >= 26 ? safe(node.getHintText()) : "";
            // WebView 155 can omit hintText for TikTok's type=text email input.
            // Infer only a fixed label from the visible, unambiguous signup form;
            // never expose the editor's value as a hint.
            if (hint.isEmpty() && signupEmailEditor(web, node)) hint = "Email address";
            if (hint.isEmpty() && signupOtpEditor(web, node)) hint = "Verification code";
            if (hint.isEmpty() && loginUsernameEditor(node)) hint = "Username or email";
            item.put("hint", hint);
            nodes.add(item);
        }
        for (int i = 0; i < node.getChildCount(); i++) collect(node.getChild(i), path + "." + i, nodes, hidden, depth + 1, web);
    }

    private static AccessibilityNodeInfo staticLabel(AccessibilityNodeInfo node, String label, int depth) {
        if (node == null || depth > 40) return null;
        if (node.isVisibleToUser() && !node.isEditable() && !node.isPassword() &&
                (matchesStaticLabel(node.getText(), label) || matchesStaticLabel(node.getContentDescription(), label))) return node;
        for (int i = 0; i < node.getChildCount(); i++) {
            AccessibilityNodeInfo found = staticLabel(node.getChild(i), label, depth + 1);
            if (found != null) return found;
        }
        return null;
    }

    private static boolean matchesStaticLabel(CharSequence value, String label) {
        return value != null && label.equalsIgnoreCase(value.toString().trim().replaceFirst("\\s*\\*$", ""));
    }

    private static boolean signupEmailEditor(AccessibilityNodeInfo web, AccessibilityNodeInfo editor) {
        if (web == null || editor == null || !editor.isEditable() || !editor.isEnabled() ||
                !editor.isVisibleToUser() || editor.isPassword() ||
                (editor.getInputType() & InputType.TYPE_MASK_CLASS) != InputType.TYPE_CLASS_TEXT ||
                editableCount(web, 0) != 1) return false;
        // "Use phone" means the email tab is selected. The phone tab instead
        // offers "Use email"; neither OTP nor unrelated text fields qualify.
        AccessibilityNodeInfo label = staticLabel(web, "Enter your email", 0);
        if (label == null || staticLabel(web, "Use phone", 0) == null) return false;
        Rect prompt = new Rect(), input = new Rect();
        label.getBoundsInScreen(prompt);
        editor.getBoundsInScreen(input);
        // Accessibility line boxes can overlap the input border by a few pixels.
        return !input.isEmpty() && prompt.exactCenterY() <= input.top &&
            input.top - prompt.bottom <= input.height() * 3 &&
            prompt.left < input.right && input.left < prompt.right;
    }

    /** Desktop Gecko can expose a single OTP input as plain text with no hint. */
    private static boolean signupOtpEditor(AccessibilityNodeInfo web, AccessibilityNodeInfo editor) {
        if (web == null || editor == null || !editor.isEditable() || !editor.isEnabled() ||
                !editor.isVisibleToUser() || editor.isPassword()) return false;
        AccessibilityNodeInfo prompt = staticLabel(web, "Enter 6-digit code", 0);
        if (prompt == null) prompt = staticLabel(web, "Verify your email", 0);
        if (prompt == null) return false;
        Rect title = new Rect(), input = new Rect();
        prompt.getBoundsInScreen(title);
        editor.getBoundsInScreen(input);
        // A header search input is above the verification title. Only the
        // field directly below that title, in the same modal column, qualifies.
        return !input.isEmpty() && input.top >= title.bottom &&
            input.top - title.bottom <= input.height() * 6 &&
            title.left < input.right && input.left < title.right;
    }

    private static boolean loginUsernameEditor(AccessibilityNodeInfo editor) {
        if (editor == null || !editor.isEditable() || !editor.isEnabled() ||
                !editor.isVisibleToUser() || editor.isPassword() ||
                (editor.getInputType() & InputType.TYPE_MASK_CLASS) != InputType.TYPE_CLASS_TEXT) return false;
        // TikTok/WebView 155 can omit the placeholder entirely. Restrict the
        // inferred label to the two-field username/password login dialog.
        AccessibilityNodeInfo dialog = editor.getParent();
        for (int depth = 0; dialog != null && depth < 40; depth++, dialog = dialog.getParent()) {
            if (!"android.app.AlertDialog".contentEquals(dialog.getClassName())) continue;
            if (staticLabel(dialog, "Log in", 0) == null ||
                    staticLabel(dialog, "Username or email", 0) == null ||
                    staticLabel(dialog, "Continue", 0) == null) return false;
            List<AccessibilityNodeInfo> fields = new ArrayList<>();
            loginFields(dialog, fields, 0);
            if (fields.size() != 2) return false;
            AccessibilityNodeInfo password = fields.get(0).isPassword() ? fields.get(0) : fields.get(1);
            AccessibilityNodeInfo username = fields.get(0).isPassword() ? fields.get(1) : fields.get(0);
            if (!password.isPassword() || username.isPassword() || !editor.equals(username)) return false;
            Rect nameBounds = new Rect(), passwordBounds = new Rect();
            username.getBoundsInScreen(nameBounds);
            password.getBoundsInScreen(passwordBounds);
            return !nameBounds.isEmpty() && !passwordBounds.isEmpty() &&
                nameBounds.bottom <= passwordBounds.top &&
                nameBounds.left < passwordBounds.right && passwordBounds.left < nameBounds.right;
        }
        return false;
    }

    private static void loginFields(AccessibilityNodeInfo node, List<AccessibilityNodeInfo> fields, int depth) {
        if (node == null || depth > 40) return;
        if (node.isEditable() && node.isEnabled() && node.isVisibleToUser()) fields.add(node);
        for (int i = 0; i < node.getChildCount(); i++) loginFields(node.getChild(i), fields, depth + 1);
    }

    /** Clear only the exact rejected OTP inserted by the current app attempt. */
    static void clearOtp(String expected, MethodChannel.Result result) {
        if (pasting || expected == null || !expected.matches("[0-9]{6}")) { result.success(false); return; }
        AccessibilityListener service = AccessibilityListener.currentInstance();
        AccessibilityNodeInfo web = webRoot(service);
        List<AccessibilityNodeInfo> fields = new ArrayList<>();
        collectOtpEditors(web, fields, 0);
        if (fields.size() != 1 && fields.size() != 6) { result.success(false); return; }
        StringBuilder value = new StringBuilder();
        for (AccessibilityNodeInfo field : fields) {
            if (!field.refresh()) { result.success(false); return; }
            CharSequence text = editorValue(field);
            if (text != null) value.append(text);
        }
        if (!expected.contentEquals(value)) { result.success(false); return; }
        Bundle empty = new Bundle();
        empty.putCharSequence(AccessibilityNodeInfo.ACTION_ARGUMENT_SET_TEXT_CHARSEQUENCE, "");
        for (int i = fields.size() - 1; i >= 0; i--) {
            if (!fields.get(i).performAction(AccessibilityNodeInfo.ACTION_SET_TEXT, empty)) { result.success(false); return; }
        }
        verifyClearedOtp(service, result, 0);
    }

    /**
     * Empty only comment editors holding exactly the comment this app typed,
     * so a failed attempt never carries it to another post. True once none does.
     */
    static void clearComment(String expected, MethodChannel.Result result) {
        String wanted = comparableComment(expected);
        if (pasting || wanted.isEmpty()) { result.success(false); return; }
        AccessibilityListener service = AccessibilityListener.currentInstance();
        List<AccessibilityNodeInfo> drafts = new ArrayList<>();
        collectCommentDrafts(webRoot(service), wanted, drafts, 0);
        Bundle empty = new Bundle();
        empty.putCharSequence(AccessibilityNodeInfo.ACTION_ARGUMENT_SET_TEXT_CHARSEQUENCE, "");
        for (AccessibilityNodeInfo draft : drafts) draft.performAction(AccessibilityNodeInfo.ACTION_SET_TEXT, empty);
        verifyClearedComment(service, wanted, result, 0);
    }

    private static void verifyClearedComment(AccessibilityListener service, String wanted, MethodChannel.Result result, int retry) {
        keyboardHandler.postDelayed(() -> {
            List<AccessibilityNodeInfo> drafts = new ArrayList<>();
            collectCommentDrafts(webRoot(service), wanted, drafts, 0);
            if (drafts.isEmpty() || retry >= 19) result.success(drafts.isEmpty());
            else verifyClearedComment(service, wanted, result, retry + 1);
        }, 100);
    }

    private static void collectCommentDrafts(AccessibilityNodeInfo node, String wanted, List<AccessibilityNodeInfo> drafts, int depth) {
        if (node == null || depth > 40) return;
        // The search player's editor may sit past the WebView edge; visibility is not required.
        if (node.isEditable() && node.refresh() && isCommentEditor(node) &&
                wanted.equals(comparableComment(editorValue(node)))) drafts.add(node);
        for (int i = 0; i < node.getChildCount(); i++) collectCommentDrafts(node.getChild(i), wanted, drafts, depth + 1);
    }

    private static void verifyClearedOtp(AccessibilityListener service, MethodChannel.Result result, int retry) {
        keyboardHandler.postDelayed(() -> {
            List<AccessibilityNodeInfo> fields = new ArrayList<>();
            collectOtpEditors(webRoot(service), fields, 0);
            boolean empty = !fields.isEmpty();
            for (AccessibilityNodeInfo field : fields) {
                CharSequence text = editorValue(field);
                if (text != null && text.length() > 0) empty = false;
            }
            if (empty || retry >= 19) result.success(empty);
            else verifyClearedOtp(service, result, retry + 1);
        }, 100);
    }

    private static void collectOtpEditors(AccessibilityNodeInfo node, List<AccessibilityNodeInfo> fields, int depth) {
        if (node == null || depth > 40) return;
        if (node.isVisibleToUser() && node.isEditable() && node.isEnabled() && !node.isPassword()) {
            String hint = safe(editorHint(node)).toLowerCase(java.util.Locale.ROOT);
            int inputClass = node.getInputType() & InputType.TYPE_MASK_CLASS;
            if (hint.contains("code") || hint.contains("otp") || hint.contains("mã") ||
                    inputClass == InputType.TYPE_CLASS_NUMBER || inputClass == InputType.TYPE_CLASS_PHONE) fields.add(node);
        }
        for (int i = 0; i < node.getChildCount(); i++) collectOtpEditors(node.getChild(i), fields, depth + 1);
    }

    static void paste(String text, String field, MethodChannel.Result result) {
        AccessibilityListener service = AccessibilityListener.currentInstance();
        AccessibilityNodeInfo web = webRoot(service);
        AccessibilityNodeInfo inputFocus = web == null ? null : web.findFocus(AccessibilityNodeInfo.FOCUS_INPUT);
        // Input focus is resolved through the Android view hierarchy. When a
        // Flutter view (snackbar, semantics update) holds it, findFocus misses
        // the WebView even though its editor is still focused in the page.
        final AccessibilityNodeInfo editor = web != null && (inputFocus == null || !inputFocus.refresh() || !inputFocus.isEditable())
            ? focusedEditor(web, 0) : inputFocus;
        String unavailable = pasting ? "busy" : field == null || text == null || text.isEmpty() ? "no-text" :
            web == null ? "no-webview" : editor == null ? "no-focused-editor" : !editor.refresh() ? "editor-detached" :
            !editor.isVisibleToUser() ? "editor-hidden" : !editor.isEditable() || !editor.isEnabled() ? "editor-disabled" :
            !service.getPackageName().contentEquals(editor.getPackageName()) ? "foreign-editor" : null;
        if (unavailable != null) {
            result.success(status(false, "editor-unavailable:" + unavailable)); return;
        }
        if (!field.equals("email") && !field.equals("password") && !field.equals("otp") && !field.equals("comment") &&
                !field.equals("search") ||
                field.equals("password") != editor.isPassword() ||
                field.equals("otp") && !text.matches("[0-9]{6}")) {
            result.success(status(false, "wrong-field")); return;
        }
        String hint = Build.VERSION.SDK_INT >= 26 && editor.getHintText() != null ? editor.getHintText().toString().toLowerCase(java.util.Locale.ROOT) : "";
        if (field.equals("email") && !hint.contains("email") &&
                (editor.getInputType() & InputType.TYPE_MASK_VARIATION) != InputType.TYPE_TEXT_VARIATION_EMAIL_ADDRESS &&
                !signupEmailEditor(web, editor) && !loginUsernameEditor(editor)) {
            result.success(status(false, "wrong-email-field")); return;
        }
        if (field.equals("comment") && !hint.contains("comment") && !hint.contains("bình luận")) {
            result.success(status(false, "wrong-comment-field")); return;
        }
        int inputClass = editor.getInputType() & InputType.TYPE_MASK_CLASS;
        // Background page inputs (e.g. search) stay exposed behind the modal,
        // so count only the slots on the focused editor's row.
        int otpSlots = field.equals("otp") ? rowEditableCount(web, editor) : 0;
        boolean splitOtp = otpSlots == 6;
        if (field.equals("otp") && !splitOtp && inputClass != InputType.TYPE_CLASS_NUMBER && inputClass != InputType.TYPE_CLASS_PHONE &&
                !hint.contains("code") && !hint.contains("otp") && !hint.contains("mã") && !signupOtpEditor(web, editor)) {
            result.success(status(false, "wrong-otp-field:slots=" + otpSlots + ",page=" + editableCount(web, 0) +
                ",class=" + inputClass)); return;
        }
        CharSequence previous = editorValue(editor);
        if (field.equals("search") && previous != null && previous.length() > 0) {
            // A search box may keep the last query; select it so the paste
            // replaces it. A query is not a draft worth preserving.
            Bundle selection = new Bundle();
            selection.putInt(AccessibilityNodeInfo.ACTION_ARGUMENT_SELECTION_START_INT, 0);
            selection.putInt(AccessibilityNodeInfo.ACTION_ARGUMENT_SELECTION_END_INT, previous.length());
            if (!editor.performAction(AccessibilityNodeInfo.ACTION_SET_SELECTION, selection)) {
                result.success(status(false, "search-not-cleared")); return;
            }
        } else if (previous != null && previous.length() > 0) {
            result.success(status(text.contentEquals(previous), "draft-exists")); return;
        }
        ClipboardManager clipboard = (ClipboardManager) service.getSystemService(Context.CLIPBOARD_SERVICE);
        ClipData currentClip = clipboard.getPrimaryClip();
        // A failed paste may still hold the clipboard: keep the user's clip
        // unless they copied something new in the meantime.
        boolean held = deferredClipboard != null && currentClip != null && currentClip.getItemCount() > 0 &&
            deferredText.contentEquals(currentClip.getItemAt(0).getText());
        ClipData oldClip = held ? deferredClip : currentClip;
        clipboardHandler.removeCallbacks(deferredRestore);
        deferredClipboard = null; deferredClip = null; deferredText = null;
        ClipData clip = ClipData.newPlainText("", text);
        PersistableBundle extras = new PersistableBundle();
        extras.putBoolean("android.content.extra.IS_SENSITIVE", true);
        clip.getDescription().setExtras(extras);
        pasting = true;
        pasteCancelled = false;
        try {
            clipboard.setPrimaryClip(clip);
            if (field.equals("otp") && !splitOtp && inputClass == InputType.TYPE_CLASS_NUMBER) {
                // Chromium acknowledges ACTION_PASTE for HTML number inputs
                // without inserting, and exposes no floating Paste menu.
                // Use the editor's Accessibility action, never DOM/InputConnection.
                Bundle arguments = new Bundle();
                arguments.putCharSequence(AccessibilityNodeInfo.ACTION_ARGUMENT_SET_TEXT_CHARSEQUENCE, text);
                if (!editor.performAction(AccessibilityNodeInfo.ACTION_SET_TEXT, arguments)) {
                    failPaste(clipboard, oldClip, text, result, "numeric-input-rejected"); return;
                }
                verifyPaste(editor, text, field, clipboard, oldClip, result, 0, null);
                return;
            }
            if (splitOtp) {
                // Chromium's ACTION_PASTE acknowledges the six-slot OTP view
                // without filling it. The real floating Paste menu does work.
                longPressPaste(service, editor, text, field, clipboard, oldClip, result);
                return;
            }
            boolean accepted = editor.performAction(AccessibilityNodeInfo.ACTION_PASTE);
            if (!accepted) {
                // A single-field OTP may still accept the real Paste menu.
                if (field.equals("otp")) { longPressPaste(service, editor, text, field, clipboard, oldClip, result); return; }
                restoreClipboard(clipboard, oldClip, text); pasting = false;
                result.success(status(false, "paste-rejected")); return;
            }
            verifyPaste(editor, text, field, clipboard, oldClip, result, 0,
                field.equals("otp") ? () -> longPressPaste(service, editor, text, field, clipboard, oldClip, result)
                : field.equals("email") ? () -> {
                    // Only the unchanged, focused, empty email field may use
                    // the Accessibility SET_TEXT fallback after paste did nothing.
                    if (!pasteCancelled && editor.refresh() && editor.isFocused() &&
                            (signupEmailEditor(webRoot(service), editor) || loginUsernameEditor(editor))) {
                        CharSequence current = editorValue(editor);
                        if (current == null || current.length() == 0) {
                            Bundle arguments = new Bundle();
                            arguments.putCharSequence(AccessibilityNodeInfo.ACTION_ARGUMENT_SET_TEXT_CHARSEQUENCE, text);
                            if (editor.performAction(AccessibilityNodeInfo.ACTION_SET_TEXT, arguments)) {
                                verifyPaste(editor, text, field, clipboard, oldClip, result, 0, null);
                                return;
                            }
                        }
                    }
                    failPaste(clipboard, oldClip, text, result, "email-input-not-confirmed");
                }
                // TikTok's comment box sometimes acknowledges ACTION_PASTE
                // without inserting. A long press there selects the
                // placeholder text instead of offering Paste, so retry the
                // action once on the still-focused, still-empty editor.
                : field.equals("comment") || field.equals("search") ? () -> {
                    if (!pasteCancelled && editor.refresh() && editor.isFocused() &&
                            editor.performAction(AccessibilityNodeInfo.ACTION_PASTE)) {
                        verifyPaste(editor, text, field, clipboard, oldClip, result, 0, null);
                    } else failPaste(clipboard, oldClip, text, result, "paste-not-inserted");
                } : null);
        } catch (Exception ignored) {
            restoreClipboardLater(clipboard, oldClip, text); pasting = false;
            result.success(status(false, "paste-failed"));
        }
    }

    private static void longPressPaste(AccessibilityListener service, AccessibilityNodeInfo editor, String text, String field,
            ClipboardManager clipboard, ClipData oldClip, MethodChannel.Result result) {
        Rect rect = new Rect(); editor.getBoundsInScreen(rect);
        gesture(service, rect.exactCenterX(), rect.exactCenterY(), longPressDuration(), () ->
            pasteMenu(service, editor, text, field, clipboard, oldClip, result, 0), () ->
            failPaste(clipboard, oldClip, text, result, "long-press-failed"));
    }

    /** Outlasts the device's "Touch & hold delay" (400/1000/1500ms), never under 850ms. */
    static int longPressDuration() {
        return Math.max(850, ViewConfiguration.getLongPressTimeout() + 450);
    }

    private static void gesture(AccessibilityListener service, float x, float y, int duration,
            Runnable complete, Runnable failed) {
        Path path = new Path(); path.moveTo(x, y);
        GestureDescription description = new GestureDescription.Builder()
            .addStroke(new GestureDescription.StrokeDescription(path, 0, duration)).build();
        boolean sent = service.dispatchGesture(description,
            new android.accessibilityservice.AccessibilityService.GestureResultCallback() {
                @Override public void onCompleted(GestureDescription gesture) { complete.run(); }
                @Override public void onCancelled(GestureDescription gesture) { failed.run(); }
            }, null);
        if (!sent) failed.run();
    }

    private static void pasteMenu(AccessibilityListener service, AccessibilityNodeInfo editor, String text, String field,
            ClipboardManager clipboard, ClipData oldClip, MethodChannel.Result result, int retry) {
        new Handler(Looper.getMainLooper()).postDelayed(() -> {
            if (pasteCancelled || AccessibilityListener.currentInstance() != service || webRoot(service) == null ||
                    !editor.refresh() || !editor.isFocused()) {
                failPaste(clipboard, oldClip, text, result, "editor-changed"); return;
            }
            AccessibilityNodeInfo menu = hostPasteMenu(service.getRootInActiveWindow(), service.getPackageName());
            if (menu == null) {
                for (AccessibilityWindowInfo window : service.getWindows()) {
                    if (window.getType() != AccessibilityWindowInfo.TYPE_APPLICATION) continue;
                    menu = hostPasteMenu(window.getRoot(), service.getPackageName());
                    if (menu != null) break;
                }
            }
            if (menu == null) {
                if (retry < 14) pasteMenu(service, editor, text, field, clipboard, oldClip, result, retry+1);
                else failPaste(clipboard, oldClip, text, result, "paste-menu-unavailable");
                return;
            }
            Rect rect = new Rect(); menu.getBoundsInScreen(rect);
            gesture(service, rect.exactCenterX(), rect.exactCenterY(), 140, () ->
                verifyPaste(editor, text, field, clipboard, oldClip, result, 0, null), () ->
                failPaste(clipboard, oldClip, text, result, "paste-menu-tap-failed"));
        }, 100);
    }

    private static AccessibilityNodeInfo hostPasteMenu(AccessibilityNodeInfo root, String pkg) {
        if (root == null || !pkg.contentEquals(root.getPackageName() == null ? "" : root.getPackageName())) return null;
        return findPasteMenu(root,pkg,0);
    }

    private static AccessibilityNodeInfo findPasteMenu(AccessibilityNodeInfo node, String pkg, int depth) {
        if (node == null || depth > 40) return null;
        CharSequence owner = node.getPackageName();
        String text = node.getText() == null ? "" : node.getText().toString().trim();
        // Android 17 embeds SystemUI's floating toolbar inside a host-owned
        // application window. The window owner is checked before traversing.
        boolean toolbarOwner = owner != null && (pkg.contentEquals(owner) || "com.android.systemui".contentEquals(owner) || "android".contentEquals(owner));
        if (node.isVisibleToUser() && node.isEnabled() && toolbarOwner &&
                (text.equalsIgnoreCase("Paste") || text.equalsIgnoreCase("Dán"))) return node;
        for (int i=0; i<node.getChildCount(); i++) {
            AccessibilityNodeInfo found = findPasteMenu(node.getChild(i), pkg, depth+1);
            if (found != null) return found;
        }
        return null;
    }

    private static void failPaste(ClipboardManager clipboard, ClipData oldClip, String text,
            MethodChannel.Result result, String reason) {
        restoreClipboardLater(clipboard, oldClip, text); pasting = false;
        result.success(status(false, reason));
    }

    private static void restoreClipboardLater(ClipboardManager clipboard, ClipData oldClip, String text) {
        clipboardHandler.removeCallbacks(deferredRestore);
        deferredClipboard = clipboard; deferredClip = oldClip; deferredText = text;
        clipboardHandler.postDelayed(deferredRestore, FAILED_RESTORE_DELAY_MS);
    }

    /** Scroll a clipped Post into view before any draft is entered. Never clicks it. */
    static Map<String, Object> revealCommentPost(String editorId, List<? extends Number> expectedBounds) {
        Map<String, Object> result = new HashMap<>();
        result.put("ok", false);
        AccessibilityNodeInfo web = webRoot(AccessibilityListener.currentInstance());
        if (web == null) { result.put("reason", "web-unavailable"); return result; }
        AccessibilityNodeInfo editor = commentEditorAt(web, editorId, expectedBounds);
        if (editor == null) { result.put("reason", "editor-unavailable"); return result; }
        if (editorValue(editor) != null && editorValue(editor).length() > 0) {
            result.put("reason", "draft-exists"); return result;
        }
        AccessibilityNodeInfo scope = editor;
        AccessibilityNodeInfo post = null;
        for (int level = 0; level < 4 && scope != null; level++) {
            scope = scope.getParent();
            post = findPost(scope, 0, false);
            if (post != null) break;
        }
        if (post == null) { result.put("reason", "post-unavailable"); return result; }
        Rect viewport = new Rect(), bounds = new Rect();
        web.getBoundsInScreen(viewport);
        AccessibilityNodeInfo host = web.getParent();
        if (host != null) {
            Rect hostBounds = new Rect(); host.getBoundsInScreen(hostBounds);
            if (!viewport.intersect(hostBounds)) viewport.setEmpty();
        }
        post.getBoundsInScreen(bounds);
        boolean visible = post.isVisibleToUser() && !bounds.isEmpty() && viewport.contains(bounds);
        boolean requested = visible || post.performAction(
            AccessibilityNodeInfo.AccessibilityAction.ACTION_SHOW_ON_SCREEN.getId());
        result.put("ok", requested);
        result.put("reason", visible ? "post-visible" : requested ? "post-reveal-requested" : "post-offscreen");
        return result; // Dart re-reads and verifies bounds after the layout settles.
    }

    private static AccessibilityNodeInfo commentEditorAt(AccessibilityNodeInfo web,
            String id, List<? extends Number> expectedBounds) {
        if (id == null || !id.matches("0(?:\\.[0-9]+){0,40}") || expectedBounds == null || expectedBounds.size() != 4) return null;
        AccessibilityNodeInfo editor = web;
        String[] indices = id.split("\\.");
        for (int i = 1; i < indices.length; i++) {
            if (editor == null || !editor.refresh()) return null;
            int index;
            try { index = Integer.parseInt(indices[i]); } catch (NumberFormatException e) { return null; }
            if (index >= editor.getChildCount()) return null;
            editor = editor.getChild(index);
        }
        if (editor == null || !editor.refresh() || !editor.isVisibleToUser() ||
                !editor.isEditable() || !editor.isEnabled() || editor.isPassword()) return null;
        Rect bounds = new Rect(); editor.getBoundsInScreen(bounds);
        Rect expected = new Rect(expectedBounds.get(0).intValue(), expectedBounds.get(1).intValue(),
            expectedBounds.get(2).intValue(), expectedBounds.get(3).intValue());
        return !bounds.isEmpty() && bounds.equals(expected) ? editor : null;
    }

    /** ACTION_CLICK on the Post control beside the filled comment editor. */
    static boolean submitComment() {
        AccessibilityNodeInfo web = webRoot(AccessibilityListener.currentInstance());
        return web != null && submitFrom(web, 0);
    }

    // A filled comment box drops its "Add comment" hint and loses focus once
    // the keyboard is dismissed, so it is identified as a non-empty editor
    // with a Post control inside its own container (at most four levels up).
    private static boolean submitFrom(AccessibilityNodeInfo node, int depth) {
        if (node == null || depth > 40) return false;
        // Cached nodes keep the editor's pre-paste (empty) text until refreshed;
        // without this the filled editor and its Post are never matched.
        if (Build.VERSION.SDK_INT < 33 && !node.refresh()) return false;
        if (node.isEditable() && !node.isPassword() && node.getText() != null &&
                !comparableComment(node.getText()).isEmpty()) {
            AccessibilityNodeInfo scope = node;
            for (int level = 0; level < 4 && scope != null; level++) {
                scope = scope.getParent();
                AccessibilityNodeInfo post = findPost(scope, 0);
                if (post == null) continue;
                // Enter submits a TikTok comment. A click on the clipped,
                // zero-width Post button is acknowledged but lands nowhere.
                if (Build.VERSION.SDK_INT >= 30 && node.performAction(
                        AccessibilityNodeInfo.AccessibilityAction.ACTION_IME_ENTER.getId())) return true;
                return post.performAction(AccessibilityNodeInfo.ACTION_CLICK);
            }
        }
        for (int i=0; i<node.getChildCount(); i++) {
            if (submitFrom(node.getChild(i), depth+1)) return true;
        }
        return false;
    }

    private static AccessibilityNodeInfo findPost(AccessibilityNodeInfo node, int depth) {
        return findPost(node, depth, true);
    }

    private static AccessibilityNodeInfo findPost(AccessibilityNodeInfo node, int depth, boolean requireEnabled) {
        if (node == null || depth > 12) return null;
        if (Build.VERSION.SDK_INT < 33 && !node.refresh()) return null;
        // Gecko exposes the search player's Post as text with an empty (not
        // null) description; match SignupNode.name and skip empty labels.
        CharSequence description = node.getContentDescription();
        String label = (description != null && description.length() > 0 ? description
            : node.getText() != null ? node.getText() : "").toString().trim();
        if ((!requireEnabled || node.isEnabled()) && !node.isEditable() && label.equalsIgnoreCase("Post")) return node;
        for (int i=0; i<node.getChildCount(); i++) {
            AccessibilityNodeInfo found = findPost(node.getChild(i), depth+1, requireEnabled);
            if (found != null) return found;
        }
        return null;
    }

    private static AccessibilityNodeInfo focusedEditor(AccessibilityNodeInfo node, int depth) {
        if (node == null || depth > 40) return null;
        if (node.isEditable() && node.isFocused() && node.isVisibleToUser()) return node;
        for (int i=0; i<node.getChildCount(); i++) {
            AccessibilityNodeInfo found = focusedEditor(node.getChild(i), depth+1);
            if (found != null) return found;
        }
        return null;
    }

    /** Visible non-password editors whose vertical center lies within [editor]'s row. */
    private static int rowEditableCount(AccessibilityNodeInfo web, AccessibilityNodeInfo editor) {
        Rect row = new Rect(); editor.getBoundsInScreen(row);
        if (row.isEmpty()) return 0;
        List<AccessibilityNodeInfo> fields = new ArrayList<>();
        loginFields(web, fields, 0);
        int count = 0;
        for (AccessibilityNodeInfo field : fields) {
            if (field.isPassword()) continue;
            Rect bounds = new Rect(); field.getBoundsInScreen(bounds);
            if (!bounds.isEmpty() && bounds.centerY() >= row.top && bounds.centerY() <= row.bottom) count++;
        }
        return count;
    }

    private static int editableCount(AccessibilityNodeInfo node, int depth) {
        if (node == null || depth > 40) return 0;
        int count = node.isVisibleToUser() && node.isEditable() && !node.isPassword() ? 1 : 0;
        for (int i=0; i<node.getChildCount(); i++) count += editableCount(node.getChild(i), depth+1);
        return count;
    }

    private static void verifyPaste(AccessibilityNodeInfo editor, String text, String field,
            ClipboardManager clipboard, ClipData oldClip, MethodChannel.Result result, int retry, Runnable emptyFallback) {
        new Handler(Looper.getMainLooper()).postDelayed(() -> {
            try {
                if (pasteCancelled) {
                    failPaste(clipboard, oldClip, text, result, "cancelled"); return;
                }
                boolean attached = editor.refresh();
                CharSequence value = attached ? editorValue(editor) : null;
                boolean exact = value != null && (field.equals("comment")
                    ? comparableComment(text).equals(comparableComment(value)) : text.contentEquals(value));
                boolean passwordLength = field.equals("password") && value != null && value.length() == text.length();
                // A six-digit paste can immediately replace the OTP view.
                AccessibilityNodeInfo web = field.equals("otp") ? webRoot(AccessibilityListener.currentInstance()) : null;
                // Report a view transition, not successful authentication. The
                // Dart runner independently waits for the signed-in screen.
                boolean otpAdvanced = field.equals("otp") && web != null &&
                    (!attached || !editor.isEditable() || editableCount(web, 0) == 0 || hasPasswordEditor(web, 0));
                boolean splitMatched = field.equals("otp") && text.equals(editableText(web, 0));
                boolean empty = attached && (value == null || value.length() == 0);
                // An empty field may still receive a slow GeckoView paste.
                int retries = empty ? PASTE_EMPTY_RETRIES : 19;
                // Acknowledged but nothing inserted: one real-menu attempt.
                // Any partial value is never pasted over.
                if (!exact && !otpAdvanced && !splitMatched && retry >= retries && emptyFallback != null && empty) {
                    emptyFallback.run(); return;
                }
                if (exact || passwordLength || otpAdvanced || splitMatched || retry >= retries) {
                    boolean ok = exact || passwordLength || otpAdvanced || splitMatched;
                    if (ok) restoreClipboard(clipboard, oldClip, text); else restoreClipboardLater(clipboard, oldClip, text);
                    pasting = false;
                    result.success(status(ok,
                        exact || splitMatched ? "value-matched" : passwordLength ? "password-length-matched" : otpAdvanced ? "otp-view-replaced" :
                        (field.equals("comment") || field.equals("search")) && empty ? "paste-not-inserted" : "value-not-confirmed"));
                } else verifyPaste(editor, text, field, clipboard, oldClip, result, retry + 1, emptyFallback);
            } catch (Exception ignored) {
                restoreClipboardLater(clipboard, oldClip, text); pasting = false;
                result.success(status(false, "verification-failed"));
            }
        }, 100);
    }

    private static Map<String, Object> status(boolean ok, String reason) {
        // Reason only; field values never reach logs.
        if (!ok) android.util.Log.w("SignupAccessibility", "paste failed: " + reason);
        Map<String, Object> value = new HashMap<>(); value.put("ok", ok); value.put("reason", reason); return value;
    }

    private static boolean hasPasswordEditor(AccessibilityNodeInfo node, int depth) {
        if (node == null || depth > 40) return false;
        if (node.isVisibleToUser() && node.isEditable() && node.isPassword()) return true;
        for (int i=0; i<node.getChildCount(); i++) if (hasPasswordEditor(node.getChild(i), depth+1)) return true;
        return false;
    }

    private static String editableText(AccessibilityNodeInfo node, int depth) {
        if (node == null || depth > 40) return "";
        if (node.isVisibleToUser() && node.isEditable() && !node.isPassword()) {
            CharSequence value = editorValue(node);
            return value == null ? "" : value.toString();
        }
        StringBuilder values = new StringBuilder();
        for (int i=0; i<node.getChildCount(); i++) values.append(editableText(node.getChild(i), depth+1));
        return values.toString();
    }

    private static void restoreClipboard(ClipboardManager clipboard, ClipData oldClip, String text) {
        try {
            ClipData current = clipboard.getPrimaryClip();
            if (current != null && current.getItemCount() > 0 && text.contentEquals(current.getItemAt(0).getText())) {
                if (oldClip != null) clipboard.setPrimaryClip(oldClip);
                else if (Build.VERSION.SDK_INT >= 28) clipboard.clearPrimaryClip();
                else clipboard.setPrimaryClip(ClipData.newPlainText("", ""));
            }
        } catch (Exception ignored) { }
    }
}
