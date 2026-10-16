package slayer.accessibility.service.flutter_accessibility_service;

import android.content.ClipData;
import android.content.ClipboardManager;
import android.content.Context;
import android.accessibilityservice.GestureDescription;
import android.graphics.Path;
import android.graphics.Rect;
import android.os.Build;
import android.os.Handler;
import android.os.Looper;
import android.os.PersistableBundle;
import android.text.InputType;
import android.view.accessibility.AccessibilityNodeInfo;
import android.view.accessibility.AccessibilityWindowInfo;
import java.util.ArrayList;
import java.util.HashMap;
import java.util.List;
import java.util.Map;
import io.flutter.plugin.common.MethodChannel;

/** On-demand snapshots and real ACTION_PASTE, restricted to the host app's WebView. */
final class SignupAccessibilityBridge {
    private static boolean pasting;
    private static boolean pasteCancelled;

    static void cancelPaste() { pasteCancelled = true; }

    static AccessibilityNodeInfo webRoot(AccessibilityListener service) {
        if (service == null) return null;
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
        if ("android.webkit.WebView".contentEquals(node.getClassName()) && node.isVisibleToUser()) return node;
        for (int i = 0; i < node.getChildCount(); i++) {
            AccessibilityNodeInfo found = findWeb(node.getChild(i), pkg, depth + 1);
            if (found != null) return found;
        }
        return null;
    }

    static Map<String, Object> snapshot() {
        AccessibilityListener service = AccessibilityListener.currentInstance();
        AccessibilityNodeInfo web = webRoot(service);
        Map<String, Object> result = new HashMap<>();
        result.put("ready", web != null);
        result.put("keyboardVisible", keyboardVisible(service));
        if (web == null) return result;
        Rect rect = new Rect();
        web.getBoundsInScreen(rect);
        result.put("webBounds", bounds(rect));
        List<Map<String, Object>> nodes = new ArrayList<>();
        collect(web, "0", nodes, 0);
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
        return result;
    }

