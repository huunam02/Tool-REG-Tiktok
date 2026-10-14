import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import '../core/app_configuration.dart';
import '../core/proxy_store.dart';
import '../core/proxy_draft.dart';
import '../core/configuration_data.dart';
import '../core/configuration_file_import.dart';
import 'app_controller.dart';

class ProxyFormController extends AppController {
  ProxyFormController({
    this.entry,
    required this.randomizeOnOpen,
    required this.selectUserAgent,
    Future<ConfigurationImportFile?> Function()? pickImportFile,
  }) : pickImportFile = pickImportFile ?? pickConfigurationImportFile,
       configurations = [ConfigurationFormFields(entry: entry)];

  final SavedProxy? entry;
  final bool randomizeOnOpen;
  final Future<String> Function() selectUserAgent;
  final Future<ConfigurationImportFile?> Function() pickImportFile;

  final form = GlobalKey<FormState>();
  List<ConfigurationFormFields> configurations;
  TextEditingController get url => configurations.first.url;
  TextEditingController get username => configurations.first.username;
  TextEditingController get password => configurations.first.password;
  TextEditingController get userAgent => configurations.first.userAgent;
  late final importData = TextEditingController();
  TextEditingController get accountEmail => configurations.first.accountEmail;
  TextEditingController get accountPassword =>
      configurations.first.accountPassword;
  TextEditingController get mailboxPassword =>
      configurations.first.mailboxPassword;
  String? importError;
  bool get hasMultipleImports => configurations.length > 1;
  AccountStatus get statusAccount => configurations.first.statusAccount;
  set statusAccount(AccountStatus value) =>
      configurations.first.statusAccount = value;
  bool get generating => configurations.any((fields) => fields.generating);
  bool get generationFailed => configurations.first.generationFailed;
  bool importing = false;
  Future<void> _userAgentQueue = Future<void>.value();

  @override
  void onInit() {
    super.onInit();
    if (randomizeOnOpen) unawaited(generateUserAgent());
  }

  Future<void> generateUserAgent() =>
      generateUserAgentFor(configurations.first);

  Future<void> generateUserAgentFor(ConfigurationFormFields fields) async {
    if (!active || fields.disposed || fields.generating) return;
    mutate(() => fields.generating = true);
    final previous = _userAgentQueue;
    final finished = Completer<void>();
    _userAgentQueue = finished.future;
    try {
      await previous;
      if (!active || fields.disposed) return;
      var generatedAgent = await selectUserAgent();
      if (!active || fields.disposed) return;
      if (generatedAgent == fields.userAgent.text) {
        generatedAgent = await selectUserAgent();
        if (!active || fields.disposed) return;
      }
      fields.userAgent.text = generatedAgent;
      mutate(() => fields.generationFailed = false);
    } catch (_) {
      if (active && !fields.disposed) {
        mutate(() => fields.generationFailed = true);
      }
    } finally {
      finished.complete();
      if (active && !fields.disposed) mutate(() => fields.generating = false);
    }
  }

  @override
  void onClose() {
    importData.dispose();
    for (final fields in configurations) {
      fields.dispose();
    }
    super.onClose();
  }

  Future<List<ProxyDraft>?> save() async {
    if (importing || generating) return null;
    final invalid = form.currentState!.validateGranularly();
    if (invalid.isNotEmpty) {
      final fieldContext = invalid.first.context;
      await WidgetsBinding.instance.endOfFrame;
      if (!active || !fieldContext.mounted) return null;
      await Scrollable.ensureVisible(
        fieldContext,
        duration: const Duration(milliseconds: 220),
        alignment: 0.15,
      );
      return null;
    }
    FocusManager.instance.primaryFocus?.unfocus();
    return [for (final fields in configurations) fields.toDraft()];
  }

  void importProxy() {
    if (!active || importing) return;
    try {
      final records = ImportedConfiguration.parseMany(importData.text);
      _applyImportedConfigurations(records);
    } on FormatException catch (error) {
      mutate(() => importError = error.message);
    }
  }

