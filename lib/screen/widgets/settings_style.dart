import 'package:flutter/material.dart';

import '../../core/app_action_theme.dart';

abstract final class SettingsStyle {
  static const background = Color(0xFF0B101B);
  static const surface = Color(0xFF141C2A);
  static const input = Color(0xFF0F1623);
  static const border = Color(0xFF283346);
  static const muted = Color(0xFFA0AEC0);
  static const primary = AppActionTheme.primary;

  static ThemeData theme(BuildContext context) {
    final base = Theme.of(context);
    final shape = RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(14),
    );
    return AppActionTheme.apply(
      base.copyWith(
        brightness: Brightness.dark,
        scaffoldBackgroundColor: background,
        colorScheme: ColorScheme.fromSeed(
          seedColor: primary,
          brightness: Brightness.dark,
          surface: surface,
        ),
        appBarTheme: const AppBarTheme(
          backgroundColor: background,
          foregroundColor: Colors.white,
          surfaceTintColor: Colors.transparent,
        ),
        inputDecorationTheme: InputDecorationTheme(
          filled: true,
          fillColor: input,
          labelStyle: const TextStyle(color: muted),
          hintStyle: const TextStyle(color: Color(0xFF718096)),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(14),
            borderSide: const BorderSide(color: border),
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(14),
            borderSide: const BorderSide(color: border),
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(14),
            borderSide: const BorderSide(color: primary, width: 1.5),
          ),
        ),
        filledButtonTheme: FilledButtonThemeData(
          style: FilledButton.styleFrom(
            minimumSize: const Size(0, 52),
            shape: shape,
            textStyle: const TextStyle(fontWeight: FontWeight.w700),
          ),
        ),
        outlinedButtonTheme: OutlinedButtonThemeData(
          style: OutlinedButton.styleFrom(
            minimumSize: const Size(0, 50),
            shape: shape,
            side: const BorderSide(color: border),
            foregroundColor: const Color(0xFFDBE4F0),
            textStyle: const TextStyle(fontWeight: FontWeight.w700),
          ),
        ),
      ),
    );
  }
}

class SettingsPanel extends StatelessWidget {
  const SettingsPanel({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.all(20),
    decoration: BoxDecoration(
      color: SettingsStyle.surface,
      borderRadius: BorderRadius.circular(20),
      border: Border.all(color: SettingsStyle.border),
    ),
    child: child,
  );
}
