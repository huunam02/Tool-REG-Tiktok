import 'dart:async';
import 'dart:convert';

import 'package:flutter/services.dart';

import 'app_configuration.dart';
import 'signup_accessibility.dart';
import 'signup_birthday_menu.dart';

class SignupCoordinateProfile {
  SignupCoordinateProfile(this.data);
  final Map<String, dynamic> data;
  bool get complete => data['complete'] == true;
  Offset point(String name) {
    final values = (data['points'] as Map)[name] as List?;
    if (values == null) throw StateError('Chưa ghi tọa độ bước $name.');
    return Offset((values[0] as num).toDouble(), (values[1] as num).toDouble());
  }

  static Future<SignupCoordinateProfile> load() async =>
      SignupCoordinateProfile(
        jsonDecode(
              await rootBundle.loadString(
                'assets/signup-coordinate-profile.json',
              ),
            )
            as Map<String, dynamic>,
      );
}

/// UI input is exclusively Accessibility gestures + ACTION_PASTE. No DOM input.
/// Coordinates are recorded; Accessibility nodes validate the expected target.
class SignupCoordinateRunner {
  SignupCoordinateRunner({
    required this.profile,
    required this.accessibility,
    required this.configuration,
    required this.isActive,
    required this.isTikTok,
    required this.getOtp,
    required this.onStatus,
    this.onUsernameSkipped,
    this.isPageReady,
    this.readBirthdayMenu,
    DateTime Function()? now,
  }) : now = now ?? DateTime.now,
       birthday =
           configuration.birthday ?? AppConfiguration.randomSignupBirthday();
  final SignupCoordinateProfile profile;
  final SignupAccessibility accessibility;
  final AppConfiguration configuration;

  /// Choose once per attempt, including when Home already generated the date.
  final DateTime birthday;
  final DateTime Function() now;
  static const _months = [
    'January',
    'February',
    'March',
    'April',
    'May',
    'June',
    'July',
    'August',
    'September',
    'October',
    'November',
    'December',
  ];
  final bool Function() isActive;
  final Future<bool> Function() isTikTok;
  final Future<String> Function() getOtp;
  final void Function(String) onStatus;
  final Future<void> Function()? onUsernameSkipped;

  /// WebView load completion is separate from visible Accessibility nodes.
  final bool Function()? isPageReady;
  final Future<SignupBirthdayMenu?> Function(String field)? readBirthdayMenu;
  final Set<String> _actions = {};
  bool _cancelled = false;
  bool readyToSubmit = false;
  bool alreadyLoggedIn = false;
  void cancel() {
    _cancelled = true;
    unawaited(accessibility.cancelPaste().catchError((_) {}));
  }

  Future<void> _guard() async {
    if (_cancelled || !isActive()) throw const SignupCancelled();
    if (!await isTikTok()) throw StateError('Đã rời trang TikTok.');
    if (_cancelled || !isActive()) throw const SignupCancelled();
  }

  Future<void> _pause([int ms = 650]) async {
    await Future<void>.delayed(Duration(milliseconds: ms));
    await _guard();
  }

  Future<SignupSnapshot> _snapshot({bool allowNotReady = false}) async {
    await _guard();
    final value = await accessibility.snapshot();
    await _guard();
    if (!allowNotReady && (!value.ready || !value.viewport.valid)) {
      throw StateError('Không đọc được WebView chuẩn 1:2 qua Accessibility.');
    }
    if (value.contains(
      RegExp(
        r'maximum number of attempts|too many (attempts|requests)',
        caseSensitive: false,
      ),
    )) {
      throw StateError('TikTok báo giới hạn số lần thử.');
    }
    if (value.contains(
      RegExp(
        r'expired or incorrect|incorrect verification code|already signed up|email is already registered',
        caseSensitive: false,
      ),
    )) {
      throw StateError(
        'TikTok báo lỗi email hoặc OTP; đã dừng và giữ màn hiện tại.',
      );
    }
    return value;
  }

