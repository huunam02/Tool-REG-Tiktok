// Debug-only entry for recording the live login controls without credentials.
// flutter run -t tools/login_calibration_main.dart -d emulator-5554
import 'package:flutter/material.dart';
import 'package:test_tiktok/core/app_configuration.dart';
import 'package:test_tiktok/screen/tiktok_page.dart';

@pragma('vm:entry-point')
void accessibilityOverlay() => runApp(const SizedBox.shrink());

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(
    MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: ThemeData.dark(),
      home: TikTokPage(configuration: AppConfiguration.defaults('')),
    ),
  );
}
