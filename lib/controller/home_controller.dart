import 'dart:async';
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:get/get.dart';

import '../core/app_configuration.dart';
import '../core/services/remote_config_service.dart';
import '../core/app_session.dart';
import '../core/nurture_data.dart';
import '../core/proxy_geolocation.dart';
import '../core/configuration_data.dart';
import '../core/desktop_user_agents.dart';
import '../core/otp_api.dart';
import '../core/otp_settings_store.dart';
import '../core/proxy_store.dart';
import '../core/webview_proxy.dart';
import '../core/webview_user_agent.dart';
import '../core/tiktok_launch_action.dart';
import 'app_controller.dart';

class HomeController extends AppController
    with GetSingleTickerProviderStateMixin, WidgetsBindingObserver {
  HomeController({
    required this.initialUserAgent,
    required this.initialOtpSettings,
    ProxyStore? store,
    OtpSettingsStore? otpSettingsStore,
    DateTime Function()? now,
    Random? workflowRandom,
    Future<bool> Function()? readLoginSession,
  }) : store = store ?? ProxyStore.instance,
       _now = now ?? DateTime.now,
       _workflowRandom = workflowRandom ?? Random(),
       _readLoginSession = readLoginSession ?? hasTikTokLoginSession,
       otpSettingsStore = otpSettingsStore ?? OtpSettingsStore.instance;

  final String initialUserAgent;
  final OtpApiSettings initialOtpSettings;
  final ProxyStore store;
  final OtpSettingsStore otpSettingsStore;
  final DateTime Function() _now;
  final Random _workflowRandom;
  final Future<bool> Function() _readLoginSession;
  int _profileLoadGeneration = 0;
  bool hasCurrentAccountSession = false;
  Timer? _scheduledLoginTimer;
  DateTime? autoLoginStartsAt;
  AppConfiguration? _scheduledConfiguration;
  Future<void> Function()? _scheduledLogin;
  bool _appActive = true;
  bool _checkingScheduledLogin = false;
  int _scheduleGeneration = 0;
  bool get waitingForAutoLogin => autoLoginStartsAt != null;

  void scheduleLoginAfterSignup(
    AppConfiguration configuration,
    Future<void> Function() login,
  ) {
    if (!active) return;
    cancelScheduledLogin();
    if (configuration.configurationId == null) {
      notify('Không tìm thấy cấu hình vừa đăng ký để tự đăng nhập lại.');
      return;
    }
    final hold = Duration(seconds: 120 + _workflowRandom.nextInt(61));
    _scheduledConfiguration = configuration;
    _scheduledLogin = login;
    mutate(() => autoLoginStartsAt = _now().add(hold));
    _scheduledLoginTimer = Timer(hold, () => unawaited(_runScheduledLogin()));
  }

  void cancelScheduledLogin() {
    _scheduleGeneration++;
    _scheduledLoginTimer?.cancel();
    _scheduledLoginTimer = null;
    _scheduledConfiguration = null;
    _scheduledLogin = null;
    autoLoginStartsAt = null;
    mutate(() {});
  }

  Future<void> _runScheduledLogin() async {
    final expected = _scheduledConfiguration;
    final login = _scheduledLogin;
    if (!active ||
        !_appActive ||
        _checkingScheduledLogin ||
        expected == null ||
        login == null ||
        autoLoginStartsAt == null ||
        _now().isBefore(autoLoginStartsAt!)) {
      return;
    }
    final generation = _scheduleGeneration;
    _checkingScheduledLogin = true;
    try {
      final selected = await store.getCurrentProfile();
      if (!active || generation != _scheduleGeneration || !_appActive) return;
      if (selected?.configurationId != expected.configurationId ||
          selected?.account?.email != expected.signupEmail ||
          selected?.account?.password != expected.signupPassword ||
          selected?.account?.mailboxPassword !=
              expected.signupMailboxPassword ||
          !sameProxy(selected?.proxy, expected.proxy) ||
          selected?.statusAccount != AccountStatus.registered) {
        cancelScheduledLogin();
        notify('Cấu hình đã thay đổi. Đã hủy lịch đăng nhập tự động.');
        return;
      }
      await restoreProxy();
      if (!active || generation != _scheduleGeneration || !_appActive) return;
      if (proxyLoadFailed ||
          currentProxy?.configurationId != expected.configurationId ||
          currentProxy?.account?.email != expected.signupEmail) {
        cancelScheduledLogin();
        notify(
          'Không thể mở lại đúng cấu hình vừa đăng ký. Đã hủy lịch đăng nhập.',
        );
        return;
      }
      cancelScheduledLogin();
      await login();
    } catch (_) {
      if (active && generation == _scheduleGeneration) {
        cancelScheduledLogin();
        notify('Không thể mở lại cấu hình để đăng nhập tự động. Hãy thử lại.');
      }
    } finally {
      _checkingScheduledLogin = false;
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _appActive = state == AppLifecycleState.resumed;
    if (_appActive) {
      if (waitingForAutoLogin) {
        unawaited(_runScheduledLogin());
      } else if (!opening && !managingProxies) {
        unawaited(refreshCurrentAccountSession());
      }
    }
  }

  late String userAgent;
  late String directUserAgent;
  late OtpApiSettings otpSettings;
  ProxyProfile? currentProxy;
  late final TabController tabs;
  int tabIndex = 0;
  List<NurtureAccount> nurtureAccounts = [];
  bool loadingAccounts = false;
  bool accountsLoadFailed = false;
  bool opening = false;
  bool loadingProxy = true;
  bool proxyLoadFailed = false;
  bool managingProxies = false;
  ProxyGeolocationLookup? _timeZoneLookup;
  late final ProxyStore proxyStore;
  bool get busy =>
      opening || loadingProxy || managingProxies || waitingForAutoLogin;
  TikTokLaunchAction get accountAction => hasCurrentAccountSession
      ? TikTokLaunchAction.browse
      : currentProxy?.statusAccount == AccountStatus.registered
      ? TikTokLaunchAction.login
      : TikTokLaunchAction.signup;
  String get accountActionLabel => hasCurrentAccountSession
      ? 'Nuôi tiếp Account'
      : accountAction == TikTokLaunchAction.login
      ? 'Đăng nhập và nuôi Account'
      : 'Đăng ký tài khoản';

  @override
  void onInit() {
    super.onInit();
    WidgetsBinding.instance.addObserver(this);
    userAgent = initialUserAgent;
    directUserAgent = initialUserAgent;
    otpSettings = initialOtpSettings;
    tabs = TabController(length: 2, vsync: this);
    tabs.addListener(() {
      if (tabIndex == tabs.index) return;
      mutate(() => tabIndex = tabs.index);
      if (tabIndex == 1) unawaited(loadNurtureAccounts());
    });
    proxyStore = store;
    unawaited(restoreProxy());
    unawaited(loadNurtureAccounts());
  }

  Future<void> loadNurtureAccounts() async {
    if (loadingAccounts) return;
    mutate(() => loadingAccounts = true);
    try {
      final accounts = await store.nurture.listAccounts();
      if (active) {
        mutate(() {
          nurtureAccounts = accounts;
          accountsLoadFailed = false;
        });
      }
    } catch (_) {
      if (active) mutate(() => accountsLoadFailed = true);
    } finally {
      if (active) mutate(() => loadingAccounts = false);
    }
  }

  Future<void> openManualViewing(
    NurtureAccount account,
    Future<void> Function(AppConfiguration, NurturePlan) navigate,
  ) async {
    if (busy || account.configurationId == null) return;
    mutate(() => managingProxies = true);
    try {
      final configurations = await store.list();
      final selected = configurations
          .where((row) => row.id == account.configurationId)
          .firstOrNull;
      if (selected == null) throw StateError('Configuration deleted');
      final current = await store.getCurrentProfile();
      if (!sameProfile(current, selected)) await clearAppSession();
      if (!active) return;
      await store.useSaved(selected.id);
      await restoreProxy();
    } catch (_) {
      if (active) notify('Không thể chọn cấu hình của tài khoản. Hãy thử lại.');
      return;
    } finally {
      if (active) mutate(() => managingProxies = false);
    }
    if (!active) {
      return;
    }
    final plan = NurturePlan.choose(RemoteConfig.searchKeywords);
    await openTikTok(
      TikTokLaunchAction.browse,
      (configuration, _) => navigate(configuration, plan),
    );
  }

  Future<void> restoreProxy() async {
    final generation = ++_profileLoadGeneration;
    mutate(() => loadingProxy = true);
    try {
      final profile = await proxyStore.getCurrentProfile();
      final restoredDirectUserAgent = profile == null && currentProxy != null
          ? await loadDirectDesktopUserAgent()
          : directUserAgent;
      final hasSession =
          profile?.account?.email.trim().isNotEmpty == true &&
          await proxyStore.canReuseCurrentAccountSession() &&
          await _readLoginSession();
      if (!active || generation != _profileLoadGeneration) return;
      mutate(() {
        currentProxy = profile;
        hasCurrentAccountSession = hasSession;
        directUserAgent = restoredDirectUserAgent;
        userAgent = profile?.userAgent ?? restoredDirectUserAgent;
        proxyLoadFailed = false;
      });
    } catch (_) {
      if (active && generation == _profileLoadGeneration) {
        mutate(() {
          proxyLoadFailed = true;
          hasCurrentAccountSession = false;
        });
      }
    } finally {
      if (active && generation == _profileLoadGeneration) {
        mutate(() => loadingProxy = false);
      }
    }
  }

  Future<void> refreshCurrentAccountSession() async {
    final profile = currentProxy;
    var hasSession = false;
    if (profile?.account?.email.trim().isNotEmpty == true) {
      try {
        hasSession =
            await proxyStore.canReuseCurrentAccountSession() &&
            await _readLoginSession();
      } catch (_) {
        // A failed session check must not block the existing login action.
      }
    }
    if (active && identical(profile, currentProxy)) {
      mutate(() => hasCurrentAccountSession = hasSession);
    }
  }

  Future<void> manageProxies(Future<void> Function() navigate) async {
    if (busy) return;
    mutate(() => managingProxies = true);
    try {
      await navigate();
      if (active) await restoreProxy();
      if (active) await loadNurtureAccounts();
    } finally {
      if (active) mutate(() => managingProxies = false);
    }
  }

  @override
  void onClose() {
    cancelScheduledLogin();
    WidgetsBinding.instance.removeObserver(this);
    _timeZoneLookup?.cancel();
    tabs.dispose();
    super.onClose();
  }

  Future<void> openTikTok(
    TikTokLaunchAction action,
    Future<void> Function(
      AppConfiguration configuration,
      TikTokLaunchAction action,
    )
    navigate,
  ) async {
    if (busy || proxyLoadFailed) return;
    final account = currentProxy?.account;
    if (action != TikTokLaunchAction.browse) {
      if (account == null) {
        notify(
          'Chọn cấu hình có tài khoản trong Quản lý cấu hình trước khi chạy.',
        );
        return;
      }
      try {
        account.validate();
      } on FormatException {
        notify(
          'Bổ sung email, mật khẩu TikTok và mật khẩu email OTP trong Quản lý cấu hình.',
        );
        return;
      }
    }
    FocusManager.instance.primaryFocus?.unfocus();
    mutate(() => opening = true);
    try {
      final browserUserAgent = await resolveWebViewUserAgent(userAgent);
      if (!active) return;
      if (needsAndroidDesktopIdentity) {
        final profile = currentProxy;
        mutate(() {
          userAgent = browserUserAgent;
          if (profile != null) {
            currentProxy = profile.copyWith(userAgent: browserUserAgent);
          }
        });
      }
      final proxy = currentProxy?.proxy;
      final otpApi = otpApiFor(action);
      await configureWebViewProxy(proxy);
      if (!active) return;
      var timeZone = currentProxy?.timeZoneId ?? '';
      if (needsAndroidDesktopIdentity && proxy != null && timeZone.isEmpty) {
        final lookup = ProxyGeolocationLookup();
        _timeZoneLookup = lookup;
        final location = await lookup.lookup(
          proxy: proxy,
          userAgent: browserUserAgent,
        );
        if (!active) return;
        timeZone = location.timeZoneId;
        final profile = currentProxy;
        if (profile?.configurationId != null) {
          final cached = await store.cacheCurrentTimeZone(
            profile!.configurationId!,
            proxy,
            timeZone,
          );
          if (!cached) throw StateError('Cấu hình đang dùng đã thay đổi.');
        }
        if (!active) return;
        if (profile != null) {
          mutate(() => currentProxy = profile.copyWith(timeZoneId: timeZone));
        }
      }
      final configuration = AppConfiguration(
        configurationId: currentProxy?.configurationId,
        userAgent: browserUserAgent,
        proxy: proxy,
        webViewTimeZone:
            needsAndroidDesktopIdentity && proxy != null && timeZone.isNotEmpty
            ? timeZone
            : null,
        comments: RemoteConfig.autoComments,
        searchKeywords: RemoteConfig.searchKeywords,
        signupEmail: account?.email ?? '',
        signupPassword: account?.password ?? '',
        loginUsername: account?.email ?? '',
        loginPassword: account?.password ?? '',
        signupMailboxPassword: account?.mailboxPassword ?? '',
        loginMailboxPassword: account?.mailboxPassword ?? '',
        otpApi: otpApi,
        birthday: action == TikTokLaunchAction.signup
            ? AppConfiguration.randomSignupBirthday()
            : null,
      );
      await navigate(configuration, action);
      if (active && action == TikTokLaunchAction.signup) {
        await restoreProxy();
      } else if (active) {
        await refreshCurrentAccountSession();
      }
      if (active) await loadNurtureAccounts();
    } on FormatException catch (error) {
      if (!active) return;
      notify(error.message);
    } on PlatformException catch (error) {
      if (!active) return;
      notify(
        error.code == 'proxy_unsupported'
            ? error.message ?? 'Thiết bị không hỗ trợ proxy.'
            : 'Không thể áp dụng proxy. Hãy kiểm tra cấu hình rồi thử lại.',
      );
    } catch (_) {
      if (!active) return;
      notify('Không thể mở TikTok. Hãy thử lại.');
    } finally {
      _timeZoneLookup?.cancel();
      _timeZoneLookup = null;
      if (active) mutate(() => opening = false);
    }
  }

  OtpApiConfiguration? otpApiFor(TikTokLaunchAction action) {
    if (action == TikTokLaunchAction.browse) return null;
    if (otpSettings.token.trim().isEmpty) {
      throw const FormatException(
        'Token OTP API chưa được cấu hình trong Remote Config.',
      );
    }
    try {
      return otpSettings.toConfiguration();
    } on FormatException {
      throw const FormatException(
        'URL OTP API trong Remote Config phải là HTTP/HTTPS hợp lệ.',
      );
    }
  }
}
