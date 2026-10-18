import 'dart:math' as math;
import 'package:flutter/material.dart';
import '../../core/constants/app_colors.dart';

/// Decorative Ilocos Norte strip — Bangui windmills turning on the hills and a
/// delivery rider riding along the road. The app twin of the web landing
/// page's hero scene. Static when the device asks for reduced motion.
class IlocosScene extends StatefulWidget {
  final double height;
  const IlocosScene({super.key, this.height = 130});

  @override
  State<IlocosScene> createState() => _IlocosSceneState();
}

class _IlocosSceneState extends State<IlocosScene> with SingleTickerProviderStateMixin {
  late final AnimationController _c =
      AnimationController(vsync: this, duration: const Duration(seconds: 22));

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (MediaQuery.of(context).disableAnimations) {
      _c.stop();
      _c.value = 0.35;
    } else if (!_c.isAnimating) {
      _c.repeat();
    }
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: SizedBox(
        height: widget.height,
        width: double.infinity,
        child: RepaintBoundary(
          child: AnimatedBuilder(
            animation: _c,
            builder: (_, __) => CustomPaint(
              painter: _ScenePainter(
                t: _c.value,
                hill: AppColors.primary100,
                ground: AppColors.surface,
                road: AppColors.primaryDark,
                bladeStroke: AppColors.primary100,
                hub: AppColors.primary,
                riderBody: AppColors.primary,
                riderInk: AppColors.primaryDark,
                box: AppColors.secondaryLight,
                wheel: AppColors.neutral800,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _ScenePainter extends CustomPainter {
  final double t;
  final Color hill, ground, road, bladeStroke, hub, riderBody, riderInk, box, wheel;

  _ScenePainter({
    required this.t,
    required this.hill,
    required this.ground,
    required this.road,
    required this.bladeStroke,
    required this.hub,
    required this.riderBody,
    required this.riderInk,
    required this.box,
    required this.wheel,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width, h = size.height;

    // Far hills
    final hills = Path()
      ..moveTo(0, h * 0.62)
      ..cubicTo(w * 0.18, h * 0.44, w * 0.32, h * 0.52, w * 0.48, h * 0.58)
      ..cubicTo(w * 0.64, h * 0.45, w * 0.82, h * 0.42, w, h * 0.55)
      ..lineTo(w, h)
      ..lineTo(0, h)
      ..close();
    canvas.drawPath(hills, Paint()..color = hill.withValues(alpha: 0.32));

    // Windmills along the ridge: (x fraction, hub y fraction, scale, speed)
    const mills = [
      (0.08, 0.30, 0.8, 1.0),
      (0.20, 0.38, 0.65, 0.8),
      (0.70, 0.26, 0.9, 1.15),
      (0.82, 0.34, 0.72, 0.9),
      (0.94, 0.30, 0.8, 1.05),
    ];
    final towerFill = Paint()..color = Colors.white;
    final stroke = Paint()
      ..color = bladeStroke
      ..style = PaintingStyle.stroke
      ..strokeWidth = 0.8;
    for (final (fx, fy, s, speed) in mills) {
      final cx = w * fx, cy = h * fy, len = 30.0 * s;
      final tower = Path()
        ..moveTo(cx - 1.2 * s, cy)
        ..lineTo(cx + 1.2 * s, cy)
        ..lineTo(cx + 2.6 * s, cy + 62 * s)
        ..lineTo(cx - 2.6 * s, cy + 62 * s)
        ..close();
      canvas.drawPath(tower, towerFill);
      canvas.drawPath(tower, stroke);
      final angle = t * 2 * math.pi * 3 * speed;
      for (var k = 0; k < 3; k++) {
        canvas.save();
        canvas.translate(cx, cy);
        canvas.rotate(angle + k * 2 * math.pi / 3);
        final blade = Path()
          ..moveTo(0, 0)
          ..lineTo(-1.8 * s, -3 * s)
          ..lineTo(-0.6 * s, -len)
          ..lineTo(0.6 * s, -len)
          ..lineTo(1.8 * s, -3 * s)
          ..close();
        canvas.drawPath(blade, towerFill);
        canvas.drawPath(blade, stroke);
        canvas.restore();
      }
      canvas.drawCircle(Offset(cx, cy), 2.4 * s, Paint()..color = hub);
    }

    // Near ground + road
    final near = Path()
      ..moveTo(0, h * 0.74)
      ..cubicTo(w * 0.3, h * 0.66, w * 0.6, h * 0.72, w, h * 0.70)
      ..lineTo(w, h)
      ..lineTo(0, h)
      ..close();
    canvas.drawPath(near, Paint()..color = ground.withValues(alpha: 0.88));
    final roadTop = h * 0.82, roadH = h * 0.11;
    canvas.drawRect(Rect.fromLTWH(0, roadTop, w, roadH), Paint()..color = road.withValues(alpha: 0.07));
    final dash = Paint()
      ..color = Colors.white
      ..strokeWidth = 2;
    for (double x = 0; x < w; x += 34) {
      canvas.drawLine(Offset(x, roadTop + roadH / 2), Offset(x + 18, roadTop + roadH / 2), dash);
    }

    // Rider on a scooter with a delivery box, riding left → right
    final rx = -60 + t * (w + 120);
    final ry = roadTop - 26;
    canvas.save();
    canvas.translate(rx, ry);
    canvas.drawRRect(
        RRect.fromRectAndRadius(const Rect.fromLTWH(-22, 4, 16, 14), const Radius.circular(3)),
        Paint()..color = box);
    final body = Path()
      ..moveTo(-12, 22)
      ..lineTo(8, 22)
      ..lineTo(14, 14)
      ..lineTo(4, 14)
      ..lineTo(0, 20)
      ..close();
    canvas.drawPath(body, Paint()..color = riderBody);
    final ink = Paint()
      ..color = riderInk
      ..strokeWidth = 4
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round
      ..style = PaintingStyle.stroke;
    canvas.drawPath(Path()..moveTo(-4, 20)..lineTo(-2, 8)..lineTo(4, 8), ink);
    canvas.drawLine(const Offset(10, 14), const Offset(13, 6), ink..strokeWidth = 2.4);
    canvas.drawCircle(const Offset(0, 2), 5, Paint()..color = riderInk);
    for (final x in [-10.0, 12.0]) {
      canvas.drawCircle(Offset(x, 26), 5, Paint()..color = wheel);
      canvas.drawCircle(Offset(x, 26), 2, Paint()..color = Colors.white);
    }
    canvas.restore();
  }

  @override
  bool shouldRepaint(_ScenePainter old) => old.t != t || old.ground != ground || old.hill != hill;
}
