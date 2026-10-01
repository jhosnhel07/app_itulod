import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';
import '../../../../core/constants/app_colors.dart';
import '../../../../core/constants/app_typography.dart';
import '../../../../core/utils/formatters.dart';
import '../../../../shared/models/booking_models.dart';
import '../../../../shared/widgets/app_button.dart';
import '../../../../shared/widgets/status_badge.dart';
import '../../../auth/presentation/providers/auth_provider.dart';
import '../../data/rider_repository.dart';
import 'rider_requests_tab.dart' show riderActiveBookingsProvider, riderRequestsProvider;
import '../../../chat/presentation/screens/chat_screen.dart' as import_chat;

class RiderTripTab extends ConsumerWidget {
  const RiderTripTab({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final activeAsync = ref.watch(riderActiveBookingsProvider);

    return RefreshIndicator(
      onRefresh: () async => ref.invalidate(riderActiveBookingsProvider),
      child: activeAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          children: [
            Padding(
              padding: const EdgeInsets.all(24),
              child: Text('Could not load trips.\n$e',
                  textAlign: TextAlign.center, style: AppTypography.body),
            ),
          ],
        ),
        data: (bookings) {
          if (bookings.isEmpty) {
            return ListView(
              physics: const AlwaysScrollableScrollPhysics(),
              children: [
                SizedBox(
                  height: MediaQuery.of(context).size.height * 0.6,
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      const Icon(Icons.two_wheeler_rounded,
                          size: 56, color: AppColors.neutral300),
                      const SizedBox(height: 12),
                      Text('No active trip. Accept a booking to get started.',
                          style: AppTypography.captionDark),
                    ],
                  ),
                ),
              ],
            );
          }
          return ListView.builder(
            physics: const AlwaysScrollableScrollPhysics(),
            padding: const EdgeInsets.all(20),
            itemCount: bookings.length,
            itemBuilder: (_, i) => _ActiveBookingCard(booking: bookings[i]),
          );
        },
      ),
    );
  }
}

class _ActiveBookingCard extends ConsumerWidget {
  final BookingBase booking;

  const _ActiveBookingCard({required this.booking});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final isOngoing = booking.status == 'ongoing';
    final paymentBlocked = booking.kind == BookingKind.transport &&
        booking.paymentMethod != null &&
        booking.paymentMethod != 'cash' &&
        booking.paymentStatus != 'paid';

