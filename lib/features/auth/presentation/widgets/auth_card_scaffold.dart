import 'package:flutter/material.dart';
import '../../../../core/constants/app_colors.dart';
import '../../../../shared/widgets/ilocos_scene.dart';

/// Centered auth card on a softly branded backdrop.
class AuthCardScaffold extends StatelessWidget {
  final Widget child;
  final double maxWidth;
  final EdgeInsetsGeometry padding;

  const AuthCardScaffold({
    super.key,
    required this.child,
    this.maxWidth = 460,
    this.padding = const EdgeInsets.fromLTRB(22, 30, 22, 22),
  });

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      body: Stack(
        children: [
          // Branded wash behind the card.
          const _BackdropBlob(
            top: -120,
            right: -90,
            size: 300,
            gradient: AppColors.primaryGradient,
            opacity: 0.16,
          ),
          _BackdropBlob(
            bottom: -140,
            left: -110,
            size: 320,
            gradient: AppColors.blushGradient,
            opacity: 0.5,
          ),
          // Ilocos Norte strip along the bottom, behind the card.
          const Positioned(left: 0, right: 0, bottom: 0, child: IlocosScene()),
          SafeArea(
            child: LayoutBuilder(
              builder: (context, constraints) {
                return SingleChildScrollView(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 16, vertical: 24),
                  child: ConstrainedBox(
                    constraints:
                        BoxConstraints(minHeight: constraints.maxHeight - 48),
                    child: Center(
                      child: ConstrainedBox(
                        constraints: BoxConstraints(maxWidth: maxWidth),
                        child: Container(
                          width: double.infinity,
                          padding: padding,
                          decoration: BoxDecoration(
                            color: AppColors.surface,
                            borderRadius: BorderRadius.circular(20),
                            border: Border.all(color: AppColors.cardBorder),
                            boxShadow: AppColors.elevatedShadow,
                          ),
                          child: child,
                        ),
                      ),
                    ),
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

class _BackdropBlob extends StatelessWidget {
  final double? top;
  final double? bottom;
  final double? left;
  final double? right;
  final double size;
  final Gradient gradient;
  final double opacity;

  const _BackdropBlob({
    this.top,
    this.bottom,
    this.left,
    this.right,
    required this.size,
    required this.gradient,
    required this.opacity,
  });

  @override
  Widget build(BuildContext context) {
    return Positioned(
      top: top,
      bottom: bottom,
      left: left,
      right: right,
      child: IgnorePointer(
        child: Opacity(
          opacity: opacity,
          child: Container(
            width: size,
            height: size,
            decoration: BoxDecoration(shape: BoxShape.circle, gradient: gradient),
          ),
        ),
      ),
    );
  }
}
