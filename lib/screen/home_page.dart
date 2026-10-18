import 'package:flutter/material.dart';

import '../controller/home_controller.dart';
import '../core/otp_settings_store.dart';
import '../core/proxy_store.dart';
import '../core/tiktok_flow_result.dart';
import 'home/auto_run_banner.dart';
import 'home/configuration_tab.dart';
import 'home/failed_configurations_tab.dart';
import 'home/home_style.dart';
import 'home/nurture_tab.dart';
import 'proxy_management_page.dart';
import 'settings_page.dart';
import 'tiktok_page.dart';
import 'widgets/controller_scope.dart';

class HomePage extends StatelessWidget {
  const HomePage({
    super.key,
    required this.userAgent,
    this.proxyStore,
    this.initialOtpSettings,
    this.otpSettingsStore,
    this.clearSession,
  });
  final String userAgent;
  final ProxyStore? proxyStore;
  final OtpApiSettings? initialOtpSettings;
  final OtpSettingsStore? otpSettingsStore;
  final Future<void> Function()? clearSession;

  @override
  Widget build(BuildContext context) => ControllerScope<HomeController>(
    controller: HomeController(
      initialUserAgent: userAgent,
      initialOtpSettings: initialOtpSettings ?? OtpApiSettings.defaults(),
      store: proxyStore,
      otpSettingsStore: otpSettingsStore,
      clearSession: clearSession,
    ),
    builder: (logic) => _HomeView(logic),
  );
}

/// The app bar, the tab bar and the routes the tabs open. Each tab's content
/// and actions live in `home/`.
class _HomeView extends StatelessWidget {
  const _HomeView(this.logic);
  final HomeController logic;

  Future<void> _manageProxies(BuildContext context) => logic.manageProxies(
    () => Navigator.of(context).push<void>(
      MaterialPageRoute(
        builder: (_) => Theme(
          data: HomeStyle.theme(context),
          child: ProxyManagementPage(store: logic.proxyStore),
        ),
      ),
    ),
  );

  Future<void> _openTikTok(
    BuildContext context,
    TikTokLaunchAction action, {
    bool startWithNurture = false,
  }) async {
    TikTokFlowResult? result;
    await logic.openTikTok(action, (configuration, action) async {
      result = await Navigator.of(context).push<TikTokFlowResult>(
        MaterialPageRoute<TikTokFlowResult>(
          builder: (_) => TikTokPage(
            configuration: configuration,
            launchAction: action,
            startWithNurture: startWithNurture,
            proxyStore: logic.proxyStore,
          ),
        ),
      );
    });
    if (!context.mounted || !logic.active) return;
    if (result == TikTokFlowResult.nurtureCompleted && context.mounted) {
      final messenger = ScaffoldMessenger.of(context);
      messenger.clearSnackBars();
      messenger.removeCurrentSnackBar();
      logic.notify('Đã nuôi xong. Tài khoản vẫn đang đăng nhập.');
    }
  }

  /// Signup continues through every unregistered configuration; nurture
  /// logs in to every registered one, then logs out.
  Future<void> _startAutoRun(BuildContext context, AutoRunMode mode) =>
      logic.startAutoRun(mode, (configuration, action) async {
        if (!context.mounted) return null;
        final result = await Navigator.of(context).push<TikTokFlowResult>(
          MaterialPageRoute<TikTokFlowResult>(
            builder: (_) => TikTokPage(
              configuration: configuration,
              launchAction: action,
              proxyStore: logic.proxyStore,
              autoAdvance: true,
              logoutAfterNurture: mode == AutoRunMode.nurture,
            ),
          ),
        );
        // Notices from the closed TikTok screen no longer apply on Home.
        if (context.mounted) ScaffoldMessenger.of(context).clearSnackBars();
        return result;
      });

  void _runAccountAction(BuildContext context) {
    if (logic.accountAction == TikTokLaunchAction.signup) {
      _startAutoRun(context, AutoRunMode.signup);
    } else {
      _openTikTok(
        context,
        logic.accountAction,
        startWithNurture: logic.hasCurrentAccountSession,
      );
    }
  }

  Future<void> _openSettings(BuildContext context) =>
      Navigator.of(context).push<void>(
        MaterialPageRoute(
          builder: (_) => SettingsPage(
            proxyStore: logic.proxyStore,
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
            onOpenIpCheck: () => logic.openTikTok(
              TikTokLaunchAction.browse,
              (configuration, _) => Navigator.of(context).push<void>(
                MaterialPageRoute(
                  builder: (_) => TikTokPage(
                    configuration: configuration,
                    startWithIpCheck: true,
                  ),
                ),
              ),
            ),
          ),
        ),
      );

  @override
  Widget build(BuildContext context) => Theme(
    data: HomeStyle.theme(context),
    child: Scaffold(
      backgroundColor: HomeStyle.background,
      appBar: AppBar(
        backgroundColor: HomeStyle.background,
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
        bottom: TabBar(
          controller: logic.tabs,
          labelColor: HomeStyle.cyan,
          unselectedLabelColor: HomeStyle.muted,
          indicatorColor: HomeStyle.cyan,
          dividerColor: HomeStyle.border,
          labelPadding: const EdgeInsets.symmetric(horizontal: 6),
          tabs: const [
            Tab(key: Key('configurationTab'), text: 'Cấu hình'),
            Tab(key: Key('nurtureTab'), text: 'Nuôi Account'),
            Tab(key: Key('failedTab'), text: 'Cấu hình lỗi'),
          ],
        ),
      ),
      body: SafeArea(
        bottom: false,
        child: Column(
          children: [
            if (logic.autoRunning) AutoRunBanner(logic: logic),
            Expanded(
              child: AbsorbPointer(
                absorbing: logic.busy,
                child: TabBarView(
                  controller: logic.tabs,
                  children: [
                    ConfigurationTab(
                      logic: logic,
                      onManageProxies: () => _manageProxies(context),
                    ),
                    NurtureTab(logic: logic),
                    FailedConfigurationsTab(logic: logic),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
      bottomNavigationBar: switch (logic.tabIndex) {
        0 => ConfigurationActionBar(
          logic: logic,
          onRunAccountAction: () => _runAccountAction(context),
          onOpenTikTok: () => _openTikTok(context, TikTokLaunchAction.browse),
        ),
        1 => NurtureActionBar(
          logic: logic,
          onNurtureAll: () => _startAutoRun(context, AutoRunMode.nurture),
        ),
        _ => FailedConfigurationsActionBar(
          logic: logic,
          onRetryAll: () => _startAutoRun(context, AutoRunMode.retryFailed),
        ),
      },
    ),
  );
}
