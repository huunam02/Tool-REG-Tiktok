import 'package:flutter/material.dart';

import '../core/otp_settings_store.dart';
import '../core/proxy_store.dart';
import '../core/app_action_theme.dart';
import 'proxy_management_page.dart';
import 'settings_page.dart';
import 'widgets/proxy_widgets.dart';
import 'tiktok_page.dart';

import '../controller/home_controller.dart';
import 'widgets/controller_scope.dart';

class HomePage extends StatelessWidget {
  const HomePage({
    super.key,
    required this.userAgent,
    this.proxyStore,
    this.initialOtpSettings = const OtpApiSettings.defaults(),
    this.otpSettingsStore,
  });
  final String userAgent;
  final ProxyStore? proxyStore;
  final OtpApiSettings initialOtpSettings;
  final OtpSettingsStore? otpSettingsStore;

  @override
  Widget build(BuildContext context) => ControllerScope<HomeController>(
        controller: HomeController(
          initialUserAgent: userAgent,
          initialOtpSettings: initialOtpSettings,
          store: proxyStore,
          otpSettingsStore: otpSettingsStore,
        ),
        builder: (logic) => _HomeView(logic),
      );
}

class _HomeView extends StatelessWidget {
  const _HomeView(this.logic);
  final HomeController logic;

  Future<void> _manageProxies(BuildContext context) => logic.manageProxies(
        () => Navigator.of(context).push<void>(
          MaterialPageRoute(
            builder: (_) => Theme(
              data: _HomeStyle.theme(context),
              child: ProxyManagementPage(store: logic.proxyStore),
            ),
          ),
        ),
      );

  Future<void> _openTikTok(BuildContext context, TikTokLaunchAction action) =>
      logic.openTikTok(
        action,
        (configuration, action) => Navigator.of(context).push<void>(
          MaterialPageRoute(
            builder: (_) =>
                TikTokPage(configuration: configuration, launchAction: action),
          ),
        ),
      );

  Future<void> _openSettings(BuildContext context) =>
      Navigator.of(context).push<void>(
        MaterialPageRoute(
          builder: (_) => SettingsPage(
            initialOtpSettings: logic.otpSettings,
            otpSettingsStore: logic.otpSettingsStore,
            onOtpSettingsChanged: logic.updateOtpSettings,
            onOpenBrowserCheck: () => logic.openTikTok(
              TikTokLaunchAction.browse,
              (configuration, _) => Navigator.of(context).push<void>(
                MaterialPageRoute(
                  builder: (_) => TikTokPage(
                    configuration: configuration,
                    startWithBrowserCheck: true,
                  ),
                ),
              ),
            ),
          ),
        ),
      );

  InputDecoration _decoration(
    String label, {
    String? hint,
    String? helper,
    IconData? icon,
  }) =>
      InputDecoration(
        labelText: label,
        hintText: hint,
        helperText: helper,
        helperMaxLines: 3,
        prefixIcon: icon == null ? null : Icon(icon, size: 20),
      );

