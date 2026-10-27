import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';

import '../../core/signup_accessibility.dart';

/// PlatformView gets real layout dimensions; no Transform/FittedBox is applied.
class StandardSignupViewport extends StatelessWidget {
  const StandardSignupViewport({
    super.key,
    required this.child,
    this.onWidth,
    this.landscape = false,
  });
  final Widget child;

  /// A desktop-shaped frame ([signupLandscapeDesignSize]) instead of 1:2.
  final bool landscape;

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
          if (landscape) return _desktopFrame(context, constraints);
          final fit = math.min(
            constraints.maxWidth / signupDesignSize.width,
            constraints.maxHeight / signupDesignSize.height,
          );
          final scale = math.min(ScreenUtil().scaleWidth, fit);
          onWidth?.call(signupDesignSize.width * scale);
          return ColoredBox(
            color: Colors.black,
            child: Center(
              child: SizedBox(
                key: const Key('standardSignupViewport'),
                width: signupDesignSize.width * scale,
                height: signupDesignSize.height * scale,
                child: child,
              ),
            ),
          );
        },
      );
    },
  );

  /// Whole device pixels in size and offset. The frame must use its measured
  /// dimensions: adding compensation pixels makes Gecko expose 1921 x 956
  /// instead of the desktop design's 1920 x 955 on Android 9.
  Widget _desktopFrame(BuildContext context, BoxConstraints constraints) {
    final ratio = MediaQuery.devicePixelRatioOf(context);
    final design = signupLandscapeDesignSize;
    final maxWidth = math.min(
      constraints.maxWidth,
      constraints.maxHeight * design.width / design.height,
    );
    final width = desktopFramePixels(maxWidth, ratio);
    final height = (width * design.height / design.width).round();
    final left = ((constraints.maxWidth * ratio - width) / 2).floor();
    final top = ((constraints.maxHeight * ratio - height) / 2).floor();
    onWidth?.call(width / ratio);
    return ColoredBox(
      color: Colors.black,
      child: Stack(
        children: [
          Positioned(
            left: left / ratio,
            top: top / ratio,
            width: width / ratio,
            height: height / ratio,
            child: KeyedSubtree(
              key: const Key('standardSignupViewport'),
              child: child,
            ),
          ),
        ],
      ),
    );
  }
}

/// Maximized Firefox page width on a 1920 x 1080 screen, in CSS px.
const desktopCssWidth = 1920;

/// Gecko keeps a whole number of app units (60 per CSS px) per device pixel,
/// so the page is exactly [desktopCssWidth] wide only for frame widths of
/// 1920 * 60 / n device pixels. Prefers 1920 px (1 dppx, the desktop's
/// scale), else the widest such frame within [maxWidth] (logical).
int desktopFramePixels(double maxWidth, double devicePixelRatio) {
  final maxPixels = (maxWidth * devicePixelRatio).floor();
  const preferred = desktopCssWidth;
  if (preferred <= maxPixels) return preferred;
  for (var units = 1; units <= 600; units++) {
    if (desktopCssWidth * 60 % units != 0) continue;
    final pixels = desktopCssWidth * 60 ~/ units;
    if (pixels <= maxPixels) return pixels;
  }
  return maxPixels;
}
