package com.stalliondz.tool.tiktok

import android.content.Context
import android.text.InputType
import android.util.Log
import android.view.inputmethod.EditorInfo
import android.view.inputmethod.InputMethodManager
import android.webkit.WebView
import org.json.JSONObject

object NativeKeyboardInput {
    fun typeText(webView: WebView, text: String, guardScript: String, complete: (Boolean) -> Unit) =
        typeText(webView, text, "", guardScript, complete)

    fun typeText(webView: WebView, text: String, expectedBefore: String,
                 guardScript: String, complete: (Boolean) -> Unit) {
        if (text.isEmpty() || !ready(webView)) {
            Log.d("NativeKeyboardInput", "Rejected: window is not ready")
            complete(false)
            return
        }
        val encodedText = JSONObject.quote(expectedBefore + text)
        val encodedBefore = JSONObject.quote(expectedBefore)
        val prepareFocus = """
            (() => {
              delete window.__flutterRestoreKeyboardFocus;
              const allowed = () => ($guardScript);
              if (!allowed()) return false;
              const editor = document.activeElement;
              if (!editor || editor.disabled || editor.readOnly || !editor.isConnected) return false;
              const value = editor.value === undefined ? editor.textContent : editor.value;
              if (value === $encodedText) return 'complete';
              // Preserve edits made while Flutter was crossing the native bridge.
              if (value !== $encodedBefore) return false;
              const start = editor.selectionStart;
              const end = editor.selectionEnd;
              const selection = window.getSelection();
              const ranges = [];
              for (let i = 0; i < (selection?.rangeCount || 0); i++) {
                ranges.push(selection.getRangeAt(i).cloneRange());
              }
              window.__flutterRestoreKeyboardFocus = () => {
                if (document.hidden || !editor.isConnected || editor.disabled || editor.readOnly) return false;
                // Native view focus may select another DOM node, or leave the
                // IME pointing at the previous one. Refresh the selected editor.
                editor.blur();
                editor.focus();
                if (start !== null && start !== undefined) {
                  editor.setSelectionRange(start, end);
                } else if (selection) {
                  selection.removeAllRanges();
                  ranges.forEach(range => selection.addRange(range));
                }
                return allowed();
              };
              return true;
            })()
        """.trimIndent()
        webView.evaluateJavascript(prepareFocus) { editable ->
            if (editable == "\"complete\"") {
                complete(true)
                return@evaluateJavascript
            }
            if (editable != "true" || !ready(webView) || !webView.requestFocus()) {
                Log.d("NativeKeyboardInput", "Rejected: target is not editable or focus unavailable")
                complete(false)
            } else {
                // DOM focus does not guarantee Android view focus. Recheck after
                // requesting it, since focus changes can cancel the pending field.
                val restoreFocus = """
                    (() => {
                      const restore = window.__flutterRestoreKeyboardFocus;
                      delete window.__flutterRestoreKeyboardFocus;
                      return restore?.() === true;
                    })()
                """.trimIndent()
                webView.evaluateJavascript(restoreFocus) { stillEditable ->
                    if (stillEditable != "true" || !ready(webView) || !webView.hasFocus()) {
                        Log.d("NativeKeyboardInput", "Rejected: target changed after native focus")
                        complete(false)
                    } else {
                        // Chromium updates its native IME state after DOM focus.
                        // Let that update arrive, then recheck cancellation/focus.
                        val keyboard = webView.context.getSystemService(Context.INPUT_METHOD_SERVICE)
                            as? InputMethodManager
                        keyboard?.restartInput(webView)
                        keyboard?.showSoftInput(webView, InputMethodManager.SHOW_IMPLICIT)
                        webView.postDelayed({ typeWhenReady(webView, text, expectedBefore, guardScript, complete) }, 150)
                    }
                }
            }
        }
    }

    private fun typeWhenReady(webView: WebView, text: String, expectedBefore: String, guardScript: String, complete: (Boolean) -> Unit) {
        if (!ready(webView) || !webView.hasFocus()) {
            complete(false)
            return
        }
        val targetScript = """
            (() => {
              if (!($guardScript)) return null;
              const editor = document.activeElement;
              if (!editor || !editor.isConnected || editor.disabled || editor.readOnly) return null;
              const value = editor.value === undefined ? editor.textContent : editor.value;
              if (value === ${JSONObject.quote(expectedBefore + text)}) return 'complete';
              if (value !== ${JSONObject.quote(expectedBefore)}) return null;
              return editor.type === 'password';
            })()
        """.trimIndent()
        webView.evaluateJavascript(targetScript) { passwordTarget ->
            if (passwordTarget == "\"complete\"") {
                complete(true)
                return@evaluateJavascript
            }
            if ((passwordTarget != "true" && passwordTarget != "false") ||
                !ready(webView) || !webView.hasFocus()) {
                complete(false)
            } else {
                val handled = try {
                    val info = EditorInfo()
                    val connection = webView.onCreateInputConnection(info)
                    val variation = info.inputType and InputType.TYPE_MASK_VARIATION
                    val nativePassword = (info.inputType and InputType.TYPE_MASK_CLASS) == InputType.TYPE_CLASS_TEXT &&
                        (variation == InputType.TYPE_TEXT_VARIATION_PASSWORD ||
                         variation == InputType.TYPE_TEXT_VARIATION_WEB_PASSWORD ||
                         variation == InputType.TYPE_TEXT_VARIATION_VISIBLE_PASSWORD)
                    if (connection == null || info.inputType == InputType.TYPE_NULL ||
                        (passwordTarget == "true") != nativePassword ||
                        (info.initialSelStart >= 0 && info.initialSelEnd >= 0 &&
                            (info.initialSelStart != expectedBefore.length || info.initialSelEnd != expectedBefore.length))) {
                        // After OTP auto-advances, DOM focus can precede the IME
                        // editor update. Reject before sending text so Dart can
                        // retry this unhandled action against the correct field.
                        Log.d("NativeKeyboardInput", "Rejected: native editor is not ready")
                        false
                    } else {
                        // Use the same input API as Android IMEs, preserving Unicode.
                        connection.commitText(text, 1)
                    }
                } catch (_: RuntimeException) {
                    // Some WebView providers can reject a connection during navigation.
                    false
                }
                Log.d("NativeKeyboardInput", "Native keyboard input accepted: $handled")
                // Flutter/JS still verify the resulting text before submit.
                complete(handled)
            }
        }
    }

    private fun ready(webView: WebView) =
        webView.isAttachedToWindow && webView.hasWindowFocus()
}
