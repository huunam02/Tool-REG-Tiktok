import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';

import 'gpu_profile.dart';

typedef GeckoJavaScriptHandler = FutureOr<dynamic> Function(List<dynamic> args);

class GeckoController {
  GeckoController._(this.viewId)
    : _channel = MethodChannel('test_tiktok/gecko_view_$viewId') {
    _channel.setMethodCallHandler(_onNativeCall);
  }

  @visibleForTesting
  factory GeckoController.test(int viewId) => GeckoController._(viewId);

  final int viewId;
  final MethodChannel _channel;
  final Map<String, GeckoJavaScriptHandler> _handlers = {};
  FutureOr<void> Function(Map<dynamic, dynamic> event)? onEvent;

  Future<dynamic> evaluateJavascript({
    required String source,
    bool pageWorld = false,
    Duration timeout = const Duration(seconds: 30),
  }) => _channel
      .invokeMethod<dynamic>('evaluateJavascript', {
        'source': source,
        'pageWorld': pageWorld,
        'timeoutMs': timeout.inMilliseconds,
      })
      .timeout(
        timeout + const Duration(seconds: 1),
        onTimeout: () => throw StateError(
          'Trang không phản hồi trong thời gian chờ; hãy tải lại TikTok.',
        ),
      );

  Future<void> start() => _channel.invokeMethod<void>('start');

  Future<void> loadUrl({required GeckoUrlRequest urlRequest}) => _channel
      .invokeMethod<void>('loadUrl', {'url': urlRequest.url.toString()});

  Future<void> reload() => _channel.invokeMethod<void>('reload');
  Future<void> stop() => _channel.invokeMethod<void>('stop');
  Future<void> goBack() => _channel.invokeMethod<void>('goBack');
  Future<void> goForward() => _channel.invokeMethod<void>('goForward');

  Future<Uri?> getUrl() async {
    final value = await _channel.invokeMethod<String>('getUrl');
    return value == null ? null : Uri.tryParse(value);
  }

  void addJavaScriptHandler({
    required String handlerName,
    required GeckoJavaScriptHandler callback,
  }) => _handlers[handlerName] = callback;

  Future<dynamic> _onNativeCall(MethodCall call) async {
    final data = (call.arguments as Map?) ?? const {};
    if (call.method == 'event') return onEvent?.call(data);
    if (call.method == 'javascriptHandler') {
      final name = data['name'] as String?;
      final callback = name == null ? null : _handlers[name];
      if (callback == null) {
        throw MissingPluginException('No JavaScript handler: $name');
      }
      return callback(List<dynamic>.from(data['args'] as List? ?? const []));
    }
    throw MissingPluginException('Unknown GeckoView callback: ${call.method}');
  }

  void dispose() {
    _handlers.clear();
    _channel.setMethodCallHandler(null);
  }
}

class GeckoUrlRequest {
  const GeckoUrlRequest({required this.url, this.headers = const {}});
  final Uri url;
  final Map<String, String>? headers;
}

class GeckoWebResourceRequest {
  const GeckoWebResourceRequest({this.isForMainFrame = true});
  final bool? isForMainFrame;
}

enum GeckoWebResourceErrorType {
  cancelled,
  timeout,
  hostLookup,
  cannotConnectToHost,
  networkConnectionLost,
  failedSslHandshake,
  secureConnectionFailed,
  proxyAuthentication,
  other,
}

class GeckoWebResourceError {
  const GeckoWebResourceError(
    this.description, {
    this.type = GeckoWebResourceErrorType.other,
  });
  final String description;
  final GeckoWebResourceErrorType type;
}

class GeckoBrowserView extends StatefulWidget {
  const GeckoBrowserView({
    super.key,
    required this.initialUrl,
    required this.contextId,
    required this.userAgent,
    required this.gpu,
    this.initialScripts = const [],
    required this.onCreated,
    required this.onLoadStart,
    required this.onProgressChanged,
    required this.onLoadStop,
    required this.onReceivedError,
  });

  final String initialUrl;
  final String contextId;
  final String userAgent;

  /// Set as Gecko's WebGL overrides, so documents, frames and workers all
  /// report it from the first script on.
  final GpuProfile gpu;
  final List<String> initialScripts;
  final FutureOr<void> Function(GeckoController controller) onCreated;
  final void Function(GeckoController controller, Uri? url) onLoadStart;
  final void Function(GeckoController controller, int progress)
  onProgressChanged;
  final FutureOr<void> Function(GeckoController controller, Uri? url)
  onLoadStop;
  final void Function(
    GeckoController controller,
    GeckoWebResourceRequest request,
    GeckoWebResourceError error,
  )
  onReceivedError;

  @override
  State<GeckoBrowserView> createState() => _GeckoBrowserViewState();
}

