import 'package:flutter/material.dart';

import '../core/proxy_store.dart';
import 'widgets/proxy_form.dart';

class EditProxyPage extends StatelessWidget {
  const EditProxyPage({
    super.key,
    required this.entry,
    required this.generateUserAgent,
  });

  final SavedProxy entry;
  final Future<String> Function() generateUserAgent;

  @override
  Widget build(BuildContext context) => ProxyForm(
        entry: entry,
        title: 'Sửa proxy',
        submitLabel: 'Lưu thay đổi',
        randomizeOnOpen: false,
        generateUserAgent: generateUserAgent,
      );
}
