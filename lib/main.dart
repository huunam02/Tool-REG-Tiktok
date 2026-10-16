import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import 'package:get/get.dart';

import 'controller/startup_controller.dart';
import 'core/app_action_theme.dart';
import 'core/otp_settings_store.dart';
import 'core/proxy_store.dart';
import 'screen/home_page.dart';
import 'screen/splash_page.dart';
import 'screen/widgets/controller_scope.dart';
import 'screen/widgets/accessibility_permission_prompt.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  if (!kIsWeb && defaultTargetPlatform == TargetPlatform.android) {
    await InAppWebViewController.setWebContentsDebuggingEnabled(kDebugMode);
  }

  runApp(const MyApp());
}

// flutter_accessibility_service initializes this engine when attaching
// to the Activity, even when no accessibility overlay is displayed.
@pragma('vm:entry-point')
void accessibilityOverlay() {
  runApp(const SizedBox.shrink());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key, this.proxyStore, this.otpSettingsStore});

  final ProxyStore? proxyStore;
  final OtpSettingsStore? otpSettingsStore;

  @override
  Widget build(BuildContext context) {
    return GetMaterialApp(
      title: 'TikTok',
      debugShowCheckedModeBanner: false,
      theme: AppActionTheme.apply(ThemeData(
        brightness: Brightness.dark,
        colorScheme: ColorScheme.fromSeed(
          seedColor: AppActionTheme.primary,
          brightness: Brightness.dark,
        ),
        scaffoldBackgroundColor: Colors.black,
        useMaterial3: true,
      )),
      home: _AppStartupPage(
        proxyStore: proxyStore,
        otpSettingsStore: otpSettingsStore,
      ),
    );
  }
}

class _AppStartupPage extends StatelessWidget {
  const _AppStartupPage({this.proxyStore, this.otpSettingsStore});
  final ProxyStore? proxyStore;
  final OtpSettingsStore? otpSettingsStore;

  @override
  Widget build(BuildContext context) => ControllerScope<StartupController>(
        controller: StartupController(
          store: proxyStore,
          otpSettingsStore: otpSettingsStore,
        ),
        builder: (logic) {
          if (logic.userAgent != null) {
            return AccessibilityPermissionPrompt(
              child: HomePage(
                userAgent: logic.userAgent!,
                proxyStore: proxyStore,
                initialOtpSettings: logic.otpSettings,
                otpSettingsStore: otpSettingsStore,
              ),
            );
          }
          return SplashPage(
            loading: logic.loading,
            failed: logic.failed,
            onRetry: () => logic.load(),
          );
        },
      );
}
