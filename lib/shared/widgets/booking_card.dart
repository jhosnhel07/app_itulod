import 'package:flutter/material.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';
import '../../core/constants/app_colors.dart';
import '../../core/constants/app_icons.dart';
import '../../core/constants/app_typography.dart';
import '../../core/theme/app_decorations.dart';
import '../../core/utils/formatters.dart';
import '../models/booking_models.dart';
import 'status_badge.dart';

class BookingCard extends StatelessWidget {
  final BookingBase booking;
  final VoidCallback? onTap;
  final Widget? trailing;

  const BookingCard({
    super.key,
    required this.booking,
    this.onTap,
    this.trailing,
  });

  (FaIconData, Color) get _kind {
    final icon = AppIcons.forKind(booking.kind);
    switch (booking.kind) {
      case BookingKind.transport:
        return (icon, AppColors.primary);
      case BookingKind.food:
        return (icon, AppColors.secondary);
      case BookingKind.parcel:
        return (icon, AppColors.success);
      case BookingKind.hauling:
        return (icon, AppColors.primaryDark);
    }
  }

  @override
  Widget build(BuildContext context) {
    final (icon, tint) = _kind;

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: AppDecorations.softCard(),
      clipBehavior: Clip.antiAlias,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.all(15),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(9),
                      decoration: AppDecorations.iconTile(tint),
                      child: SizedBox.square(dimension: 20, child: Center(child: FaIcon(icon, color: tint, size: 17))),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            booking.kind.label,
                            style: AppTypography.bodyBold.copyWith(fontSize: 14),
                          ),
                          Text(
                            Formatters.dateOnly(booking.createdAt),
                            style: AppTypography.caption,
                          ),
                        ],
                      ),
                    ),
                    StatusBadge(status: booking.status),
                  ],
                ),
                const SizedBox(height: 12),
                Text(
                  booking.routeLine,
                  style: AppTypography.bodyMedium.copyWith(fontSize: 14),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 12),
                const Divider(height: 1),
                const SizedBox(height: 10),
                Row(
                  children: [
                    Text(
                      booking.displayFare,
                      style: AppTypography.h3.copyWith(
                        color: AppColors.primaryDark,
                        fontSize: 16,
                      ),
                    ),
                    const Spacer(),
                    if (booking.rating != null)
                      Row(
                        mainAxisSize: MainAxisSize.min,
                        children: List.generate(
                          booking.rating!,
                          (_) => const Icon(Icons.star_rounded,
                              size: 15, color: Color(0xFFF6B73C)),
                        ),
                      ),
                    if (trailing != null) ...[
                      const SizedBox(width: 8),
                      trailing!,
                    ],
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
