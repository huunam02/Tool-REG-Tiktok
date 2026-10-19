import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/proxy_store.dart';
import '../../core/webview_user_agent.dart';
import '../../core/app_configuration.dart';
import '../../core/account_password.dart';
import '../../core/otp_api.dart';
import '../../core/configuration_data.dart';
import '../../core/configuration_file_import.dart';
import '../../core/nurture_data.dart';
import '../../core/proxy_time_zone.dart';
import '../../controller/proxy_form_controller.dart';
import 'controller_scope.dart';
import 'proxy_widgets.dart';

export '../../core/proxy_draft.dart';

enum _ImportSource { file, clipboard }

class ProxyForm extends StatelessWidget {
  const ProxyForm({
    super.key,
    this.entry,
    required this.title,
    required this.submitLabel,
    required this.randomizeOnOpen,
    required this.generateUserAgent,
    this.pickImportFile,
    this.detectTimeZone,
  });

  final SavedProxy? entry;
  final String title;
  final String submitLabel;
  final bool randomizeOnOpen;
  final Future<String> Function() generateUserAgent;
  final Future<ConfigurationImportFile?> Function()? pickImportFile;
  final Future<String> Function(WebViewProxy proxy, String userAgent)?
  detectTimeZone;

  @override
  Widget build(BuildContext context) => ControllerScope<ProxyFormController>(
    controller: ProxyFormController(
      entry: entry,
      randomizeOnOpen: randomizeOnOpen,
      selectUserAgent: generateUserAgent,
      pickImportFile: pickImportFile,
      detectTimeZone: detectTimeZone,
    ),
    builder: (logic) => _ProxyFormView(
      logic: logic,
      title: title,
      submitLabel: submitLabel,
      randomizeOnOpen: randomizeOnOpen,
    ),
  );
}

class _ProxyFormView extends StatelessWidget {
  const _ProxyFormView({
    required this.logic,
    required this.title,
    required this.submitLabel,
    required this.randomizeOnOpen,
  });
  final ProxyFormController logic;
  final String title;
  final String submitLabel;
  final bool randomizeOnOpen;

  static const _fieldLabelStyle = TextStyle(
    fontSize: 13,
    height: 1.4,
    fontWeight: FontWeight.w600,
  );

  Future<void> _save(BuildContext context) async {
    final drafts = await logic.save();
    if (drafts != null && context.mounted) {
      Navigator.pop(context, logic.entry == null ? drafts : drafts.single);
    }
  }