    private static void collectPickers(AccessibilityNodeInfo node, String pkg, String path,
            List<Map<String,Object>> nodes, int depth) {
        if (node == null || depth > 40 || !pkg.contentEquals(node.getPackageName() == null ? "" : node.getPackageName())) return;
        String type = String.valueOf(node.getClassName());
        if (node.isVisibleToUser() && (type.equals("android.widget.ListView") || type.equals("android.widget.NumberPicker"))) {
            int start = nodes.size();
            collect(node, path, nodes, 0);
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
        if (!keyboardVisible(service)) { result.success(true); return; }
        AccessibilityNodeInfo focused = web.findFocus(AccessibilityNodeInfo.FOCUS_INPUT);
        if (focused != null) focused.performAction(AccessibilityNodeInfo.ACTION_CLEAR_FOCUS);
        // GLOBAL_ACTION_BACK can pop Flutter's route instead of consuming IME.
        // Hide only the soft keyboard, then immediately restore normal policy.
        boolean hidden = service.getSoftKeyboardController().setShowMode(android.accessibilityservice.AccessibilityService.SHOW_MODE_HIDDEN);
        new Handler(Looper.getMainLooper()).postDelayed(() -> {
            service.getSoftKeyboardController().setShowMode(android.accessibilityservice.AccessibilityService.SHOW_MODE_AUTO);
            result.success(hidden);
        }, 300);
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

    private static void collect(AccessibilityNodeInfo node, String path, List<Map<String, Object>> nodes, int depth) {
        if (node == null || depth > 40 || nodes.size() >= 1200) return;
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
            item.put("length", node.isEditable() && node.getText() != null ? node.getText().length() : 0);
            // Field values must never reach calibration files or debug logs.
            item.put("text", node.isEditable() || node.isPassword() ? "" : safe(node.getText()));
            item.put("description", node.isEditable() || node.isPassword() ? "" : safe(node.getContentDescription()));
            item.put("hint", Build.VERSION.SDK_INT >= 26 ? safe(node.getHintText()) : "");
            nodes.add(item);
        }
        for (int i = 0; i < node.getChildCount(); i++) collect(node.getChild(i), path + "." + i, nodes, depth + 1);
    }

    static void paste(String text, String field, MethodChannel.Result result) {
        AccessibilityListener service = AccessibilityListener.currentInstance();
        AccessibilityNodeInfo web = webRoot(service);
        AccessibilityNodeInfo editor = web == null ? null : web.findFocus(AccessibilityNodeInfo.FOCUS_INPUT);
        if (pasting || field == null || text == null || text.isEmpty() || editor == null || !editor.isVisibleToUser() ||
                !editor.isEditable() || !editor.isEnabled() || !service.getPackageName().contentEquals(editor.getPackageName())) {
            result.success(status(false, "editor-unavailable")); return;
        }
        if (!field.equals("email") && !field.equals("password") && !field.equals("otp") ||
                field.equals("password") != editor.isPassword() ||
                field.equals("otp") && !text.matches("[0-9]{6}")) {
            result.success(status(false, "wrong-field")); return;
        }
        String hint = Build.VERSION.SDK_INT >= 26 && editor.getHintText() != null ? editor.getHintText().toString().toLowerCase(java.util.Locale.ROOT) : "";
        if (field.equals("email") && !hint.contains("email") &&
                (editor.getInputType() & InputType.TYPE_MASK_VARIATION) != InputType.TYPE_TEXT_VARIATION_EMAIL_ADDRESS) {
            result.success(status(false, "wrong-email-field")); return;
        }
        int inputClass = editor.getInputType() & InputType.TYPE_MASK_CLASS;
        boolean splitOtp = field.equals("otp") && editableCount(web, 0) == 6;
        if (field.equals("otp") && !splitOtp && inputClass != InputType.TYPE_CLASS_NUMBER && inputClass != InputType.TYPE_CLASS_PHONE &&
                !hint.contains("code") && !hint.contains("otp") && !hint.contains("mã")) {
            result.success(status(false, "wrong-otp-field")); return;
        }
        CharSequence previous = editor.getText();
        if (previous != null && previous.length() > 0) {
            result.success(status(text.contentEquals(previous), "draft-exists")); return;
        }
        ClipboardManager clipboard = (ClipboardManager) service.getSystemService(Context.CLIPBOARD_SERVICE);
        ClipData oldClip = clipboard.getPrimaryClip();
        ClipData clip = ClipData.newPlainText("", text);
        PersistableBundle extras = new PersistableBundle();
        extras.putBoolean("android.content.extra.IS_SENSITIVE", true);
        clip.getDescription().setExtras(extras);
        pasting = true;
        pasteCancelled = false;
        try {
            clipboard.setPrimaryClip(clip);
            if (field.equals("otp")) {
                // Chromium's ACTION_PASTE acknowledges the six-slot OTP view
                // without filling it. The real floating Paste menu does work.
                Rect rect = new Rect(); editor.getBoundsInScreen(rect);
                gesture(service, rect.exactCenterX(), rect.exactCenterY(), 850, () ->
                    pasteMenu(service, editor, text, clipboard, oldClip, result, 0), () ->
                    failPaste(clipboard, oldClip, text, result, "long-press-failed"));
                return;
            }
            boolean accepted = editor.performAction(AccessibilityNodeInfo.ACTION_PASTE);
            if (!accepted) {
                restoreClipboard(clipboard, oldClip, text); pasting = false;
                result.success(status(false, "paste-rejected")); return;
            }
            verifyPaste(editor, text, field, clipboard, oldClip, result, 0);
        } catch (Exception ignored) {
            restoreClipboard(clipboard, oldClip, text); pasting = false;
            result.success(status(false, "paste-failed"));
        }
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

    private static void pasteMenu(AccessibilityListener service, AccessibilityNodeInfo editor, String text,
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
                if (retry < 14) pasteMenu(service, editor, text, clipboard, oldClip, result, retry+1);
                else failPaste(clipboard, oldClip, text, result, "paste-menu-unavailable");
                return;
            }
            Rect rect = new Rect(); menu.getBoundsInScreen(rect);
            gesture(service, rect.exactCenterX(), rect.exactCenterY(), 140, () ->
                verifyPaste(editor, text, "otp", clipboard, oldClip, result, 0), () ->
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
        restoreClipboard(clipboard, oldClip, text); pasting = false;
        result.success(status(false, reason));
    }

    private static int editableCount(AccessibilityNodeInfo node, int depth) {
        if (node == null || depth > 40) return 0;
        int count = node.isVisibleToUser() && node.isEditable() && !node.isPassword() ? 1 : 0;
        for (int i=0; i<node.getChildCount(); i++) count += editableCount(node.getChild(i), depth+1);
        return count;
    }

    private static void verifyPaste(AccessibilityNodeInfo editor, String text, String field,
            ClipboardManager clipboard, ClipData oldClip, MethodChannel.Result result, int retry) {
        new Handler(Looper.getMainLooper()).postDelayed(() -> {
            try {
                if (pasteCancelled) {
                    failPaste(clipboard, oldClip, text, result, "cancelled"); return;
                }
                boolean attached = editor.refresh();
                CharSequence value = attached ? editor.getText() : null;
                boolean exact = value != null && text.contentEquals(value);
                boolean passwordLength = field.equals("password") && value != null && value.length() == text.length();
                // A six-digit paste can immediately replace the OTP view.
                AccessibilityNodeInfo web = field.equals("otp") ? webRoot(AccessibilityListener.currentInstance()) : null;
                boolean otpAdvanced = field.equals("otp") && hasPasswordEditor(web, 0);
                boolean splitMatched = field.equals("otp") && text.equals(editableText(web, 0));
                if (exact || passwordLength || otpAdvanced || splitMatched || retry >= 19) {
                    restoreClipboard(clipboard, oldClip, text); pasting = false;
                    result.success(status(exact || passwordLength || otpAdvanced || splitMatched,
                        exact || splitMatched ? "value-matched" : passwordLength ? "password-length-matched" : otpAdvanced ? "otp-view-replaced" : "value-not-confirmed"));
                } else verifyPaste(editor, text, field, clipboard, oldClip, result, retry + 1);
            } catch (Exception ignored) {
                restoreClipboard(clipboard, oldClip, text); pasting = false;
                result.success(status(false, "verification-failed"));
            }
        }, 100);
    }

    private static Map<String, Object> status(boolean ok, String reason) {
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
        if (node.isVisibleToUser() && node.isEditable() && !node.isPassword()) return node.getText() == null ? "" : node.getText().toString();
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
