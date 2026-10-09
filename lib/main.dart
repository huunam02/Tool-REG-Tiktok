import 'package:flutter/material.dart';

import 'home_page.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // // -- Bỏ comment đoạn này nếu bạn muốn set Proxy cho toàn bộ Webview --
  // if (!kIsWeb && (Platform.isAndroid || Platform.isIOS)) {
  //   await ProxyController.instance().setProxyOverride(
  //     settings: ProxySettings(
  //       proxyRules: [ProxyRule(url: "http://192.168.1.1:8888")], // Đổi lại IP của bạn
  //       bypassRules: ["www.google.com"]
  //     )
  //   );
  // }

  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'TikTok',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        brightness: Brightness.dark,
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFFFE2C55),
          brightness: Brightness.dark,
        ),
        scaffoldBackgroundColor: Colors.black,
        useMaterial3: true,
      ),
      home: const HomePage(),
    );
  }
}
