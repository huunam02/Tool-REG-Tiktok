import 'package:flutter/material.dart';

import '../../core/controller/home_controller.dart';
import '../../core/nurture_data.dart';
import '../../core/signup_failure.dart';
import '../widgets/proxy_widgets.dart';
import 'home_style.dart';

/// Nuôi Account tab: nurture statistics of every registered account.
class NurtureTab extends StatelessWidget {
  const NurtureTab({super.key, required this.logic, required this.onNurture});

  final HomeController logic;
  final ValueChanged<int> onNurture;

  @override
  Widget build(BuildContext context) => HomeRefreshList(
    storageKey: 'home-nurture',
    onRefresh: logic.loadNurtureAccounts,
    children: [
      Text(
        'Tài khoản đã đăng ký số lượng: ${logic.nurtureAccounts.length}',
        style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
      ),
      const SizedBox(height: 6),
      const Text(
        'Bấm Nuôi để mở tài khoản với proxy và phiên đã lưu của tài khoản đó.',
        style: TextStyle(fontSize: 12, color: HomeStyle.muted),
      ),
      const SizedBox(height: 16),
      if (logic.loadingAccounts) const LinearProgressIndicator(),
      if (logic.accountsLoadFailed)
        HomeSection(
          title: 'Không thể tải thống kê',
          description: 'Dữ liệu cũ vẫn được giữ trong máy.',
          icon: Icons.error_outline,
          children: [
            OutlinedButton(
              onPressed: logic.loadNurtureAccounts,
              child: const Text('Thử lại'),
            ),
          ],
        )
      else if (!logic.loadingAccounts && logic.nurtureAccounts.isEmpty)
        HomeSection(
          title: 'Chưa có tài khoản đã đăng ký',
          description:
              'Tài khoản hiện ở đây sau khi đăng ký thành công hoặc khi '
              'cấu hình được bật Đã đăng ký.',
          icon: Icons.person_add_alt,
          children: [
            OutlinedButton(
              onPressed: () =>
                  logic.tabs.animateTo(HomeController.configurationTab),
              child: const Text('Đi đến Cấu hình'),
            ),
          ],
        )
      else
        for (final account in logic.nurtureAccounts) ...[
          _NurtureAccountCard(
            account: account,
            onNurture: logic.busy || account.configurationId == null
                ? null
                : () => onNurture(account.configurationId!),
            first:
                account.configurationId != null &&
                account.configurationId ==
                    logic.nurturePriority?.configurationId,
            onTap: logic.busy || account.configurationId == null
                ? null
                : () => logic.selectNurturePriority(account.configurationId!),
          ),
          const SizedBox(height: 12),
        ],
    ],
  );
}

/// Nuôi toàn bộ: log in to and nurture every registered account.
class NurtureActionBar extends StatelessWidget {
  const NurtureActionBar({
    super.key,
    required this.logic,
    required this.onNurtureAll,
  });

  final HomeController logic;
  final VoidCallback onNurtureAll;

  @override
  Widget build(BuildContext context) => HomeBottomBar(
    children: [
      FilledButton(
        key: const Key('nurtureAll'),
        onPressed:
            logic.busy ||
                logic.proxyLoadFailed ||
                logic.registeredAccountCount == 0
            ? null
            : onNurtureAll,
        child: Text(
          'Chạy nuôi lần lượt các tài khoản',
          textAlign: TextAlign.center,
        ),
      ),
      const SizedBox(height: 6),
    ],
  );
}

class _NurtureAccountCard extends StatelessWidget {
  const _NurtureAccountCard({
    required this.account,
    required this.first,
    required this.onTap,
    required this.onNurture,
  });

  final NurtureAccount account;

  /// Nurtured first by Chạy nuôi lần lượt.
  final bool first;
  final VoidCallback? onTap;
  final VoidCallback? onNurture;

  @override
  Widget build(BuildContext context) => Material(
    key: Key('nurtureAccount-${account.key}'),
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
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
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
                      // Plain text: a tap anywhere on the card selects it.
                      Text(
                        account.email,
                        style: const TextStyle(fontWeight: FontWeight.w700),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        account.configurationName.isEmpty
                            ? 'Cấu hình đã xóa'
                            : account.configurationName,
                        style: const TextStyle(
                          color: HomeStyle.muted,
                          fontSize: 12,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Text(
                      account.phaseLabel,
                      style: const TextStyle(
                        color: HomeStyle.cyan,
                        fontSize: 12,
                      ),
                    ),
                    if (first) ...[
                      const SizedBox(height: 8),
                      const ProxyBadge(
                        label: 'Chạy trước',
                        color: HomeStyle.cyan,
                      ),
                    ],
                  ],
                ),
              ],
            ),
            const SizedBox(height: 14),
            FilledButton.icon(
              key: Key('nurtureOne-${account.configurationId}'),
              onPressed: onNurture,
              icon: const Icon(Icons.play_arrow),
              label: const Text('Nuôi'),
            ),
            const SizedBox(height: 14),
            _Info(
              key: const Key('nurtureRegisteredAt'),
              icon: Icons.event_available_outlined,
              label: 'Tạo tài khoản',
              value: account.registeredAt == null
                  ? 'Chưa ghi nhận'
                  : formatFailureTime(account.registeredAt!),
            ),
            _Info(
              key: const Key('nurtureCount'),
              icon: Icons.repeat,
              label: 'Số lần nuôi',
              value: '${account.nurtureCount} lần',
            ),
            _Info(
              key: const Key('nurtureLastAt'),
              icon: Icons.history,
              label: 'Nuôi lần cuối',
              value: account.lastNurturedAt == null
                  ? 'Chưa nuôi'
                  : formatFailureTime(account.lastNurturedAt!),
            ),
            const SizedBox(height: 14),
            Row(
              children: [
                _Stat(
                  value: '${account.totals.minutes.toStringAsFixed(1)} phút',
                  label: 'Xem video',
                ),
                _Stat(value: '${account.totals.videos}', label: 'Video đã xem'),
                _Stat(value: '${account.totals.likes}', label: 'Thả tim'),
                _Stat(value: '${account.totals.comments}', label: 'Bình luận'),
              ],
            ),
          ],
        ),
      ),
    ),
  );
}

class _Stat extends StatelessWidget {
  const _Stat({required this.value, required this.label});

  final String value;
  final String label;

  @override
  Widget build(BuildContext context) => Expanded(
    child: Column(
      children: [
        Text(
          value,
          style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
        ),
        const SizedBox(height: 4),
        Text(
          label,
          style: const TextStyle(fontSize: 11, color: HomeStyle.muted),
          textAlign: TextAlign.center,
        ),
      ],
    ),
  );
}

class _Info extends StatelessWidget {
  const _Info({
    super.key,
    required this.icon,
    required this.label,
    required this.value,
  });

  final IconData icon;
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 3),
    child: Row(
      children: [
        Icon(icon, size: 16, color: HomeStyle.muted),
        const SizedBox(width: 8),
        Text(
          '$label: ',
          style: const TextStyle(fontSize: 13, color: HomeStyle.muted),
        ),
        Expanded(
          child: Text(
            value,
            style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
          ),
        ),
      ],
    ),
  );
}
