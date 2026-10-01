import 'package:flutter/material.dart';

/// ─────────────────────────────────────────────────────────────────────────
/// iTULOD splash / loading screen — presentational widget.
///
/// Pure UI: shows the logo, a tagline, and either an animated loading
/// indicator or (when [error] is set) an error message with a Retry button.
/// All timing / navigation lives in the widgets that host this one, so this
/// file is safe to tweak in isolation.
/// ─────────────────────────────────────────────────────────────────────────

/// Brand palette for the splash screen only. Kept local so restyling the
/// splash never touches the rest of the app's theme.
class SplashColors {
  SplashColors._();
  static const primary = Color(0xFF2563EB);
  static const secondary = Color(0xFF1D4ED8);
  static const accent = Color(0xFFF97316);
  static const background = Color(0xFFF8FAFC);
  static const text = Color(0xFF0F172A);
  static const textMuted = Color(0xFF475569);
}

const String _kTagline = 'Your Ride. Your Delivery. Your Way.';

/// Just the circular illustration (no baked-in wordmark) — matches the native
/// launch screen so the hand-off is seamless. The "iTULOD" name is drawn as
/// crisp text below it.
const String _kLogoAsset = 'assets/images/splash_icon.png';

class SplashView extends StatefulWidget {
  /// When non-null the loading indicator is replaced by this message plus a
  /// Retry button that calls [onRetry].
  final String? error;
  final VoidCallback? onRetry;

  /// When true the whole screen fades out, then calls [onFinished] — used to
  /// hand off smoothly to the first real screen.
  final bool finishing;
  final VoidCallback? onFinished;

  const SplashView({
    super.key,
    this.error,
    this.onRetry,
    this.finishing = false,
    this.onFinished,
  });

  @override
  State<SplashView> createState() => _SplashViewState();
}

class _SplashViewState extends State<SplashView>
    with TickerProviderStateMixin {
  // Entrance: logo settles, then tagline fades up.
  late final AnimationController _entrance;
  late final Animation<double> _logoSettle;
  late final Animation<double> _taglineFade;

  // Exit fade for a smooth hand-off.
  late final AnimationController _exit;

  @override
  void initState() {
    super.initState();

    _entrance = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 650),
    );
    // The logo is already on screen from the native launch screen, so it only
    // gets a subtle settle; the tagline fades up just after.
    _logoSettle = CurvedAnimation(
      parent: _entrance,
      curve: const Interval(0.0, 0.6, curve: Curves.easeOutCubic),
    );
    _taglineFade = CurvedAnimation(
      parent: _entrance,
      curve: const Interval(0.25, 1.0, curve: Curves.easeOutCubic),
    );
    _entrance.forward();

    _exit = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 400),
      value: 1,
    )..addStatusListener((s) {
        if (s == AnimationStatus.dismissed) widget.onFinished?.call();
      });

    if (widget.finishing) _exit.reverse();
  }

  @override
  void didUpdateWidget(covariant SplashView old) {
    super.didUpdateWidget(old);
    if (widget.finishing && !old.finishing) _exit.reverse();
  }

  @override
  void dispose() {
    _entrance.dispose();
    _exit.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.sizeOf(context);
    final logoSize = (size.shortestSide * 0.42).clamp(148.0, 210.0);
    final hPad = (size.width * 0.12).clamp(28.0, 72.0);
    final isError = widget.error != null;

    // The background stays solid through the hand-off; only the content fades,
    // so there is never a flash of black between the splash and the next
    // screen (which also has a light background).
    return Scaffold(
      backgroundColor: SplashColors.background,
      body: FadeTransition(
        opacity: _exit,
        child: SafeArea(
          child: LayoutBuilder(
            builder: (context, c) {
              final group = Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  _Logo(settle: _logoSettle, size: logoSize),
                  const SizedBox(height: 22),
                  FadeSlide(
                    animation: _taglineFade,
                    child: const _Wordmark(),
                  ),
                  const SizedBox(height: 10),
                  FadeSlide(
                    animation: _taglineFade,
                    offset: 8,
                    child: const Text(
                      _kTagline,
                      textAlign: TextAlign.center,
                      maxLines: 2,
                      softWrap: true,
                      style: TextStyle(
                        fontSize: 14.5,
                        height: 1.45,
                        fontWeight: FontWeight.w500,
                        letterSpacing: 0.2,
                        color: SplashColors.textMuted,
                      ),
                    ),
                  ),
                  const SizedBox(height: 44),
                  AnimatedSwitcher(
                    duration: const Duration(milliseconds: 250),
                    child: isError
                        ? _ErrorState(
                            key: const ValueKey('error'),
                            message: widget.error!,
                            onRetry: widget.onRetry,
                          )
                        : const _LoadingDots(key: ValueKey('loading')),
                  ),
                ],
              );

              return SingleChildScrollView(
                padding: EdgeInsets.symmetric(horizontal: hPad, vertical: 24),
                child: ConstrainedBox(
                  // Fill the viewport so the group can be truly centred; the
                  // scroll view only kicks in if the group can't fit.
                  constraints: BoxConstraints(minHeight: c.maxHeight - 48),
                  child: Align(
                    // Dead centre, with a hair of downward bias so the top-
                    // heavy logo doesn't read as sitting high.
                    alignment: const Alignment(0, 0.05),
                    child: group,
                  ),
                ),
              );
            },
          ),
        ),
      ),
    );
  }
}

