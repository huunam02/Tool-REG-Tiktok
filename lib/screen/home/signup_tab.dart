import 'package:flutter/material.dart';

import '../../core/controller/home_controller.dart';
import '../../core/proxy_store.dart';
import '../widgets/proxy_widgets.dart';
import 'home_style.dart';

/// Đăng ký tab: configurations waiting for their first signup. The tapped
/// one runs first; the run then continues down the list.
class SignupTab extends StatelessWidget {
  const SignupTab({super.key, required this.logic});

  final HomeController logic;

  @override
  Widget build(BuildContext context) {
    final pending = logic.signupConfigurations;
    final loading = logic.loadingSignups;
    final first = logic.signupPriority;
    return HomeRefreshList(
      storageKey: 'home-signup',
      onRefresh: logic.loadSignupConfigurations,
      children: [
        Text(
          'Chờ đăng ký: ${pending.length}',
          style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
        ),
        const SizedBox(height: 6),
        const Text(
          'Chạm vào một cấu hình để chạy nó trước.',
          style: TextStyle(fontSize: 12, color: HomeStyle.muted),
        ),
        const SizedBox(height: 16),
        if (loading) const LinearProgressIndicator(),
        if (logic.signupsLoadFailed)
          HomeSection(
            title: 'Không thể tải cấu hình chờ đăng ký',
            description: 'Kéo xuống để thử lại.',
            icon: Icons.error_outline,
            children: const [],
          )
        else if (!loading && pending.isEmpty)
          HomeSection(
            title: 'Không còn cấu hình chờ đăng ký',
            description:
                'Thêm cấu hình có tài khoản chưa đăng ký trong Quản lý '
                'cấu hình. Cấu hình đăng ký lỗi nằm ở tab Cấu hình lỗi.',
            icon: Icons.how_to_reg_outlined,
            children: [
              OutlinedButton(
                onPressed: () =>
                    logic.tabs.animateTo(HomeController.configurationTab),
                child: const Text('Đi đến Cấu hình'),
              ),
            ],
          )
        else
          for (final entry in pending) ...[
            _SignupCard(
              entry: entry,
              first: entry.id == first?.id,
              onTap: logic.busy
                  ? null
                  : () => logic.selectSignupPriority(entry.id),
            ),
            const SizedBox(height: 12),
          ],
      ],
    );
  }
}

/// Signs up every pending configuration in turn, starting with the chosen
/// one; each account opens on its own configuration's proxy.
class SignupActionBar extends StatelessWidget {
  const SignupActionBar({
    super.key,
    required this.logic,
    required this.onStartSignup,
  });

  final HomeController logic;
  final VoidCallback onStartSignup;

  @override
  Widget build(BuildContext context) {
    final first = logic.signupPriority;
    return HomeBottomBar(
      children: [
        FilledButton(
          key: const Key('signupAll'),
          onPressed: logic.busy || logic.proxyLoadFailed || first == null
              ? null
              : onStartSignup,
          child: const Text(
            'Chạy đăng ký lần lượt tài khoản',
            textAlign: TextAlign.center,
          ),
        ),
        const SizedBox(height: 6),
      ],
    );
  }
}

class _SignupCard extends StatelessWidget {
  const _SignupCard({
    required this.entry,
    required this.first,
    required this.onTap,
  });

  final SavedProxy entry;
  final bool first;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) => Material(
    key: Key('signupConfiguration-${entry.id}'),
    color: first ? HomeStyle.selectedSurface : HomeStyle.surface,
    shape: RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(20),
      side: BorderSide(
        color: first ? HomeStyle.cyan : HomeStyle.border,
        width: first ? 1.5 : 1,
      ),
    ),
    clipBehavior: Clip.antiAlias,
    child: InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Row(
          children: [
            Icon(
              first ? Icons.radio_button_checked : Icons.radio_button_off,
              color: first ? HomeStyle.cyan : HomeStyle.muted,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    entry.account?.email ?? entry.name,
                    style: const TextStyle(fontWeight: FontWeight.w700),
                  ),
                  const SizedBox(height: 4),
                  if (entry.account?.email != null &&
                      entry.name != entry.account?.email) ...[
                    Text(
                      entry.name,
                      style: const TextStyle(
                        color: HomeStyle.muted,
                        fontSize: 12,
                      ),
                    ),
                    const SizedBox(height: 2),
                  ],
                  Text(
                    'Proxy: ${proxyLabel(entry.proxy)}',
                    style: const TextStyle(
                      color: HomeStyle.muted,
                      fontSize: 12,
                    ),
                  ),
                ],
              ),
            ),
            if (first) ...[
              const SizedBox(width: 8),
              const ProxyBadge(label: 'Chạy trước', color: HomeStyle.cyan),
            ],
          ],
        ),
      ),
    ),
  );
}