  Future<SignupSnapshot> _wait(
    bool Function(SignupSnapshot) matches,
    String status, {
    int seconds = 30,
  }) async {
    onStatus(status);
    final deadline = now().add(Duration(seconds: seconds));
    while (now().isBefore(deadline)) {
      final value = await _snapshot();
      if (matches(value)) return value;
      await _pause(300);
    }
    throw StateError('Chưa xác nhận được bước: $status');
  }

  static RegExp exact(String text) =>
      RegExp('^${RegExp.escape(text)}\$', caseSensitive: false);

  String _entryAction(SignupSnapshot snapshot) {
    // TikTok can open this modal before the runner starts. Its controls take
    // precedence over any home-page nodes still exposed behind the overlay.
    if (snapshot.contains(exact('Sign up for TikTok'))) {
      return 'signup-phone-email';
    }
    if (snapshot.contains(exact('Log in to TikTok'))) return 'open-signup';
    return 'open-login';
  }

  RegExp _entryLabel(String action) => exact(switch (action) {
    'open-signup' => 'Sign up',
    'signup-phone-email' => 'Use phone or email',
    _ => 'Log in',
  });

  Future<SignupSnapshot> _waitForEntryReady() async {
    onStatus('Đang chờ trang và nút đăng ký sẵn sàng…');
    final deadline = now().add(const Duration(seconds: 60));
    DateTime? pageReadySince;
    DateTime? targetStableSince;
    Rect? previousViewport;
    Rect? previousTarget;
    String? previousAction;
    while (now().isBefore(deadline)) {
      final snapshot = await _snapshot(allowNotReady: true);
      if (!(isPageReady?.call() ?? true) ||
          !snapshot.ready ||
          !snapshot.viewport.valid) {
        pageReadySince = null;
        targetStableSince = null;
        previousViewport = null;
        previousTarget = null;
        previousAction = null;
        await _pause(300);
        continue;
      }
      if (_authenticated(snapshot)) return snapshot;
      final timestamp = now();
      pageReadySince ??= timestamp;
      final action = _entryAction(snapshot);
      final label = _entryLabel(action);
      final point = snapshot.viewport.toScreen(profile.point(action));
      final targets = snapshot.nodes.where(
        (n) => n.enabled && label.hasMatch(n.label) && n.bounds.contains(point),
      );
      final target = targets.isEmpty ? null : targets.last;
      if (target == null) {
        targetStableSince = null;
        previousTarget = null;
      } else {
        if (previousAction != action ||
            previousViewport != snapshot.viewport.bounds ||
            previousTarget != target.bounds) {
          targetStableSince = timestamp;
        }
        if (timestamp.difference(pageReadySince) >=
                const Duration(seconds: 5) &&
            timestamp.difference(targetStableSince!) >=
                const Duration(seconds: 2)) {
          return snapshot;
        }
        previousTarget = target.bounds;
      }
      previousAction = action;
      previousViewport = snapshot.viewport.bounds;
      await _pause(300);
    }
    throw StateError(
      'Trang hoặc nút đăng nhập/đăng ký chưa ổn định; đã dừng trước khi bấm.',
    );
  }

  Future<void> _tap(
    String name, {
    RegExp? expected,
    bool editable = false,
    Future<void> Function()? onTapped,
  }) async {
    if (_actions.contains(name)) {
      throw StateError('Bước $name đã thực hiện, không bấm lại.');
    }
    final snapshot = await _snapshot();
    final point = profile.point(name);
    {
      final physical = snapshot.viewport.toScreen(point);
      final match = snapshot.nodes.any(
        (n) =>
            n.enabled &&
            (!editable || n.editable) &&
            (expected == null || expected.hasMatch(n.label)) &&
            n.bounds.contains(physical),
      );
      if (!match) {
        throw StateError(
          'Tọa độ bước $name không trúng control đã ghi. Cần đo lại.',
        );
      }
    }
    _actions.add(name); // A gesture is never repeated on timeout/navigation.
    await accessibility.tap(snapshot.viewport, point);
    await onTapped?.call();
    await _pause();
  }

