import 'dart:async';

import 'package:flutter_inappwebview/flutter_inappwebview.dart';

class TestSessionPlatform extends InAppWebViewPlatform {
  final calls = <String>[];
  Completer<bool>? cookieGate;
  Completer<void>? cacheGate;

  @override
  PlatformCookieManager createPlatformCookieManager(
    PlatformCookieManagerCreationParams params,
  ) => _Cookies(params, this);

  @override
  PlatformWebStorageManager createPlatformWebStorageManager(
    PlatformWebStorageManagerCreationParams params,
  ) => _Storage(params, this);

  @override
  PlatformInAppWebViewController createPlatformInAppWebViewControllerStatic() =>
      _Controller(
        const PlatformInAppWebViewControllerCreationParams(id: null),
        this,
      );
}

class _Cookies extends PlatformCookieManager {
  _Cookies(super.params, this.platform) : super.implementation();
  final TestSessionPlatform platform;

  @override
  Future<bool> deleteAllCookies() async {
    platform.calls.add('cookies');
    return platform.cookieGate == null
        ? true
        : await platform.cookieGate!.future;
  }
}

class _Storage extends PlatformWebStorageManager {
  _Storage(super.params, this.platform) : super.implementation();
  final TestSessionPlatform platform;

  @override
  Future<void> deleteAllData() async {
    platform.calls.add('android-storage');
  }

  @override
  Future<void> removeDataModifiedSince({
    required Set<WebsiteDataType> dataTypes,
    required DateTime date,
  }) async {
    platform.calls.add('apple-storage');
  }
}

class _Controller extends PlatformInAppWebViewController {
  _Controller(super.params, this.platform) : super.implementation();
  final TestSessionPlatform platform;

  @override
  Future<void> clearAllCache({bool includeDiskFiles = true}) async {
    platform.calls.add('cache');
    if (platform.cacheGate != null) await platform.cacheGate!.future;
  }
}
