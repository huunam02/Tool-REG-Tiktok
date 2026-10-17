import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';

import '../../core/signup_accessibility.dart';

/// PlatformView gets real layout dimensions; no Transform/FittedBox is applied.
class StandardSignupViewport extends StatelessWidget {
  const StandardSignupViewport({super.key, required this.child, this.onWidth});
  final Widget child;

  /// Frame width in logical pixels (= Android dp), reported before the
  /// WebView is created so its CSS scale matches the frame, not the screen.
  final ValueChanged<double>? onWidth;
  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      return ScreenUtilInit(
        designSize: signupDesignSize,
        enableScaleText: () => false,
        builder: (context, _) {
          final scale = math.min(
            ScreenUtil().scaleWidth,
            math.min(constraints.maxWidth / 400, constraints.maxHeight / 800),
          );
          onWidth?.call(400 * scale);
          return ColoredBox(
            color: Colors.black,
            child: Center(
              child: SizedBox(
                key: const Key('standardSignupViewport'),
                width: 400 * scale,
                height: 800 * scale,
                child: child,
              ),
            ),
          );
        },
      );
    },
  );
}
