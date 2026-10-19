import 'package:flutter/material.dart';

import '../core/proxy_store.dart';
import '../core/app_configuration.dart';
import 'widgets/proxy_form.dart';

class EditProxyPage extends StatelessWidget {
  const EditProxyPage({
    super.key,
    required this.entry,
    required this.generateUserAgent,
    this.detectTimeZone,
  });

  final SavedProxy entry;
  final Future<String> Function() generateUserAgent;
  final Future<String> Function(WebViewProxy, String)? detectTimeZone;

  @override
  Widget build(BuildContext context) => ProxyForm(
    entry: entry,
    title: 'Sửa cấu hình',
    submitLabel: 'Lưu thay đổi',
    randomizeOnOpen: false,
    generateUserAgent: generateUserAgent,
    detectTimeZone: detectTimeZone,
  );
}
