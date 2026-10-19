import 'package:flutter/material.dart';

import 'widgets/proxy_form.dart';
import '../core/app_configuration.dart';

class CreateProxyPage extends StatelessWidget {
  const CreateProxyPage({
    super.key,
    required this.generateUserAgent,
    this.detectTimeZone,
  });

  final Future<String> Function() generateUserAgent;
  final Future<String> Function(WebViewProxy, String)? detectTimeZone;

  @override
  Widget build(BuildContext context) => ProxyForm(
    title: 'Tạo cấu hình',
    submitLabel: 'Tạo cấu hình',
    randomizeOnOpen: true,
    generateUserAgent: generateUserAgent,
    detectTimeZone: detectTimeZone,
  );
}