  Future<void> _showImportOptions(BuildContext context) async {
    FocusManager.instance.primaryFocus?.unfocus();
    final source = await showModalBottomSheet<_ImportSource>(
      context: context,
      backgroundColor: ProxyColors.surface,
      showDragHandle: true,
      useSafeArea: true,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (sheetContext) => Theme(
        data: ProxyColors.theme(sheetContext),
        child: SafeArea(
          top: false,
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 20),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const Text(
                  'Import dữ liệu',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
                ),
                const SizedBox(height: 16),
                ListTile(
                  key: const Key('importFromFile'),
                  leading: const Icon(
                    Icons.folder_open_rounded,
                    color: ProxyColors.cyan,
                  ),
                  title: const Text('Từ file'),
                  subtitle: const Text('Excel (.xlsx, .xls) hoặc TXT'),
                  trailing: const Icon(Icons.chevron_right_rounded),
                  tileColor: ProxyColors.input,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14),
                  ),
                  onTap: () => Navigator.pop(sheetContext, _ImportSource.file),
                ),
                const SizedBox(height: 10),
                ListTile(
                  key: const Key('pasteProxyData'),
                  leading: const Icon(
                    Icons.content_paste_rounded,
                    color: ProxyColors.cyan,
                  ),
                  title: const Text('Dán từ clipboard'),
                  subtitle: const Text(
                    'Dán nội dung cấu hình, mỗi dòng một cấu hình',
                  ),
                  trailing: const Icon(Icons.chevron_right_rounded),
                  tileColor: ProxyColors.input,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14),
                  ),
                  onTap: () =>
                      Navigator.pop(sheetContext, _ImportSource.clipboard),
                ),
              ],
            ),
          ),
        ),
      ),
    );
    if (!context.mounted) return;
    switch (source) {
      case _ImportSource.file:
        await logic.importFromFile();
      case _ImportSource.clipboard:
        await logic.pasteImportData();
      case null:
        break;
    }
  }

  Widget _fieldLabel(String label, {Widget? action}) {
    final text = Text(label, style: _fieldLabelStyle);
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: action == null
          ? text
          : Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Expanded(child: text),
                const SizedBox(width: 8),
                Flexible(child: action),
              ],
            ),
    );
  }

  Widget _section(
    String title,
    String helper,
    IconData icon,
    List<Widget> children,
  ) => ProxyPanel(
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              padding: const EdgeInsets.all(9),
              decoration: BoxDecoration(
                color: ProxyColors.cyan.withValues(alpha: 0.09),
                borderRadius: BorderRadius.circular(11),
              ),
              child: Icon(icon, size: 19, color: ProxyColors.cyan),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: const TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    helper,
                    style: const TextStyle(
                      fontSize: 12,
                      height: 1.5,
                      color: ProxyColors.muted,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
        const SizedBox(height: 20),
        ...children,
      ],
    ),
  );

  /// Cấu hình nuôi of one configuration, prefilled with the defaults.
  List<Widget> _nurtureSettingsFields(
    ConfigurationFormFields fields,
    int index,
  ) {
    const d = NurtureSettings.defaults;
    const maxMinutes = NurtureSettings.maxSessionMinutes;
    String? number(String? value, int min, int max, String unit) {
      final parsed = int.tryParse(value?.trim() ?? '');
      if (parsed == null || parsed < min || parsed > max) {
        return 'Từ $min đến $max$unit.';
      }
      return null;
    }

    Widget field(
      String name,
      TextEditingController controller,
      String label,
      String unit,
      int fallback,
      String? Function(String?) validator,
    ) => TextFormField(
      key: _configurationKey(name, index),
      controller: controller,
      keyboardType: TextInputType.number,
      textInputAction: TextInputAction.next,
      inputFormatters: [
        FilteringTextInputFormatter.digitsOnly,
        LengthLimitingTextInputFormatter(3),
      ],
      decoration: InputDecoration(
        labelText: label,
        suffixText: unit.trim(),
        helperText: 'Mặc định: $fallback$unit',
        errorMaxLines: 2,
      ),
      validator: validator,
    );

    String? rate(String? value) => number(value, 0, 100, '%');
    Widget pair(Widget first, Widget second) => Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(child: first),
        const SizedBox(width: 12),
        Expanded(child: second),
      ],
    );

    return [
      _fieldLabel(
        'Cấu hình nuôi',
        action: TextButton(
          key: _configurationKey('resetNurtureSettings', index),
          onPressed: () => logic.mutate(() => fields.showNurtureSettings(d)),
          child: const Text('Mặc định'),
        ),
      ),
      pair(
        field(
          'nurtureLikePercent',
          fields.nurtureLikePercent,
          'Thả tim',
          '%',
          d.likePercent,
          rate,
        ),
        field(
          'nurtureCommentPercent',
          fields.nurtureCommentPercent,
          'Bình luận',
          '%',
          d.commentPercent,
          rate,
        ),
      ),
      const SizedBox(height: 12),
      field(
        'nurtureLongWatchPercent',
        fields.nurtureLongWatchPercent,
        'Tỷ lệ xem lâu (không vuốt ngay)',
        '%',
        d.longWatchPercent,
        rate,
      ),
      const SizedBox(height: 12),
      pair(
        field(
          'nurtureMinMinutes',
          fields.nurtureMinMinutes,
          'Nuôi tối thiểu',
          ' phút',
          d.minMinutes,
          (value) => number(value, 1, maxMinutes, ' phút'),
        ),
        field(
          'nurtureMaxMinutes',
          fields.nurtureMaxMinutes,
          'Nuôi tối đa',
          ' phút',
          d.maxMinutes,
          (value) =>
              number(value, 1, maxMinutes, ' phút') ??
              ((int.tryParse(fields.nurtureMinMinutes.text.trim()) ?? 0) >
                      int.parse(value!.trim())
                  ? 'Phải ≥ thời gian tối thiểu.'
                  : null),
        ),
      ),
      const SizedBox(height: 6),
      const Text(
        'Video được thả tim hoặc bình luận luôn xem hết; video còn lại xem '
        'lâu theo tỷ lệ trên, nếu không thì vuốt sau vài giây.',
        style: TextStyle(fontSize: 12, height: 1.4, color: ProxyColors.muted),
      ),
    ];
  }

  Key _configurationKey(String name, int index) =>
      Key(index == 0 ? name : '$name-$index');

  Widget _configurationSection(
    ConfigurationFormFields fields,
    int index,
  ) => KeyedSubtree(
    key: ObjectKey(fields),
    child: _section(
      'Thông tin cấu hình',
      logic.hasMultipleImports
          ? 'Cấu hình ${index + 1}. Proxy, tài khoản và User-Agent riêng.'
          : 'Nhập proxy HTTP/HTTPS có cổng, User-Agent và tài khoản TikTok dùng cho đăng ký, đăng nhập và lấy OTP email.',
      Icons.tune,
      [
        _fieldLabel('Địa chỉ proxy'),
        TextFormField(
          key: _configurationKey('savedProxyUrl', index),
          controller: fields.url,
          onChanged: (_) => logic.update(),
          autocorrect: false,
          keyboardType: TextInputType.url,
          textInputAction: TextInputAction.next,
          decoration: const InputDecoration(
            hintText: 'Nhập địa chỉ proxy (host:port)',
            prefixIcon: Icon(Icons.link, size: 20),
          ),
          validator: (value) {
            try {
              WebViewProxy.parse(value ?? '');
              return null;
            } on FormatException catch (error) {
              return error.message;
            }
          },
        ),
        const SizedBox(height: 16),
        _fieldLabel('Tên đăng nhập proxy (không bắt buộc)'),
        TextFormField(
          key: _configurationKey('savedProxyUsername', index),
          controller: fields.username,
          onChanged: (_) => logic.update(),
          autocorrect: false,
          textInputAction: TextInputAction.next,
          decoration: const InputDecoration(
            hintText: 'Nhập tên đăng nhập proxy',
            prefixIcon: Icon(Icons.person_outline, size: 20),
          ),
        ),
        const SizedBox(height: 16),
        _fieldLabel('Mật khẩu proxy (không bắt buộc)'),
        TextFormField(
          key: _configurationKey('savedProxyPassword', index),
          controller: fields.password,
          onChanged: (_) => logic.update(),
          autocorrect: false,
          enableSuggestions: false,
          textInputAction: TextInputAction.next,
          decoration: const InputDecoration(
            hintText: 'Nhập mật khẩu proxy',
            prefixIcon: Icon(Icons.lock_outline, size: 20),
          ),
        ),
        const SizedBox(height: 20),
        _fieldLabel(
          'User-Agent',
          action: Tooltip(
            message: 'Tạo User-Agent mới',
            child: OutlinedButton.icon(
              key: _configurationKey('generateProxyUserAgent', index),
              onPressed: fields.generating
                  ? null
                  : () => logic.generateUserAgentFor(fields),
              style: OutlinedButton.styleFrom(
                minimumSize: const Size(0, 32),
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 6,
                ),
                textStyle: const TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                ),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(8),
                ),
              ),
              icon: const Icon(Icons.refresh, size: 15),
              label: Text(fields.generating ? 'Đang lấy…' : 'Đổi User-Agent'),
            ),
          ),
        ),
        TextFormField(
          key: _configurationKey('savedProxyUserAgent', index),
          controller: fields.userAgent,
          onChanged: (_) => logic.normalizeUserAgentFor(fields),
          enabled: !fields.generating,
          autocorrect: false,
          enableSuggestions: false,
          minLines: 3,
          maxLines: 6,
          style: const TextStyle(fontSize: 12, height: 1.6),
          decoration: InputDecoration(
            hintText: 'Nhập User-Agent trên một dòng',
            helperText: needsAndroidDesktopIdentity
                ? 'Mặc định TikTok và kiểm tra proxy dùng Chrome theo WebView đang cài. '
                      'Mẫu lưu ở đây chỉ dùng khi chọn User-Agent đã chọn (thủ công) trong màn TikTok.'
                : null,
            helperMaxLines: 4,
          ),
          validator: (value) =>
              value == null ||
                  value.trim().isEmpty ||
                  RegExp(r'[\r\n]').hasMatch(value.trim())
              ? 'Nhập User-Agent hợp lệ trên một dòng.'
              : null,
        ),
        if (needsAndroidDesktopIdentity)
          Align(
            alignment: Alignment.centerRight,
            child: TextButton.icon(
              key: _configurationKey('useMiuiUserAgent', index),
              onPressed: fields.generating
                  ? null
                  : () => logic.useMiuiUserAgentFor(fields),
              icon: const Icon(Icons.phone_android, size: 16),
              label: const Text('Dùng Miui Browser 14 (Desktop)'),
            ),
          ),
        if (fields.generationFailed)
          const Padding(
            padding: EdgeInsets.only(top: 10),
            child: Text(
              'Không thể tạo User-Agent. Nhấn nút để thử lại.',
              style: TextStyle(color: ProxyColors.amber, fontSize: 12),
            ),
          ),
        const SizedBox(height: 20),
        _fieldLabel(
          'Múi giờ WebView',
          action: TextButton.icon(
            key: _configurationKey('detectProxyTimeZone', index),
            onPressed: !logic.canDetectTimeZone || fields.detectingTimeZone
                ? null
                : () => logic.detectTimeZoneFor(fields),
            icon: fields.detectingTimeZone
                ? const SizedBox(
                    width: 14,
                    height: 14,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.refresh, size: 16),
            label: Text(
              fields.detectingTimeZone ? 'Đang tra…' : 'Tra theo proxy',
            ),
          ),
        ),
        TextFormField(
          key: _configurationKey('savedProxyTimeZone', index),
          controller: fields.timeZoneId,
          autocorrect: false,
          enableSuggestions: false,
          textInputAction: TextInputAction.next,
          onChanged: (_) => logic.mutate(() => fields.timeZoneError = null),
          decoration: const InputDecoration(
            hintText: 'America/New_York',
            helperText: 'Mã múi giờ IANA. Để trống để tự tra khi mở WebView.',
            helperMaxLines: 2,
            prefixIcon: Icon(Icons.schedule, size: 20),
          ),
          validator: (value) {
            try {
              normalizeProxyTimeZone(value);
              return null;
            } on FormatException catch (error) {
              return error.message;
            }
          },
        ),
        if (fields.timeZoneError != null)
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Text(
              fields.timeZoneError!,
              style: const TextStyle(color: ProxyColors.amber, fontSize: 12),
            ),
          ),
        const SizedBox(height: 16),
        _fieldLabel(
          'Thiết bị (GPU)',
          action: TextButton.icon(
            key: _configurationKey('changeGpuProfile', index),
            onPressed: () => logic.mutate(fields.changeGpuProfile),
            icon: const Icon(Icons.refresh, size: 16),
            label: const Text('Đổi'),
          ),
        ),
        // Read-only: chosen at random, only Đổi or a backup changes it.
        InputDecorator(
          decoration: const InputDecoration(
            helperText: 'GPU điện thoại mà trang web thấy qua WebGL.',
            prefixIcon: Icon(Icons.smartphone, size: 20),
          ),
          child: Text(
            fields.gpuProfile.label,
            key: _configurationKey('savedGpuProfile', index),
          ),
        ),
        const SizedBox(height: 20),
        SwitchListTile(
          key: _configurationKey('savedNurtureAfterSignup', index),
          contentPadding: EdgeInsets.zero,
          title: const Text('Nuôi sau khi đăng ký', style: _fieldLabelStyle),
          value: fields.nurtureAfterSignup,
          onChanged: (value) => logic.setNurtureAfterSignup(fields, value),
        ),
        const SizedBox(height: 8),
        ..._nurtureSettingsFields(fields, index),
        const SizedBox(height: 16),
        _fieldLabel('Email đăng ký'),
        TextFormField(
          key: _configurationKey('savedAccountEmail', index),
          controller: fields.accountEmail,
          autocorrect: false,
          keyboardType: TextInputType.emailAddress,
          decoration: const InputDecoration(
            hintText: 'Nhập email',
            prefixIcon: Icon(Icons.alternate_email, size: 20),
          ),
          validator: (value) => OtpApiConfiguration.isEmail(value?.trim() ?? '')
              ? null
              : 'Nhập email tài khoản hợp lệ.',
        ),
        const SizedBox(height: 16),
        _fieldLabel('Mật khẩu TikTok'),
        TextFormField(
          key: _configurationKey('savedAccountPassword', index),
          controller: fields.accountPassword,
          autocorrect: false,
          enableSuggestions: false,
          decoration: InputDecoration(
            hintText: 'Nhập mật khẩu TikTok',
            prefixIcon: const Icon(Icons.lock_outline, size: 20),
            helperText:
                'Tự tạo 9–13 ký tự: chữ đầu viết hoa, 2 số cuối. Giữ mật khẩu từ import.',
            helperMaxLines: 2,
            suffixIcon: IconButton(
              tooltip: 'Tạo mật khẩu khác',
              onPressed: () => logic.mutate(
                () => fields.accountPassword.text = generateAccountPassword(),
              ),
              icon: const Icon(Icons.refresh),
            ),
          ),
          validator: (value) => value == null || value.trim().isEmpty
              ? 'Nhập mật khẩu TikTok.'
              : null,
        ),
        const SizedBox(height: 16),
        _fieldLabel('Mật khẩu email lấy OTP'),
        TextFormField(
          key: _configurationKey('savedMailboxPassword', index),
          controller: fields.mailboxPassword,
          autocorrect: false,
          enableSuggestions: false,
          decoration: const InputDecoration(
            hintText: 'Nhập mật khẩu email lấy OTP',
            prefixIcon: Icon(Icons.mail_outline, size: 20),
          ),
          validator: (value) => value == null || value.trim().isEmpty
              ? 'Nhập mật khẩu email lấy OTP.'
              : null,
        ),
        const SizedBox(height: 8),
        SwitchListTile(
          key: _configurationKey('savedAccountStatus', index),
          contentPadding: EdgeInsets.zero,
          title: const Text('Đã đăng ký', style: _fieldLabelStyle),
          value: fields.statusAccount == AccountStatus.registered,
          onChanged: (value) => logic.mutate(
            () => fields.statusAccount = value
                ? AccountStatus.registered
                : AccountStatus.unregistered,
          ),
        ),
      ],
    ),
  );

  @override
  Widget build(BuildContext context) => Theme(
    data: ProxyColors.theme(context),
    child: Scaffold(
      appBar: AppBar(
        title: Text(
          title,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(fontSize: 19, fontWeight: FontWeight.w700),
        ),
      ),
      body: Form(
        key: logic.form,
        child: SingleChildScrollView(
          key: const Key('proxyEditorScroll'),
          keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 720),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  if (logic.entry == null) ...[
                    ProxyPanel(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          _fieldLabel('Dữ liệu import cấu hình'),
                          TextFormField(
                            key: const Key('proxyImportData'),
                            controller: logic.importData,
                            enabled:
                                !(logic.importing || logic.detectingTimeZones),
                            autocorrect: false,
                            enableSuggestions: false,
                            keyboardType: TextInputType.multiline,
                            textInputAction: TextInputAction.newline,
                            minLines: 3,
                            maxLines: 8,
                            onChanged: logic.clearImportError,
                            decoration: InputDecoration(
                              hintText: 'Dán nội dung cấu hình',
                              helperText:
                                  'Để đọc Excel/TXT, chọn Import data > Từ file.\n'
                                  'host:port:user:pass|email|mật khẩu TikTok|mật khẩu email OTP[|0/1]\n'
                                  'Mỗi dòng một cấu hình. 1: đã đăng ký; 0 hoặc bỏ qua: chưa đăng ký.',
                              helperMaxLines: 6,
                              errorText: logic.importError,
                              errorMaxLines: 4,
                              suffixIcon: IconButton(
                                key: const Key('applyProxyImportData'),
                                tooltip: 'Import dữ liệu đã nhập',
                                onPressed:
                                    (logic.importing ||
                                        logic.detectingTimeZones)
                                    ? null
                                    : logic.importProxy,
                                icon: const Icon(Icons.check_rounded, size: 20),
                              ),
                            ),
                          ),
                          const SizedBox(height: 10),
                          OutlinedButton.icon(
                            key: const Key('importProxyData'),
                            onPressed:
                                (logic.importing || logic.detectingTimeZones)
                                ? null
                                : () => _showImportOptions(context),
                            icon: const Icon(
                              Icons.file_download_outlined,
                              size: 19,
                            ),
                            label: Text(
                              logic.importing
                                  ? 'Đang import…'
                                  : logic.detectingTimeZones
                                  ? 'Đang tra múi giờ…'
                                  : 'Import data',
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 16),
                  ],
                  if (logic.hasMultipleImports) ...[
                    _fieldLabel(
                      '${logic.configurations.length} cấu hình',
                      action: TextButton(
                        onPressed: (logic.importing || logic.detectingTimeZones)
                            ? null
                            : logic.clearImportedConfigurations,
                        child: const Text('Bỏ danh sách'),
                      ),
                    ),
                    const SizedBox(height: 8),
                  ],
                  for (
                    var index = 0;
                    index < logic.configurations.length;
                    index++
                  ) ...[
                    _configurationSection(logic.configurations[index], index),
                    if (index < logic.configurations.length - 1)
                      const SizedBox(height: 16),
                  ],
                ],
              ),
            ),
          ),
        ),
      ),
      bottomNavigationBar: Container(
        decoration: const BoxDecoration(
          color: ProxyColors.background,
          border: Border(top: BorderSide(color: ProxyColors.border)),
        ),
        child: SafeArea(
          top: false,
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: FilledButton(
              key: const Key('saveProxyEntry'),
              onPressed:
                  logic.generating ||
                      (logic.importing || logic.detectingTimeZones) ||
                      logic.configurations.any(
                        (fields) => fields.userAgent.text.trim().isEmpty,
                      )
                  ? null
                  : () => _save(context),
              child: Text(
                logic.hasMultipleImports
                    ? 'Tạo ${logic.configurations.length} cấu hình'
                    : submitLabel,
              ),
            ),
          ),
        ),
      ),
    ),
  );
}
