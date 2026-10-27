import 'dart:convert';

import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'signup_accessibility.dart';

/// Recorded design coordinates, reused across attempts and app restarts.
/// Existing points are never overwritten. When the live control no longer
/// covers one (another device, font or TikTok layout), the control's own
/// Accessibility bounds decide where to tap.
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
  /// Points recorded in the desktop frame are kept apart from the 1:2
  /// frame's: the two design spaces do not share coordinates.
  static String key(String action, {required bool desktop}) =>
      desktop ? 'desktop/$action' : action;
  Offset? point(String action, {bool desktop = false}) =>
      _points[key(action, desktop: desktop)];
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
    final name = key(action, desktop: viewport.landscape);
    final existing = _points[name];
    if (existing != null) return viewport.tapPoint(node.bounds, existing);
    // Validates the design range and viewport before saving.
    final point = viewport.tapPoint(node.bounds);
    final rounded = Offset(
      double.parse(point.dx.toStringAsFixed(2)),
      double.parse(point.dy.toStringAsFixed(2)),
    );
    if (!node.bounds.contains(viewport.toScreen(rounded))) {
      throw StateError('Control $label quá nhỏ để ghi tọa độ $action.');
    }
    final updated = {
      ...points,
      name: [rounded.dx, rounded.dy],
    };
    await save?.call(updated); // Persistence must finish before the first tap.
    _points[name] = rounded;
    return rounded;
  }
}
