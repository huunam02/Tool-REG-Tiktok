import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';

import '../../core/signup_accessibility.dart';

/// PlatformView gets real layout dimensions; no Transform/FittedBox is applied.
class StandardSignupViewport extends StatelessWidget {
  const StandardSignupViewport({super.key, required this.child});
  final Widget child;
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
