import 'package:flutter/material.dart';

import '../../controller/home_controller.dart';
import '../../core/nurture_data.dart';
import 'home_style.dart';

/// Nuôi Account tab: nurture statistics of every registered account.
class NurtureTab extends StatelessWidget {
  const NurtureTab({super.key, required this.logic});

  final HomeController logic;

  @override
  Widget build(BuildContext context) => HomeRefreshList(
    storageKey: 'home-nurture',
    onRefresh: logic.loadNurtureAccounts,
    children: [
      Text(
        'Tài khoản đã đăng ký số lượng: ${logic.nurtureAccounts.length}',
        style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
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
              onPressed: () => logic.tabs.animateTo(0),
              child: const Text('Đi đến Cấu hình'),
            ),
          ],
        )
      else
        for (final account in logic.nurtureAccounts) ...[
          _NurtureAccountCard(account: account),
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
        child: Text('Chạy nuôi toàn bộ tài khoản', textAlign: TextAlign.center),
      ),
      const SizedBox(height: 6),
    ],
  );
}

class _NurtureAccountCard extends StatelessWidget {
  const _NurtureAccountCard({required this.account});

  final NurtureAccount account;

  @override
  Widget build(BuildContext context) => Material(
    color: HomeStyle.surface,
    shape: RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(20),
      side: const BorderSide(color: HomeStyle.border),
    ),
    child: Padding(
      padding: const EdgeInsets.all(18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const CircleAvatar(
                backgroundColor: Color(0xFF123136),
                foregroundColor: HomeStyle.cyan,
                child: Icon(Icons.person_outline),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    SelectableText(
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
              Text(
                account.phaseLabel,
                style: const TextStyle(color: HomeStyle.cyan, fontSize: 12),
              ),
            ],
          ),
          const SizedBox(height: 18),
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