  void _applyImportedConfigurations(List<ImportedConfiguration> records) {
    final first = configurations.first;
    final oldFields = configurations.skip(1).toList();
    mutate(() {
      first.applyImport(records.first);
      configurations = [
        first,
        for (final data in records.skip(1))
          ConfigurationFormFields()..applyImport(data),
      ];
      importError = null;
      importData.clear();
    });
    for (final fields in oldFields) {
      fields.dispose();
    }
    for (final fields in configurations.skip(1)) {
      unawaited(generateUserAgentFor(fields));
    }
    FocusManager.instance.primaryFocus?.unfocus();
    notify('Đã import thành công ${records.length} cấu hình.');
  }

  Future<void> importFromFile() async {
    if (!active || importing) return;
    mutate(() => importing = true);
    try {
      final file = await pickImportFile();
      if (!active || file == null) return;
      final records = await compute(decodeConfigurationImportFile, file);
      if (!active) return;
      _applyImportedConfigurations(records);
    } on FormatException catch (error) {
      mutate(() => importError = error.message);
    } catch (_) {
      mutate(() => importError = 'Không thể mở hoặc đọc file. Hãy thử lại.');
    } finally {
      mutate(() => importing = false);
    }
  }

  Future<void> pasteImportData() async {
    if (!active || importing) return;
    mutate(() => importing = true);
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
      _applyImportedConfigurations(ImportedConfiguration.parseMany(text));
    } on FormatException catch (error) {
      mutate(() => importError = error.message);
    } catch (_) {
      if (active) notify('Không thể đọc dữ liệu từ clipboard.');
    } finally {
      mutate(() => importing = false);
    }
  }

  void clearImportError(String _) => mutate(() => importError = null);

  void clearImportedConfigurations() {
    if (importing) return;
    final oldFields = configurations.skip(1).toList();
    mutate(() {
      configurations = [configurations.first];
      url.clear();
      username.clear();
      password.clear();
      accountEmail.clear();
      accountPassword.clear();
      mailboxPassword.clear();
      statusAccount = AccountStatus.unregistered;
    });
    for (final fields in oldFields) {
      fields.dispose();
    }
  }
}

class ConfigurationFormFields {
  ConfigurationFormFields({SavedProxy? entry})
    : url = TextEditingController(
        text: entry?.proxy == null ? '' : proxyAddress(entry!.proxy!),
      ),
      username = TextEditingController(text: entry?.proxy?.username),
      password = TextEditingController(text: entry?.proxy?.password),
      userAgent = TextEditingController(text: entry?.userAgent),
      accountEmail = TextEditingController(text: entry?.account?.email),
      accountPassword = TextEditingController(text: entry?.account?.password),
      mailboxPassword = TextEditingController(
        text: entry?.account?.mailboxPassword,
      ),
      statusAccount = entry?.statusAccount ?? AccountStatus.unregistered;

  final TextEditingController url;
  final TextEditingController username;
  final TextEditingController password;
  final TextEditingController userAgent;
  final TextEditingController accountEmail;
  final TextEditingController accountPassword;
  final TextEditingController mailboxPassword;
  AccountStatus statusAccount;
  bool generating = false;
  bool generationFailed = false;
  bool disposed = false;

  void applyImport(ImportedConfiguration data) {
    url.text = proxyAddress(data.proxy);
    username.text = data.proxy.username;
    password.text = data.proxy.password;
    accountEmail.text = data.account.email;
    accountPassword.text = data.account.password;
    mailboxPassword.text = data.account.mailboxPassword;
    statusAccount = data.statusAccount;
  }

  ProxyDraft toDraft() => ProxyDraft(
    accountEmail.text.trim(),
    WebViewProxy.parse(
      url.text,
      username: username.text,
      password: password.text,
    ),
    userAgent.text.trim(),
    account: AccountCredentials(
      email: accountEmail.text.trim(),
      password: accountPassword.text,
      mailboxPassword: mailboxPassword.text,
    ),
    statusAccount: statusAccount,
  );

  void dispose() {
    disposed = true;
    for (final field in [
      url,
      username,
      password,
      userAgent,
      accountEmail,
      accountPassword,
      mailboxPassword,
    ]) {
      field.dispose();
    }
  }
}
