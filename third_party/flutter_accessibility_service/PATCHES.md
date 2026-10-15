# Local patch of flutter_accessibility_service 1.2.0

Source: https://pub.dev/packages/flutter_accessibility_service/versions/1.2.0
Upstream: https://github.com/X-SLAYER/flutter_accessibility_service
The upstream LICENSE is included.

Only AccessibilityListener.java is changed: service connection initializes the
service and gesture support even when the optional Flutter overlay engine has
not started. The overlay attaches lazily when an engine is available, and its
view detaches when the service is destroyed. This prevents the null-engine
crash seen when Android reconnects an enabled service before opening the app.
