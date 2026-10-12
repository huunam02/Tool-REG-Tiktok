package com.stalliondz.tool.tiktok

import android.util.Log
import android.view.inputmethod.EditorInfo
import android.webkit.WebView

object NativeClipboardPaste {
    fun paste(webView: WebView, guardScript: String, complete: (Boolean) -> Unit) {
        if (!ready(webView)) {
            Log.d("NativeClipboardPaste", "Rejected: window is not ready")
            complete(false)
            return
        }
        val prepareFocus = """
            (() => {
              delete window.__flutterRestoreClipboardFocus;
              const allowed = () => ($guardScript);
              if (!allowed()) return false;
              const editor = document.activeElement;
              const start = editor.selectionStart;
              const end = editor.selectionEnd;
              const selection = window.getSelection();
              const ranges = [];
              for (let i = 0; i < (selection?.rangeCount || 0); i++) {
                ranges.push(selection.getRangeAt(i).cloneRange());
              }
              window.__flutterRestoreClipboardFocus = () => {
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
            if (editable != "true" || !ready(webView) || !webView.requestFocus()) {
                Log.d("NativeClipboardPaste", "Rejected: target is not editable or focus unavailable")
                complete(false)
            } else {
                // DOM focus does not guarantee Android view focus. Recheck after
                // requesting it, since focus changes can cancel the pending field.
                val restoreFocus = """
                    (() => {
                      const restore = window.__flutterRestoreClipboardFocus;
                      delete window.__flutterRestoreClipboardFocus;
                      return restore?.() === true;
                    })()
                """.trimIndent()
                webView.evaluateJavascript(restoreFocus) { stillEditable ->
                    if (stillEditable != "true" || !ready(webView) || !webView.hasFocus()) {
                        Log.d("NativeClipboardPaste", "Rejected: target changed after native focus")
                        complete(false)
                    } else {
                        // Chromium updates its native IME state after DOM focus.
                        // Let that update arrive, then recheck cancellation/focus.
                        webView.postDelayed({ pasteWhenReady(webView, guardScript, complete) }, 150)
                    }
                }
            }
        }
    }

    private fun pasteWhenReady(webView: WebView, guardScript: String, complete: (Boolean) -> Unit) {
        if (!ready(webView) || !webView.hasFocus()) {
            complete(false)
            return
        }
        webView.evaluateJavascript(guardScript) { allowed ->
            if (allowed != "true" || !ready(webView) || !webView.hasFocus()) {
                complete(false)
            } else {
                val handled = try {
                    val connection = webView.onCreateInputConnection(EditorInfo())
                    connection?.performContextMenuAction(android.R.id.paste) == true
                } catch (_: RuntimeException) {
                    // Some WebView providers can reject a connection during navigation.
                    false
                }
                Log.d("NativeClipboardPaste", "Native paste accepted: $handled")
                // Flutter/JS still verify the resulting text before submit.
                complete(handled)
            }
        }
    }

    private fun ready(webView: WebView) =
        webView.isAttachedToWindow && webView.hasWindowFocus()
}
