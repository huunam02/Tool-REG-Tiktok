import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:test_tiktok/controller/tiktok_controller.dart';
import 'package:test_tiktok/core/app_configuration.dart';
import 'package:test_tiktok/core/login_accessibility_runner.dart';
import 'package:test_tiktok/core/login_coordinate_profile.dart';
import 'package:test_tiktok/core/nurture_coordinate_profile.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:test_tiktok/core/otp_api.dart';
import 'package:test_tiktok/core/signup_accessibility.dart';
import 'package:test_tiktok/core/tiktok_launch_action.dart';
import 'package:test_tiktok/core/scripts/auto_login_script.dart';
import 'package:test_tiktok/core/scripts/auto_watch_script.dart';

final _configuration = AppConfiguration(
  userAgent: 'agent',
  comments: [],
  signupEmail: '',
  signupPassword: '',
  loginUsername: 'person@example.com',
  loginPassword: 'password',
  loginOtp: '012345',
);

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));
  for (final scenario in [
    'wait-for-enabled',
    'disabled',
    'no-feedback',
    'cancel',
    'mailbox-error',
    'draft',
  ]) {
    testWidgets('resend OTP guard: $scenario', (tester) async {
      final screen = _Screen()
        ..state = 'otp'
        ..resendAvailable =
            scenario != 'disabled' && scenario != 'wait-for-enabled'
        ..acknowledgeResend = scenario != 'no-feedback';
      final profile = LoginCoordinateProfile({});
      var reads = 0, cancellations = 0;
      late LoginAccessibilityRunner runner;
      screen.afterTap = (action) {
        if (scenario == 'cancel' && action == 'resend') runner.cancel();
      };
      runner = LoginAccessibilityRunner(
        accessibility: screen,
        profile: profile,
        configuration: _configuration,
        isActive: () => true,
        isTikTok: () async => true,
        isPageReady: () => true,
        now: tester.binding.clock.now,
        onStatus: (_) {},
        cancelOtpRequest: () {
          cancellations++;
        },
        getOtp: () async {
          reads++;
          if (scenario == 'mailbox-error') {
            throw StateError('Mailbox credentials rejected');
          }
          if (reads == 1) {
            if (scenario == 'wait-for-enabled') {
              Timer(
                const Duration(seconds: 2),
                () => screen.resendAvailable = true,
              );
            }
            if (scenario == 'draft') screen.values['otp'] = '123';
            throw LoginOtpTimeout();
          }
          return '012345';
        },
      );
      final error = await _finish(tester, runner.run());
      if (scenario == 'wait-for-enabled') {
        expect(error, isNull);
        expect(screen.state, 'authenticated');
        expect(reads, 2);
        expect(profile.points, contains('resend-code'));
      } else {
        expect(
          error,
          scenario == 'cancel'
              ? isA<LoginAccessibilityCancelled>()
              : isA<StateError>(),
        );
        expect(reads, 1);
        expect(screen.pasted, isEmpty);
      }
      expect(cancellations, scenario == 'mailbox-error' ? 0 : 1);
      expect(
        screen.taps.where((a) => a == 'resend').length,
        ['wait-for-enabled', 'no-feedback', 'cancel'].contains(scenario)
            ? 1
            : 0,
      );
    });
  }

  testWidgets(
    'hung mailbox request is cancelled before one resend and its late code is ignored',
    (tester) async {
      final screen = _Screen()
        ..state = 'otp'
        ..resendAvailable = true;
      final oldCode = Completer<String>();
      var requests = 0, cancelled = false;
      final configuration = AppConfiguration(
        userAgent: 'agent',
        comments: [],
        signupEmail: '',
        signupPassword: '',
        loginUsername: 'person@example.com',
        loginPassword: 'password',
        otpApi: OtpApiConfiguration(
          url: Uri.parse('https://example.com/api/code'),
          readerToken: 'token',
          waitSeconds: 1,
        ),
      );
      final runner = LoginAccessibilityRunner(
        accessibility: screen,
        profile: LoginCoordinateProfile({}),
        configuration: configuration,
        isActive: () => true,
        isTikTok: () async => true,
        isPageReady: () => true,
        now: tester.binding.clock.now,
        onStatus: (_) {},
        cancelOtpRequest: () => cancelled = true,
        getOtp: () {
          requests++;
          if (requests == 1) return oldCode.future;
          expectSync(cancelled, isTrue);
          return Future.value('012345');
        },
      );
      expect(await _finish(tester, runner.run()), isNull);
      oldCode.complete('999999');
      await tester.pump(const Duration(seconds: 1));
      expect(requests, 2);
      expect(screen.values['otp'], '012345');
      expect(screen.taps.where((a) => a == 'resend'), hasLength(1));
    },
  );
  testWidgets(
    'replays live identity Email and OTP coordinates and submits Next once',
    (tester) async {
      final fixture = _LiveRecording();
      final raw =
          jsonDecode(
                File('assets/login-coordinate-profile.json').readAsStringSync(),
              )
              as Map;
      final points = Map<String, dynamic>.from(raw['points'] as Map);
      final runner = LoginAccessibilityRunner(
        accessibility: fixture,
        profile: LoginCoordinateProfile({
          for (final entry in points.entries)
            entry.key: Offset(
              (entry.value[0] as num).toDouble(),
              (entry.value[1] as num).toDouble(),
            ),
        }),
        configuration: _configuration,
        isActive: () => true,
        isTikTok: () async => true,
        isPageReady: () => true,
        getOtp: () async {
          expectSync(fixture.stage, 'otp');
          return '012345';
        },
        onStatus: (_) {},
        now: tester.binding.clock.now,
      );
      expect(await _finish(tester, runner.run()), isNull);
      expect(fixture.stage, 'authenticated');
      expect(
        fixture.actions.where((a) => a == 'select-verification-email'),
        hasLength(1),
      );
      expect(fixture.actions.where((a) => a == 'submit-otp'), hasLength(1));
      expect(fixture.actions, isNot(contains('send-code')));
      expect(fixture.values['otp'], '012345');
    },
  );
  testWidgets(
    'replays the six live recorded controls despite duplicate labels and changing node IDs',
    (tester) async {
      final fixture = _LiveRecording();
      final raw =
          jsonDecode(
                File('assets/login-coordinate-profile.json').readAsStringSync(),
              )
              as Map;
      final points = Map<String, dynamic>.from(raw['points'] as Map);
      final profile = LoginCoordinateProfile({
        for (final entry in points.entries)
          entry.key: Offset(
            (entry.value[0] as num).toDouble(),
            (entry.value[1] as num).toDouble(),
          ),
      });
      var active = true;
      fixture.onSubmit = () => active = false;
      final runner = LoginAccessibilityRunner(
        accessibility: fixture,
        profile: profile,
        configuration: _configuration,
        isActive: () => active,
        isTikTok: () async => true,
        isPageReady: () => true,
        getOtp: () async => throw StateError('No OTP before password response'),
        onStatus: (_) {},
        now: tester.binding.clock.now,
      );
      expect(
        await _finish(tester, runner.run()),
        isA<LoginAccessibilityCancelled>(),
      );
      expect(fixture.actions, [
        'open-login',
        'phone-email',
        'use-email',
        'focus-email',
        'paste-email',
        'focus-password',
        'paste-password',
        'submit-password',
      ]);
    },
  );
  for (final scenario in [
    'password-only',
    'email-otp',
    'send-code',
    'auto-submit-otp',
    'phone-form',
    'already-logged-in',
  ]) {
    testWidgets('Accessibility completes login: $scenario', (tester) async {
      final screen = _Screen()
        ..needsOtp = scenario != 'password-only'
        ..needsSend = scenario == 'send-code'
        ..autoSubmitOtp = scenario == 'auto-submit-otp';
      if (scenario == 'already-logged-in') screen.state = 'authenticated';
      if (scenario == 'phone-form') screen.state = 'phone';
      var requests = 0;
      final runner = LoginAccessibilityRunner(
        profile: LoginCoordinateProfile({}),
        accessibility: screen,
        configuration: _configuration,
        isActive: () => true,
        isTikTok: () async => true,
        isPageReady: () => true,
        now: tester.binding.clock.now,
        random: Random(4),
        getOtp: () async {
          expectSync(screen.state, 'otp');
          expectSync(screen.needsSend, isFalse);
          requests++;
          return '012345';
        },
        onStatus: (_) {},
      );
      expect(await _finish(tester, runner.run()), isNull);
      expect(screen.state, 'authenticated');
      expect(
        requests,
        scenario == 'password-only' || scenario == 'already-logged-in' ? 0 : 1,
      );
      expect(screen.taps.toSet().length, screen.taps.length);
      expect(runner.alreadyLoggedIn, scenario == 'already-logged-in');
      if (requests == 1) {
        expect(screen.pasted, ['email', 'password', 'otp']);
        expect(screen.values['otp'], '012345');
      }
    });
  }

  for (final scenario in [
    'no-delivery',
    'disabled-send-code',
    'password-stuck',
    'draft',
    'paste-failure',
    'disabled-submit',
    'captcha',
    'rate-limit',
    'wrong-origin',
  ]) {
    testWidgets('Accessibility stops safely: $scenario', (tester) async {
      final screen = _Screen()
        ..needsSend =
            scenario == 'no-delivery' || scenario == 'disabled-send-code'
        ..disableSend = scenario == 'disabled-send-code'
        ..acknowledgeSend = scenario != 'no-delivery'
        ..passwordStuck = scenario == 'password-stuck'
        ..rejectPaste = scenario == 'paste-failure'
        ..disableSubmit = scenario == 'disabled-submit';
      if (scenario == 'draft') screen.values['email'] = 'existing@example.org';
      if (scenario == 'captcha' || scenario == 'rate-limit') {
        screen.state = scenario;
      }
      var requests = 0;
      final runner = LoginAccessibilityRunner(
        profile: LoginCoordinateProfile({}),
        accessibility: screen,
        configuration: _configuration,
        isActive: () => true,
        isTikTok: () async => scenario != 'wrong-origin',
        isPageReady: () => true,
        now: tester.binding.clock.now,
        random: Random(4),
        getOtp: () async {
          requests++;
          return '012345';
        },
        onStatus: (_) {},
      );
      final failure = await _finish(tester, runner.run());
      expect(
        failure,
        scenario == 'rate-limit'
            ? isA<LoginAccessibilityRateLimited>()
            : isA<StateError>(),
      );
      expect(requests, 0);
      expect(
        screen.taps.where((t) => t == 'submit-password').length,
        lessThanOrEqualTo(1),
      );
      expect(
        screen.taps.where((t) => t == 'send-code').length,
        lessThanOrEqualTo(1),
      );
      if (scenario == 'disabled-submit') {
        expect(screen.taps, isNot(contains('submit-password')));
      }
      if (scenario == 'draft') expect(screen.pasted, isEmpty);
    });
  }

  testWidgets(
    'cancellation during a focus delay prevents paste and further gestures',
    (tester) async {
      final screen = _Screen();
      late LoginAccessibilityRunner runner;
      runner = LoginAccessibilityRunner(
        profile: LoginCoordinateProfile({}),
        accessibility: screen,
        configuration: _configuration,
        isActive: () => true,
        isTikTok: () async => true,
        isPageReady: () => true,
        getOtp: () async => throw StateError('Unexpected OTP'),
        onStatus: (_) {},
        now: tester.binding.clock.now,
      );
      screen.afterTap = (action) {
        if (action == 'focus-email') runner.cancel();
      };
      expect(
        await _finish(tester, runner.run()),
        isA<LoginAccessibilityCancelled>(),
      );
      expect(screen.pasted, isEmpty);
      expect(screen.taps.last, 'focus-email');
      expect(screen.cancelledPaste, isTrue);
    },
  );

  testWidgets('CAPTCHA during the mailbox wait stops before pasting OTP', (
    tester,
  ) async {
    final screen = _Screen();
    final response = Completer<String>();
    final runner = LoginAccessibilityRunner(
      profile: LoginCoordinateProfile({}),
      accessibility: screen,
      configuration: _configuration,
      isActive: () => true,
      isTikTok: () async => true,
      isPageReady: () => true,
      getOtp: () {
        screen.state = 'captcha';
        return response.future;
      },
      onStatus: (_) {},
      now: tester.binding.clock.now,
    );
    final error = await _finish(tester, runner.run());
    expect(error, isA<StateError>());
    expect(screen.pasted, ['email', 'password']);
    response.complete('012345');
    await tester.pump(const Duration(seconds: 1));
    expect(screen.pasted, ['email', 'password']);
  });

  for (final scenario in [
    'success',
    'background',
    'resend-success',
    'resend-timeout',
  ]) {
    final backgroundDuringOtp = scenario == 'background';
    final resends = scenario.startsWith('resend-');
    final succeeds = !backgroundDuringOtp && scenario != 'resend-timeout';
    testWidgets('Android controller uses plugin and OTP API: $scenario', (
      tester,
    ) async {
      debugDefaultTargetPlatformOverride = TargetPlatform.android;
      addTearDown(() => debugDefaultTargetPlatformOverride = null);
      const channel = MethodChannel('x-slayer/accessibility_channel');
      final screen = _Screen()..resendAvailable = resends;
      final calls = <String>[];
      final messenger =
          TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
      messenger.setMockMethodCallHandler(channel, (call) async {
        calls.add(call.method);
        switch (call.method) {
          case 'signupSnapshot':
            return screen.data();
          case 'dispatchGesture':
            final point = call.arguments['strokes'][0]['path'][0];
            await screen.tap(
              const SignupViewport(Rect.fromLTWH(0, 0, 400, 800)),
              Offset(
                (point['x'] as num).toDouble(),
                (point['y'] as num).toDouble(),
              ),
            );
            return true;
          case 'signupPasteFocused':
            return screen.paste(
              call.arguments['text'],
              call.arguments['field'],
            );
          case 'signupDismissKeyboard':
            await screen.dismissKeyboard();
            return true;
          default:
            return true;
        }
      });
      addTearDown(() => messenger.setMockMethodCallHandler(channel, null));
      final view = _WebView();
      final notices = <String>[];
      final reader = _Reader();
      final secondReader = _Reader();
      var readerCount = 0;
      final logic = TikTokController(
        configuration: AppConfiguration(
          userAgent: 'agent',
          comments: [],
          signupEmail: '',
          signupPassword: '',
          loginUsername: _configuration.loginUsername,
          loginPassword: _configuration.loginPassword,
          loginMailboxPassword: 'mail-password',
          otpApi: OtpApiConfiguration(
            url: Uri.parse('https://example.com/api/code'),
            readerToken: 'test-token',
          ),
        ),
        otpReaderFactory: (_) => readerCount++ == 0 ? reader : secondReader,
        loginProfileLoader: () async => LoginCoordinateProfile({}),
        nurtureProfileLoader: () async => NurtureCoordinateProfile({}),
        launchAction: TikTokLaunchAction.login,
        useAccessibility: true,
        now: tester.binding.clock.now,
      )..onInit();
      addTearDown(logic.onClose);
      logic.webViewController = InAppWebViewController.fromPlatform(
        platform: view,
      );
      logic.initialPageLoaded = true;
      logic.onNotice = (notice) => notices.add(notice.message);
      reader.onFetch = () {
        expectSync(screen.state, 'otp');
        if (backgroundDuringOtp) {
          logic.didChangeAppLifecycleState(AppLifecycleState.paused);
        } else if (resends) {
          reader.response.completeError(
            const OtpApiException('OTP timed out', timedOut: true),
          );
        } else {
          reader.response.complete('012345');
        }
      };
      secondReader.onFetch = () {
        expectSync(screen.taps.where((a) => a == 'resend'), hasLength(1));
        if (scenario == 'resend-timeout') {
          secondReader.response.completeError(
            const OtpApiException('OTP timed out again', timedOut: true),
          );
        } else {
          secondReader.response.complete('012345');
        }
      };
      expect(await _finish(tester, logic.autoLogin()), isNull);
      expect(reader.requests, [
        (_configuration.loginUsername, 'mail-password'),
      ]);
      expect(reader.closed, isTrue);
      expect(logic.loginOtpRequest, isNull);
      expect(logic.loginConfirmed, succeeds);
      expect(logic.autoLoginBusy, isFalse);
      expect(logic.autoWatchEnabled, succeeds);
      expect(readerCount, resends ? 2 : 1);
      expect(screen.taps.where((a) => a == 'resend').length, resends ? 1 : 0);
      if (resends) expect(secondReader.closed, isTrue);
      if (backgroundDuringOtp) {
        reader.response.complete('012345');
        await tester.pump(const Duration(seconds: 1));
        expect(screen.pasted, ['email', 'password']);
        expect(notices, isNot(contains('Đăng nhập TikTok thành công.')));
      } else if (succeeds) {
        expect(notices, contains('Đăng nhập TikTok thành công.'));
      } else {
        expect(notices.single, contains('đã gửi lại 1 lần'));
        expect(screen.pasted, ['email', 'password']);
      }
      expect(
        calls,
        containsAll([
          'signupSnapshot',
          'dispatchGesture',
          'signupPasteFocused',
          'signupDismissKeyboard',
        ]),
      );
      expect(
        view.sources.any(
          (s) =>
              s.contains(autoLoginStepScript) ||
              s.contains('__flutterAutoLogin'),
        ),
        isFalse,
      );
      expect(
        view.sources.any((s) => s.contains(autoWatchStartScript)),
        isFalse,
      );
      logic.onClose();
      debugDefaultTargetPlatformOverride = null;
    });
  }
}