  Future<void> _paste(String field, String text) async {
    await _guard();
    if (text.isEmpty) throw StateError('Thiếu dữ liệu $field trong cấu hình.');
    final result = await accessibility.paste(text, field);
    await _guard();
    if (result['ok'] != true) {
      throw StateError(
        'Accessibility chưa dán được $field (${result['reason'] ?? 'unknown'}).',
      );
    }
    await _pause();
  }

  Future<void> _hideKeyboard() async {
    final snapshot = await _snapshot();
    if (!snapshot.keyboardVisible) return;
    await accessibility.dismissKeyboard();
    await _wait((s) => !s.keyboardVisible, 'Đang đóng bàn phím…', seconds: 5);
  }

  bool _birthdayValue(SignupSnapshot s, String field, String value) =>
      s.nodes.any(
        (n) =>
            n.className.endsWith('Spinner') &&
            n.text.trim() == value &&
            n.label.toLowerCase().contains(field.toLowerCase()),
      );

  bool _authenticated(SignupSnapshot s) =>
      s.contains(exact('Messages')) &&
      s.contains(exact('Profile')) &&
      !s.contains(exact('Log in')) &&
      !s.contains(exact('Log in to TikTok')) &&
      !s.contains(exact('Sign up for TikTok')) &&
      !s.nodes.any((n) => n.password) &&
      !s.contains(
        RegExp(r'^create (a |your )?username$', caseSensitive: false),
      );

  Future<void> selectBirthday() async {
    final date = birthday;
    onStatus(
      'Đang chọn ngày sinh ${AppConfiguration.formatBirthday(date)} bằng Accessibility…',
    );
    // Year/month before day keeps February 29 and 30/31-day months valid.
    await _selectBirthday('Year', '${date.year}', date.year);
    await _selectBirthday('Month', _months[date.month - 1], date.month);
    await _selectBirthday('Day', '${date.day}', date.day);
    final snapshot = await _snapshot();
    if (!_birthdayValue(snapshot, 'Month', _months[date.month - 1]) ||
        !_birthdayValue(snapshot, 'Day', '${date.day}') ||
        !_birthdayValue(snapshot, 'Year', '${date.year}')) {
      throw StateError(
        'Ngày sinh trên TikTok chưa khớp ngày đã chọn, không gửi mã.',
      );
    }
  }

  Future<SignupBirthdayMenu?> _birthdayMenu(
    SignupSnapshot s,
    String field,
  ) async {
    final lists = s.nodes.where(
      (n) =>
          n.picker &&
          n.enabled &&
          (n.className.endsWith('ListView') ||
              n.className.endsWith('NumberPicker')),
    );
    if (lists.isNotEmpty) {
      final bounds = lists.first.bounds.intersect(s.viewport.bounds);
      Rect toDesign(Rect rect) => Rect.fromPoints(
        s.viewport.fromScreen(rect.topLeft),
        s.viewport.fromScreen(rect.bottomRight),
      );
      return SignupBirthdayMenu(
        field: field,
        expanded: true,
        bounds: toDesign(bounds),
        scrollable: lists.first.scrollable,
        options: [
          for (final n in s.nodes)
            if (n.picker &&
                n.enabled &&
                n.text.trim().isNotEmpty &&
                n.bounds.overlaps(bounds) &&
                n.bounds.center.dy > bounds.top + 2 &&
                n.bounds.center.dy < bounds.bottom - 2)
              SignupBirthdayOption(
                n.text.trim(),
                toDesign(n.bounds.intersect(bounds)),
              ),
        ],
      );
    }
    await _guard();
    final menu = await readBirthdayMenu?.call(field);
    await _guard();
    if (menu != null && menu.field != field) {
      throw StateError('Dropdown ngày sinh không khớp $field.');
    }
    return menu;
  }

