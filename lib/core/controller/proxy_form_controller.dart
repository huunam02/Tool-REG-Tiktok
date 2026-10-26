import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import '../app_configuration.dart';
import '../account_password.dart';
import '../proxy_store.dart';
import '../proxy_draft.dart';
import '../configuration_data.dart';
import '../configuration_file_import.dart';
import '../gpu_profile.dart';
import '../nurture_data.dart';
import '../proxy_time_zone.dart';
import '../proxy_time_zone_detector.dart';
import '../webview_user_agent.dart';
import '../chrome_user_agent.dart';
import 'app_controller.dart';

class ProxyFormController extends AppController {
  ProxyFormController({
    this.entry,
    required this.randomizeOnOpen,
    required this.selectUserAgent,
    Future<ConfigurationImportFile?> Function()? pickImportFile,
    Future<String> Function(WebViewProxy proxy, String userAgent)?
    detectTimeZone,
  }) : _detectTimeZoneOverride = detectTimeZone,
       pickImportFile = pickImportFile ?? pickConfigurationImportFile,
       configurations = [ConfigurationFormFields(entry: entry)];

  final SavedProxy? entry;
  final bool randomizeOnOpen;
  final Future<String> Function() selectUserAgent;
  final Future<ConfigurationImportFile?> Function() pickImportFile;
  final Future<String> Function(WebViewProxy, String)? _detectTimeZoneOverride;
  final _timeZoneDetector = ProxyTimeZoneDetector();
  bool get canDetectTimeZone =>
      _detectTimeZoneOverride != null || needsAndroidDesktopIdentity;
  bool get detectingTimeZones =>
      configurations.any((fields) => fields.detectingTimeZone);