Future<Object?> _finish(WidgetTester tester, Future<void> future) async {
  var done = false;
  Object? failure;
  final handled = future.then(
    (_) {
      done = true;
    },
    onError: (Object error) {
      failure = error;
      done = true;
    },
  );
  for (var i = 0; i < 900 && !done; i++) {
    await tester.pump(const Duration(milliseconds: 250));
  }
  expect(done, isTrue, reason: 'Login must finish within its bounded wait');
  await handled;
  return failure;
}

class _Screen extends SignupAccessibility {
  String state = 'home', focused = '';
  bool needsOtp = true, needsSend = false, acknowledgeSend = true;
  bool autoSubmitOtp = false, passwordStuck = false, rejectPaste = false;
  bool keyboard = false, cancelledPaste = false, disableSubmit = false;
  bool disableSend = false;
  bool resendAvailable = false, acknowledgeResend = true;
  final values = <String, String>{};
  final taps = <String>[], pasted = <String>[];
  final targets = <String, Rect>{};
  void Function(String)? afterTap;

  Map<String, dynamic> data() {
    targets.clear();
    final nodes = <Map<String, dynamic>>[];
    void node(
      String id,
      String text,
      double y, {
      bool editor = false,
      bool password = false,
      bool enabled = true,
      String hint = '',
      bool clickable = true,
    }) {
      final bounds = Rect.fromLTWH(100, y, 200, 30);
      targets[id] = bounds;
      nodes.add({
        'id': id,
        'text': text,
        'bounds': [100, y, 300, y + 30],
        'enabled': enabled,
        'clickable': clickable,
        'editable': editor,
        'password': password,
        'hint': hint,
        'focused': focused == id,
        'length': values[id]?.length ?? 0,
      });
    }

    switch (state) {
      case 'home':
        node('open-login', 'Log in', 20);
      case 'methods':
        node('title', 'Log in to TikTok', 100, clickable: false);
        node('phone-email', 'Use phone or email', 200, clickable: false);
      case 'phone':
        node('phone', '', 250, editor: true, hint: 'Phone number');
        node('use-email', 'Email / Username', 200, clickable: false);
      case 'form':
        node('title', 'Log in', 100, clickable: false);
        node('email', '', 200, editor: true, hint: 'Email or username');
        node(
          'password',
          '',
          300,
          editor: true,
          password: true,
          hint: 'Password',
        );
        node('submit-password', 'Log in', 400, enabled: !disableSubmit);
      case 'identity':
        node('title', 'Verify it’s really you', 100, clickable: false);
        node('select-email', 'Email [email]', 200, clickable: false);
      case 'otp':
        node('title', 'Enter 6-digit code', 100, clickable: false);
        node('otp', '', 200, editor: true, hint: '6-digit code');
        if (needsSend) {
          node('send-code', 'Send code', 300, enabled: !disableSend);
        } else {
          node(
            'resend',
            resendAvailable ? 'Resend code' : 'Resend code (45s)',
            300,
            enabled: resendAvailable,
          );
        }
        node('submit-otp', 'Next', 400);
      case 'authenticated':
        node('search', '', 50, editor: true, hint: 'Search');
        node('messages', 'Messages', 100);
        node('profile', 'Profile', 200);
      case 'captcha':
        node('captcha', 'Drag the slider to fit the puzzle', 100);
      case 'rate-limit':
        node('error', 'Maximum number of attempts reached', 100);
    }
    return {
      'ready': true,
      'webBounds': [0, 0, 400, 800],
      'keyboardVisible': keyboard,
      'nodes': nodes,
    };
  }

