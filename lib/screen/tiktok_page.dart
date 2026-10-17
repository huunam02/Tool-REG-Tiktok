import 'dart:collection';

import 'package:flutter/material.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';

import '../controller/tiktok_controller.dart';
import '../core/scripts/auto_cookie_script.dart';
import '../core/scripts/auto_interest_script.dart';
import '../core/scripts/auto_watch_script.dart';
import '../core/app_configuration.dart';
import '../core/app_action_theme.dart';
import '../core/otp_api.dart';
import '../core/proxy_store.dart';
import '../core/nurture_data.dart';
import '../core/nurture_store.dart';
import '../core/tiktok_launch_action.dart';
import '../core/tiktok_flow_result.dart';
import '../core/webview_failure.dart';
import '../core/webview_locale.dart';
import '../core/webview_privacy.dart';
import '../core/webview_user_agent.dart';
import '../core/webview_timezone.dart';
import 'widgets/controller_scope.dart';
import 'widgets/signup_viewport.dart';

export '../core/tiktok_launch_action.dart';

class TikTokPage extends StatelessWidget {
  const TikTokPage({
    super.key,
    required this.configuration,
    this.launchAction = TikTokLaunchAction.browse,
    this.startWithNurture = false,
    this.startWithBrowserCheck = false,
    this.startWithIpCheck = false,
    bool useNativeWebView = false,
    this.useInstalledEngine = true,
    this.manualViewingPlan,
    this.nurtureRepository,
    this.otpReaderFactory,
    this.proxyStore,
  }) : useNativeWebView = useNativeWebView || manualViewingPlan != null;

  final AppConfiguration configuration;
  final TikTokLaunchAction launchAction;
  final bool startWithNurture;
  final bool startWithBrowserCheck;
  final bool startWithIpCheck;
  final bool useNativeWebView;
  final bool useInstalledEngine;
  final NurturePlan? manualViewingPlan;
  final NurtureRepository? nurtureRepository;
  final OtpCodeReader Function(OtpApiConfiguration)? otpReaderFactory;
  final ProxyStore? proxyStore;
  String get initialUrl => startWithBrowserCheck
      ? TikTokController.browserCheckUrl
      : startWithIpCheck
      ? TikTokController.ipCheckUrl
      : manualViewingPlan?.initialUrl ?? launchAction.initialUrl;

  @override
  Widget build(BuildContext context) => ControllerScope<TikTokController>(
    floatingNotices: true,
    controller: TikTokController(
      configuration: configuration,
      launchAction: launchAction,
      startWithNurture: startWithNurture,
      startWithBrowserCheck: startWithBrowserCheck,
      startWithIpCheck: startWithIpCheck,
      useNativeWebView: useNativeWebView,
      useInstalledEngine: useInstalledEngine,
      manualViewingPlan: manualViewingPlan,
      nurtureRepository: nurtureRepository,
      otpReaderFactory: otpReaderFactory,
      proxyStore: proxyStore,
      onFlowFinished: (result) {
        if (context.mounted && ModalRoute.of(context)?.isCurrent == true) {
          Navigator.of(context).pop<TikTokFlowResult>(result);
        }
      },
      onReturnToConfiguration: () {
        if (context.mounted) Navigator.of(context).maybePop();
      },
    ),
    builder: (logic) => _TikTokView(logic),
  );
}

class _TikTokView extends StatelessWidget {
  const _TikTokView(this.logic);
  final TikTokController logic;

  Widget _signupViewport(Widget child) => logic.usesAccessibilityAccountFlow
      ? StandardSignupViewport(
          onWidth: (width) => logic.signupViewportWidth = width,
          child: child,
        )
      : child;

