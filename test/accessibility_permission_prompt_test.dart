import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:test_tiktok/screen/widgets/accessibility_permission_prompt.dart';

void main() {
  testWidgets('prompts on startup and dismisses only after settings grant',
      (tester) async {
    var enabled = false;
    var requests = 0;
    await tester.pumpWidget(MaterialApp(
        home: AccessibilityPermissionPrompt(
      isEnabled: () async => enabled,
      requestPermission: () async {
        requests++;
        enabled = true;
        return true;
      },
      child: const Scaffold(body: Text('Home')),
    )));
    await tester.pumpAndSettle();
    expect(find.text('Bật quyền Trợ năng'), findsOneWidget);
    expect(requests, 0);
    await tester.tap(find.byKey(const Key('openAccessibilitySettings')));
    await tester.pumpAndSettle();
    expect(requests, 1);
    expect(
        find.byKey(const Key('accessibilityPermissionDialog')), findsNothing);
    expect(find.text('Home'), findsOneWidget);
  });

  testWidgets('does not prompt if the Android service is already enabled',
      (tester) async {
    var requests = 0;
    await tester.pumpWidget(MaterialApp(
        home: AccessibilityPermissionPrompt(
      isEnabled: () async => true,
      requestPermission: () async {
        requests++;
        return true;
      },
      child: const Scaffold(body: Text('Home')),
    )));
    await tester.pumpAndSettle();
    expect(find.byType(AlertDialog), findsNothing);
    expect(requests, 0);
  });

  testWidgets(
      'keeps instructions if returning without permission; allows postponing',
      (tester) async {
    await tester.pumpWidget(MaterialApp(
        home: AccessibilityPermissionPrompt(
      isEnabled: () async => false,
      requestPermission: () async => false,
      child: const Scaffold(body: Text('Home')),
    )));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('openAccessibilitySettings')));
    await tester.pumpAndSettle();
    expect(find.textContaining('Quyền Trợ năng chưa được bật'), findsOneWidget);
    await tester.tap(find.text('Để sau'));
    await tester.pumpAndSettle();
    expect(find.byType(AlertDialog), findsNothing);
    await tester.pump();
    expect(find.byType(AlertDialog), findsNothing);
  });
}
