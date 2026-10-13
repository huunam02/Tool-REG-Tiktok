import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../core/app_configuration.dart';
import '../core/proxy_store.dart';
import '../core/proxy_draft.dart';
import 'app_controller.dart';

class ProxyFormController extends AppController {
  ProxyFormController(
      {this.entry,
      required this.randomizeOnOpen,
      required this.selectUserAgent});

  final SavedProxy? entry;
  final bool randomizeOnOpen;
  final Future<String> Function() selectUserAgent;

  final form = GlobalKey<FormState>();
  late final name = TextEditingController(text: entry?.name);
  late final url = TextEditingController(
      text: entry == null ? '' : proxyAddress(entry!.proxy));
  late final username = TextEditingController(text: entry?.proxy.username);
  late final password = TextEditingController(text: entry?.proxy.password);
  late final userAgent = TextEditingController(text: entry?.userAgent);
  late final importData = TextEditingController();
  String? importError;
  bool generating = false;
  bool generationFailed = false;

  @override
  void onInit() {
    super.onInit();
    if (randomizeOnOpen) unawaited(generateUserAgent());
  }

  Future<void> generateUserAgent() async {
    if (generating) return;
    mutate(() => generating = true);
    try {
      var generatedAgent = await selectUserAgent();
      if (!active) return;
      if (generatedAgent == userAgent.text) {
        generatedAgent = await selectUserAgent();
        if (!active) return;
      }
      userAgent.text = generatedAgent;
      mutate(() => generationFailed = false);
    } catch (_) {
      if (active) mutate(() => generationFailed = true);
    } finally {
      if (active) mutate(() => generating = false);
    }
  }

  @override
  void onClose() {
    for (final controller in [
      name,
      url,
      username,
      password,
      userAgent,
      importData
    ]) {
      controller.dispose();
    }
    super.onClose();
  }

  Future<ProxyDraft?> save() async {
    final invalid = form.currentState!.validateGranularly();
    if (invalid.isNotEmpty) {
      final fieldContext = invalid.first.context;
      await WidgetsBinding.instance.endOfFrame;
      if (!active || !fieldContext.mounted) return null;
      await Scrollable.ensureVisible(fieldContext,
          duration: const Duration(milliseconds: 220), alignment: 0.15);
      return null;
    }
    final proxy = WebViewProxy.parse(url.text,
        username: username.text, password: password.text)!;
    FocusManager.instance.primaryFocus?.unfocus();
    return ProxyDraft(name.text.trim(), proxy, userAgent.text.trim());
  }

  void importProxy() {
    if (!active) return;
    try {
      final proxy = WebViewProxy.parseImport(importData.text);
      mutate(() {
        url.text = proxyAddress(proxy);
        username.text = proxy.username;
        password.text = proxy.password;
        importError = null;
        importData.clear();
      });
      FocusManager.instance.primaryFocus?.unfocus();
      notify('Đã import thông tin kết nối. Nhập tên proxy rồi lưu.');
    } on FormatException catch (error) {
      mutate(() => importError = error.message);
    }
  }

  Future<void> pasteImportData() async {
    if (!active) return;
    try {
      final clipboard = await Clipboard.getData(Clipboard.kTextPlain);
      if (!active) return;
      final text = clipboard?.text;
      if (text == null || text.isEmpty) {
        notify('Clipboard không có dữ liệu để dán.');
        return;
      }
      mutate(() {
        importData.value = TextEditingValue(
          text: text,
          selection: TextSelection.collapsed(offset: text.length),
        );
        importError = null;
      });
      importProxy();
    } catch (_) {
      if (active) notify('Không thể đọc dữ liệu từ clipboard.');
    }
  }

  void clearImportError(String _) => mutate(() => importError = null);
}
