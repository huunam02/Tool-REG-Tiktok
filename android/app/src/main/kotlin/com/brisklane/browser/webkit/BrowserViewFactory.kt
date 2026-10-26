package com.brisklane.browser.webkit

import android.app.Activity
import android.content.Context
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.StandardMessageCodec
import io.flutter.plugin.platform.PlatformView
import io.flutter.plugin.platform.PlatformViewFactory

class BrowserViewFactory(
    private val activity: Activity,
    private val messenger: BinaryMessenger,
) : PlatformViewFactory(StandardMessageCodec.INSTANCE) {
    override fun create(context: Context, viewId: Int, args: Any?): PlatformView {
        // HTML <select> opens a native dialog, which needs the Activity window.
        @Suppress("UNCHECKED_CAST")
        return BrowserPlatformView(activity, messenger, viewId, args as? Map<String, Any?> ?: emptyMap())
    }
}
