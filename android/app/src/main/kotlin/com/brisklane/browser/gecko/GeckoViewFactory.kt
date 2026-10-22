package com.brisklane.browser.gecko

import android.app.Activity
import android.content.Context
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.StandardMessageCodec
import io.flutter.plugin.platform.PlatformView
import io.flutter.plugin.platform.PlatformViewFactory

class GeckoViewFactory(
    private val activity: Activity,
    private val messenger: BinaryMessenger,
) :
    PlatformViewFactory(StandardMessageCodec.INSTANCE) {
    override fun create(context: Context, viewId: Int, args: Any?): PlatformView {
        // GeckoView resolves its Window from the Activity, which Flutter's view context may not expose.
        @Suppress("UNCHECKED_CAST")
        return GeckoPlatformView(activity, messenger, viewId, args as? Map<String, Any?> ?: emptyMap())
    }
}
