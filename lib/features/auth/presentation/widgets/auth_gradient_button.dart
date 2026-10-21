import 'package:flutter/material.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../../../core/constants/app_colors.dart';

class AuthGradientButton extends StatelessWidget {
  final String text;
  final VoidCallback? onPressed;
  final bool isLoading;
  final bool orange;
  final FaIconData? leadingIcon;
  final FaIconData? trailingIcon;
  final bool expanded;

  const AuthGradientButton({
    super.key,
    required this.text,
    this.onPressed,
    this.isLoading = false,
    this.orange = false,
    this.leadingIcon,
    this.trailingIcon,
    this.expanded = true,
  });

  @override
  Widget build(BuildContext context) {
    final colors = orange
        ? [AppColors.brandOrange, AppColors.brandOrangeDark]
        : [AppColors.brandBlue, AppColors.brandBlueDark];
    final shadow = orange
        ? AppColors.brandOrange.withValues(alpha: 0.35)
        : AppColors.brandBlue.withValues(alpha: 0.35);

    return SizedBox(
      width: expanded ? double.infinity : null,
      height: 52,
      child: DecoratedBox(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: colors,
          ),
          borderRadius: BorderRadius.circular(14),
          boxShadow: [
            BoxShadow(color: shadow, blurRadius: 14, offset: const Offset(0, 4)),
          ],
        ),
        child: ElevatedButton(
          onPressed: isLoading ? null : onPressed,
          style: ElevatedButton.styleFrom(
            backgroundColor: Colors.transparent,
            shadowColor: Colors.transparent,
            disabledBackgroundColor: Colors.transparent,
            foregroundColor: Colors.white,
            elevation: 0,
            // Tighter than the Material default so long labels still fit when
            // this button shares a row with the back button on a narrow phone.
            padding: const EdgeInsets.symmetric(horizontal: 12),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
          ),
          child: isLoading
              ? const SizedBox(
                  width: 22,
                  height: 22,
                  child: CircularProgressIndicator(
                    strokeWidth: 2.5,
                    valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                  ),
                )
              : Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (leadingIcon != null) ...[
                      FaIcon(leadingIcon, size: 15, color: Colors.white),
                      const SizedBox(width: 8),
                    ],
                    // Scale the label down rather than overflow it: labels like
                    // "Submit Application" are wider than the space left beside
                    // a back button at 360-375dp.
                    Flexible(
                      child: FittedBox(
                        fit: BoxFit.scaleDown,
                        child: Text(
                          text,
                          maxLines: 1,
                          softWrap: false,
                          style: GoogleFonts.poppins(
                            fontWeight: FontWeight.w700,
                            fontSize: 16,
                            color: Colors.white,
                          ),
                        ),
                      ),
                    ),
                    if (trailingIcon != null) ...[
                      const SizedBox(width: 8),
                      FaIcon(trailingIcon, size: 14, color: Colors.white),
                    ],
                  ],
                ),
        ),
      ),
    );
  }
}

class AuthBackButton extends StatelessWidget {
  final VoidCallback onPressed;

  const AuthBackButton({super.key, required this.onPressed});

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 50,
      child: OutlinedButton(
        onPressed: onPressed,
        style: OutlinedButton.styleFrom(
          // Size to content. This button sits next to an Expanded sibling in a
          // Row, so it is laid out with an unbounded width — a full-width
          // minimumSize here would force an infinite width and fail layout.
          minimumSize: const Size(0, 50),
          backgroundColor: AppColors.pick(0xFFF1F5F9, 0xFF1C2839),
          foregroundColor: AppColors.slate,
          side: BorderSide(color: AppColors.pick(0xFFE5E7EB, 0xFF2A384C), width: 1.5),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          padding: const EdgeInsets.symmetric(horizontal: 20),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            FaIcon(FontAwesomeIcons.arrowLeft, size: 13, color: AppColors.slate),
            const SizedBox(width: 7),
            Text(
              'Back',
              style: GoogleFonts.inter(
                fontWeight: FontWeight.w600,
                fontSize: 14.4,
                color: AppColors.slate,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
