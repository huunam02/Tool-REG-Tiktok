import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/proxy_store.dart';
import '../../core/app_action_theme.dart';

abstract final class ProxyColors {
  static const background = Color(0xFF0B101B);
  static const surface = Color(0xFF141C2A);
  static const input = Color(0xFF0F1623);
  static const border = Color(0xFF283346);
  static const muted = Color(0xFFA0AEC0);
  static const cyan = AppActionTheme.primary;
  static const green = Color(0xFF74DBA1);
  static const amber = Color(0xFFFFCD78);
  static const red = Color(0xFFFF7B7B);

  static ThemeData theme(BuildContext context) {
    final scheme = ColorScheme.fromSeed(
      seedColor: cyan,
      brightness: Brightness.dark,
      surface: surface,
    );
    final shape = RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(14),
    );
    return AppActionTheme.apply(
      Theme.of(context).copyWith(
        brightness: Brightness.dark,
        colorScheme: scheme,
        scaffoldBackgroundColor: background,
        appBarTheme: const AppBarTheme(
          backgroundColor: background,
          foregroundColor: Colors.white,
          surfaceTintColor: Colors.transparent,
        ),
        textTheme: Theme.of(context).textTheme.apply(
          bodyColor: const Color(0xFFF0F4FA),
          displayColor: const Color(0xFFF0F4FA),
        ),
        inputDecorationTheme: InputDecorationTheme(
          filled: true,
          fillColor: input,
          labelStyle: const TextStyle(color: muted, fontSize: 14),
          hintStyle: const TextStyle(color: Color(0xFF718096), fontSize: 13),
          helperStyle: const TextStyle(color: muted, fontSize: 12),
          contentPadding: const EdgeInsets.symmetric(
            horizontal: 16,
            vertical: 16,
          ),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(14),
            borderSide: const BorderSide(color: border),
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(14),
            borderSide: const BorderSide(color: border),
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(14),
            borderSide: const BorderSide(color: cyan, width: 1.5),
          ),
        ),
        filledButtonTheme: FilledButtonThemeData(
          style: FilledButton.styleFrom(
            backgroundColor: cyan,
            foregroundColor: background,
            shape: shape,
            minimumSize: const Size(0, 50),
            textStyle: Theme.of(
              context,
            ).textTheme.labelLarge?.copyWith(fontWeight: FontWeight.w700),
          ),
        ),
        outlinedButtonTheme: OutlinedButtonThemeData(
          style: OutlinedButton.styleFrom(
            foregroundColor: const Color(0xFFDBE4F0),
            side: const BorderSide(color: border),
            shape: shape,
            minimumSize: const Size(0, 48),
          ),
        ),
        iconTheme: const IconThemeData(color: muted),
      ),
    );
  }
}

class ProxyBadge extends StatelessWidget {
  const ProxyBadge({super.key, required this.label, required this.color});
  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
    decoration: BoxDecoration(
      color: color.withValues(alpha: 0.10),
      border: Border.all(color: color.withValues(alpha: 0.20)),
      borderRadius: BorderRadius.circular(9),
    ),
    child: Text(
      label,
      style: TextStyle(color: color, fontSize: 11, fontWeight: FontWeight.w600),
    ),
  );
}

class ProxyUsageBadge extends StatelessWidget {
  const ProxyUsageBadge({super.key, required this.used});
  final bool used;

  @override
  Widget build(BuildContext context) => ProxyBadge(
    label: used ? 'Đã sử dụng' : 'Chưa sử dụng',
    color: used ? ProxyColors.green : ProxyColors.amber,
  );
}

class ProxyPanel extends StatelessWidget {
  const ProxyPanel({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(18),
  });
  final Widget child;
  final EdgeInsetsGeometry padding;

  @override
  Widget build(BuildContext context) => Container(
    padding: padding,
    decoration: BoxDecoration(
      color: ProxyColors.surface,
      border: Border.all(color: ProxyColors.border),
      borderRadius: BorderRadius.circular(20),
    ),
    child: child,
  );
}

class ProxyDetails extends StatelessWidget {
  const ProxyDetails({
    super.key,
    required this.profile,
    required this.keyPrefix,
    this.showName = false,
    this.userAgentKey,
  });
  final ProxyProfile profile;
  final String keyPrefix;
  final bool showName;
  final Key? userAgentKey;

