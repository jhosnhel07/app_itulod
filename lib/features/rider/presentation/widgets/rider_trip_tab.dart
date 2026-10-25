import 'dart:async';

import 'package:flutter/material.dart';
import '../../../../shared/widgets/loading_skeleton.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../../../core/constants/app_colors.dart';
import '../../../../core/constants/app_typography.dart';
import '../../../../core/utils/formatters.dart';
import '../../../../shared/models/booking_models.dart';
import '../../../../shared/providers/booking_extras_providers.dart';
import '../../../../shared/widgets/app_button.dart';
import '../../../../shared/widgets/success_moment.dart';
import '../../../../shared/widgets/app_confirm_dialog.dart';
import '../../../../shared/widgets/booking_route_map.dart';
import '../../../../shared/widgets/status_badge.dart';
import '../../../auth/presentation/providers/auth_provider.dart';
import '../../../chat/presentation/screens/chat_screen.dart';
import '../../data/rider_repository.dart';
import 'rider_earnings_tab.dart' show riderEarningsProvider;
import 'rider_home_tab.dart' show riderHomeSnapshotProvider;
import 'rider_requests_tab.dart' show riderActiveBookingsProvider, riderRequestsProvider;

/// The rider's active job(s) — the web's "Accepted bookings" tab
/// (rider.js renderAcceptedCard + the navigation map).
class RiderTripTab extends ConsumerWidget {
  const RiderTripTab({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final activeAsync = ref.watch(riderActiveBookingsProvider);

    return RefreshIndicator(
      onRefresh: () async => ref.invalidate(riderActiveBookingsProvider),
      child: activeAsync.when(
        loading: () => const SkeletonList(count: 2),
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
                      Icon(Icons.two_wheeler_rounded,
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

class _ActiveBookingCard extends ConsumerStatefulWidget {
  final BookingBase booking;

  const _ActiveBookingCard({required this.booking});

  @override
  ConsumerState<_ActiveBookingCard> createState() => _ActiveBookingCardState();
}

class _ActiveBookingCardState extends ConsumerState<_ActiveBookingCard> {
  late final TextEditingController _fareController;
  bool _busy = false;
  bool _showMap = true;

  BookingBase get booking => widget.booking;
  bool get _isOngoing => booking.status == 'ongoing';

  /// Food/parcel: the rider confirms the real fare at pickup before the job
  /// can be completed (web: needsFinalFare).
  bool get _needsFinalFare => booking.kind != BookingKind.transport && booking.finalFare == null;

  bool get _paymentBlocked =>
      booking.kind == BookingKind.transport &&
      booking.paymentMethod != null &&
      booking.paymentMethod != 'cash' &&
      booking.paymentStatus != 'paid';

  @override
  void initState() {
    super.initState();
    final suggested = booking.estimatedFare;
    _fareController = TextEditingController(
        text: suggested == null ? '' : suggested.toStringAsFixed(2));
  }

  @override
  void dispose() {
    _fareController.dispose();
    super.dispose();
  }

  void _toast(String message, {Color? color}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message), backgroundColor: color),
    );
  }

  static String _clean(Object e) => e.toString().replaceFirst('Exception: ', '');

  Future<bool> _confirm(String title, String body, String action, {bool danger = false}) async {
    return showAppConfirm(
      context,
      title: title,
      message: body,
      confirmText: action,
      cancelText: 'Never mind',
      danger: danger,
    );
  }

  /// Runs [action] even if this card is rebuilt meanwhile (a live update can
  /// replace it): the providers and the messenger are captured up front, so
  /// the list still refreshes and the result is still shown.
  /// [done] is a title for the success moment (showSuccessMoment) instead of
  /// a snackbar — used for the big one, completing a trip.
  Future<void> _run(Future<void> Function() action, {String? success, String? done}) async {
    final container = ProviderScope.containerOf(context, listen: false);
    final messenger = ScaffoldMessenger.maybeOf(context);
    final rootNav = Navigator.of(context, rootNavigator: true);
    void show(String message, Color color) =>
        messenger?.showSnackBar(SnackBar(content: Text(message), backgroundColor: color));
    if (mounted) setState(() => _busy = true);
    try {
      await action();
      container
        ..invalidate(riderActiveBookingsProvider)
        ..invalidate(riderRequestsProvider)
        ..invalidate(riderHomeSnapshotProvider)
        ..invalidate(riderEarningsProvider);
      if (done != null && rootNav.mounted) {
        unawaited(showSuccessMoment(rootNav.context, title: done, message: success));
      } else if (success != null) {
        show(success, AppColors.success);
      }
    } catch (e) {
      show(_clean(e), AppColors.danger);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  // ── Actions ───────────────────────────────────────────────────────────

  Future<void> _start() async {
    final riderId = ref.read(authNotifierProvider).profile!.id;
    await _run(() => ref.read(riderRepositoryProvider).updateStatus(booking, 'ongoing', riderId: riderId),
        success: 'Trip started.');
  }

  Future<void> _release() async {
    if (!await _confirm('Release this job?',
        "Release it back to other riders? Only do this if you genuinely can't complete it.", 'Release')) {
      return;
    }
    await _run(() => ref.read(riderRepositoryProvider).releaseBooking(booking),
        success: 'Job released — another rider can pick it up.');
  }

  Future<void> _noShow() async {
    if (!await _confirm('Mark as no-show?',
        "Use this only if you arrived and the customer/order wasn't there.", 'No-show',
        danger: true)) {
      return;
    }
    final riderId = ref.read(authNotifierProvider).profile!.id;
    await _run(() => ref.read(riderRepositoryProvider).updateStatus(booking, 'no_show', riderId: riderId),
        success: 'Marked as no-show.');
  }

  Future<XFile?> _pickPhoto(String title) async {
    final source = await showModalBottomSheet<ImageSource>(
      context: context,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(title: Text(title, style: AppTypography.bodyBold)),
            ListTile(
              leading: const Icon(Icons.photo_camera_outlined),
              title: const Text('Take a photo'),
              onTap: () => Navigator.pop(ctx, ImageSource.camera),
            ),
            ListTile(
              leading: const Icon(Icons.photo_library_outlined),
              title: const Text('Choose from gallery'),
              onTap: () => Navigator.pop(ctx, ImageSource.gallery),
            ),
          ],
        ),
      ),
    );
    if (source == null) return null;
    return ImagePicker().pickImage(source: source, maxWidth: 1600, imageQuality: 80);
  }

  /// Food: optional receipt photo, then finalize-fare. Parcel: finalize-fare.
  Future<void> _setFare() async {
    final amount = double.tryParse(_fareController.text.trim());
    if (amount == null || amount <= 0) {
      _toast('Enter the final fare first.', color: AppColors.danger);
      return;
    }
    final riderId = ref.read(authNotifierProvider).profile!.id;
    final repo = ref.read(riderRepositoryProvider);
    final b = booking;
    if (b is FoodDeliveryModel) {
      final photo = await _pickPhoto('Photo of the receipt (optional)');
      final bytes = await photo?.readAsBytes();
      await _run(
        () => repo.confirmFoodFare(
          riderId: riderId,
          booking: b,
          amount: amount,
          receiptBytes: bytes,
          receiptName: photo?.name,
        ),
        success: 'Fare confirmed. The customer has been notified.',
      );
    } else {
      await _run(() => repo.finalizeFare(b, amount),
          success: 'Fare confirmed. The customer has been notified.');
    }
  }

  Future<void> _complete() async {
    final riderId = ref.read(authNotifierProvider).profile!.id;
    final repo = ref.read(riderRepositoryProvider);
    if (booking.kind == BookingKind.transport) {
      await _run(() => repo.updateStatus(booking, 'completed', riderId: riderId),
          done: 'Trip complete!', success: 'Nice work — your earnings are updated.');
      return;
    }

    // Food/parcel/hauling: the proof-of-delivery photo is its own step and
    // must be saved first (web: takeDeliveryProof; enforced by sql/031).
    if (!_hasProof) {
      _toast('Take a proof of delivery photo first.', color: AppColors.danger);
      return;
    }
    await _run(() => repo.updateStatus(booking, 'completed', riderId: riderId),
        done: 'Delivery complete!', success: 'Nice work — your earnings are updated.');
  }

  bool get _hasProof => (booking.deliveryProofUrl ?? '').isNotEmpty;

  /// Takes the proof-of-delivery photo and saves it on the booking, which
  /// unlocks "Mark Complete".
  Future<void> _takeProof() async {
    final riderId = ref.read(authNotifierProvider).profile!.id;
    final repo = ref.read(riderRepositoryProvider);
    final photo = await _pickPhoto('Proof of delivery');
    if (photo == null || !mounted) return;
    final b = booking;
    _toast('Uploading photo…');
    await _run(() async {
      final url = await repo.uploadDeliveryProof(
        riderId: riderId,
        booking: b,
        bytes: await photo.readAsBytes(),
        fileName: photo.name,
      );
      await repo.saveDeliveryProof(b, url);
    }, success: 'Proof of delivery saved — you can now mark it complete.');
  }

  Future<void> _openNavigation() async {
    final destination = _isOngoing ? booking.dropoffLine : booking.pickupLine;
    final uri = Uri.https('www.google.com', '/maps/dir/', {
      'api': '1',
      'destination': destination,
      'travelmode': 'driving',
    });
    if (!await launchUrl(uri, mode: LaunchMode.externalApplication)) {
      _toast('Could not open maps.', color: AppColors.danger);
    }
  }

  // ── UI ────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final stopsAsync = booking.kind == BookingKind.transport
        ? ref.watch(rideStopsProvider(booking.id))
        : const AsyncValue<List<RideStop>>.data([]);
    final stops = stopsAsync.valueOrNull ?? const <RideStop>[];
    final canComplete = _isOngoing && !_needsFinalFare;
    final needsProof = booking.kind != BookingKind.transport;

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
            const SizedBox(height: 10),
            Text(booking.routeLine, style: AppTypography.bodyMedium.copyWith(fontSize: 14)),
            const SizedBox(height: 6),
            Row(
              children: [
                Text('Fare: ${booking.displayFare}', style: AppTypography.captionDark),
                if (booking.paymentMethod != null && booking.paymentMethod != 'cash') ...[
                  const SizedBox(width: 8),
                  StatusBadge(
                    status: '${booking.paymentMethod == 'wallet' ? 'Wallet' : 'GCash'} · ${booking.paymentStatus ?? 'pending'}',
                    fontSize: 10,
                  ),
                ],
              ],
            ),
            if (booking.expiresAt != null) ...[
              const SizedBox(height: 8),
              _note(
                Icons.hourglass_top_rounded,
                'Start the trip before ${Formatters.timeOnly(booking.expiresAt)} — a 15-minute grace period after acceptance.',
              ),
            ],
            if (_paymentBlocked) ...[
              const SizedBox(height: 8),
              _note(Icons.info_outline_rounded,
                  'Waiting for online payment confirmation before starting the trip.'),
            ],
            const SizedBox(height: 12),
            Row(
              children: [
                _stepIcon(true, Icons.flag_circle_outlined, 'Accepted'),
                _stepConnector(_isOngoing),
                _stepIcon(_isOngoing, Icons.directions_rounded, 'On trip'),
                _stepConnector(false),
                _stepIcon(false, Icons.emoji_events_outlined, 'Complete'),
              ],
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Text('Navigation', style: AppTypography.bodyBold),
                const Spacer(),
                TextButton.icon(
                  onPressed: () => setState(() => _showMap = !_showMap),
                  icon: Icon(_showMap ? Icons.expand_less : Icons.expand_more, size: 18),
                  label: Text(_showMap ? 'Hide map' : 'Show map'),
                ),
              ],
            ),
            if (_showMap && !stopsAsync.isLoading)
              BookingRouteMap(booking: booking, stops: stops, height: 200),
            const SizedBox(height: 8),
            OutlinedButton.icon(
              onPressed: _openNavigation,
              icon: const Icon(Icons.navigation_rounded, size: 18),
              label: Text(_isOngoing ? 'Navigate to drop-off' : 'Navigate to pickup'),
            ),
            if (stops.isNotEmpty) ...[
              const SizedBox(height: 12),
              _StopsList(booking: booking, stops: stops),
            ],
            if (booking.kind != BookingKind.transport) ...[
              const SizedBox(height: 12),
              _OrderDetails(booking: booking, canMarkOutOfStock: _isOngoing),
            ],
            if (_needsFinalFare) ...[
              const SizedBox(height: 14),
              Text(
                booking.kind == BookingKind.food
                    ? 'Confirm the fare at pickup (items + delivery). You can attach a photo of the receipt.'
                    : booking.kind == BookingKind.hauling
                        ? 'Confirm the fare once you\'ve seen the load (vehicle + helpers).'
                        : 'Confirm the fare once you\'ve seen the parcel.',
                style: AppTypography.caption,
              ),
              const SizedBox(height: 8),
              Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _fareController,
                      keyboardType: const TextInputType.numberWithOptions(decimal: true),
                      decoration: const InputDecoration(
                        prefixText: '₱ ',
                        hintText: 'Final fare',
                        isDense: true,
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                  OutlinedButton(
                    onPressed: _busy ? null : _setFare,
                    child: const Text('Set fare'),
                  ),
                ],
              ),
            ],
            const SizedBox(height: 14),
            OutlinedButton.icon(
              onPressed: () => Navigator.push(context, ChatScreen.route(booking)),
              icon: const Icon(Icons.chat_bubble_outline_rounded, size: 18),
              label: const Text('Chat with customer'),
            ),
            if (canComplete && needsProof) ...[
              const SizedBox(height: 10),
              _proofSection(),
            ],
            const SizedBox(height: 10),
            Row(
              children: [
                if (!_isOngoing) ...[
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: _busy ? null : _release,
                      style: OutlinedButton.styleFrom(
                        foregroundColor: AppColors.neutral700,
                        side: BorderSide(color: AppColors.cardBorder),
                      ),
                      icon: const Icon(Icons.undo_rounded, size: 18),
                      label: const Text('Release'),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: _busy ? null : _noShow,
                      style: OutlinedButton.styleFrom(
                        foregroundColor: AppColors.danger,
                        side: const BorderSide(color: AppColors.danger),
                      ),
                      icon: const Icon(Icons.person_off_rounded, size: 18),
                      label: const Text('No-show'),
                    ),
                  ),
                  const SizedBox(width: 8),
                ],
                Expanded(
                  child: AppButton(
                    text: _isOngoing ? 'Mark Complete' : 'Start Trip',
                    icon: _isOngoing ? Icons.task_alt_rounded : Icons.play_arrow_rounded,
                    isLoading: _busy,
                    onPressed: _paymentBlocked || (_isOngoing && (!canComplete || (needsProof && !_hasProof)))
                        ? null
                        : (_isOngoing ? _complete : _start),
                  ),
                ),
              ],
            ),
            if (_isOngoing && (!canComplete || (needsProof && !_hasProof))) ...[
              const SizedBox(height: 6),
              Center(
                child: Text(
                    !canComplete
                        ? 'Set the final fare before completing.'
                        : 'Take a proof of delivery photo before completing.',
                    style: AppTypography.caption),
              ),
            ],
          ],
        ),
      ),
    );
  }

  /// Step before "Mark Complete" on a drop-off: take the photo, or show the
  /// saved one with a Retake option.
  Widget _proofSection() {
    final url = booking.deliveryProofUrl;
    if (url == null || url.isEmpty) {
      return OutlinedButton.icon(
        onPressed: _busy ? null : _takeProof,
        icon: const Icon(Icons.photo_camera_rounded, size: 18),
        label: const Text('Take proof of delivery'),
      );
    }
    return Container(
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(
        color: AppColors.success.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.success.withValues(alpha: 0.35)),
      ),
      child: Row(
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(8),
            child: Image.network(
              url,
              width: 44,
              height: 44,
              fit: BoxFit.cover,
              errorBuilder: (_, __, ___) => const SizedBox(
                width: 44,
                height: 44,
                child: Icon(Icons.image_rounded, color: AppColors.success),
              ),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text('Proof of delivery saved',
                style: AppTypography.bodyBold.copyWith(color: AppColors.success)),
          ),
          TextButton.icon(
            onPressed: _busy ? null : _takeProof,
            icon: const Icon(Icons.cameraswitch_rounded, size: 16),
            label: const Text('Retake'),
          ),
        ],
      ),
    );
  }

  Widget _note(IconData icon, String text) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: AppColors.warning50,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        children: [
          Icon(icon, size: 14, color: AppColors.warning),
          const SizedBox(width: 6),
          Expanded(child: Text(text, style: AppTypography.caption.copyWith(fontSize: 11.5))),
        ],
      ),
    );
  }

  Widget _stepIcon(bool active, IconData icon, String label) {
    return Expanded(
      child: Column(
        children: [
          Icon(icon, color: active ? AppColors.success : AppColors.neutral300, size: 26),
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
}

/// Multi-stop rides: stops in order, with "Mark arrived" on the next one.
class _StopsList extends ConsumerWidget {
  final BookingBase booking;
  final List<RideStop> stops;

  const _StopsList({required this.booking, required this.stops});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final next = stops.where((s) => !s.arrived).firstOrNull;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Stops', style: AppTypography.bodyBold),
        const SizedBox(height: 4),
        for (final s in stops)
          Row(
            children: [
              Icon(s.arrived ? Icons.check_circle_rounded : Icons.radio_button_unchecked,
                  size: 16, color: s.arrived ? AppColors.success : AppColors.neutral400),
              const SizedBox(width: 6),
              Expanded(
                child: Text('Stop ${s.stopOrder}: ${s.address}',
                    style: AppTypography.caption.copyWith(fontSize: 12.5)),
              ),
              if (s.id == next?.id)
                TextButton(
                  onPressed: () async {
                    try {
                      await ref.read(riderRepositoryProvider).markStopArrived(s.id);
                      ref.invalidate(rideStopsProvider(booking.id));
                      if (context.mounted) {
                        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                          content: Text('Marked stop ${s.stopOrder} arrived.'),
                          backgroundColor: AppColors.success,
                        ));
                      }
                    } catch (e) {
                      if (context.mounted) {
                        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                          content: Text('$e'),
                          backgroundColor: AppColors.danger,
                        ));
                      }
                    }
                  },
                  child: const Text('Mark arrived'),
                ),
            ],
          ),
      ],
    );
  }
}