  Widget _section(
    String title,
    String description,
    IconData icon,
    List<Widget> fields,
  ) =>
      Material(
        color: _HomeStyle.surface,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(22),
          side: const BorderSide(color: _HomeStyle.border),
        ),
        clipBehavior: Clip.antiAlias,
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: _HomeStyle.cyan.withValues(alpha: 0.09),
                      borderRadius: BorderRadius.circular(13),
                    ),
                    child: Icon(icon, size: 22, color: _HomeStyle.cyan),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          title,
                          style: const TextStyle(
                            fontSize: 17,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          description,
                          style: const TextStyle(
                            fontSize: 12,
                            height: 1.5,
                            color: _HomeStyle.muted,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 22),
              ...fields,
            ],
          ),
        ),
      );

  Widget _pair(Widget first, Widget second, bool wide) => wide
      ? Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(child: first),
            const SizedBox(width: 18),
            Expanded(child: second),
          ],
        )
      : Column(children: [first, const SizedBox(height: 16), second]);

  @override
  Widget build(BuildContext context) => Theme(
        data: _HomeStyle.theme(context),
        child: Scaffold(
          backgroundColor: _HomeStyle.background,
          appBar: AppBar(
            backgroundColor: _HomeStyle.background,
            surfaceTintColor: Colors.transparent,
            centerTitle: false,
            toolbarHeight: 72,
            titleSpacing: 20,
            title: Row(
              children: [
                ClipRRect(
                  borderRadius: BorderRadius.circular(10),
                  child: SizedBox(
                    width: 44,
                    height: 44,
                    child: Image.asset('assets/logo.png', fit: BoxFit.cover),
                  ),
                ),
                const SizedBox(width: 12),
                const Expanded(
                  child: Text(
                    'Tool TikTok',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
                  ),
                ),
              ],
            ),
            actions: [
              IconButton(
                key: const Key('openSettings'),
                tooltip: 'Cài đặt',
                onPressed: logic.busy ? null : () => _openSettings(context),
                icon: const Icon(Icons.settings_outlined),
              ),
              const SizedBox(width: 8),
            ],
          ),
          body: SafeArea(
            bottom: false,
            child: AbsorbPointer(
              absorbing: logic.busy,
              child: LayoutBuilder(
                builder: (context, constraints) {
                  final wide = constraints.maxWidth >= 760;
                  return _homeContent(wide, [
                    _pair(_proxySection(context), _commentsSection(), wide),
                    const SizedBox(height: 18),
                  ]);
                },
              ),
            ),
          ),
          bottomNavigationBar: _actionBar(context),
        ),
      );

  Widget _homeContent(
    bool wide,
    List<Widget> sections,
  ) =>
      Form(
        key: logic.formKey,
        child: SingleChildScrollView(
          key: const PageStorageKey('home-general'),
          keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
          padding: EdgeInsets.fromLTRB(wide ? 28 : 16, 16, wide ? 28 : 16, 24),
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 1080),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: sections,
              ),
            ),
          ),
        ),
      );

  Widget _actionBar(BuildContext context) => Container(
        decoration: const BoxDecoration(
          color: _HomeStyle.background,
          border: Border(top: BorderSide(color: _HomeStyle.border)),
        ),
        child: SafeArea(
          top: false,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
            child: Center(
              heightFactor: 1,
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 1080),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    if (logic.currentProxy != null) ...[
                      FilledButton(
                        key: const Key('runAccountAction'),
                        onPressed: logic.busy ||
                                logic.proxyLoadFailed ||
                                logic.currentProxy?.account == null
                            ? null
                            : () => _openTikTok(context, logic.accountAction),
                        child: Text(
                          logic.accountAction == TikTokLaunchAction.login
                              ? 'Đăng nhập tài khoản'
                              : 'Đăng ký tài khoản',
                          textAlign: TextAlign.center,
                        ),
                      ),
                      const SizedBox(height: 10),
                    ],
                    OutlinedButton(
                      key: const Key('openTikTok'),
                      onPressed: logic.busy || logic.proxyLoadFailed
                          ? null
                          : () =>
                              _openTikTok(context, TikTokLaunchAction.browse),
                      child: Text(
                        logic.opening ? 'Đang mở TikTok…' : 'Mở TikTok',
                        textAlign: TextAlign.center,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      );

  Widget _proxySection(BuildContext context) =>
      _section('Cấu hình', 'Proxy và tài khoản đang sử dụng.', Icons.public, [
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
          onPressed: logic.busy ? null : () => _manageProxies(context),
          child: const Text('Quản lý cấu hình'),
        ),
      ]);

  Widget _commentsSection() => _section(
        'Bình luận',
        'Danh sách các bình luận random',
        Icons.chat_bubble_outline,
        [
          TextFormField(
            key: const Key('comments'),
            controller: logic.comments,
            minLines: 4,
            maxLines: 10,
            decoration: _decoration(
              'Nội dung bình luận',
              helper: 'Mỗi dòng là một bình luận.',
            ),
          ),
        ],
      );
}

abstract final class _HomeStyle {
  static const background = Color(0xFF0B101B);
  static const surface = Color(0xFF141C2A);
  static const input = Color(0xFF0F1623);
  static const border = Color(0xFF283346);
  static const muted = Color(0xFFA0AEC0);
  static const cyan = AppActionTheme.primary;

  static ThemeData theme(BuildContext context) {
    final scheme = ColorScheme.fromSeed(
      seedColor: cyan,
      brightness: Brightness.dark,
      surface: surface,
    );
    final base = Theme.of(context);
    final shape = RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(14),
    );
    final text = base.textTheme.labelLarge?.copyWith(
      fontSize: 13,
      fontWeight: FontWeight.w700,
    );
    return AppActionTheme.apply(
      base.copyWith(
        brightness: Brightness.dark,
        colorScheme: scheme,
        textTheme: base.textTheme.apply(
          bodyColor: const Color(0xFFF0F4FA),
          displayColor: const Color(0xFFF0F4FA),
        ),
        iconTheme: const IconThemeData(color: muted),
        inputDecorationTheme: InputDecorationTheme(
          filled: true,
          fillColor: input,
          contentPadding: const EdgeInsets.symmetric(
            horizontal: 16,
            vertical: 17,
          ),
          labelStyle: const TextStyle(color: muted, fontSize: 14),
          hintStyle: const TextStyle(color: Color(0xFF718096), fontSize: 14),
          helperStyle: const TextStyle(color: muted, fontSize: 12, height: 1.5),
          prefixIconColor: muted,
          suffixIconColor: muted,
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
            minimumSize: const Size(0, 52),
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
            shape: shape,
            textStyle: text,
          ),
        ),
        outlinedButtonTheme: OutlinedButtonThemeData(
          style: OutlinedButton.styleFrom(
            foregroundColor: const Color(0xFFDBE4F0),
            side: const BorderSide(color: border),
            minimumSize: const Size(0, 48),
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
            shape: shape,
            textStyle: text,
          ),
        ),
      ),
    );
  }
}