// ─── Logo ──────────────────────────────────────────────────────────────────

class _Logo extends StatelessWidget {
  final Animation<double> settle;
  final double size;

  const _Logo({required this.settle, required this.size});

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: settle,
      builder: (context, child) {
        final t = settle.value.clamp(0.0, 1.0);
        return Transform.scale(scale: 0.94 + 0.06 * t, child: child);
      },
      child: Container(
        width: size,
        height: size,
        // splash_icon.png already carries transparent margin for the native
        // splash's circular mask, so the card needs almost none.
        padding: EdgeInsets.all(size * 0.02),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(size * 0.28),
          boxShadow: const [
            BoxShadow(
              color: Color(0x140F172A),
              blurRadius: 30,
              offset: Offset(0, 14),
            ),
          ],
        ),
        child: Image.asset(_kLogoAsset, fit: BoxFit.contain),
      ),
    );
  }
}

// ─── Wordmark ──────────────────────────────────────────────────────────────

/// "iTULOD" drawn as text — sharper than the baked-in logo wordmark and it
/// can never be clipped. Orange dotted "i" like the app's auth header.
class _Wordmark extends StatelessWidget {
  const _Wordmark();

  @override
  Widget build(BuildContext context) {
    return Text.rich(
      TextSpan(
        style: const TextStyle(
          fontSize: 26,
          fontWeight: FontWeight.w800,
          letterSpacing: 1.5,
          height: 1,
        ),
        children: const [
          TextSpan(text: 'i', style: TextStyle(color: SplashColors.accent)),
          TextSpan(text: 'TULOD', style: TextStyle(color: SplashColors.text)),
        ],
      ),
    );
  }
}

// ─── Loading indicator: three subtle dots ──────────────────────────────────

class _LoadingDots extends StatefulWidget {
  const _LoadingDots({super.key});

  @override
  State<_LoadingDots> createState() => _LoadingDotsState();
}

class _LoadingDotsState extends State<_LoadingDots>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1100),
  )..repeat();

  // The 3rd dot carries a small brand-orange accent.
  static const _colors = [
    SplashColors.primary,
    SplashColors.secondary,
    SplashColors.accent,
  ];

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _c,
      builder: (context, _) {
        return Row(
          mainAxisSize: MainAxisSize.min,
          children: List.generate(3, (i) {
            final phase = (_c.value + i * 0.2) % 1.0;
            // ease 0→1→0 across the cycle
            final wave = phase < 0.5 ? phase * 2 : (1 - phase) * 2;
            final t = Curves.easeInOut.transform(wave.clamp(0.0, 1.0));
            return Container(
              width: 8,
              height: 8,
              margin: const EdgeInsets.symmetric(horizontal: 5),
              transform: Matrix4.translationValues(0, -5 * t, 0),
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: _colors[i].withValues(alpha: 0.35 + 0.65 * t),
              ),
            );
          }),
        );
      },
    );
  }
}

// ─── Error state ───────────────────────────────────────────────────────────

class _ErrorState extends StatelessWidget {
  final String message;
  final VoidCallback? onRetry;

  const _ErrorState({super.key, required this.message, this.onRetry});

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          message,
          textAlign: TextAlign.center,
          style: const TextStyle(
            fontSize: 13.5,
            height: 1.45,
            color: SplashColors.textMuted,
          ),
        ),
        const SizedBox(height: 18),
        SizedBox(
          height: 46,
          child: FilledButton(
            onPressed: onRetry,
            style: FilledButton.styleFrom(
              backgroundColor: SplashColors.primary,
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(horizontal: 34),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
              textStyle: const TextStyle(
                fontSize: 14.5,
                fontWeight: FontWeight.w600,
              ),
            ),
            child: const Text('Retry'),
          ),
        ),
      ],
    );
  }
}

// ─── Small shared fade+slide helper ────────────────────────────────────────

class FadeSlide extends StatelessWidget {
  final Animation<double> animation;
  final Widget child;
  final double offset;

  const FadeSlide({
    super.key,
    required this.animation,
    required this.child,
    this.offset = 12,
  });

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: animation,
      builder: (context, child) => Opacity(
        opacity: animation.value.clamp(0.0, 1.0),
        child: Transform.translate(
          offset: Offset(0, offset * (1 - animation.value.clamp(0.0, 1.0))),
          child: child,
        ),
      ),
      child: child,
    );
  }
}
