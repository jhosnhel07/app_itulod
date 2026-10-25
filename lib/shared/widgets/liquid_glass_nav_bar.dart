import 'dart:math' as math;
import 'dart:ui' show ImageFilter, lerpDouble;
import 'package:flutter/material.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';
import '../../core/constants/app_colors.dart';
import '../../core/constants/app_typography.dart';

class LiquidNavItem {
  final FaIconData icon;
  final FaIconData activeIcon;
  final String label;
  final int badge;
  const LiquidNavItem({
    required this.icon,
    required this.activeIcon,
    required this.label,
    this.badge = 0,
  });
}

/// Floating frosted-glass bottom bar with a "liquid" highlight — the app twin
/// of the web's js/liquid-nav.js. When the tab changes, the highlight's
/// leading edge reaches the new tab first and its trailing edge catches up,
/// so it stretches across like a drop of water (thinning a little), then
/// settles. [compact] (set while the page scrolls down) narrows the bar and
/// hides the labels.
class LiquidGlassNavBar extends StatefulWidget {
  final List<LiquidNavItem> items;
  final int currentIndex;
  final ValueChanged<int> onTap;
  final bool compact;

  /// Six tabs don't fit six labels — show only the selected tab's label.
  final bool labelsOnlyWhenSelected;

  const LiquidGlassNavBar({
    super.key,
    required this.items,
    required this.currentIndex,
    required this.onTap,
    this.compact = false,
    this.labelsOnlyWhenSelected = false,
  });

  /// Height the Scaffold reserves for the bar (bar + its floating margins).
  static const double slotHeight = 86;

  @override
  State<LiquidGlassNavBar> createState() => _LiquidGlassNavBarState();
}

class _LiquidGlassNavBarState extends State<LiquidGlassNavBar> with SingleTickerProviderStateMixin {
  late final AnimationController _c =
      AnimationController(vsync: this, duration: const Duration(milliseconds: 560), value: 1);
  late int _from = widget.currentIndex;
  late int _to = widget.currentIndex;

  static const _lead = Interval(0, 0.55, curve: Curves.easeOutCubic);
  static const _trail = Interval(0.22, 1, curve: Curves.easeInOutCubic);

