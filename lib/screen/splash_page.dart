import 'package:flutter/material.dart';

import '../core/app_action_theme.dart';

class SplashPage extends StatelessWidget {
  const SplashPage({
    super.key,
    required this.loading,
    required this.failed,
    required this.onRetry,
  });

  final bool loading;
  final bool failed;
  final VoidCallback onRetry;

  static const _background = Color(0xFF0B101B);
  static const _surface = Color(0xFF141C2A);
  static const _border = Color(0xFF283346);
  static const _muted = Color(0xFFA0AEC0);

  @override
  Widget build(BuildContext context) => Scaffold(
    key: const Key('splashPage'),
    backgroundColor: _background,
    body: Stack(
      fit: StackFit.expand,
      children: [
        const _SplashBackground(),
        SafeArea(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 28),
            child: Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 420),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    const _Brand(),
                    const SizedBox(height: 56),
                    AnimatedSwitcher(
                      duration: const Duration(milliseconds: 220),
                      child: failed
                          ? _Failure(onRetry: onRetry, loading: loading)
                          : const _Loading(),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
        const Positioned(
          left: 24,
          right: 24,
          bottom: 24,
          child: SafeArea(
            top: false,
            child: Text(
              'QUẢN LÝ TIKTOK',
              textAlign: TextAlign.center,
              style: TextStyle(
                color: Color(0xFF657287),
                fontSize: 10,
                fontWeight: FontWeight.w700,
                letterSpacing: 2.2,
              ),
            ),
          ),
        ),
      ],
    ),
  );
}

class _Brand extends StatelessWidget {
  const _Brand();

  @override
  Widget build(BuildContext context) => Column(
    children: [
      Container(
        width: 112,
        height: 112,
        padding: const EdgeInsets.all(7),
        decoration: BoxDecoration(
          color: SplashPage._surface,
          borderRadius: BorderRadius.circular(30),
          border: Border.all(
            color: AppActionTheme.primary.withValues(alpha: 0.34),
          ),
          boxShadow: [
            BoxShadow(
              color: AppActionTheme.primary.withValues(alpha: 0.13),
              blurRadius: 40,
              spreadRadius: 4,
            ),
          ],
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(23),
          child: Image.asset('assets/logo.png', fit: BoxFit.cover),
        ),
      ),
      const SizedBox(height: 24),
      const Text(
        'Tool TikTok',
        textAlign: TextAlign.center,
        style: TextStyle(
          color: Colors.white,
          fontSize: 30,
          fontWeight: FontWeight.w800,
          letterSpacing: -0.7,
        ),
      ),
      const SizedBox(height: 8),
      const Text(
        'Quản lý tác vụ và kết nối proxy',
        textAlign: TextAlign.center,
        style: TextStyle(color: SplashPage._muted, fontSize: 13, height: 1.5),
      ),
    ],
  );
}

class _Loading extends StatelessWidget {
  const _Loading();

  @override
  Widget build(BuildContext context) => const Column(
    key: Key('splashLoading'),
    children: [
      SizedBox(
        width: 28,
        height: 28,
        child: CircularProgressIndicator(
          strokeWidth: 2.6,
          color: AppActionTheme.primary,
          backgroundColor: SplashPage._border,
        ),
      ),
      SizedBox(height: 16),
      Text(
        'Đang tải cấu hình…',
        textAlign: TextAlign.center,
        style: TextStyle(color: SplashPage._muted, fontSize: 12),
      ),
    ],
  );
}

class _Failure extends StatelessWidget {
  const _Failure({required this.onRetry, required this.loading});

  final VoidCallback onRetry;
  final bool loading;

  @override
  Widget build(BuildContext context) => Container(
    key: const Key('splashFailure'),
    padding: const EdgeInsets.all(20),
    decoration: BoxDecoration(
      color: SplashPage._surface,
      borderRadius: BorderRadius.circular(18),
      border: Border.all(color: SplashPage._border),
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const Text(
          'Không thể tải cấu hình ứng dụng. Hãy thử lại.',
          textAlign: TextAlign.center,
          style: TextStyle(color: Colors.white, height: 1.5),
        ),
        const SizedBox(height: 16),
        FilledButton(
          key: const Key('retryStartup'),
          onPressed: loading ? null : onRetry,
          child: Text(loading ? 'Đang thử lại…' : 'Thử lại'),
        ),
      ],
    ),
  );
}

class _SplashBackground extends StatelessWidget {
  const _SplashBackground();

  @override
  Widget build(BuildContext context) => DecoratedBox(
    decoration: const BoxDecoration(
      gradient: RadialGradient(
        center: Alignment(0, -0.45),
        radius: 1.15,
        colors: [Color(0xFF123139), SplashPage._background],
        stops: [0, 0.72],
      ),
    ),
    child: CustomPaint(painter: _GridPainter()),
  );
}

class _GridPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    const gap = 36.0;
    final paint = Paint()
      ..color = Colors.white.withValues(alpha: 0.025)
      ..strokeWidth = 1;
    for (var x = 0.0; x <= size.width; x += gap) {
      canvas.drawLine(Offset(x, 0), Offset(x, size.height), paint);
    }
    for (var y = 0.0; y <= size.height; y += gap) {
      canvas.drawLine(Offset(0, y), Offset(size.width, y), paint);
    }
  }

  @override
  bool shouldRepaint(covariant _GridPainter oldDelegate) => false;
}