  Future<void> _selectBirthday(String field, String value, int target) async {
    var menu = await _birthdayMenu(await _snapshot(), field);
    // A stopped attempt may have left this combobox open. Do not toggle it shut.
    if (menu?.expanded != true) {
      await _tap(
        'open-${field.toLowerCase()}',
        expected: RegExp(field, caseSensitive: false),
      );
    }
    onStatus('Đang mở danh sách $field…');
    final deadline = now().add(const Duration(seconds: 5));
    while (now().isBefore(deadline)) {
      menu = await _birthdayMenu(await _snapshot(), field);
      if (menu?.expanded == true) break;
      await _pause(300);
    }
    if (menu?.expanded != true) {
      throw StateError('Chưa đọc được danh sách $field đang mở.');
    }
    final seen = <String>{};
    for (var scrolls = 0; scrolls < 80; scrolls++) {
      final snapshot = await _snapshot();
      menu = await _birthdayMenu(snapshot, field);
      if (menu == null || !menu.expanded) {
        throw StateError('Không đọc được danh sách $field.');
      }
      final listBounds = menu.bounds;
      final options = menu.options.toList()
        ..sort((a, b) => a.bounds.top.compareTo(b.bounds.top));
      final matches = options.where((n) => n.text.trim() == value);
      if (matches.isNotEmpty) {
        final visible = matches.first.bounds.intersect(listBounds);
        await accessibility.tap(snapshot.viewport, visible.center);
        await _pause();
        await _wait(
          (s) =>
              _birthdayValue(s, field, value) && !s.nodes.any((n) => n.picker),
          'Kiểm tra $field sinh…',
          seconds: 5,
        );
        return;
      }
      int? ordinal(SignupBirthdayOption node) => field == 'Month'
          ? (_months.contains(node.text.trim())
                ? _months.indexOf(node.text.trim()) + 1
                : null)
          : int.tryParse(node.text.trim());
      final visibleValues = options.map(ordinal).whereType<int>().toList();
      if (visibleValues.isEmpty ||
          listBounds.height < 20 ||
          listBounds.width < 4) {
        throw StateError('Không đọc được mục trong danh sách $field.');
      }
      if (!menu.scrollable) {
        throw StateError('Danh sách $field không có mục $value.');
      }
      final signature = visibleValues.join(',');
      if (!seen.add(signature)) {
        throw StateError('Danh sách $field không cuộn tới $value; đã dừng.');
      }
      final ascending =
          visibleValues.length < 2 || visibleValues.last > visibleValues.first;
      final min = visibleValues.reduce((a, b) => a < b ? a : b);
      final max = visibleValues.reduce((a, b) => a > b ? a : b);
      if (target >= min && target <= max) {
        throw StateError('Thiếu mục $value trong danh sách $field.');
      }
      final forward = ascending ? target > max : target < min;
      final top = listBounds.top + listBounds.height * 0.2;
      final bottom = listBounds.bottom - listBounds.height * 0.2;
      await accessibility.swipe(
        snapshot.viewport,
        Offset(listBounds.center.dx, forward ? bottom : top),
        Offset(listBounds.center.dx, forward ? top : bottom),
      );
      await _pause(450);
    }
    throw StateError('Chưa tìm được $value trong danh sách $field.');
  }