  @override
  Future<SignupSnapshot> snapshot() async => SignupSnapshot(data());
  @override
  Future<void> tap(SignupViewport viewport, Offset point) async {
    final action = targets.entries
        .firstWhere((entry) => entry.value.contains(viewport.toScreen(point)))
        .key;
    final isEditor = ['email', 'password', 'otp'].contains(action);
    taps.add(isEditor ? 'focus-$action' : action);
    if (isEditor) {
      focused = action;
      keyboard = true;
    }
    state = switch (action) {
      'open-login' => 'methods',
      'phone-email' => 'phone',
      'use-email' => 'form',
      'submit-password' =>
        passwordStuck
            ? 'form'
            : needsOtp
            ? 'identity'
            : 'authenticated',
      'select-email' => 'otp',
      'submit-otp' => 'authenticated',
      _ => state,
    };
    if (action == 'send-code' && acknowledgeSend) needsSend = false;
    if (action == 'resend' && acknowledgeResend) resendAvailable = false;
    afterTap?.call(isEditor ? 'focus-$action' : action);
  }

  @override
  Future<Map<String, dynamic>> paste(String text, String field) async {
    pasted.add(field);
    if (rejectPaste) return {'ok': false, 'reason': 'paste-rejected'};
    values[field] = text;
    if (field == 'otp' && autoSubmitOtp) state = 'authenticated';
    return {'ok': true};
  }

