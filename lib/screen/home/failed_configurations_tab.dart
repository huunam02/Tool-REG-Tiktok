import 'package:flutter/material.dart';

import '../../core/controller/home_controller.dart';
import '../../core/proxy_store.dart';
import '../../core/signup_failure.dart';
import '../widgets/proxy_widgets.dart';
import 'home_style.dart';

/// Cấu hình lỗi tab: configurations whose automatic signup failed, each
/// with its details and the log of failed attempts.
class FailedConfigurationsTab extends StatelessWidget {
  const FailedConfigurationsTab({super.key, required this.logic});

  final HomeController logic;

  @override
  Widget build(BuildContext context) {
    final failed = logic.failedConfigurations;
    final loading = logic.loadingFailures;
    return HomeRefreshList(
      storageKey: 'home-failed',
      onRefresh: logic.loadFailedConfigurations,
      children: [
        Text(
          'Cấu hình lỗi: ${failed.length}',
          style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
        ),
        const SizedBox(height: 6),
        const Text(
          'Chạm vào một cấu hình để đăng ký lại nó trước.',
          style: TextStyle(fontSize: 12, color: ProxyColors.muted),
        ),
        const SizedBox(height: 16),
        if (loading) const LinearProgressIndicator(),
        if (logic.failuresLoadFailed)
          const _Message(
            icon: Icons.error_outline,
            title: 'Không thể tải cấu hình lỗi',
            detail: 'Kéo xuống để thử lại.',
            color: ProxyColors.amber,
          )
        else if (!loading && failed.isEmpty)
          const _Message(
            icon: Icons.check_circle_outline,
            title: 'Không có cấu hình lỗi',
            detail:
                'Cấu hình đăng ký tự động thất bại sẽ hiện ở đây kèm '
                'nhật ký lỗi.',
            color: ProxyColors.green,
          )
        else
          for (final entry in failed) ...[
            _FailedConfigurationCard(
              entry: entry,
              first:
                  entry.configuration.id ==
                  logic.failedPriority?.configuration.id,
              onTap: logic.busy
                  ? null
                  : () => logic.selectFailedPriority(entry.configuration.id),
              busy: logic.busy || logic.proxyLoadFailed,
              onDismiss: () => logic.dismissFailure(entry.configuration.id),
            ),
            const SizedBox(height: 12),
          ],
      ],
    );
  }
}

/// Đăng ký lại: sign up every failed configuration again, in turn.
class FailedConfigurationsActionBar extends StatelessWidget {
  const FailedConfigurationsActionBar({
    super.key,
    required this.logic,
    required this.onRetryAll,
  });

  final HomeController logic;
  final VoidCallback onRetryAll;

  @override
  Widget build(BuildContext context) {
    final count = logic.failedConfigurations.length;
    return HomeBottomBar(
      children: [
        FilledButton(
          key: const Key('retryFailedSignups'),
          onPressed: logic.busy || logic.proxyLoadFailed || count == 0
              ? null
              : onRetryAll,
          child: Text(
            'Chạy đăng ký lần lượt lại tài khoản',
            textAlign: TextAlign.center,
          ),
        ),
        const SizedBox(height: 6),
      ],
    );
  }
}

class _Message extends StatelessWidget {
  const _Message({
    required this.icon,
    required this.title,
    required this.detail,
    required this.color,
  });

  final IconData icon;
  final String title;
  final String detail;
  final Color color;

  @override
  Widget build(BuildContext context) => ProxyPanel(
    child: Row(
      children: [
        Icon(icon, color: color),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(title, style: const TextStyle(fontWeight: FontWeight.w700)),
              const SizedBox(height: 4),
              Text(
                detail,
                style: const TextStyle(fontSize: 12, color: ProxyColors.muted),
              ),
            ],
          ),
        ),
      ],
    ),
  );
}

class _FailedConfigurationCard extends StatelessWidget {
  const _FailedConfigurationCard({
    required this.entry,
    required this.first,
    required this.onTap,
    required this.busy,
    required this.onDismiss,
  });

  final FailedConfiguration entry;

  /// Signed up again first by Chạy đăng ký lại.
  final bool first;
  final VoidCallback? onTap;
  final bool busy;
  final VoidCallback onDismiss;

  SavedProxy get configuration => entry.configuration;