  Widget _field(
    BuildContext context,
    String label,
    String value,
    IconData icon, {
    Key? valueKey,
  }) => Container(
    padding: const EdgeInsets.fromLTRB(12, 12, 8, 12),
    decoration: BoxDecoration(
      color: ProxyColors.input,
      borderRadius: BorderRadius.circular(13),
      border: Border.all(color: ProxyColors.border.withValues(alpha: 0.7)),
    ),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(top: 2),
          child: Icon(icon, size: 17, color: ProxyColors.muted),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                label,
                style: const TextStyle(fontSize: 11, color: ProxyColors.muted),
              ),
              const SizedBox(height: 5),
              SelectableText(
                value,
                key: valueKey,
                style: const TextStyle(
                  fontSize: 12,
                  height: 1.55,
                  color: Color(0xFFF0F4FA),
                ),
              ),
            ],
          ),
        ),
        IconButton(
          tooltip: 'Sao chép ${label.toLowerCase()}',
          visualDensity: VisualDensity.compact,
          iconSize: 16,
          onPressed: () async {
            await Clipboard.setData(ClipboardData(text: value));
            if (!context.mounted) return;
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(content: Text('Đã sao chép ${label.toLowerCase()}.')),
            );
          },
          icon: const Icon(Icons.copy_outlined),
        ),
      ],
    ),
  );

  @override
  Widget build(BuildContext context) {
    final proxy = profile.proxy;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (showName &&
            profile.name.isNotEmpty &&
            profile.name != proxyLabel(proxy)) ...[
          Text(
            profile.name,
            style: const TextStyle(
              fontSize: 16,
              height: 1.4,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 12),
        ],
        _field(
          context,
          'Địa chỉ proxy',
          proxyLabel(proxy),
          Icons.link,
          valueKey: Key('${keyPrefix}Address'),
        ),
        const SizedBox(height: 10),
        _field(
          context,
          'Tài khoản proxy',
          proxy?.username.isEmpty ?? true
              ? 'Không yêu cầu xác thực'
              : proxy!.username,
          Icons.person_outline,
          valueKey: Key('${keyPrefix}Username'),
        ),
        if (proxy?.password.isNotEmpty ?? false) ...[
          const SizedBox(height: 10),
          _field(
            context,
            'Mật khẩu proxy',
            proxy!.password,
            Icons.lock_outline,
            valueKey: Key('${keyPrefix}Password'),
          ),
        ],
        const SizedBox(height: 10),
        _field(
          context,
          'User-Agent',
          profile.userAgent,
          Icons.computer_outlined,
          valueKey: userAgentKey ?? Key('${keyPrefix}UserAgent'),
        ),
        const SizedBox(height: 10),
        _field(
          context,
          'Múi giờ WebView',
          profile.timeZoneId.isEmpty ? 'Chưa xác định' : profile.timeZoneId,
          Icons.schedule,
          valueKey: Key('${keyPrefix}TimeZone'),
        ),
        const SizedBox(height: 10),
        _field(
          context,
          'Thiết bị (GPU)',
          profile.gpuProfile.label,
          Icons.smartphone,
          valueKey: Key('${keyPrefix}GpuProfile'),
        ),
        if (profile.account != null) ...[
          const SizedBox(height: 10),
          _field(
            context,
            'Trạng thái tài khoản',
            profile.statusAccount.label,
            Icons.verified_user_outlined,
            valueKey: Key('${keyPrefix}AccountStatus'),
          ),
          const SizedBox(height: 10),
          _field(
            context,
            'Nuôi sau khi đăng ký',
            profile.nurtureAfterSignup ? 'Bật' : 'Tắt (chỉ đăng ký)',
            Icons.spa_outlined,
            valueKey: Key('${keyPrefix}NurtureAfterSignup'),
          ),
          const SizedBox(height: 10),
          _field(
            context,
            'Cấu hình nuôi',
            profile.nurtureSettings.summary,
            Icons.tune,
            valueKey: Key('${keyPrefix}NurtureSettings'),
          ),
          const SizedBox(height: 10),
          _field(
            context,
            'Email TikTok',
            profile.account!.email,
            Icons.alternate_email,
            valueKey: Key('${keyPrefix}AccountEmail'),
          ),
          const SizedBox(height: 10),
          _field(
            context,
            'Mật khẩu TikTok',
            profile.account!.password,
            Icons.lock_outline,
            valueKey: Key('${keyPrefix}AccountPassword'),
          ),
          const SizedBox(height: 10),
          _field(
            context,
            'Data Mail',
            profile.account!.mailboxPassword,
            Icons.mail_outline,
            valueKey: Key('${keyPrefix}MailboxPassword'),
          ),
        ] else ...[
          const SizedBox(height: 10),
          const Text(
            'Chưa có tài khoản. Bổ sung trong Quản lý cấu hình.',
            style: TextStyle(fontSize: 12, color: ProxyColors.muted),
          ),
        ],
      ],
    );
  }
}
