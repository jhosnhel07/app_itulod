import 'package:flutter/material.dart';
import '../../core/constants/app_colors.dart';
import '../../core/constants/app_typography.dart';

/// Small pill that colour-codes a booking / application / payment status.
class StatusBadge extends StatelessWidget {
  final String status;
  final double fontSize;

  const StatusBadge({
    super.key,
    required this.status,
    this.fontSize = 11.5,
  });

  @override
  Widget build(BuildContext context) {
    final (bg, fg) = _palette(status.toLowerCase());

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: fg.withValues(alpha: 0.22)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 6,
            height: 6,
            margin: const EdgeInsets.only(right: 6),
            decoration: BoxDecoration(color: fg, shape: BoxShape.circle),
          ),
          Text(
            status.replaceAll('_', '-').toUpperCase(),
            style: AppTypography.overline.copyWith(
              color: fg,
              fontSize: fontSize,
              letterSpacing: 0.5,
            ),
          ),
        ],
      ),
    );
  }

  (Color, Color) _palette(String status) {
    switch (status) {
      case 'completed':
      case 'approved':
      case 'paid':
        return (AppColors.success50, AppColors.success);
      case 'ongoing':
      case 'accepted':
        return (AppColors.info50, AppColors.primaryDark);
      case 'pending':
        return (AppColors.warning50, AppColors.warning);
      case 'cancelled':
      case 'rejected':
      case 'failed':
        return (AppColors.danger50, AppColors.danger);
      case 'no_show':
        return (AppColors.secondary50, AppColors.secondaryDark);
      case 'expired':
        return (AppColors.neutral100, AppColors.neutral500);
      default:
        return (AppColors.neutral100, AppColors.neutral600);
    }
  }
}