  @override
  Widget build(BuildContext context) {
    final latest = entry.latest;
    final older = entry.failures.skip(1).toList();
    return Material(
      key: Key('failedConfiguration-${configuration.id}'),
      color: first ? HomeStyle.selectedSurface : ProxyColors.surface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(20),
        side: first
            ? const BorderSide(color: ProxyColors.cyan, width: 1.5)
            : BorderSide(color: ProxyColors.red.withValues(alpha: 0.25)),
      ),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(18, 18, 18, 8),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // Plain text: a tap anywhere on the card selects it.
                        Text(
                          configuration.account?.email ?? configuration.name,
                          style: const TextStyle(fontWeight: FontWeight.w700),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          proxyLabel(configuration.proxy),
                          style: const TextStyle(
                            color: ProxyColors.muted,
                            fontSize: 12,
                          ),
                        ),
                        const SizedBox(height: 8),
                        Wrap(
                          spacing: 8,
                          runSpacing: 8,
                          children: [
                            ProxyBadge(
                              label: 'Lỗi ${entry.failureCount} lần',
                              color: ProxyColors.red,
                            ),
                            if (first)
                              const ProxyBadge(
                                label: 'Chạy trước',
                                color: ProxyColors.cyan,
                              ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 14),
              if (latest != null)
                _FailureEntry(
                  key: Key('latestFailure-${configuration.id}'),
                  failure: latest,
                  latest: true,
                ),
              if (older.isNotEmpty)
                _Expandable(
                  key: Key('failureLog-${configuration.id}'),
                  color: ProxyColors.red,
                  title:
                      'Nhật ký lỗi các lần trước (${entry.failureCount - 1})',
                  children: [
                    for (final failure in older) ...[
                      _FailureEntry(failure: failure),
                      const SizedBox(height: 8),
                    ],
                    if (entry.failureCount > entry.failures.length)
                      Text(
                        'Chỉ hiện ${entry.failures.length} lần gần nhất.',
                        style: const TextStyle(
                          fontSize: 11,
                          color: ProxyColors.muted,
                        ),
                      ),
                  ],
                ),
              _Expandable(
                key: Key('failedDetails-${configuration.id}'),
                color: ProxyColors.cyan,
                title: 'Thông tin cấu hình',
                children: [
                  ProxyDetails(
                    profile: configuration,
                    keyPrefix: 'failed${configuration.id}',
                    showName: true,
                  ),
                ],
              ),
              Align(
                alignment: Alignment.centerRight,
                child: TextButton(
                  key: Key('dismissFailure-${configuration.id}'),
                  onPressed: busy ? null : onDismiss,
                  child: const Text('Bỏ khỏi danh sách lỗi'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// A collapsible section. Unlike ExpansionTile it keeps no PageStorage
/// state, which would collide with the SelectableTexts in the same list.
class _Expandable extends StatefulWidget {
  const _Expandable({
    super.key,
    required this.title,
    required this.color,
    required this.children,
  });

  final String title;
  final Color color;
  final List<Widget> children;

  @override
  State<_Expandable> createState() => _ExpandableState();
}

class _ExpandableState extends State<_Expandable> {
  bool expanded = false;

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      InkWell(
        borderRadius: BorderRadius.circular(10),
        onTap: () => setState(() => expanded = !expanded),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 12),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  widget.title,
                  style: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              AnimatedRotation(
                turns: expanded ? 0.5 : 0,
                duration: const Duration(milliseconds: 200),
                child: Icon(
                  Icons.expand_more,
                  color: expanded ? widget.color : ProxyColors.muted,
                ),
              ),
            ],
          ),
        ),
      ),
      if (expanded) ...[...widget.children, const SizedBox(height: 8)],
    ],
  );
}

/// One attempt, marked in red without dominating the card.
class _FailureEntry extends StatelessWidget {
  const _FailureEntry({super.key, required this.failure, this.latest = false});

  final SignupFailure failure;
  final bool latest;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.fromLTRB(12, 8, 12, 10),
    decoration: BoxDecoration(
      color: ProxyColors.red.withValues(alpha: latest ? 0.05 : 0.03),
      borderRadius: BorderRadius.circular(10),
      border: Border(
        left: BorderSide(
          color: ProxyColors.red.withValues(alpha: latest ? 0.7 : 0.4),
          width: 2,
        ),
      ),
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(
              latest ? Icons.error_outline : Icons.history,
              size: 14,
              color: ProxyColors.red,
            ),
            const SizedBox(width: 6),
            Expanded(
              child: Text(
                latest ? 'Lỗi gần nhất' : 'Lần đăng ký lỗi',
                style: const TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                  color: ProxyColors.red,
                ),
              ),
            ),
            Text(
              formatFailureTime(failure.createdAt),
              style: const TextStyle(fontSize: 11, color: ProxyColors.muted),
            ),
          ],
        ),
        const SizedBox(height: 4),
        SelectableText(
          failure.message,
          style: const TextStyle(
            fontSize: 12,
            height: 1.45,
            color: Color(0xFFDCCBCB),
          ),
        ),
        if (failure.step.isNotEmpty) ...[
          const SizedBox(height: 4),
          Text(
            'Bước: ${failure.step}',
            style: const TextStyle(fontSize: 11, color: ProxyColors.muted),
          ),
        ],
      ],
    ),
  );
}
