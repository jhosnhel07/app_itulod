import 'package:flutter/material.dart';
import '../../core/constants/app_colors.dart';
import '../../core/constants/app_typography.dart';

enum AppButtonType { primary, secondary, outline, danger, ghost }

/// The app's standard button. [primary] gets the iTULOD Blue gradient and a
/// soft glow; the other variants are flat.
class AppButton extends StatelessWidget {
  final String text;
  final VoidCallback? onPressed;
  final bool isLoading;
  final AppButtonType type;
  final IconData? icon;
  final double? width;
  final double height;

  const AppButton({
    super.key,
    required this.text,
    this.onPressed,
    this.isLoading = false,
    this.type = AppButtonType.primary,
    this.icon,
    this.width,
    this.height = 52,
  });

  bool get _isPrimary => type == AppButtonType.primary;

  @override
  Widget build(BuildContext context) {
    late Color textColor;
    Gradient? gradient;
    Color bgColor = Colors.transparent;
    BorderSide borderSide = BorderSide.none;
    List<BoxShadow> shadow = const [];

    switch (type) {
      case AppButtonType.primary:
        gradient = AppColors.primaryGradient;
        textColor = Colors.white;
        shadow = AppColors.primaryGlow;
        break;
      case AppButtonType.secondary:
        bgColor = AppColors.secondary50;
        textColor = AppColors.secondaryDark;
        borderSide = BorderSide(color: AppColors.blushBorder, width: 1.5);
        break;
      case AppButtonType.outline:
        bgColor = Colors.white;
        textColor = AppColors.primary;
        borderSide = const BorderSide(color: AppColors.primary, width: 1.5);
        break;
      case AppButtonType.danger:
        bgColor = AppColors.danger;
        textColor = Colors.white;
        break;
      case AppButtonType.ghost:
        bgColor = AppColors.neutral100;
        textColor = AppColors.neutral700;
        break;
    }

    final enabled = !isLoading && onPressed != null;
    final effectiveOnPressed = isLoading ? null : onPressed;

    return Opacity(
      opacity: enabled ? 1 : 0.55,
      child: DecoratedBox(
        decoration: BoxDecoration(
          gradient: gradient,
          color: gradient == null ? bgColor : null,
          borderRadius: BorderRadius.circular(14),
          border: borderSide == BorderSide.none
              ? null
              : Border.fromBorderSide(borderSide),
          boxShadow: enabled ? shadow : const [],
        ),
        child: SizedBox(
          width: width ?? double.infinity,
          height: height,
          child: ElevatedButton(
            onPressed: effectiveOnPressed,
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.transparent,
              foregroundColor: textColor,
              disabledBackgroundColor: Colors.transparent,
              disabledForegroundColor: textColor,
              shadowColor: Colors.transparent,
              elevation: 0,
              padding: const EdgeInsets.symmetric(horizontal: 18),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(14),
              ),
            ).copyWith(
              overlayColor: WidgetStatePropertyAll(
                (_isPrimary ? Colors.white : textColor).withValues(alpha: 0.08),
              ),
            ),
            child: isLoading
                ? SizedBox(
                    width: 22,
                    height: 22,
                    child: CircularProgressIndicator(
                      strokeWidth: 2.5,
                      valueColor: AlwaysStoppedAnimation<Color>(textColor),
                    ),
                  )
                : Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      if (icon != null) ...[
                        Icon(icon, size: 19, color: textColor),
                        const SizedBox(width: 8),
                      ],
                      Flexible(
                        child: Text(
                          text,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: AppTypography.button.copyWith(color: textColor),
                        ),
                      ),
                    ],
                  ),
          ),
        ),
      ),
    );
  }
}
