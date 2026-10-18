import 'package:flutter/material.dart';

/// Fades and lifts its child in once, staggered by [index] — the app twin of
/// the web's listRise animation on restaurant and menu cards. Plays only on
/// first build, so list refreshes don't re-animate.
class RiseIn extends StatelessWidget {
  final int index;
  final Widget child;

  const RiseIn({super.key, required this.index, required this.child});

  @override
  Widget build(BuildContext context) {
    if (MediaQuery.of(context).disableAnimations) return child;
    // Each item waits 30ms longer than the previous one, up to 150ms.
    final delayMs = (index.clamp(0, 5)) * 30;
    const runMs = 320;
    final total = delayMs + runMs;
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0, end: 1),
      duration: Duration(milliseconds: total),
      curve: Interval(delayMs / total, 1, curve: Curves.easeOutCubic),
      builder: (context, t, child) => Opacity(
        opacity: t,
        child: Transform.translate(offset: Offset(0, (1 - t) * 10), child: child),
      ),
      child: child,
    );
  }
}