  final form = GlobalKey<FormState>();
  List<ConfigurationFormFields> configurations;
  TextEditingController get url => configurations.first.url;
  TextEditingController get username => configurations.first.username;
  TextEditingController get password => configurations.first.password;
  TextEditingController get userAgent => configurations.first.userAgent;
  TextEditingController get timeZoneId => configurations.first.timeZoneId;
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
      // The store hands out the Chrome identity and normalizes on save.
      final generatedAgent = await selectUserAgent();
      if (!active || fields.disposed) return;
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
    _timeZoneDetector.cancel();
    importData.dispose();
    for (final fields in configurations) {
      fields.dispose();
    }
    super.onClose();
  }

  Future<List<ProxyDraft>?> save() async {
    if (importing || generating || detectingTimeZones) return null;
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
    if (!active || importing || detectingTimeZones) return;
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
          ConfigurationFormFields()
            ..applyImport(data)
            ..nurtureAfterSignup = first.nurtureAfterSignup,
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
    if (canDetectTimeZone) {
      for (final fields in configurations) {
        unawaited(detectTimeZoneFor(fields));
      }
    }
    FocusManager.instance.primaryFocus?.unfocus();
    notify('Đã import thành công ${records.length} cấu hình.');
  }

  Future<void> importFromFile() async {
    if (!active || importing || detectingTimeZones) return;
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
    if (!active || importing || detectingTimeZones) return;
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

  void setNurtureAfterSignup(ConfigurationFormFields fields, bool value) =>
      mutate(() => fields.nurtureAfterSignup = value);

  Future<void> detectTimeZoneFor(ConfigurationFormFields fields) async {
    if (!active ||
        fields.disposed ||
        fields.detectingTimeZone ||
        !canDetectTimeZone) {
      return;
    }
    final revision = fields.revision;
    mutate(() {
      fields.detectingTimeZone = true;
      fields.timeZoneError = null;
    });
    try {
      final proxy = fields.parseProxy();
      if (proxy == null) {
        throw const FormatException('Nhập proxy trước khi tra múi giờ.');
      }
      final zone = normalizeProxyTimeZone(
        await (_detectTimeZoneOverride ?? _timeZoneDetector.detect)(
          proxy,
          fields.userAgent.text,
        ),
      );
      if (!active || fields.disposed || fields.revision != revision) return;
      if (zone.isEmpty) {
        throw const FormatException('API chưa xác định được múi giờ.');
      }
      mutate(() => fields.timeZoneId.text = zone);
    } catch (error) {
      if (active && !fields.disposed && fields.revision == revision) {
        mutate(
          () => fields.timeZoneError = error is FormatException
              ? error.message
              : 'Không thể tra múi giờ qua proxy. Hãy thử lại.',
        );
      }
    } finally {
      if (active && !fields.disposed) {
        mutate(() => fields.detectingTimeZone = false);
      }
    }
  }

  void clearImportedConfigurations() {
    if (importing || detectingTimeZones) return;
    final oldFields = configurations.skip(1).toList();
    mutate(() {
      configurations = [configurations.first];
      url.clear();
      username.clear();
      password.clear();
      accountEmail.clear();
      accountPassword.text = generateAccountPassword();
      mailboxPassword.clear();
      timeZoneId.clear();
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
      userAgent = TextEditingController(
        text: entry == null
            ? ''
            : normalizeDesktopUserAgentForPlatform(entry.userAgent),
      ),
      timeZoneId = TextEditingController(text: entry?.timeZoneId),
      accountEmail = TextEditingController(text: entry?.account?.email),
      accountPassword = TextEditingController(
        text: entry == null
            ? generateAccountPassword()
            : entry.account?.password,
      ),
      mailboxPassword = TextEditingController(
        text: entry?.account?.mailboxPassword,
      ),
      statusAccount = entry?.statusAccount ?? AccountStatus.unregistered,
      gpuProfileId = GpuProfile.isKnown(entry?.gpuProfileId ?? '')
          ? entry!.gpuProfileId
          : GpuProfile.random().id,
      nurtureAfterSignup = entry?.nurtureAfterSignup ?? false {
    showNurtureSettings(entry?.nurtureSettings ?? NurtureSettings.defaults);
    for (final field in [url, username, password]) {
      field.addListener(() {
        revision++;
        timeZoneId.clear();
        timeZoneError = null;
      });
    }
    timeZoneId.addListener(() => revision++);
    var dataMailEmail = AccountCredentials.emailFromDataMail(
      mailboxPassword.text,
    );
    mailboxPassword.addListener(() {
      final email = AccountCredentials.emailFromDataMail(mailboxPassword.text);
      if (email == dataMailEmail) return;
      // Follow Data Mail unless the email was typed by hand.
      final current = accountEmail.text.trim();
      if (current.isEmpty || current == dataMailEmail) {
        accountEmail.text = email;
      }
      dataMailEmail = email;
    });
  }

  final TextEditingController url;
  String _proxyProtocol = 'http';
  String get proxyProtocol {
    final scheme = Uri.tryParse(url.text.trim())?.scheme;
    return const {'http', 'https', 'socks5', 'socks5h'}.contains(scheme)
        ? scheme!
        : _proxyProtocol;
  }

  void setProxyProtocol(String protocol) {
    if (!const {'http', 'https', 'socks5', 'socks5h'}.contains(protocol)) {
      return;
    }
    _proxyProtocol = protocol;
    final address = url.text.trim().replaceFirst(
      RegExp(r'^[A-Za-z0-9]+://'),
      '',
    );
    if (address.isNotEmpty) {
      url.text = '$protocol://$address';
    } else {
      revision++;
      timeZoneId.clear();
      timeZoneError = null;
    }
  }

  WebViewProxy? parseProxy([String? value]) {
    final address = (value ?? url.text).trim();
    return WebViewProxy.parse(
      address.isEmpty || address.contains('://')
          ? address
          : '$proxyProtocol://$address',
      username: username.text,
      password: password.text,
    );
  }

  final TextEditingController username;
  final TextEditingController password;
  final TextEditingController userAgent;
  final TextEditingController timeZoneId;
  int revision = 0;
  bool detectingTimeZone = false;
  String? timeZoneError;
  final TextEditingController accountEmail;
  final TextEditingController accountPassword;
  final TextEditingController mailboxPassword;
  AccountStatus statusAccount;
  bool nurtureAfterSignup;

  /// The phone GPU pages see over WebGL; shown read-only, only Đổi or a
  /// backup changes it.
  String gpuProfileId;
  GpuProfile get gpuProfile => GpuProfile.byId(gpuProfileId);
  void changeGpuProfile() => gpuProfileId = GpuProfile.other(gpuProfileId).id;

  /// Cấu hình nuôi of this configuration.
  final nurtureLikePercent = TextEditingController();
  final nurtureCommentPercent = TextEditingController();
  final nurtureLongWatchPercent = TextEditingController();
  final nurtureMinMinutes = TextEditingController();
  final nurtureMaxMinutes = TextEditingController();
  bool generating = false;
  bool generationFailed = false;
  bool disposed = false;

  void applyImport(ImportedConfiguration data) {
    timeZoneId.clear();
    timeZoneError = null;
    final proxy = data.proxy;
    url.text = proxy == null ? '' : proxyAddress(proxy);
    username.text = proxy?.username ?? '';
    password.text = proxy?.password ?? '';
    accountPassword.text = data.account.password.trim().isEmpty
        ? generateAccountPassword()
        : data.account.password;
    mailboxPassword.text = data.account.dataMail;
    accountEmail.text = data.account.email;
    statusAccount = data.statusAccount;
    final settings = data.nurtureSettings;
    if (settings != null) showNurtureSettings(settings);
    final gpu = data.gpuProfileId;
    if (gpu != null) gpuProfileId = gpu;
  }

  void showNurtureSettings(NurtureSettings settings) {
    nurtureLikePercent.text = '${settings.likePercent}';
    nurtureCommentPercent.text = '${settings.commentPercent}';
    nurtureLongWatchPercent.text = '${settings.longWatchPercent}';
    nurtureMinMinutes.text = '${settings.minMinutes}';
    nurtureMaxMinutes.text = '${settings.maxMinutes}';
  }

  /// The form validators reject non-numbers before a draft is built.
  NurtureSettings get nurtureSettings {
    int read(TextEditingController input) => int.parse(input.text.trim());
    return NurtureSettings(
      likePercent: read(nurtureLikePercent),
      commentPercent: read(nurtureCommentPercent),
      longWatchPercent: read(nurtureLongWatchPercent),
      minMinutes: read(nurtureMinMinutes),
      maxMinutes: read(nurtureMaxMinutes),
    );
  }

  ProxyDraft toDraft() => ProxyDraft(
    accountEmail.text.trim(),
    parseProxy(),
    normalizeDesktopUserAgentForPlatform(userAgent.text.trim()),
    account: AccountCredentials(
      email: accountEmail.text.trim(),
      password: accountPassword.text,
      dataMail: mailboxPassword.text.trim(),
    ),
    statusAccount: statusAccount,
    timeZoneId: normalizeProxyTimeZone(timeZoneId.text),
    nurtureAfterSignup: nurtureAfterSignup,
    nurtureSettings: nurtureSettings,
    gpuProfileId: gpuProfileId,
  );

  void dispose() {
    disposed = true;
    for (final field in [
      url,
      username,
      password,
      userAgent,
      timeZoneId,
      accountEmail,
      accountPassword,
      mailboxPassword,
      nurtureLikePercent,
      nurtureCommentPercent,
      nurtureLongWatchPercent,
      nurtureMinMinutes,
      nurtureMaxMinutes,
    ]) {
      field.dispose();
    }
  }
}