  @override
  Future<void> dismissKeyboard() async {
    keyboard = false;
  }

  @override
  Future<void> cancelPaste() async {
    cancelledPaste = true;
  }
}

class _WebView extends PlatformInAppWebViewController {
  _WebView()
    : super.implementation(
        const PlatformInAppWebViewControllerCreationParams(id: 77),
      );
  final sources = <String>[];
  @override
  Future<WebUri?> getUrl() async => WebUri('https://www.tiktok.com/');
  @override
  Future<dynamic> evaluateJavascript({
    required String source,
    ContentWorld? contentWorld,
  }) async {
    sources.add(source);
    return true;
  }
}

class _Reader implements OtpCodeReader {
  final response = Completer<String>();
  final requests = <(String, String)>[];
  void Function()? onFetch;
  bool closed = false;
  @override
  Future<String> fetchCode({required String email, required String password}) {
    requests.add((email, password));
    onFetch?.call();
    return response.future;
  }

  @override
  void close() {
    closed = true;
  }
}

class _LiveRecording extends SignupAccessibility {
  final recording =
      jsonDecode(
            File(
              'test/fixtures/login_accessibility_recording.json',
            ).readAsStringSync(),
          )
          as Map;
  final rawProfile =
      jsonDecode(
            File('assets/login-coordinate-profile.json').readAsStringSync(),
          )
          as Map;
  String stage = 'home', focused = '';
  final values = <String, String>{};
  final actions = <String>[];
  void Function()? onSubmit;