    return Card(
      margin: const EdgeInsets.only(bottom: 16),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Text('${booking.kind.label} booking', style: AppTypography.h3),
                const Spacer(),
                StatusBadge(status: booking.status),
              ],
            ),
            const SizedBox(height: 12),
            Text(booking.routeLine,
                style: AppTypography.bodyMedium.copyWith(fontSize: 14)),
            if (booking.expiresAt != null) ...[
              const SizedBox(height: 8),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                decoration: BoxDecoration(
                  color: AppColors.warning50,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.hourglass_top_rounded,
                        size: 13, color: AppColors.warning),
                    const SizedBox(width: 6),
                    Text(
                      'Start the trip before ${Formatters.timeOnly(booking.expiresAt)} — '
                      'a 15-minute grace period after acceptance.',
                      style: AppTypography.caption.copyWith(fontSize: 11),
                    ),
                  ],
                ),
              ),
            ],
            const SizedBox(height: 12),
            // Trip progress steps
            Row(
              children: [
                _stepIcon(true, Icons.flag_circle_outlined, 'Accepted'),
                _stepConnector(isOngoing || false),
                _stepIcon(isOngoing, Icons.directions_rounded, 'On trip'),
                _stepConnector(false),
                _stepIcon(false, Icons.emoji_events_outlined, 'Complete'),
              ],
            ),
            if (paymentBlocked) ...[
              const SizedBox(height: 10),
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: AppColors.warning.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.info_outline_rounded,
                        color: AppColors.warning, size: 18),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        'Waiting for online payment confirmation before starting the trip.',
                        style: AppTypography.captionDark.copyWith(fontSize: 12),
                      ),
                    ),
                  ],
                ),
              ),
            ],
            const SizedBox(height: 14),
            if (isOngoing && booking.kind == BookingKind.food) ...[
              AppButton(
                text: 'Adjust Final Bill (Receipt)',
                icon: Icons.receipt_long_rounded,
                onPressed: () => _adjustFoodBill(context, ref),
              ),
              const SizedBox(height: 10),
            ],
            Row(
              children: [
                if (booking.kind == BookingKind.food || booking.kind == BookingKind.parcel) ...[
                  Expanded(
                    child: AppButton(
                      text: 'View Order',
                      icon: Icons.list_alt_rounded,
                      onPressed: () => _viewOrderDetails(context, ref, isOngoing),
                    ),
                  ),
                  const SizedBox(width: 10),
                ],
                Expanded(
                  child: AppButton(
                    text: 'Chat',
                    icon: Icons.chat_bubble_outline_rounded,
                    onPressed: () {
                      Navigator.push(context, MaterialPageRoute(builder: (_) => import_chat.ChatScreen(bookingId: booking.id)));
                    },
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            Row(
              children: [
                if (!isOngoing)
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: () async {
                        final confirmed = await showDialog<bool>(
                          context: context,
                          builder: (ctx) => AlertDialog(
                            title: const Text('Release Request?'),
                            content: const Text('This will release the booking back to other riders.'),
                            actions: [
                              TextButton(
                                  onPressed: () => Navigator.pop(ctx, false),
                                  child: const Text('Never mind')),
                              TextButton(
                                  onPressed: () => Navigator.pop(ctx, true),
                                  style: TextButton.styleFrom(foregroundColor: AppColors.danger),
                                  child: const Text('Release')),
                            ],
                          ),
                        );
                        if (confirmed != true) return;

                        try {
                          await ref.read(riderRepositoryProvider).cancelAndRematchBooking(booking);
                          ref.invalidate(riderActiveBookingsProvider);
                          ref.invalidate(riderRequestsProvider);
                          if (context.mounted) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(content: Text('Booking released.')),
                            );
                          }
                        } catch (e) {
                          if (context.mounted) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(content: Text('Release failed: $e'), backgroundColor: AppColors.danger),
                            );
                          }
                        }
                      },
                      style: OutlinedButton.styleFrom(
                        foregroundColor: AppColors.text,
                        side: const BorderSide(color: AppColors.border),
                      ),
                      icon: const Icon(Icons.arrow_back_rounded, size: 18),
                      label: const Text('Release'),
                    ),
                  ),
                if (!isOngoing) const SizedBox(width: 8),
                if (!isOngoing)
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: () async {
                        final confirmed = await showDialog<bool>(
                          context: context,
                          builder: (ctx) => AlertDialog(
                            title: const Text('Mark as No-show?'),
                            content: const Text('Use this only if you arrived and the customer/order wasn\'t there.'),
                            actions: [
                              TextButton(
                                  onPressed: () => Navigator.pop(ctx, false),
                                  child: const Text('Cancel')),
                              TextButton(
                                  onPressed: () => Navigator.pop(ctx, true),
                                  style: TextButton.styleFrom(foregroundColor: AppColors.danger),
                                  child: const Text('No-show')),
                            ],
                          ),
                        );
                        if (confirmed != true) return;

                        try {
                          await ref.read(riderRepositoryProvider).updateBookingStatus(booking, 'no_show');
                          ref.invalidate(riderActiveBookingsProvider);
                          if (context.mounted) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(content: Text('Marked as no-show.')),
                            );
                          }
                        } catch (e) {
                          if (context.mounted) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(content: Text('No-show failed: $e'), backgroundColor: AppColors.danger),
                            );
                          }
                        }
                      },
                      style: OutlinedButton.styleFrom(
                        foregroundColor: AppColors.danger,
                        side: const BorderSide(color: AppColors.danger),
                      ),
                      icon: const Icon(Icons.person_off_rounded, size: 18),
                      label: const Text('No-show'),
                    ),
                  ),
                if (!isOngoing) const SizedBox(width: 10),
                Expanded(
                  child: AppButton(
                    text: isOngoing ? 'Mark Complete' : 'Start Trip',
                    icon: isOngoing ? Icons.task_alt_rounded : Icons.play_arrow_rounded,
                    onPressed: paymentBlocked
                        ? null
                        : () async {
                            final profile = ref.read(authNotifierProvider).profile!;
                            final repo = ref.read(riderRepositoryProvider);
                            try {
                              String? photoUrl;
                              if (isOngoing && (booking.kind == BookingKind.food || booking.kind == BookingKind.parcel)) {
                                final ImagePicker picker = ImagePicker();
                                final XFile? image = await picker.pickImage(source: ImageSource.camera);
                                if (image != null) {
                                  // Show a loading snackbar
                                  if (context.mounted) {
                                    ScaffoldMessenger.of(context).showSnackBar(
                                      const SnackBar(content: Text('Uploading proof of delivery...')),
                                    );
                                  }
                                  photoUrl = await repo.uploadDropoffPhoto(booking.id, image.path);
                                } else {
                                  // cancelled picking image
                                  if (context.mounted) {
                                    ScaffoldMessenger.of(context).showSnackBar(
                                      const SnackBar(content: Text('Proof of delivery is required to complete this trip.'), backgroundColor: AppColors.warning),
                                    );
                                  }
                                  return;
                                }
                              }

                              await repo.updateStatus(
                                booking,
                                isOngoing ? 'completed' : 'ongoing',
                                riderId: profile.id,
                                dropoffPhotoUrl: photoUrl,
                              );
                              ref.invalidate(riderActiveBookingsProvider);
                              ref.invalidate(riderRequestsProvider);
                              if (context.mounted && isOngoing) {
                                ScaffoldMessenger.of(context).showSnackBar(
                                  const SnackBar(
                                    content: Text('Trip completed! Earnings updated.'),
                                    backgroundColor: AppColors.success,
                                  ),
                                );
                              }
                            } catch (e) {
                              if (context.mounted) {
                                ScaffoldMessenger.of(context).showSnackBar(
                                  SnackBar(
                                      content: Text('Update failed: $e'),
                                      backgroundColor: AppColors.danger),
                                );
                              }
                            }
                          },
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Center(
              child: Text('Fare: ${Formatters.currency(booking.finalFare ?? booking.estimatedFare)}',
                  style: AppTypography.captionDark),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _adjustFoodBill(BuildContext context, WidgetRef ref) async {
    final foodBooking = booking as FoodDeliveryModel;
    final controller = TextEditingController(text: foodBooking.totalItemsPrice?.toStringAsFixed(0) ?? '');
    
    final newAmount = await showDialog<double>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Adjust Food Bill'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Enter the actual amount on the physical receipt:'),
            const SizedBox(height: 16),
            TextField(
              controller: controller,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(prefixText: '₱ ', hintText: 'e.g., 500'),
              autofocus: true,
            ),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
          FilledButton(
            onPressed: () {
              final val = double.tryParse(controller.text.trim());
              Navigator.pop(ctx, val);
            },
            child: const Text('Next'),
          ),
        ],
      ),
    );

    if (newAmount == null || !context.mounted) return;

    final picker = ImagePicker();
    final image = await picker.pickImage(source: ImageSource.camera);
    if (image == null) return;

    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Uploading receipt...')));

    try {
      await ref.read(riderRepositoryProvider).adjustFoodBill(booking.id, newAmount, image.path);
      ref.invalidate(riderActiveBookingsProvider);
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Bill adjusted successfully.'), backgroundColor: AppColors.success));
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Failed: $e'), backgroundColor: AppColors.danger));
      }
    }
  }

  Widget _stepIcon(bool active, IconData icon, String label) {
    return Expanded(
      child: Column(
        children: [
          Icon(icon,
              color: active ? AppColors.success : AppColors.neutral300, size: 26),
          const SizedBox(height: 4),
          Text(label,
              style: AppTypography.caption.copyWith(
                fontSize: 11,
                color: active ? AppColors.success : AppColors.neutral400,
              )),
        ],
      ),
    );
  }

  Widget _stepConnector(bool reached) {
    return Container(
      width: 24,
      height: 2,
      margin: const EdgeInsets.only(bottom: 18),
      color: reached ? AppColors.success : AppColors.neutral300,
    );
  }

  void _viewOrderDetails(BuildContext context, WidgetRef ref, bool isOngoing) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (ctx) => DraggableScrollableSheet(
        initialChildSize: 0.6,
        minChildSize: 0.4,
        maxChildSize: 0.9,
        expand: false,
        builder: (_, scrollController) {
          if (booking.kind == BookingKind.food) {
            final f = booking as FoodDeliveryModel;
            return ListView(
              controller: scrollController,
              padding: const EdgeInsets.all(20),
              children: [
                Text('Order for ${f.restaurantName}', style: AppTypography.h3),
                const SizedBox(height: 10),
                if (f.instructions.isNotEmpty) ...[
                  Container(
                    padding: const EdgeInsets.all(10),
                    color: AppColors.primary50,
                    child: Text('Note: ${f.instructions}'),
                  ),
                  const SizedBox(height: 10),
                ],
                const Divider(),
                ...?f.items?.asMap().entries.map((entry) {
                  final index = entry.key;
                  final map = entry.value as Map<String, dynamic>;
                  final isOos = map['is_out_of_stock'] == true;
                  
                  return ListTile(
                    contentPadding: EdgeInsets.zero,
                    title: Text(
                      '${map['quantity']}x ${map['name']}',
                      style: TextStyle(
                        decoration: isOos ? TextDecoration.lineThrough : null,
                        color: isOos ? Colors.grey : null,
                      ),
                    ),
                    trailing: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          '₱${map['price'] ?? 0.0}',
                          style: TextStyle(
                            decoration: isOos ? TextDecoration.lineThrough : null,
                            color: isOos ? Colors.grey : null,
                          ),
                        ),
                        if (!isOos && isOngoing)
                          IconButton(
                            icon: const Icon(Icons.remove_shopping_cart, size: 20, color: Colors.red),
                            tooltip: 'Mark Out of Stock',
                            onPressed: () async {
                              final confirm = await showDialog<bool>(
                                context: context,
                                builder: (c) => AlertDialog(
                                  title: const Text('Mark Out of Stock?'),
                                  content: const Text('This will mark the item as out of stock.'),
                                  actions: [
                                    TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('Cancel')),
                                    TextButton(onPressed: () => Navigator.pop(c, true), child: const Text('Confirm')),
                                  ],
                                ),
                              );
                              if (confirm == true) {
                                try {
                                  await ref.read(riderRepositoryProvider).markItemOutOfStock(f.id, index);
                                  ref.invalidate(riderActiveBookingsProvider);
                                  if (context.mounted) Navigator.pop(context); // close modal to refresh
                                } catch (e) {
                                  if (context.mounted) {
                                    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Error: $e')));
                                  }
                                }
                              }
                            },
                          ),
                      ],
                    ),
                  );
                }),
                const Divider(),
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('Est. Food Total', style: TextStyle(fontWeight: FontWeight.bold)),
                  trailing: Text('₱${f.totalItemsPrice?.toStringAsFixed(2)}', style: const TextStyle(fontWeight: FontWeight.bold)),
                ),
              ],
            );
          } else if (booking.kind == BookingKind.parcel) {
            final p = booking as ParcelDeliveryModel;
            return ListView(
              controller: scrollController,
              padding: const EdgeInsets.all(20),
              children: [
                Text('Parcel Details', style: AppTypography.h3),
                const SizedBox(height: 10),
                ListTile(title: const Text('Size'), subtitle: Text(p.parcelSize)),
                ListTile(title: const Text('Description'), subtitle: Text(p.parcelDescription)),
                if (p.instructions.isNotEmpty)
                  ListTile(title: const Text('Instructions'), subtitle: Text(p.instructions)),
                if (p.isRoundTrip)
                  ListTile(
                    title: const Text('Round Trip'), 
                    subtitle: const Text('Return to sender after dropoff'),
                    leading: const Icon(Icons.loop_rounded, color: AppColors.primary),
                  ),
                if (p.codAmount > 0)
                  ListTile(
                    title: const Text('Collect COD'), 
                    subtitle: Text('₱${p.codAmount.toStringAsFixed(2)}'),
                    leading: const Icon(Icons.payments_rounded, color: AppColors.success),
                  ),
              ],
            );
          }
          return const SizedBox.shrink();
        },
      ),
    );
  }
}

