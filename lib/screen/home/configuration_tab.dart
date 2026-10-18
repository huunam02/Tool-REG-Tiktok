import 'package:flutter/material.dart';

import '../../controller/home_controller.dart';
import '../widgets/proxy_widgets.dart';
import 'home_style.dart';

/// Cấu hình tab: the configuration in use.
class ConfigurationTab extends StatelessWidget {
  const ConfigurationTab({
    super.key,
    required this.logic,
    required this.onManageProxies,
  });

  final HomeController logic;
  final VoidCallback onManageProxies;

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      final wide = constraints.maxWidth >= 760;
      return SingleChildScrollView(
        key: const PageStorageKey('home-general'),
        keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
        padding: EdgeInsets.fromLTRB(wide ? 28 : 16, 16, wide ? 28 : 16, 24),
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 1080),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [_configuration(), const SizedBox(height: 18)],
            ),
          ),
        ),
      );
    },
  );

  Widget _configuration() => HomeSection(
    title: 'Cấu hình',
    description: 'Proxy và tài khoản đang sử dụng.',
    icon: Icons.public,
    children: [
      if (logic.loadingProxy)
        const LinearProgressIndicator()
      else if (logic.proxyLoadFailed) ...[
        const Text('Không thể tải cấu hình đang sử dụng. Hãy thử lại.'),
        const SizedBox(height: 8),
        OutlinedButton(
          key: const Key('retryProxyCache'),
          onPressed: logic.busy ? null : logic.restoreProxy,
          child: const Text('Tải lại cấu hình'),
        ),
      ] else if (logic.currentProxy == null) ...[
        const SelectableText(
          'Chưa chọn cấu hình',
          key: Key('currentProxyAddress'),
          style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
        ),
      ] else ...[
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [ProxyUsageBadge(used: logic.currentProxy!.hasBeenUsed)],
        ),
        const SizedBox(height: 14),
        ProxyDetails(profile: logic.currentProxy!, keyPrefix: 'currentProxy'),
      ],
      const SizedBox(height: 16),
      FilledButton(
        key: const Key('manageProxies'),
        onPressed: logic.busy ? null : onManageProxies,
        child: const Text('Quản lý cấu hình'),
      ),
    ],
  );
}

/// Signup, login or nurture for the selected configuration, and Mở TikTok.
class ConfigurationActionBar extends StatelessWidget {
  const ConfigurationActionBar({
    super.key,
    required this.logic,
    required this.onRunAccountAction,
    required this.onOpenTikTok,
  });

  final HomeController logic;
  final VoidCallback onRunAccountAction;
  final VoidCallback onOpenTikTok;

  @override
  Widget build(BuildContext context) => HomeBottomBar(
    children: [
      if (logic.currentProxy != null) ...[
        FilledButton(
          key: const Key('runAccountAction'),
          onPressed:
              logic.busy ||
                  logic.proxyLoadFailed ||
                  logic.currentProxy?.account == null
              ? null
              : onRunAccountAction,
          child: Text(logic.accountActionLabel, textAlign: TextAlign.center),
        ),
        const SizedBox(height: 10),
      ],
      OutlinedButton(
        key: const Key('openTikTok'),
        onPressed: logic.busy || logic.proxyLoadFailed ? null : onOpenTikTok,
        child: Text(
          logic.opening ? 'Đang mở TikTok…' : 'Mở TikTok',
          textAlign: TextAlign.center,
        ),
      ),
    ],
  );
}
