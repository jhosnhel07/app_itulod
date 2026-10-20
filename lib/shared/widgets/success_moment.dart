import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../core/constants/app_colors.dart';
import '../../core/constants/app_typography.dart';
import 'app_button.dart';

/// A short animated check for the big wins (booking placed, trip completed) —
/// the app twin of the web's celebrate() in js/utils.js. Closes on OK, on a
/// tap outside, or by itself after a few seconds. Completes when it closes,
/// so callers can await it before leaving the screen.
Future<void> showSuccessMoment(
  BuildContext context, {
  required String title,
  String? message,
}) {
  final navigator = Navigator.of(context, rootNavigator: true);
  var open = true;
  final timer = Timer(Duration(milliseconds: message == null ? 3200 : 5200), () {
    if (open && navigator.mounted) navigator.pop();
  });
  return showGeneralDialog<void>(
    context: navigator.context,
    barrierDismissible: true,
    barrierLabel: 'Close',
    barrierColor: const Color(0x730A121C),
    transitionDuration: const Duration(milliseconds: 220),
    pageBuilder: (_, __, ___) => _SuccessCard(title: title, message: message),
    transitionBuilder: (_, anim, __, child) {
      final curved = CurvedAnimation(parent: anim, curve: Curves.easeOutBack);
      return FadeTransition(
        opacity: anim,
        child: ScaleTransition(scale: Tween(begin: 0.9, end: 1.0).animate(curved), child: child),
      );
    },
  ).whenComplete(() {
    open = false;
    timer.cancel();
  });
}

class _SuccessCard extends StatelessWidget {
  final String title;
  final String? message;

  const _SuccessCard({required this.title, this.message});

  @override
  Widget build(BuildContext context) {
    final still = MediaQuery.of(context).disableAnimations;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Material(
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(20),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 340),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(24, 28, 24, 20),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  TweenAnimationBuilder<double>(
                    tween: Tween(begin: still ? 1 : 0, end: 1),
                    duration: const Duration(milliseconds: 900),
                    builder: (_, t, __) => CustomPaint(
                      size: const Size(76, 76),
                      painter: _CheckPainter(t),
                    ),
                  ),
                  const SizedBox(height: 12),
                  Text(title, style: AppTypography.h3, textAlign: TextAlign.center),
                  if (message != null) ...[
                    const SizedBox(height: 6),
                    Text(
                      message!,
                      style: AppTypography.body.copyWith(color: AppColors.neutral500, height: 1.5),
                      textAlign: TextAlign.center,
                    ),
                  ],
                  const SizedBox(height: 16),
                  AppButton(
                    text: 'OK',
                    width: 140,
                    height: 44,
                    onPressed: () => Navigator.of(context).pop(),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Draws the ring (first ~55% of [t]) then the tick (the rest).
class _CheckPainter extends CustomPainter {
  final double t;
  _CheckPainter(this.t);

  @override
  void paint(Canvas canvas, Size size) {
    final s = size.width / 52;
    final ring = (t / 0.55).clamp(0.0, 1.0);
    final tick = ((t - 0.6) / 0.4).clamp(0.0, 1.0);
    final paint = Paint()
      ..color = AppColors.success
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;

    canvas.drawArc(
      Rect.fromCircle(center: Offset(26 * s, 26 * s), radius: 24 * s),
      -math.pi / 2,
      2 * math.pi * ring,
      false,
      paint..strokeWidth = 3 * s,
    );

    if (tick > 0) {
      final path = Path()
        ..moveTo(15 * s, 27 * s)
        ..lineTo(22 * s, 34 * s)
        ..lineTo(37 * s, 18 * s);
      final metric = path.computeMetrics().first;
      canvas.drawPath(metric.extractPath(0, metric.length * tick), paint..strokeWidth = 4 * s);
    }
  }

  @override
  bool shouldRepaint(_CheckPainter old) => old.t != t;
}