  Widget _autoWatchButton() {
    final enabled =
        !logic.waitingToLogout &&
        !logic.logoutBusy &&
        (logic.loginConfirmed ||
            logic.launchAction == TikTokLaunchAction.browse) &&
        logic.webViewController != null &&
        !logic.autoWatchBusy &&
        !logic.autoLoginBusy &&
        !logic.autoSignupBusy &&
        logic.loadingProgress == 100 &&
        logic.pageFailure == null &&
        logic.accountFailure == null &&
        (logic.initialActionStarted ||
            logic.launchAction == TikTokLaunchAction.browse);

    return Tooltip(
      message: logic.autoWatchEnabled
          ? 'Dừng tự động xem video và bình luận'
          : !logic.loginConfirmed &&
                logic.launchAction != TikTokLaunchAction.browse
          ? 'Đăng nhập tự động thành công để bật Auto nuôi'
          : 'Bật tự động xem video và bình luận',
      child: SizedBox(
        height: 36,
        child: FilledButton.icon(
          key: const Key('autoWatch'),
          onPressed: enabled ? logic.toggleAutoWatch : null,
          style: FilledButton.styleFrom(
            backgroundColor: logic.autoWatchEnabled
                ? AppActionTheme.primary
                : const Color(0xFFEAF9F8),
            foregroundColor: AppActionTheme.onPrimary,
            disabledBackgroundColor: const Color(0xFFF1F3F5),
            disabledForegroundColor: const Color(0xFF9AA0A8),
            padding: const EdgeInsets.symmetric(horizontal: 12),
            minimumSize: const Size(0, 36),
            shape: const StadiumBorder(),
            side: BorderSide(
              color: enabled
                  ? AppActionTheme.primary.withValues(alpha: 0.5)
                  : const Color(0xFFE5E7EB),
            ),
            textStyle: const TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w600,
            ),
          ),
          icon: Icon(
            logic.autoWatchEnabled
                ? Icons.stop_rounded
                : Icons.play_arrow_rounded,
            size: 18,
          ),
          label: const Text('Auto nuôi'),
        ),
      ),
    );
  }

  Widget _autoControls() => Positioned(
    left: 12,
    right: 12,
    bottom: 12,
    child: SafeArea(
      top: false,
      child: Align(
        alignment: Alignment.bottomRight,
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 280),
          child: Material(
            key: const Key('accountAutoControls'),
            color: const Color(0xFF262626),
            borderRadius: BorderRadius.circular(12),
            elevation: 6,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      logic.logoutBusy
                          ? 'Đang đăng xuất TikTok để quay về Home…'
                          : logic.waitingToLogout
                          ? 'Đăng ký thành công. Chờ 2–4 phút trước khi đăng xuất…'
                          : (logic.autoLoginBusy &&
                                    logic.loginOtpRequest != null &&
                                    logic.activeLoginOtp.isEmpty) ||
                                (logic.autoSignupBusy &&
                                    logic.signupOtpRequest != null &&
                                    logic.activeSignupOtp.isEmpty)
                          ? 'Đang chờ API lấy OTP… (tối đa ${logic.configuration.otpApi?.waitSeconds ?? 180} giây)'
                          : logic.autoLoginBusy
                          ? logic.loginStatus
                          : logic.signupStatus,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontSize: 12, color: Colors.white),
                    ),
                  ),
                  const SizedBox(width: 8),
                  OutlinedButton(
                    style: OutlinedButton.styleFrom(
                      minimumSize: const Size(48, 36),
                      padding: const EdgeInsets.symmetric(horizontal: 10),
                      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    ),
                    onPressed: logic.cancelAutoActions,
                    child: const Text('Dừng'),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    ),
  );

  @override
  Widget build(BuildContext context) {
    logic.setTikTokScreenVisible(ModalRoute.of(context)?.isCurrent ?? true);
    return PopScope(
      canPop: logic.manualViewingPlan == null || logic.manualViewingClosed,
      onPopInvokedWithResult: (didPop, _) async {
        if (didPop || logic.manualViewingClosed || logic.manualViewingClosing) {
          return;
        }
        await logic.closeManualViewing();
        if (context.mounted) Navigator.of(context).pop();
      },
      child: Theme(
        data: AppActionTheme.apply(Theme.of(context)),
        child: Scaffold(
          resizeToAvoidBottomInset: logic.useNativeWebView,
          appBar: AppBar(
            backgroundColor: Colors.white,
            iconTheme: const IconThemeData(color: Colors.black),
            titleSpacing: 16,
            title: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  logic.browserCheckOpen
                      ? 'Kiểm tra trình duyệt'
                      : logic.useNativeWebView
                      ? 'TikTok · Tương thích'
                      : 'TikTok',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontWeight: FontWeight.w700,
                    color: Colors.black,
                  ),
                ),
                if (logic.detectedIp != null)
                  Text(
                    'IP: ${logic.detectedIp}',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 11,
                      color: Colors.black54,
                      fontWeight: FontWeight.w400,
                    ),
                  ),
                if (logic.manualViewingPlan != null)
                  Text(
                    '${logic.manualViewingPlan!.mode.label}${logic.manualViewingPlan!.keyword.isEmpty ? '' : ' · ${logic.manualViewingPlan!.keyword}'} · xem thủ công',
                    key: const Key('manualViewingStatus'),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontSize: 11, color: Colors.black54),
                  ),
              ],
            ),
            actionsPadding: const EdgeInsets.only(right: 8),
            actions: [
              if (!logic.browserCheckOpen && !logic.useNativeWebView)
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 4),
                  child: _autoWatchButton(),
                ),
              IconButton(
                tooltip: 'Tải lại',
                onPressed: logic.reloadPage,
                icon: const Icon(Icons.refresh, color: Colors.black),
              ),
              if (needsAndroidDesktopIdentity &&
                  logic.manualViewingPlan == null)
                IconButton(
                  key: const Key('nativeWebView'),
                  tooltip: logic.usesEngineIdentity
                      ? 'Dùng User-Agent đã chọn (thủ công)'
                      : 'Desktop theo WebView (thủ công)',
                  icon: const Icon(Icons.web, color: Colors.black),
                  onPressed: () {
                    logic.cancelAutoActions();
                    Navigator.of(context).pushReplacement(
                      MaterialPageRoute<void>(
                        builder: (_) => TikTokPage(
                          configuration: logic.configuration,
                          proxyStore: logic.proxyStore,
                          useNativeWebView: true,
                          useInstalledEngine: !logic.usesEngineIdentity,
                        ),
                      ),
                    );
                  },
                ),
            ],
          ),
          body: Stack(
            fit: StackFit.expand,
            children: [
              _signupViewport(
                InAppWebView(
                  initialUrlRequest: logic.needsDesktopIdentity
                      ? null
                      : URLRequest(
                          url: WebUri(logic.initialUrl),
                          headers: logic.navigationHeaders,
                        ),
                  initialUserScripts: UnmodifiableListView([
                    if (!logic.useNativeWebView &&
                        needsAndroidDesktopIdentity &&
                        logic.configuration.webViewTimeZone != null)
                      webViewTimeZoneUserScript(
                        logic.configuration.webViewTimeZone!,
                      ),
                    if (!logic.usesEngineIdentity) pixelGpuInfoUserScript(),
                    disableWebRtcUserScript(
                      localIp: logic.configuration.webViewLocalIp,
                    ),
                    if (forceEnglishWebViewLocale && !logic.useNativeWebView)
                      englishWebViewLocaleUserScript(),
                    if (!logic.useNativeWebView &&
                        !logic.usesAccessibilityAccountFlow)
                      UserScript(
                        source: inlineVideoScript,
                        injectionTime:
                            UserScriptInjectionTime.AT_DOCUMENT_START,
                      ),
                    if (!logic.useNativeWebView &&
                        !logic.usesAccessibilityAccountFlow)
                      UserScript(
                        source: autoAcceptCookieScript,
                        injectionTime: UserScriptInjectionTime.AT_DOCUMENT_END,
                        forMainFrameOnly: true,
                      ),
                    if (!logic.useNativeWebView &&
                        !logic.usesAccessibilityAccountFlow)
                      UserScript(
                        source: autoSelectInterestScript,
                        injectionTime: UserScriptInjectionTime.AT_DOCUMENT_END,
                        forMainFrameOnly: true,
                      ),
                  ]),
                  initialSettings: InAppWebViewSettings(
                    userAgent: logic.usesEngineIdentity
                        ? null
                        : logic.configuration.userAgent,
                    preferredContentMode: UserPreferredContentMode.DESKTOP,
                    useWideViewPort: true,
                    loadWithOverviewMode: true,
                    initialScale: 0,
                    supportZoom: !logic.usesAccessibilityAccountFlow,
                    builtInZoomControls: !logic.usesAccessibilityAccountFlow,
                    displayZoomControls: false,
                    textZoom: 100,
                    javaScriptEnabled: true,
                    mediaPlaybackRequiresUserGesture: false,
                    allowsInlineMediaPlayback: true,
                    incognito: false,
                    cacheEnabled: true,
                  ),
                  onWebViewCreated: logic.onWebViewCreated,
                  onReceivedHttpAuthRequest: logic.onReceivedHttpAuthRequest,
                  onLoadStart: logic.onLoadStart,
                  onProgressChanged: logic.onProgressChanged,
                  onLoadStop: logic.onLoadStop,
                  onReceivedError: logic.onReceivedError,
                  onReceivedHttpError: logic.onReceivedHttpError,
                  onConsoleMessage: logic.onConsoleMessage,
                  shouldOverrideUrlLoading: logic.shouldOverrideUrlLoading,
                ),
              ),
              if (logic.loadingProgress < 100)
                Positioned(
                  top: 0,
                  left: 0,
                  right: 0,
                  child: IgnorePointer(
                    child: LinearProgressIndicator(
                      value: logic.loadingProgress / 100,
                      minHeight: 2,
                      backgroundColor: Colors.white12,
                      color: AppActionTheme.primary,
                    ),
                  ),
                ),
              if (logic.pageFailure != null)
                _ErrorView(
                  failure: logic.pageFailure!,
                  onRetry: logic.retryPage,
                ),
              if (logic.autoLoginBusy ||
                  logic.autoSignupBusy ||
                  logic.waitingToLogout ||
                  logic.logoutBusy)
                _autoControls(),
            ],
          ),
        ),
      ),
    );
  }
}

class _ErrorView extends StatelessWidget {
  const _ErrorView({required this.failure, required this.onRetry});

  final WebViewFailure failure;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return Positioned(
      left: 12,
      right: 12,
      bottom: 12,
      child: SafeArea(
        top: false,
        child: Align(
          alignment: Alignment.bottomRight,
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 340, maxHeight: 220),
            child: Material(
              key: const Key('webViewFailure'),
              color: const Color(0xFF262626),
              borderRadius: BorderRadius.circular(12),
              elevation: 6,
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(12),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      failure.title,
                      style: const TextStyle(
                        fontSize: 14,
                        color: Colors.white,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      failure.message,
                      style: const TextStyle(
                        fontSize: 12,
                        color: Colors.white70,
                      ),
                    ),
                    if (failure.code != null) ...[
                      const SizedBox(height: 6),
                      Text(
                        failure.code!,
                        style: const TextStyle(
                          fontSize: 11,
                          color: Colors.white54,
                        ),
                      ),
                    ],
                    const SizedBox(height: 8),
                    FilledButton(
                      key: const Key('retryWebViewFailure'),
                      onPressed: onRetry,
                      child: const Text('Thử lại'),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