class _GeckoBrowserViewState extends State<GeckoBrowserView> {
  GeckoController? _controller;

  @override
  Widget build(BuildContext context) {
    if (defaultTargetPlatform != TargetPlatform.android) {
      return const Center(child: Text('Ứng dụng chỉ hỗ trợ Android.'));
    }
    // GeckoView renders into a SurfaceView, which needs Hybrid Composition.
    const viewType = 'test_tiktok/gecko_view';
    return PlatformViewLink(
      viewType: viewType,
      surfaceFactory: (context, controller) => AndroidViewSurface(
        controller: controller as AndroidViewController,
        gestureRecognizers: const <Factory<OneSequenceGestureRecognizer>>{},
        hitTestBehavior: PlatformViewHitTestBehavior.opaque,
      ),
      onCreatePlatformView: (params) {
        final controller = PlatformViewsService.initExpensiveAndroidView(
          id: params.id,
          viewType: viewType,
          layoutDirection: TextDirection.ltr,
          creationParams: {
            'initialUrl': widget.initialUrl,
            'contextId': widget.contextId,
            'userAgent': widget.userAgent,
            'webGlVendor': widget.gpu.webGlVendor,
            'webGlRenderer': widget.gpu.webGlRenderer,
            'initialScripts': widget.initialScripts,
          },
          creationParamsCodec: const StandardMessageCodec(),
          onFocus: () => params.onFocusChanged(true),
        );
        controller
          ..addOnPlatformViewCreatedListener(params.onPlatformViewCreated)
          ..addOnPlatformViewCreatedListener(_onPlatformViewCreated)
          ..create();
        return controller;
      },
    );
  }

  void _onPlatformViewCreated(int id) {
    final controller = GeckoController._(id);
    _controller = controller;
    controller.onEvent = (event) {
      if (!mounted) return;
      final url = Uri.tryParse(event['url']?.toString() ?? '');
      switch (event['type']) {
        case 'loadStart':
          widget.onLoadStart(controller, url);
        case 'progress':
          widget.onProgressChanged(
            controller,
            (event['progress'] as num?)?.toInt() ?? 0,
          );
        case 'loadStop':
          // false also means a newer navigation (a redirect, a script
          // setting location) replaced this load, like WebView's
          // ERR_ABORTED; real failures arrive as loadError.
          if (event['success'] != false) {
            unawaited(Future.sync(() => widget.onLoadStop(controller, url)));
          }
        case 'loadError':
          final type = GeckoWebResourceErrorType.values.firstWhere(
            (value) => value.name == event['errorType'],
            orElse: () => GeckoWebResourceErrorType.other,
          );
          widget.onReceivedError(
            controller,
            const GeckoWebResourceRequest(),
            GeckoWebResourceError(
              'Gecko không tải được trang (mã ${event['code']}).',
              type: type,
            ),
          );
      }
    };
    unawaited(
      Future.sync(
        () => widget.onCreated(controller),
      ).whenComplete(controller.start),
    );
  }

  @override
  void dispose() {
    _controller?.dispose();
    super.dispose();
  }
}

class ProfileVpn {
  static const _channel = MethodChannel('test_tiktok/profile_vpn');

  static Future<void> start({
    required String profileId,
    required Uri proxy,
    String username = '',
    String password = '',
    String label = '',
  }) async {
    final uri = proxy.replace(
      userInfo: username.isEmpty
          ? ''
          : '${Uri.encodeComponent(username)}:${Uri.encodeComponent(password)}',
    );
    await _invoke('start', {
      'profileId': profileId,
      'proxy': uri.toString(),
      'label': label,
    });
  }

  static Future<void> stop() => _invoke('stop');

  /// A successful IP response is insufficient if the tunnel disappeared or
  /// another profile replaced it before the browser was opened.
  static Future<void> requireRunning(String profileId) async {
    final status = await _channel
        .invokeMapMethod<String, dynamic>('status')
        .timeout(const Duration(seconds: 5));
    if (status?['running'] != true || status?['profileId'] != profileId) {
      throw const FormatException(
        'Proxy chưa sẵn sàng hoặc đã bị ngắt. Đã chặn mở WebView; hãy thử lại.',
      );
    }
  }

  /// Native replies once the tunnel carries this profile's traffic (or has
  /// stopped); the timeout leaves room for the VPN permission dialog.
  static Future<void> _invoke(String method, [Object? arguments]) => _channel
      .invokeMethod<void>(method, arguments)
      .timeout(
        const Duration(seconds: 60),
        onTimeout: () => throw PlatformException(
          code: 'vpn_failed',
          message: 'Proxy không phản hồi. Hãy thử lại.',
        ),
      );
}
