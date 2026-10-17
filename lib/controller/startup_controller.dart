import 'dart:async';

import '../core/desktop_user_agents.dart';
import '../core/otp_settings_store.dart';
import '../core/proxy_store.dart';
import 'app_controller.dart';

class StartupController extends AppController {
  StartupController({ProxyStore? store, OtpSettingsStore? otpSettingsStore})
    : store = store ?? ProxyStore.instance,
      otpSettingsStore = otpSettingsStore ?? OtpSettingsStore.instance;

  final ProxyStore store;
  final OtpSettingsStore otpSettingsStore;
  String? userAgent;
  OtpApiSettings otpSettings = OtpApiSettings.defaults();
  bool loading = true;
  bool failed = false;

  @override
  void onInit() {
    super.onInit();
    unawaited(load(keepSplashVisible: true));
  }

  Future<void> load({bool keepSplashVisible = false}) async {
    if (loading && !keepSplashVisible) return;
    mutate(() {
      loading = true;
      failed = false;
    });
    final minimumDisplay = keepSplashVisible
        ? Future<void>.delayed(const Duration(milliseconds: 700))
        : Future<void>.value();
    try {
      final settingsFuture = otpSettingsStore.load().catchError(
        (_) => OtpApiSettings.defaults(),
      );
      final profile = await store.getCurrentProfile();
      final agent = profile?.userAgent ?? await loadDirectDesktopUserAgent();
      final settings = await settingsFuture;
      await minimumDisplay;
      mutate(() {
        userAgent = agent;
        otpSettings = settings;
      });
    } catch (_) {
      await minimumDisplay;
      mutate(() => failed = true);
    } finally {
      mutate(() => loading = false);
    }
  }
}
