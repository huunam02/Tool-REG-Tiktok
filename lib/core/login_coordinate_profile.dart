import 'dart:convert';

import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'signup_accessibility.dart';

/// Recorded design coordinates, reused across attempts and app restarts.
/// Existing points are never silently moved when TikTok changes its layout.
class LoginCoordinateProfile {
  LoginCoordinateProfile(
    Map<String, Offset> points, {
    this.save,
    this.label = 'đăng nhập',
  }) : _points = Map.of(points);

  static const storageKey = 'login_coordinate_profile_v1';
  final Map<String, Offset> _points;
  final String label;
  final Future<void> Function(Map<String, List<double>>)? save;
  Offset? point(String action) => _points[action];
  Map<String, List<double>> get points => {
    for (final entry in _points.entries)
      entry.key: [entry.value.dx, entry.value.dy],
  };

  static Future<LoginCoordinateProfile> load() async {
    final asset =
        jsonDecode(
              await rootBundle.loadString(
                'assets/login-coordinate-profile.json',
              ),
            )
            as Map;
    final preferences = await SharedPreferences.getInstance();
    final recorded = preferences.getString(storageKey);
    final merged = <String, dynamic>{
      ...Map<String, dynamic>.from(asset['points'] as Map),
      if (recorded != null)
        ...Map<String, dynamic>.from(jsonDecode(recorded) as Map),
    };
    return LoginCoordinateProfile(
      {
        for (final entry in merged.entries)
          entry.key: Offset(
            (entry.value[0] as num).toDouble(),
            (entry.value[1] as num).toDouble(),
          ),
      },
      save: (points) async {
        if (!await preferences.setString(storageKey, jsonEncode(points))) {
          throw StateError(
            'Không lưu được tọa độ đăng nhập; đã dừng trước khi bấm.',
          );
        }
      },
    );
  }

  Future<Offset> target(
    String action,
    SignupViewport viewport,
    SignupNode node,
  ) async {
    final existing = _points[action];
    if (existing != null) {
      if (!node.bounds.contains(viewport.toScreen(existing))) {
        throw StateError(
          'Tọa độ $label bước $action không còn trúng control. Cần ghi mẫu lại.',
        );
      }
      return existing;
    }
    final point = viewport.fromScreen(node.bounds.center);
    viewport.toScreen(
      point,
    ); // Validate design range and viewport before saving.
    final rounded = Offset(
      double.parse(point.dx.toStringAsFixed(2)),
      double.parse(point.dy.toStringAsFixed(2)),
    );
    if (!node.bounds.contains(viewport.toScreen(rounded))) {
      throw StateError('Control $label quá nhỏ để ghi tọa độ $action.');
    }
    final updated = {
      ...points,
      action: [rounded.dx, rounded.dy],
    };
    await save?.call(updated); // Persistence must finish before the first tap.
    _points[action] = rounded;
    return rounded;
  }
}