  @override
  Future<SignupSnapshot> snapshot() async {
    final data = Map<String, dynamic>.from(
      jsonDecode(jsonEncode(recording[stage])) as Map,
    );
    for (final node in data['nodes'] as List) {
      // Chromium renumbers the complete tree when the IME changes windows.
      if (focused.isNotEmpty) node['id'] = 'renumbered.${node['id']}';
      if (node['editable'] == true && node['hint'] != 'Search') {
        final field = node['password'] == true
            ? 'password'
            : '${node['hint']}'.contains('code')
            ? 'otp'
            : 'email';
        node['length'] = values[field]?.length ?? 0;
        node['focused'] = focused == field;
      }
      if (node['text'] == 'Continue') {
        node['enabled'] =
            values.containsKey('email') && values.containsKey('password');
      }
      if (node['text'] == 'Next') node['enabled'] = values['otp']?.length == 6;
    }
    return SignupSnapshot(data);
  }

  @override
  Future<void> tap(SignupViewport viewport, Offset point) async {
    final points = Map<String, dynamic>.from(rawProfile['points'] as Map);
    final action = points.entries
        .firstWhere(
          (entry) =>
              (point -
                      Offset(
                        (entry.value[0] as num).toDouble(),
                        (entry.value[1] as num).toDouble(),
                      ))
                  .distance <
              0.01,
        )
        .key;
    actions.add(action);
    stage = switch (action) {
      'open-login' => 'methods',
      'phone-email' => 'phone',
      'use-email' => 'form',
      'submit-password' => 'identity',
      'select-verification-email' => 'otp',
      'submit-otp' => 'authenticated',
      _ => stage,
    };
    if (action.startsWith('focus-')) focused = action.substring(6);
    if (action == 'submit-password') onSubmit?.call();
  }

  @override
  Future<Map<String, dynamic>> paste(String text, String field) async {
    values[field] = text;
    actions.add('paste-$field');
    return {'ok': true};
  }

  @override
  Future<void> cancelPaste() async {}
}