/// Food: the order lines (with out-of-stock) and notes. Parcel: the parcel
/// facts the rider needs at pickup.
class _OrderDetails extends ConsumerWidget {
  final BookingBase booking;
  final bool canMarkOutOfStock;

  const _OrderDetails({required this.booking, required this.canMarkOutOfStock});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final b = booking;
    if (b is HaulingBookingModel) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Hauling job', style: AppTypography.bodyBold),
          const SizedBox(height: 4),
          _line('Items', '${b.categoryLabel} — ${b.itemDescription}'),
          if (b.estimatedWeightKg != null) _line('Weight', '~${b.estimatedWeightKg!.toStringAsFixed(0)} kg'),
          _line('Helpers', b.helpers == 0 ? 'None — driver only' : '${b.helpers} (${Formatters.currency(b.helperFee)} each)'),
          _line('Pickup', '${b.senderName}${b.senderPhone.isEmpty ? '' : ' · ${b.senderPhone}'}'),
          _line('Receiver', '${b.receiverName}${b.receiverPhone.isEmpty ? '' : ' · ${b.receiverPhone}'}'),
          if (b.scheduledFor != null) _line('Scheduled', Formatters.date(b.scheduledFor!)),
          if (b.instructions.isNotEmpty) _line('Instructions', b.instructions),
        ],
      );
    }
    if (b is ParcelDeliveryModel) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Parcel', style: AppTypography.bodyBold),
          const SizedBox(height: 4),
          _line('Size', b.parcelSize),
          if (b.parcelWeight != null) _line('Weight', '${b.parcelWeight!.toStringAsFixed(1)} kg'),
          if (b.parcelDescription.isNotEmpty) _line('Contents', b.parcelDescription),
          _line('Sender', '${b.senderName}${b.senderPhone.isEmpty ? '' : ' · ${b.senderPhone}'}'),
          _line('Receiver', '${b.receiverName}${b.receiverPhone.isEmpty ? '' : ' · ${b.receiverPhone}'}'),
          if (b.instructions.isNotEmpty) _line('Instructions', b.instructions),
          if (b.isRoundTrip) _line('Round trip', 'Return to the sender after drop-off'),
          if (b.codAmount > 0) _line('Collect COD', Formatters.currency(b.codAmount)),
        ],
      );
    }
    if (b is TransportBookingModel) {
      return _line('Passengers', '${b.passengers}');
    }
    if (b is! FoodDeliveryModel) return const SizedBox.shrink();

    final itemsAsync = ref.watch(foodOrderItemsProvider(b.id));
    final items = itemsAsync.valueOrNull ?? const <FoodOrderItem>[];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Order from ${b.restaurantName}', style: AppTypography.bodyBold),
        if (b.instructions.isNotEmpty) ...[
          const SizedBox(height: 4),
          _line('Note', b.instructions),
        ],
        const SizedBox(height: 4),
        for (final item in items)
          Row(
            children: [
              Expanded(
                child: Text(
                  '${item.quantity} × ${item.name}${item.isOutOfStock ? ' (out of stock)' : ''}',
                  style: AppTypography.caption.copyWith(
                    fontSize: 12.5,
                    decoration: item.isOutOfStock ? TextDecoration.lineThrough : null,
                  ),
                ),
              ),
              Text(Formatters.currency(item.subtotal),
                  style: AppTypography.caption.copyWith(
                    decoration: item.isOutOfStock ? TextDecoration.lineThrough : null,
                  )),
              if (canMarkOutOfStock && !item.isOutOfStock)
                IconButton(
                  visualDensity: VisualDensity.compact,
                  tooltip: 'Mark out of stock',
                  icon: const Icon(Icons.remove_shopping_cart_outlined, size: 18, color: AppColors.danger),
                  onPressed: () async {
                    final ok = await showAppConfirm(
                      context,
                      title: 'Mark as out of stock?',
                      message: '${item.name} will be crossed off the order.',
                      confirmText: 'Out of stock',
                      icon: Icons.remove_shopping_cart_outlined,
                    );
                    if (!ok) return;
                    try {
                      await ref.read(riderRepositoryProvider).markItemOutOfStock(item.id);
                      ref.invalidate(foodOrderItemsProvider(b.id));
                    } catch (e) {
                      if (context.mounted) {
                        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                          content: Text(e.toString().replaceFirst('Exception: ', '')),
                          backgroundColor: AppColors.danger,
                        ));
                      }
                    }
                  },
                ),
            ],
          ),
        if (b.itemSubtotal != null) ...[
          const Divider(height: 12),
          _line('Item subtotal', Formatters.currency(b.itemSubtotal)),
          if (b.deliveryFee != null) _line('Delivery fee', Formatters.currency(b.deliveryFee)),
        ],
      ],
    );
  }

  Widget _line(String label, String value) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 2),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SizedBox(width: 96, child: Text(label, style: AppTypography.caption)),
            Expanded(child: Text(value, style: AppTypography.caption.copyWith(fontSize: 12.5))),
          ],
        ),
      );
}
