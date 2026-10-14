import 'package:flutter/material.dart';

import 'widgets/proxy_form.dart';

class CreateProxyPage extends StatelessWidget {
  const CreateProxyPage({super.key, required this.generateUserAgent});

  final Future<String> Function() generateUserAgent;

  @override
  Widget build(BuildContext context) => ProxyForm(
        title: 'Tạo cấu hình',
        submitLabel: 'Tạo cấu hình',
        randomizeOnOpen: true,
        generateUserAgent: generateUserAgent,
      );
}
