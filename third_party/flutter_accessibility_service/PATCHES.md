# Local patch of flutter_accessibility_service 1.2.0

Source: https://pub.dev/packages/flutter_accessibility_service/versions/1.2.0
Upstream: https://github.com/X-SLAYER/flutter_accessibility_service
The upstream LICENSE is included.

AccessibilityListener.java: service connection initializes the
service and gesture support even when the optional Flutter overlay engine has
not started. The overlay attaches lazily when an engine is available, and its
view detaches when the service is destroyed. This prevents the null-engine
crash seen when Android reconnects an enabled service before opening the app.

Utils.java: permission checks match normalized ComponentName entries from
ENABLED_ACCESSIBILITY_SERVICES rather than comparing raw strings or relying on
the global accessibility flag. An enabled grant is independent of the service
reconnecting after the app process restarts.

SignupAccessibilityBridge.java: the six-slot OTP check counts only editors on
the focused editor's row. Background page inputs stay exposed behind TikTok's
modal and made a page-wide count miss six, failing OTP paste with
wrong-otp-field. That failure now reports the row and page counts.

SignupAccessibilityBridge.java: the long press that opens the Paste menu
lasts the device's long-press timeout plus 450ms (at least 850ms), so a
Medium/Long "Touch & hold delay" setting still opens the menu.

AccessibilityListener.java: continuous gestures round coordinates to Android's
screen pixels and hold the existing pointer through stationary intermediate
segments. Android 9 cancels a continued stroke when subpixel movement produces
no touch events. A press-only callback can also finish before its requested
duration; the next segment now waits for the remaining hold time. Native
instrumentation tests cover both cases with one DOWN/UP pair and no CANCEL.
