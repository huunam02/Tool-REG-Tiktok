import 'dart:convert';

import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'login_coordinate_profile.dart';
import 'signup_accessibility.dart';

/// Each video orientation/layout retains its own immutable recorded points.
class NurtureCoordinateProfile extends LoginCoordinateProfile {
  NurtureCoordinateProfile(super.points, {super.save})
    : super(label: 'nuôi tài khoản');

  static const storageKey = 'nurture_coordinate_profile_v1';

  static String panelKey(
    String orientation,
    String action,
    SignupViewport viewport,
    SignupNode node,
  ) {
    final a = viewport.fromScreen(node.bounds.topLeft);
    final b = viewport.fromScreen(node.bounds.bottomRight);
    return '$orientation/panel/$action/${a.dx.round()}-${a.dy.round()}-${b.dx.round()}-${b.dy.round()}';
  }

  static Future<NurtureCoordinateProfile> load() async {
    final asset =
        jsonDecode(
              await rootBundle.loadString(
                'assets/nurture-coordinate-profile.json',
              ),
            )
            as Map;
    final preferences = await SharedPreferences.getInstance();
    final saved = preferences.getString(storageKey);
    final points = <String, dynamic>{
      ...Map<String, dynamic>.from(asset['points'] as Map),
      if (saved != null) ...Map<String, dynamic>.from(jsonDecode(saved) as Map),
    };
    return NurtureCoordinateProfile(
      {
        for (final entry in points.entries)
          if (!(entry.key.contains('/panel/') &&
              entry.key.split('/').length == 3))
            entry.key: Offset(
              (entry.value[0] as num).toDouble(),
              (entry.value[1] as num).toDouble(),
            ),
      },
      save: (value) async {
        if (!await preferences.setString(storageKey, jsonEncode(value))) {
          throw StateError(
            'Không lưu được tọa độ nuôi; đã dừng trước khi bấm.',
          );
        }
      },
    );
  }
}
