import 'package:flutter/material.dart';
import 'package:shimmer/shimmer.dart';
import '../../core/constants/app_colors.dart';

class LoadingSkeleton extends StatelessWidget {
  final double width;
  final double height;
  final double borderRadius;

  const LoadingSkeleton({
    super.key,
    required this.width,
    required this.height,
    this.borderRadius = 8,
  });

  @override
  Widget build(BuildContext context) {
    return Shimmer.fromColors(
      baseColor: AppColors.neutral100,
      highlightColor: AppColors.surfaceAlt,
      child: Container(
        width: width,
        height: height,
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(borderRadius),
        ),
      ),
    );
  }
}

/// Booking-card-shaped placeholders shown while a list loads, so the screen
/// opens with the shape of what's coming instead of a spinner (web:
/// skeletonList()). A plain Column, so it works inside scroll views too.
class SkeletonList extends StatelessWidget {
  final int count;
  final EdgeInsetsGeometry padding;

  const SkeletonList({super.key, this.count = 4, this.padding = const EdgeInsets.all(16)});

  @override
  Widget build(BuildContext context) {
    Widget bar(double w, double h) => Container(
          width: w,
          height: h,
          decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(6)),
        );
    return Padding(
      padding: padding,
      child: Shimmer.fromColors(
        baseColor: AppColors.neutral100,
        highlightColor: AppColors.surfaceAlt,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            for (var i = 0; i < count; i++)
              Container(
                margin: const EdgeInsets.only(bottom: 12),
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: Colors.white, width: 1.5),
                ),
                child: Row(
                  children: [
                    Container(
                      width: 44,
                      height: 44,
                      decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(12)),
                    ),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          FractionallySizedBox(widthFactor: i.isEven ? 0.75 : 0.6, child: bar(double.infinity, 12)),
                          const SizedBox(height: 8),
                          FractionallySizedBox(widthFactor: 0.4, child: bar(double.infinity, 10)),
                        ],
                      ),
                    ),
                    const SizedBox(width: 14),
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [bar(56, 12), const SizedBox(height: 8), bar(40, 10)],
                    ),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }
}
