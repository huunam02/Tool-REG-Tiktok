import 'package:flutter/material.dart';

import 'app_session.dart';
import 'home_page.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

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
      home: const _SessionStartupPage(),
    );
  }
}

class _SessionStartupPage extends StatefulWidget {
  const _SessionStartupPage();

  @override
  State<_SessionStartupPage> createState() => _SessionStartupPageState();
}

class _SessionStartupPageState extends State<_SessionStartupPage> {
  late Future<String> _session;

  @override
  void initState() {
    super.initState();
    _session = prepareAppSession();
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<String>(
      future: _session,
      builder: (context, snapshot) {
        if (snapshot.hasData) return HomePage(userAgent: snapshot.data!);
        return Scaffold(
          body: Center(
            child: snapshot.hasError
                ? Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Text('Không thể tạo phiên mới. Hãy thử lại.'),
                      const SizedBox(height: 16),
                      FilledButton(
                        onPressed: () => setState(() {
                          _session = prepareAppSession();
                        }),
                        child: const Text('Thử lại'),
                      ),
                    ],
                  )
                : const CircularProgressIndicator(),
          ),
        );
      },
    );
  }
}
