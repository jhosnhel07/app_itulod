import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';

import '../../../../core/constants/app_colors.dart';
import '../../../../core/constants/app_icons.dart';
import '../../../../core/constants/app_typography.dart';
import '../../../../shared/models/booking_models.dart';
import '../../../../shared/screens/booking_details_sheet.dart';
import '../../../../shared/widgets/app_button.dart';
import '../../../auth/presentation/providers/auth_provider.dart';
import '../../../chat/presentation/screens/chat_screen.dart';
import '../../data/customer_repository.dart';
import 'cancellation_dialog.dart';
import 'customer_home_tab.dart' show customerHomeSummaryProvider;

const _nouns = {
  BookingKind.transport: 'ride',
  BookingKind.food: 'food order',
  BookingKind.parcel: 'parcel delivery',
  BookingKind.hauling: 'hauling job',
};
const _stages = {
  'pending': 'waiting for a rider',
  'accepted': 'with a rider on the way',
  'ongoing': 'in progress',
};

/// Top of the booking screens: your newest booking that's still going
/// (pending / accepted / ongoing) with View, Chat and Cancel, so nobody books
/// the same thing twice by mistake (web: customer.js renderBookActive).
class ActiveBookingBanner extends ConsumerWidget {
  const ActiveBookingBanner({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final list = ref.watch(customerHomeSummaryProvider).valueOrNull?.activeBookings ?? const <BookingBase>[];
    if (list.isEmpty) return const SizedBox.shrink();
    final b = list.first;
    final more = list.length - 1;
    // Rounded corners need one border colour, so the blue accent is a stripe.
    return Container(
      margin: const EdgeInsets.only(bottom: 14),
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.cardBorder),
      ),
      child: IntrinsicHeight(
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Container(width: 4, color: AppColors.primary),
            Expanded(
                child:
                    Padding(padding: const EdgeInsets.fromLTRB(12, 12, 12, 8), child: _content(context, ref, b, more))),
          ],
        ),
      ),
    );
  }

  Widget _content(BuildContext context, WidgetRef ref, BookingBase b, int more) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Container(
              width: 38,
              height: 38,
              alignment: Alignment.center,
              decoration: BoxDecoration(color: AppColors.primary, borderRadius: BorderRadius.circular(11)),
              child: FaIcon(AppIcons.forKind(b.kind), color: Colors.white, size: 16),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('You have a ${_nouns[b.kind]} ${_stages[b.status] ?? b.status}',
                      style: AppTypography.bodyBold.copyWith(fontSize: 13.5)),
                  const SizedBox(height: 2),
                  Text('${b.routeLine} · ${b.displayFare}',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: AppTypography.caption.copyWith(fontSize: 12)),
                  if (more > 0)
                    Text('+$more more in My Bookings',
                        style: AppTypography.caption
                            .copyWith(fontSize: 12, color: AppColors.primary, fontWeight: FontWeight.w600)),
                ],
              ),
            ),
          ],
        ),
        const SizedBox(height: 6),
        Wrap(
          spacing: 6,
          children: [
            TextButton.icon(
              onPressed: () => showActiveBookingDetails(context, ref, b),
              icon: const Icon(Icons.visibility_outlined, size: 17),
              label: const Text('View'),
            ),
            if (b.canSendChat)
              TextButton.icon(
                onPressed: () => Navigator.of(context).push(ChatScreen.route(b)),
                icon: const Icon(Icons.chat_bubble_outline_rounded, size: 17),
                label: const Text('Chat'),
              ),
            if (b.canCancel)
              TextButton.icon(
                style: TextButton.styleFrom(foregroundColor: AppColors.danger),
                onPressed: () => showCancellationDialog(context, ref, b),
                icon: const Icon(Icons.close_rounded, size: 17),
                label: const Text('Cancel'),
              ),
          ],
        ),
      ],
    );
  }
}

Future<void> showActiveBookingDetails(BuildContext context, WidgetRef ref, BookingBase b) async {
  await showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (sheetContext) => BookingDetailsSheet(
      booking: b,
      actions: [
        if (b.canCancel)
          AppButton(
            text: 'Cancel booking',
            type: AppButtonType.danger,
            onPressed: () {
              Navigator.pop(sheetContext);
              showCancellationDialog(context, ref, b);
            },
          ),
      ],
    ),
  );
  ref.invalidate(customerHomeSummaryProvider);
}

/// Before a second booking of the same service while one is still going:
/// ask, don't block (two rides for the family is fine). Checked fresh.
/// Returns true to go ahead (web: okToBookAgain).
Future<bool> okToBookAgain(BuildContext context, WidgetRef ref, BookingKind kind) async {
  final userId = ref.read(authNotifierProvider).profile?.id;
  if (userId == null) return true;
  BookingBase? existing;
  try {
    existing = await ref.read(customerRepositoryProvider).findActiveBooking(userId, kind);
  } catch (_) {
    return true; // can't check — don't stand in the way
  }
  if (existing == null || !context.mounted) return true;
  final b = existing;
  final go = await showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      icon: const Icon(Icons.copy_all_rounded, color: AppColors.primary),
      title: const Text('Book another?'),
      content: Text('You already have a ${_nouns[kind]} ${_stages[b.status] ?? b.status}. Book another one?'),
      actions: [
        TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('View my booking')),
        FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Book anyway')),
      ],
    ),
  );
  if (go == true) return true;
  if (go == false && context.mounted) await showActiveBookingDetails(context, ref, b);
  return false;
}
