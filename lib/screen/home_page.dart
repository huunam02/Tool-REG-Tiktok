import 'package:flutter/material.dart';

import '../core/controller/home_controller.dart';
import '../core/controller/tiktok_controller.dart';
import '../core/otp_settings_store.dart';
import '../core/proxy_store.dart';
import '../core/tiktok_flow_result.dart';
import 'home/auto_run_banner.dart';
import 'home/configuration_tab.dart';
import 'home/failed_configurations_tab.dart';
import 'home/home_style.dart';
import 'home/nurture_tab.dart';
import 'home/signup_tab.dart';
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
          child: ProxyManagementPage(
            store: logic.proxyStore,
            onCheckIp: (entry) => logic.checkConfiguration(
              entry,
              (configuration) => Navigator.of(context).push<void>(
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
      ),
    ),
  );

  /// Signup continues through every unregistered configuration; nurture
  /// reuses each registered account’s session and retains it after nurturing.
  Future<void> _startAutoRun(
    BuildContext context,
    AutoRunMode mode, {
    int? firstId,
    List<int> order = const [],
    int? onlyId,
  }) => logic.startAutoRun(
    mode,
    firstId: firstId,
    order: order,
    onlyId: onlyId,
    (configuration, action) async {
      if (!context.mounted) return null;
      final result = await Navigator.of(context).push<TikTokFlowResult>(
        MaterialPageRoute<TikTokFlowResult>(
          builder: (_) => TikTokPage(
            configuration: configuration,
            launchAction: action,
            proxyStore: logic.proxyStore,
            autoAdvance: true,
          ),
        ),
      );
      // Notices from the closed TikTok screen no longer apply on Home.
      if (context.mounted) ScaffoldMessenger.of(context).clearSnackBars();
      return result;
    },
  );

  Future<void> _openSettings(BuildContext context) =>
      Navigator.of(context).push<void>(
        MaterialPageRoute(
          builder: (settings) => SettingsPage(
            proxyStore: logic.proxyStore,
            onBrowserCheck: () => logic.openBrowserCheck(
              (configuration) => Navigator.of(settings).push<void>(
                MaterialPageRoute(
                  builder: (_) => TikTokPage(
                    configuration: configuration,
                    startWithBrowserCheck: true,
                    browserCheckPage: TikTokController.deviceBrowserCheckUrl,
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
          indicatorSize: TabBarIndicatorSize.tab,
          dividerColor: HomeStyle.border,
          labelPadding: const EdgeInsets.symmetric(horizontal: 4),
          tabs: const [
            Tab(key: Key('configurationTab'), text: 'Cấu hình'),
            Tab(key: Key('signupTab'), text: 'Đăng ký'),
            Tab(key: Key('nurtureTab'), text: 'Nuôi'),
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
                    SignupTab(
                      logic: logic,
                      onSignup: (id) => _startAutoRun(
                        context,
                        AutoRunMode.signup,
                        firstId: id,
                        onlyId: id,
                      ),
                    ),
                    NurtureTab(
                      logic: logic,
                      onNurture: (id) => logic.nurtureAccount(id, (
                        configuration,
                        action,
                      ) async {
                        if (!context.mounted) return;
                        await Navigator.of(context).push<TikTokFlowResult>(
                          MaterialPageRoute(
                            builder: (_) => TikTokPage(
                              configuration: configuration,
                              launchAction: action,
                              proxyStore: logic.proxyStore,
                            ),
                          ),
                        );
                      }),
                    ),
                    FailedConfigurationsTab(logic: logic),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
      bottomNavigationBar: switch (logic.tabIndex) {
        // Cấu hình has no actions of its own beyond Quản lý cấu hình.
        HomeController.configurationTab => null,
        // Each list runs from its chosen item, then in the order it shows.
        HomeController.signupTab => SignupActionBar(
          logic: logic,
          onStartSignup: () => _startAutoRun(
            context,
            AutoRunMode.signup,
            firstId: logic.signupPriority?.id,
            order: [for (final entry in logic.signupConfigurations) entry.id],
          ),
        ),
        HomeController.nurtureTab => NurtureActionBar(
          logic: logic,
          onNurtureAll: () => _startAutoRun(
            context,
            AutoRunMode.nurture,
            firstId: logic.nurturePriority?.configurationId,
            order: [
              for (final account in logic.nurtureAccounts)
                ?account.configurationId,
            ],
          ),
        ),
        _ => FailedConfigurationsActionBar(
          logic: logic,
          onRetryAll: () => _startAutoRun(
            context,
            AutoRunMode.retryFailed,
            firstId: logic.failedPriority?.configuration.id,
            order: [
              for (final failed in logic.failedConfigurations)
                failed.configuration.id,
            ],
          ),
        ),
      },
    ),
  );
}