  Future<void> run({
    bool stopBeforeSubmit = false,
    bool stopBeforeSendCode = false,
  }) async {
    if (!profile.complete) {
      throw StateError('Profile tọa độ chưa thu thập đầy đủ.');
    }
    final entry = await _waitForEntryReady();
    if (_authenticated(entry)) {
      alreadyLoggedIn = true;
      onStatus('Tài khoản TikTok đã đăng nhập.');
      return;
    }
    final entryAction = _entryAction(entry);
    if (entryAction == 'open-login') {
      await _tap('open-login', expected: exact('Log in'));
      await _wait(
        (s) => s.contains(exact('Log in to TikTok')),
        'Đang mở hộp đăng nhập…',
      );
    }
    if (entryAction != 'signup-phone-email') {
      await _tap('open-signup', expected: exact('Sign up'));
      await _wait(
        (s) => s.contains(exact('Sign up for TikTok')),
        'Đang mở đăng ký…',
      );
    }
    await _tap('signup-phone-email', expected: exact('Use phone or email'));
    await _wait((s) => s.contains(exact('Use email')), 'Đang mở biểu mẫu…');
    await _tap('use-email', expected: exact('Use email'));
    await _wait(
      (s) => s.editors.any((n) => n.hint.toLowerCase().contains('email')),
      'Đang chờ ô email…',
    );
    await selectBirthday();
    onStatus('Đang dán email bằng Accessibility…');
    await _tap('focus-email', editable: true);
    await _paste('email', configuration.signupEmail.trim());
    await _hideKeyboard();
    await _wait(
      (s) => s.find(exact('Send code')) != null,
      'Đang kiểm tra nút gửi mã…',
    );
    if (stopBeforeSendCode) {
      onStatus('Đã kiểm tra đến trước Send code.');
      return;
    }
    await _tap('send-code', expected: exact('Send code'));
    await _wait(
      (s) => s.contains(
        RegExp(r'resend|verify your email|enter.*code', caseSensitive: false),
      ),
      'Đang chờ TikTok xác nhận gửi mã…',
      seconds: 20,
    );
    onStatus('Đang lấy OTP…');
    final otp = await getOtp();
    await _guard();
    if (!RegExp(r'^\d{6}$').hasMatch(otp)) {
      throw StateError('OTP không đủ 6 số.');
    }
    await _wait((s) => s.editors.any((n) => !n.password), 'Đang chờ ô OTP…');
    await _tap('focus-otp', editable: true);
    await _paste('otp', otp);
    final afterOtp = await _snapshot();
    if (!afterOtp.editors.any((n) => n.password) &&
        profile.data['points']['submit-otp'] != null) {
      await _hideKeyboard();
      await _tap(
        'submit-otp',
        expected: RegExp(
          r'^(next|continue|verify|confirm)$',
          caseSensitive: false,
        ),
      );
    }
    await _wait(
      (s) => s.editors.any((n) => n.password),
      'Đang chờ ô mật khẩu…',
      seconds: 15,
    );
    onStatus('Đang dán mật khẩu bằng Accessibility…');
    await _tap('focus-password', editable: true);
    await _paste('password', configuration.signupPassword);
    await _hideKeyboard();
    await _wait(
      (s) =>
          s.nodes.any(
            (n) =>
                n.password && n.length == configuration.signupPassword.length,
          ) &&
          s.find(exact('Sign up')) != null,
      'Đang kiểm tra mật khẩu và nút Sign up…',
    );
    readyToSubmit = true;
    if (stopBeforeSubmit) {
      onStatus('Đã nhập xong, đang dừng trước Sign up.');
      return;
    }
    await finish();
  }

  Future<void> finish() async {
    if (!readyToSubmit) throw StateError('Chưa xác nhận xong bước mật khẩu.');
    onStatus('Đang bấm Sign up…');
    await _tap('submit-password', expected: exact('Sign up'));
    final next = await _wait(
      (s) =>
          s.contains(
            RegExp(r'^create (a |your )?username$', caseSensitive: false),
          ) ||
          _authenticated(s),
      'Đang chờ kết quả đăng ký…',
      seconds: 30,
    );
    if (next.contains(
      RegExp(r'^create (a |your )?username$', caseSensitive: false),
    )) {
      await _wait((s) => s.find(exact('Skip')) != null, 'Đang chờ Skip…');
      await _tap(
        'skip-username',
        expected: exact('Skip'),
        onTapped: onUsernameSkipped,
      );
      await _wait(_authenticated, 'Đang xác nhận hoàn tất…', seconds: 30);
    }
    onStatus('Đã qua luồng đăng ký.');
  }
}

class SignupCancelled implements Exception {
  const SignupCancelled();
}
