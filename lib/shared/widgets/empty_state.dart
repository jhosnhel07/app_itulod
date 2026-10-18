import 'package:flutter/material.dart';
import '../../core/constants/app_colors.dart';
import '../../core/constants/app_typography.dart';

/// Illustrated empty state: the icon sits in a soft blue→blush medallion with
/// two halo rings, then a title and an optional hint (web: emptyState()).
class EmptyState extends StatelessWidget {
  final IconData icon;
  final String title;
  final String? message;

  const EmptyState({super.key, required this.icon, required this.title, this.message});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 132,
            height: 132,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: AppColors.secondary50.withValues(alpha: 0.7),
            ),
            alignment: Alignment.center,
            child: Container(
              width: 108,
              height: 108,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: AppColors.primary50.withValues(alpha: 0.6),
              ),
              alignment: Alignment.center,
              child: Container(
                width: 86,
                height: 86,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: [AppColors.primary50, AppColors.secondary50],
                  ),
                  boxShadow: AppColors.cardShadow,
                ),
                child: Icon(icon, size: 36, color: AppColors.primary),
              ),
            ),
          ),
          const SizedBox(height: 18),
          Text(title, textAlign: TextAlign.center, style: AppTypography.h3.copyWith(fontSize: 17)),
          if (message != null) ...[
            const SizedBox(height: 6),
            ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 280),
              child: Text(message!,
                  textAlign: TextAlign.center,
                  style: AppTypography.caption.copyWith(fontSize: 13.5, height: 1.5)),
            ),
          ],
        ],
      ),
    );
  }
}
