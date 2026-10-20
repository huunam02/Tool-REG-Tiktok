import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:test_tiktok/screen/widgets/accessibility_permission_prompt.dart';

void main() {
  testWidgets('prompts on startup and dismisses only after settings grant', (
    tester,
  ) async {
    var enabled = false;
    var requests = 0;
    await tester.pumpWidget(
      MaterialApp(
        home: AccessibilityPermissionPrompt(
          isEnabled: () async => enabled,
          requestPermission: () async {
            requests++;
            enabled = true;
            return true;
          },
          child: const Scaffold(body: Text('Home')),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Bật quyền Trợ năng'), findsOneWidget);
    expect(requests, 0);
    await tester.tap(find.byKey(const Key('openAccessibilitySettings')));
    await tester.pumpAndSettle();
    expect(requests, 1);
    expect(
      find.byKey(const Key('accessibilityPermissionDialog')),
      findsNothing,
    );
    expect(find.text('Home'), findsOneWidget);
  });

  testWidgets('does not prompt if the Android service is already enabled', (
    tester,
  ) async {
    var requests = 0;
    await tester.pumpWidget(
      MaterialApp(
        home: AccessibilityPermissionPrompt(
          isEnabled: () async => true,
          requestPermission: () async {
            requests++;
            return true;
          },
          child: const Scaffold(body: Text('Home')),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.byType(AlertDialog), findsNothing);
    expect(requests, 0);
  });

  testWidgets('does not request permission when the startup check fails', (
    tester,
  ) async {
    var requests = 0;
    await tester.pumpWidget(
      MaterialApp(
        home: AccessibilityPermissionPrompt(
          isEnabled: () async => throw StateError('channel not ready'),
          requestPermission: () async {
            requests++;
            return true;
          },
          child: const Scaffold(body: Text('Home')),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.byType(AlertDialog), findsNothing);
    expect(requests, 0);
    expect(find.text('Home'), findsOneWidget);
  });

  testWidgets(
    'manual check reports unknown status without saying permission is off',
    (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (context) => Scaffold(
              body: TextButton(
                onPressed: () => showAccessibilityPermissionDialog(
                  context,
                  isEnabled: () async => throw StateError('channel not ready'),
                  requestPermission: () async => false,
                ),
                child: const Text('Check'),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('Check'));
      await tester.pumpAndSettle();
      expect(find.text('Kiểm tra quyền Trợ năng'), findsOneWidget);
      expect(find.text('Bật quyền Trợ năng'), findsNothing);
      expect(
        find.byKey(const Key('openAccessibilitySettings')),
        findsOneWidget,
      );
    },
  );

  testWidgets('fresh startup checks the existing grant again', (tester) async {
    var enabled = false;
    Widget app() => MaterialApp(
      home: AccessibilityPermissionPrompt(
        isEnabled: () async => enabled,
        requestPermission: () async {
          enabled = true;
          return true;
        },
        child: const Scaffold(body: Text('Home')),
      ),
    );
    await tester.pumpWidget(app());
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('openAccessibilitySettings')));
    await tester.pumpAndSettle();
    await tester.pumpWidget(const SizedBox());
    await tester.pumpWidget(app());
    await tester.pumpAndSettle();
    expect(find.byType(AlertDialog), findsNothing);
  });

  testWidgets(
    'keeps instructions if returning without permission; allows postponing',
    (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: AccessibilityPermissionPrompt(
            isEnabled: () async => false,
            requestPermission: () async => false,
            child: const Scaffold(body: Text('Home')),
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('openAccessibilitySettings')));
      await tester.pumpAndSettle();
      expect(
        find.textContaining('Quyền Trợ năng chưa được bật'),
        findsOneWidget,
      );
      await tester.tap(find.text('Để sau'));
      await tester.pumpAndSettle();
      expect(find.byType(AlertDialog), findsNothing);
      await tester.pump();
      expect(find.byType(AlertDialog), findsNothing);
    },
  );
}
