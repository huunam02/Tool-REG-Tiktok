import 'dart:async';
import 'dart:convert';
import 'dart:math';

import 'package:flutter/services.dart';

import 'app_configuration.dart';
import 'cookie_consent_accessibility.dart';
import 'privacy_notice_accessibility.dart';
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

/// UI input uses Accessibility gestures and editor actions. No DOM input.
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
    this.isForeground,
    DateTime Function()? now,
    Random? random,
  }) : now = now ?? DateTime.now,
       _random = random ?? Random(),
       birthday =
           configuration.birthday ?? AppConfiguration.randomSignupBirthday();
  final SignupCoordinateProfile profile;
  final SignupAccessibility accessibility;
  final AppConfiguration configuration;

  /// Choose once per attempt, including when Home already generated the date.
  final DateTime birthday;
  final DateTime Function() now;
  final Random _random;
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

  /// False while a notification shade or system dialog covers the app.
  final bool Function()? isForeground;
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
    // Wait out a shade or dialog: a gesture now would land on it, not TikTok.
    while (!(isForeground?.call() ?? true)) {
      await Future<void>.delayed(const Duration(milliseconds: 250));
      if (_cancelled || !isActive()) throw const SignupCancelled();
    }
    if (!await isTikTok()) throw StateError('Đã rời trang TikTok.');
    if (_cancelled || !isActive()) throw const SignupCancelled();
  }

  Future<void> _pause([int ms = 650]) async {
    await Future<void>.delayed(Duration(milliseconds: ms));
    await _guard();
  }

  Future<void> _pauseAfterAction({
    bool afterOtp = false,
    bool birthdayAction = false,
  }) => _pause(
    afterOtp
        ? 650
        : birthdayAction
        ? 1000 + _random.nextInt(2001)
        : 2000 + _random.nextInt(5001),
  );

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
        r'already signed up|email is already registered',
        caseSensitive: false,
      ),
    )) {
      throw StateError(
        'Email này đã có tài khoản TikTok. Hãy bật Đã đăng ký cho cấu hình '
        'rồi dùng Đăng nhập hoặc Nuôi toàn bộ.',
      );
    }
    if (value.contains(
      RegExp(
        r'expired or incorrect|incorrect verification code',
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
      if (await _dismissPrivacyNoticeIfShown(value)) continue;
      await _pause(300);
    }
    throw StateError('Chưa xác nhận được bước: $status');
  }

  static const _maxOpenLoginTaps = 3;
  static const _openLoginRetryAfter = Duration(seconds: 10);

  /// TikTok can drop the Log in tap while the page still hydrates. Opening
  /// the dialog submits nothing, so a bounded retry is safe.
  Future<SignupSnapshot> _openLoginDialog() async {
    const status = 'Đang mở hộp đăng nhập…';
    for (var taps = 1; ; taps++) {
      _actions.remove('open-login');
      await _tap('open-login', expected: exact('Log in'));
      onStatus(status);
      final deadline = now().add(_openLoginRetryAfter);
      while (now().isBefore(deadline)) {
        final value = await _snapshot();
        if (_entryAction(value) != 'open-login') return value;
        await _pause(300);
      }
      if (taps >= _maxOpenLoginTaps) {
        throw StateError('Chưa xác nhận được bước: $status');
      }
    }
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
    final started = now();
    final deadline = started.add(const Duration(seconds: 60));
    DateTime? pageReadySince;
    DateTime? targetStableSince;
    Rect? previousViewport;
    Rect? previousTarget;
    String? previousAction;
    // Why the last read was not ready; shown in the failure so a customer's
    // device can be diagnosed from the Cấu hình lỗi card alone.
    var reason = 'chưa đọc được trang';
    while (now().isBefore(deadline)) {
      final snapshot = await _snapshot(allowNotReady: true);
      if (!snapshot.ready || !snapshot.viewport.valid) {
        final b = snapshot.viewport.bounds;
        reason = !snapshot.serviceConnected
            ? 'dịch vụ Trợ năng chưa chạy; hãy tắt rồi bật lại Trợ năng '
                  'hoặc khởi động lại điện thoại'
            : !snapshot.ready
            ? 'không đọc được WebView qua Trợ năng'
            : 'khung WebView ${b.width.round()}×${b.height.round()} '
                  'không đúng tỉ lệ 1:2';
        pageReadySince = null;
        targetStableSince = null;
        previousViewport = null;
        previousTarget = null;
        previousAction = null;
        await _pause(300);
        continue;
      }
      // A slow phone or proxy can show the page long before the browser's
      // load event (the customer's Galaxy S8). A stable entry control is then
      // accepted after 20s with a longer stability check.
      final loaded = isPageReady?.call() ?? true;
      if (_authenticated(snapshot) && loaded) return snapshot;
      if (await _acceptCookiesIfShown(snapshot)) {
        // The banner closing can shift layout; re-check target stability.
        targetStableSince = null;
        previousTarget = null;
        continue;
      }
      final timestamp = now();
      // The five-second settle restarts whenever the load is pending again
      // (e.g. a reload); the fallback below tracks the target meanwhile.
      pageReadySince = loaded ? pageReadySince ?? timestamp : null;
      final action = _entryAction(snapshot);
      final label = _entryLabel(action);
      final target = _target(snapshot, action, expected: label);
      if (target == null) {
        targetStableSince = null;
        previousTarget = null;
        final name = switch (action) {
          'open-signup' => 'Sign up',
          'signup-phone-email' => 'Use phone or email',
          _ => 'Log in',
        };
        reason =
            (snapshot.nodes.any((n) => label.hasMatch(n.label))
                ? 'nút "$name" đang bị tắt'
                : 'không thấy nút "$name"') +
            (loaded ? '' : ', trang chưa báo tải xong');
      } else {
        if (previousAction != action ||
            previousViewport != snapshot.viewport.bounds ||
            previousTarget != target.bounds) {
          targetStableSince = timestamp;
        }
        final settled = timestamp.difference(targetStableSince!);
        if (loaded &&
            timestamp.difference(pageReadySince!) >=
                const Duration(seconds: 5) &&
            settled >= const Duration(seconds: 2)) {
          return snapshot;
        }
        if (!loaded &&
            timestamp.difference(started) >= const Duration(seconds: 20) &&
            settled >= const Duration(seconds: 3)) {
          return snapshot;
        }
        final b = target.bounds;
        reason = loaded
            ? 'nút còn di chuyển (${b.left.round()},${b.top.round()})'
            : 'trang chưa báo tải xong';
        previousTarget = target.bounds;
      }
      previousAction = action;
      previousViewport = snapshot.viewport.bounds;
      await _pause(300);
    }
    if (reason == 'không đọc được WebView qua Trợ năng') {
      try {
        final diagnosis = await accessibility.diagnoseWeb();
        if (diagnosis.isNotEmpty) reason = '$reason [$diagnosis]';
      } catch (_) {
        // Diagnostics must not replace the original failure.
      }
    }
    throw StateError(
      'Trang hoặc nút đăng nhập/đăng ký chưa ổn định ($reason); '
      'đã dừng trước khi bấm.',
    );
  }

  /// The live control for step [name]. The recorded point only picks among
  /// matching nodes; the tap itself follows the node's Accessibility bounds,
  /// so it lands on any screen size, font or WebView version.
  SignupNode? _target(
    SignupSnapshot snapshot,
    String name, {
    RegExp? expected,
    bool editable = false,
    bool Function(SignupNode)? where,
  }) {
    final candidates = snapshot.nodes.where(
      (n) =>
          n.enabled &&
          (!editable || n.editable) &&
          (expected == null || expected.hasMatch(n.label)) &&
          (where?.call(n) ?? true),
    );
    final recorded = _recorded(name);
    if (recorded != null) {
      return snapshot.viewport.nearest(candidates, recorded);
    }
    final visible = candidates
        .where((n) => !n.bounds.intersect(snapshot.viewport.bounds).isEmpty)
        .toList();
    // Without a recorded point the control must be unambiguous. A label is
    // often exposed twice (clickable View and its TextView); act on the View.
    final actionable = visible.where((n) => n.clickable || n.editable).toList();
    final pool = actionable.isEmpty ? visible : actionable;
    return pool.length == 1 ? pool.single : null;
  }

  /// TikTok's cookie banner (EU IPs) can appear at any step and covers the
  /// bottom of the page. Accept it once like a regular visitor; its absence
  /// never blocks signup. Returns whether a tap was made.
  Future<bool> _acceptCookiesIfShown(SignupSnapshot snapshot) async {
    if (_actions.contains('accept-cookies')) return false;
    final node = CookieConsentAccessibility.button(snapshot);
    if (node == null) return false;
    onStatus('Đang bấm Allow all cho cookie TikTok…');
    _actions.add('accept-cookies'); // One attempt even if the banner stays.
    await accessibility.tapScreen(
      snapshot.viewport.bounds,
      node.bounds.intersect(snapshot.viewport.bounds).center,
    );
    await _pauseAfterAction();
    return true;
  }

  static const _maxPrivacyNoticeTaps = 3;
  int _privacyNoticeTaps = 0;

  /// TikTok's one-time privacy notice appears once the new account exists
  /// and hides the page until Got it is tapped. Returns whether it tapped.
  Future<bool> _dismissPrivacyNoticeIfShown(SignupSnapshot snapshot) async {
    if (_privacyNoticeTaps >= _maxPrivacyNoticeTaps) return false;
    final node = PrivacyNoticeAccessibility.button(snapshot);
    if (node == null) return false;
    _privacyNoticeTaps++;
    onStatus('Đang bấm Got it cho thông báo quyền riêng tư của TikTok…');
    await accessibility.tapScreen(
      snapshot.viewport.bounds,
      node.bounds.intersect(snapshot.viewport.bounds).center,
    );
    await _pauseAfterAction();
    return true;
  }

  Offset? _recorded(String name) =>
      (profile.data['points'] as Map)[name] == null
      ? null
      : profile.point(name);

  Future<void> _tap(
    String name, {
    RegExp? expected,
    bool editable = false,
    bool Function(SignupNode)? where,
    Future<void> Function()? onTapped,
    bool birthdayAction = false,
  }) async {
    if (_actions.contains(name)) {
      throw StateError('Bước $name đã thực hiện, không bấm lại.');
    }
    var snapshot = await _snapshot();
    if (await _acceptCookiesIfShown(snapshot)) snapshot = await _snapshot();
    final node = _target(
      snapshot,
      name,
      expected: expected,
      editable: editable,
      where: where,
    );
    if (node == null) {
      throw StateError('Không thấy control của bước $name trên màn hình.');
    }
    final point = snapshot.viewport.tapPoint(node.bounds, _recorded(name));
    _actions.add(name); // A gesture is never repeated on timeout/navigation.
    await accessibility.tap(snapshot.viewport, point);
    await onTapped?.call();
    await _pauseAfterAction(birthdayAction: birthdayAction);
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
    await _pauseAfterAction(afterOtp: field == 'otp');
  }

  static final _resend = exact('Resend code');

  /// An API timeout taps Resend code once, then asks the API for the new code.
  Future<String> _readOtp() async {
    try {
      return await getOtp();
    } on SignupOtpTimeout {
      await _resendOtpOnce();
    }
    onStatus('Đã gửi lại mã 1 lần. Đang lấy OTP mới…');
    try {
      return await getOtp();
    } on SignupOtpTimeout catch (error) {
      throw StateError(
        '${error.message} Đã gửi lại mã 1 lần; đã dừng, không gửi lại thêm.',
      );
    }
  }

  Future<void> _resendOtpOnce() async {
    // Resend stays disabled while TikTok's countdown runs.
    await _wait(
      (s) => _target(s, 'resend-code', expected: _resend) != null,
      'Hết thời gian chờ OTP. Đang chờ Resend code được bật…',
      seconds: 75,
    );
    onStatus('Đang bấm Resend code một lần bằng Accessibility…');
    await _tap('resend-code', expected: _resend);
    await _wait(
      (s) =>
          s.nodes.any((n) => !n.enabled && _resend.hasMatch(n.label)) ||
          s.contains(RegExp(r'^\d+\s*s$')),
      'Đang chờ TikTok xác nhận gửi lại mã…',
      seconds: 15,
    );
  }

  Future<void> _hideKeyboard() async {
    final snapshot = await _snapshot();
    if (!snapshot.keyboardVisible) return;
    await accessibility.dismissKeyboard();
    await _wait((s) => !s.keyboardVisible, 'Đang đóng bàn phím…', seconds: 5);
    await _pauseAfterAction();
  }

  bool _birthdayValue(SignupSnapshot s, String field, String value) =>
      s.nodes.any(
        (n) =>
            n.className.endsWith('Spinner') &&
            n.text.trim() == value &&
            n.label.toLowerCase().contains(field.toLowerCase()),
      ) ||
      // GeckoView exposes the combobox as "<field>. Double-tap…" and its
      // selected value as a child node inside the combobox bounds.
      s.nodes.any(
        (n) =>
            n.className.endsWith('EditText') &&
            RegExp('^$field\\b', caseSensitive: false).hasMatch(n.label) &&
            s.nodes.any(
              (c) =>
                  c != n &&
                  c.text.trim() == value &&
                  n.bounds.contains(c.bounds.center),
            ),
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
        birthdayAction: true,
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
    final visits = <String, int>{};
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
        await _pauseAfterAction(birthdayAction: true);
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
      final attempts = visits.update(
        signature,
        (count) => count + 1,
        ifAbsent: () => 1,
      );
      // dispatchGesture can complete without scrolling a busy HTML dropdown.
      // Retry at most three swipes for the same visible range; one missed
      // gesture or stale read must not abort an otherwise usable form.
      if (attempts > 3) {
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
      // Use more of the list on recovery, keeping both ends inside its bounds.
      final inset = attempts == 1 ? 0.2 : 0.1;
      final top = listBounds.top + listBounds.height * inset;
      final bottom = listBounds.bottom - listBounds.height * inset;
      await accessibility.swipe(
        snapshot.viewport,
        Offset(listBounds.center.dx, forward ? bottom : top),
        Offset(listBounds.center.dx, forward ? top : bottom),
      );
      await _pauseAfterAction(birthdayAction: true);
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
    var entryAction = _entryAction(entry);
    if (entryAction == 'open-login') {
      entryAction = _entryAction(await _openLoginDialog());
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
    await _tap('focus-email', editable: true, where: (n) => !n.password);
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
    final otp = await _readOtp();
    await _guard();
    if (!RegExp(r'^\d{6}$').hasMatch(otp)) {
      throw StateError('OTP không đủ 6 số.');
    }
    await _wait((s) => s.editors.any((n) => !n.password), 'Đang chờ ô OTP…');
    await _tap('focus-otp', editable: true, where: (n) => !n.password);
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
    await _tap('focus-password', editable: true, where: (n) => n.password);
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

/// The OTP API found no code in time; signup may resend it once.
class SignupOtpTimeout extends StateError {
  SignupOtpTimeout([super.message = 'Hết thời gian chờ OTP đăng ký.']);
}
