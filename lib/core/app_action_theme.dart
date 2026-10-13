import 'package:flutter/material.dart';

abstract final class AppActionTheme {
  static const primary = Color(0xFF47E4DE);
  static const onPrimary = Color(0xFF0B101B);

  static ThemeData apply(ThemeData base) => base.copyWith(
        colorScheme: base.colorScheme.copyWith(
            primary: primary,
            onPrimary: onPrimary,
            secondary: primary,
            onSecondary: onPrimary),
        filledButtonTheme: FilledButtonThemeData(
            style: (base.filledButtonTheme.style ?? const ButtonStyle()).merge(
                FilledButton.styleFrom(
                    backgroundColor: primary, foregroundColor: onPrimary))),
        outlinedButtonTheme: OutlinedButtonThemeData(
            style: (base.outlinedButtonTheme.style ?? const ButtonStyle())
                .merge(OutlinedButton.styleFrom(foregroundColor: primary))
                .copyWith(
                    side: WidgetStateProperty.resolveWith((states) =>
                        BorderSide(
                            color: states.contains(WidgetState.disabled)
                                ? base.colorScheme.onSurface
                                    .withValues(alpha: 0.12)
                                : primary)))),
        textButtonTheme: TextButtonThemeData(
            style: (base.textButtonTheme.style ?? const ButtonStyle())
                .merge(TextButton.styleFrom(foregroundColor: primary))),
        floatingActionButtonTheme: base.floatingActionButtonTheme
            .copyWith(backgroundColor: primary, foregroundColor: onPrimary),
        snackBarTheme: base.snackBarTheme.copyWith(actionTextColor: primary),
      );
}