  @override
  void didUpdateWidget(LiquidGlassNavBar old) {
    super.didUpdateWidget(old);
    if (old.currentIndex != widget.currentIndex) {
      _from = old.currentIndex;
      _to = widget.currentIndex;
      if (MediaQuery.of(context).disableAnimations) {
        _c.value = 1;
      } else {
        _c.forward(from: 0);
      }
    }
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final compact = widget.compact;
    final bottomInset = MediaQuery.of(context).padding.bottom;
    return SizedBox(
      height: LiquidGlassNavBar.slotHeight + bottomInset,
      child: LayoutBuilder(builder: (context, box) {
        final side = compact ? box.maxWidth * 0.14 : 12.0;
        return Align(
          alignment: Alignment.topCenter,
          child: AnimatedPadding(
            duration: const Duration(milliseconds: 320),
            curve: Curves.easeOutBack,
            padding: EdgeInsets.fromLTRB(side, compact ? 14 : 6, side, 0),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 280),
              curve: Curves.easeOut,
              height: compact ? 52 : 66,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(28),
                boxShadow: AppColors.dark
                    ? const [BoxShadow(color: Color(0x80000000), blurRadius: 30, offset: Offset(0, 14))]
                    : const [
                        BoxShadow(color: Color(0x2E0D47A1), blurRadius: 30, offset: Offset(0, 14)),
                        BoxShadow(color: Color(0x140D47A1), blurRadius: 6, offset: Offset(0, 2)),
                      ],
              ),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(28),
                child: BackdropFilter(
                  filter: ImageFilter.blur(sigmaX: 22, sigmaY: 22),
                  child: Container(
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(28),
                      color: AppColors.surface.withValues(alpha: AppColors.dark ? 0.62 : 0.66),
                      border: Border.all(
                        color: AppColors.dark ? const Color(0x14FFFFFF) : const Color(0xBFFFFFFF),
                      ),
                      // Glass sheen across the top half.
                      gradient: LinearGradient(
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                        stops: const [0, 0.55],
                        colors: [
                          Colors.white.withValues(alpha: AppColors.dark ? 0.07 : 0.55),
                          Colors.white.withValues(alpha: 0),
                        ],
                      ),
                    ),
                    padding: EdgeInsets.all(compact ? 4 : 6),
                    child: LayoutBuilder(builder: (context, inner) => _content(inner, compact)),
                  ),
                ),
              ),
            ),
          ),
        );
      }),
    );
  }

  Widget _content(BoxConstraints inner, bool compact) {
    final n = widget.items.length;
    final itemW = inner.maxWidth / n;
    return AnimatedBuilder(
      animation: _c,
      builder: (context, _) {
        final t = _c.value;
        final movingRight = _to >= (_from >= 0 && _from < n ? _from : _to);
        final lead = _lead.transform(t), trail = _trail.transform(t);
        const inset = 2.0;
        // A page opened from the profile menu (Profile, Notifications) has no
        // button here — no highlight then, and no slide in from nowhere.
        final hasTarget = _to >= 0 && _to < n;
        final from = _from >= 0 && _from < n ? _from : _to;
        final fromL = from * itemW + inset, fromR = (from + 1) * itemW - inset;
        final toL = _to * itemW + inset, toR = (_to + 1) * itemW - inset;
        final left = lerpDouble(fromL, toL, movingRight ? trail : lead)!;
        final right = lerpDouble(fromR, toR, movingRight ? lead : trail)!;
        // Thins a little while stretched, then settles.
        final squish = from == _to ? 1.0 : 1 - 0.14 * math.sin(math.pi * t);
        return Stack(
          children: [
            if (hasTarget)
            Positioned(
              left: left,
              width: math.max(0, right - left),
              top: 0,
              bottom: 0,
              child: Transform.scale(scaleY: squish, child: _blob()),
            ),
            Row(
              children: [
                for (var i = 0; i < n; i++)
                  Expanded(child: _item(i, compact)),
              ],
            ),
          ],
        );
      },
    );
  }

  Widget _blob() {
    return DecoratedBox(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(22),
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: AppColors.dark
              ? const [Color(0x662196F3), Color(0x292196F3)]
              : const [Color(0xFAE3F2FD), Color(0x8C90CAF9)],
        ),
        border: Border.all(color: AppColors.dark ? const Color(0x2EFFFFFF) : const Color(0xF2FFFFFF)),
        boxShadow: [
          BoxShadow(
            color: AppColors.primary.withValues(alpha: AppColors.dark ? 0.25 : 0.22),
            blurRadius: 14,
            offset: const Offset(0, 5),
          ),
        ],
      ),
    );
  }

  Widget _item(int i, bool compact) {
    final item = widget.items[i];
    final selected = i == widget.currentIndex;
    final showLabel = !compact && (!widget.labelsOnlyWhenSelected || selected);
    final color = selected ? AppColors.primaryDark : AppColors.neutral500;
    Widget icon = SizedBox(
      width: 26,
      height: 23,
      child: Center(child: FaIcon(selected ? item.activeIcon : item.icon, size: 20, color: color)),
    );
    if (item.badge > 0) {
      icon = Badge(label: Text('${item.badge}'), child: icon);
    }
    return Semantics(
      selected: selected,
      button: true,
      label: item.label,
      child: InkWell(
        borderRadius: BorderRadius.circular(22),
        onTap: () => widget.onTap(i),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            AnimatedScale(
              scale: selected ? 1.08 : 1,
              duration: const Duration(milliseconds: 250),
              curve: Curves.easeOutBack,
              child: icon,
            ),
            AnimatedSize(
              duration: const Duration(milliseconds: 220),
              curve: Curves.easeOut,
              child: showLabel
                  ? Padding(
                      padding: const EdgeInsets.only(top: 3),
                      child: Text(
                        item.label,
                        maxLines: 1,
                        overflow: TextOverflow.fade,
                        softWrap: false,
                        style: AppTypography.caption.copyWith(
                          fontSize: 11,
                          fontWeight: selected ? FontWeight.w800 : FontWeight.w600,
                          color: color,
                        ),
                      ),
                    )
                  : const SizedBox.shrink(),
            ),
          ],
        ),
      ),
    );
  }
}

/// Wrap a dashboard body: reports whether the user is scrolling down (→ bar
/// goes compact) or up (→ full size). Only vertical scrolling counts.
class LiquidNavScrollWatcher extends StatelessWidget {
  final Widget child;
  final ValueChanged<bool> onCompactChanged;
  const LiquidNavScrollWatcher({super.key, required this.child, required this.onCompactChanged});

  @override
  Widget build(BuildContext context) {
    return NotificationListener<ScrollUpdateNotification>(
      onNotification: (n) {
        if (n.metrics.axis != Axis.vertical) return false;
        final delta = n.scrollDelta ?? 0;
        if (delta > 6 && n.metrics.pixels > 80) {
          onCompactChanged(true);
        } else if (delta < -6 || n.metrics.pixels < 40) {
          onCompactChanged(false);
        }
        return false;
      },
      child: child,
    );
  }
}
