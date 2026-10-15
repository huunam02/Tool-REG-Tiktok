import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../core/app_configuration.dart';
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

class HomeController extends AppController {
  HomeController({
    required this.initialUserAgent,
    required this.initialOtpSettings,
    ProxyStore? store,
    OtpSettingsStore? otpSettingsStore,
  }) : store = store ?? ProxyStore.instance,
       otpSettingsStore = otpSettingsStore ?? OtpSettingsStore.instance;

  final String initialUserAgent;
  final OtpApiSettings initialOtpSettings;
  final ProxyStore store;
  final OtpSettingsStore otpSettingsStore;

  final formKey = GlobalKey<FormState>();
  late String userAgent;
  late String directUserAgent;
  late OtpApiSettings otpSettings;
  ProxyProfile? currentProxy;
  late final TextEditingController comments;
  bool opening = false;
  bool loadingProxy = true;
  bool proxyLoadFailed = false;
  bool managingProxies = false;
  ProxyGeolocationLookup? _timeZoneLookup;
  late final ProxyStore proxyStore;
  bool get busy => opening || loadingProxy || managingProxies;
  TikTokLaunchAction get accountAction =>
      currentProxy?.statusAccount == AccountStatus.registered
      ? TikTokLaunchAction.login
      : TikTokLaunchAction.signup;

  @override
  void onInit() {
    super.onInit();
    userAgent = initialUserAgent;
    directUserAgent = initialUserAgent;
    otpSettings = initialOtpSettings;
    final defaults = AppConfiguration.defaults(userAgent);
    comments = TextEditingController(text: defaults.comments.join('\n'));
    proxyStore = store;
    unawaited(restoreProxy());
  }

  Future<void> restoreProxy() async {
    mutate(() => loadingProxy = true);
    try {
      final profile = await proxyStore.getCurrentProfile();
      final restoredDirectUserAgent = profile == null && currentProxy != null
          ? await loadDirectDesktopUserAgent()
          : directUserAgent;
      if (!active) return;
      mutate(() {
        currentProxy = profile;
        directUserAgent = restoredDirectUserAgent;
        userAgent = profile?.userAgent ?? restoredDirectUserAgent;
        proxyLoadFailed = false;
      });
    } catch (_) {
      if (active) mutate(() => proxyLoadFailed = true);
    } finally {
      if (active) mutate(() => loadingProxy = false);
    }
  }

  Future<void> manageProxies(Future<void> Function() navigate) async {
    if (busy) return;
    mutate(() => managingProxies = true);
    try {
      await navigate();
      if (active) await restoreProxy();
    } finally {
      if (active) mutate(() => managingProxies = false);
    }
  }

  @override
  void onClose() {
    _timeZoneLookup?.cancel();
    comments.dispose();
    super.onClose();
  }

  void updateOtpSettings(OtpApiSettings settings) =>
      mutate(() => otpSettings = settings);

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
        userAgent: browserUserAgent,
        proxy: proxy,
        webViewTimeZone:
            needsAndroidDesktopIdentity && proxy != null && timeZone.isNotEmpty
            ? timeZone
            : null,
        comments: AppConfiguration.parseComments(comments.text),
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
      throw const FormatException('Hãy cấu hình token OTP API trong Cài đặt.');
    }
    try {
      return otpSettings.toConfiguration();
    } on FormatException {
      throw const FormatException(
        'Hãy cấu hình URL OTP API HTTP/HTTPS hợp lệ trong Cài đặt.',
      );
    }
  }
}
