import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/constants/app_colors.dart';
import '../../core/constants/app_strings.dart';
import '../../core/constants/app_typography.dart';
import '../../core/supabase/supabase_client.dart';
import '../../core/utils/app_log.dart';
import '../../core/utils/formatters.dart';
import '../models/booking_models.dart';
import '../widgets/status_badge.dart';

/// Bottom sheet mirroring the web app's booking-details modal.
class BookingDetailsSheet extends ConsumerStatefulWidget {
  final BookingBase booking;
  /// Optional actions rendered under the details (cancel / rate buttons).
  final List<Widget> actions;

  const BookingDetailsSheet({
    super.key,
    required this.booking,
    this.actions = const [],
  });

  @override
  ConsumerState<BookingDetailsSheet> createState() => _BookingDetailsSheetState();
}

class _BookingDetailsSheetState extends ConsumerState<BookingDetailsSheet> {
  Map<String, dynamic>? _riderProfile;
  bool _loadingRider = true;

  @override
  void initState() {
    super.initState();
    _loadRider();
  }

  Future<void> _loadRider() async {
    final riderId = widget.booking.riderId;
    if (riderId == null || riderId.isEmpty) {
      setState(() => _loadingRider = false);
      return;
    }
    try {
      final row = await SupabaseConfig.client
          .from('profiles')
          .select('full_name, phone, avatar_url')
          .eq('id', riderId)
          .maybeSingle();
      if (mounted) setState(() => _riderProfile = row);
    } catch (e, s) {
      AppLog.warn('BookingDetailsSheet: rider profile lookup failed', e, s);
    }
    if (mounted) setState(() => _loadingRider = false);
  }

  @override
  Widget build(BuildContext context) {
    final b = widget.booking;

    return DraggableScrollableSheet(
      expand: false,
      initialChildSize: 0.65,
      maxChildSize: 0.92,
      builder: (context, scrollController) {
        return Container(
          decoration: const BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
          ),
          child: Column(
            children: [
              Padding(
                padding: const EdgeInsets.only(top: 12),
                child: Container(
                  width: 40,
                  height: 4,
                  decoration: BoxDecoration(
                    color: AppColors.neutral300,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              Expanded(
                child: ListView(
                  controller: scrollController,
                  padding: const EdgeInsets.all(20),
                  children: [
                    Row(
                      children: [
                        Text('${b.kind.label} booking', style: AppTypography.h3),
                        const Spacer(),
                        StatusBadge(status: b.status),
                      ],
                    ),
                    const SizedBox(height: 12),
                    if (_expiryNotice(b) != null) ...[
                      _noticeBanner(_expiryNotice(b)!),
                      const SizedBox(height: 16),
                    ],
                    _section('Route', [
                      _detailRow('From', _pickup(b)),
                      _detailRow('To', _dropoff(b)),
                    ]),
                    ..._kindSpecific(b),
                    _section('Fare & payment', [
                      _detailRow('Estimated fare', Formatters.currency(b.estimatedFare)),
                      if (b.finalFare != null)
                        _detailRow('Final fare', Formatters.currency(b.finalFare)),
                      if (b.paymentMethod != null)
                        _detailRow('Method', b.paymentMethod!.toUpperCase()),
                      if (b.paymentStatus != null)
                        Padding(
                          padding: const EdgeInsets.symmetric(vertical: 6),
                          child: Row(
                            children: [
                              SizedBox(
                                width: 110,
                                child: Text('Payment', style: AppTypography.captionDark),
                              ),
                              StatusBadge(status: b.paymentStatus!, fontSize: 11),
                            ],
                          ),
                        ),
                    ]),
                    _riderSection(),
                    if (b.cancelledReason != null && b.cancelledReason!.isNotEmpty)
                      _section('Cancellation', [
                        Text(b.cancelledReason!, style: AppTypography.body.copyWith(color: AppColors.danger)),
                      ]),
                    if (b.rating != null)
                      _section('Your rating', [
                        Row(
                          children: List.generate(
                            b.rating!,
                            (_) => const Icon(Icons.star, size: 18, color: Colors.amber),
                          ),
                        ),
                        if (b.review != null && b.review!.isNotEmpty) ...[
                          const SizedBox(height: 6),
                          Text(b.review!, style: AppTypography.body),
                        ],
                      ]),
                    _section('', [
                      _detailRow('Booked on', Formatters.date(b.createdAt)),
                    ]),
                  ],
                ),
              ),
              if (widget.actions.isNotEmpty)
                SafeArea(
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(20, 8, 20, 16),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: widget.actions,
                    ),
                  ),
                ),
            ],
          ),
        );
      },
    );
  }

  String _pickup(BookingBase b) {
    switch (b.kind) {
      case BookingKind.transport:
        return (b as dynamic).pickupAddress as String;
      case BookingKind.food:
        return (b as dynamic).pickupAddress as String;
      case BookingKind.parcel:
        return (b as dynamic).senderAddress as String;
    }
  }

  String _dropoff(BookingBase b) {
    switch (b.kind) {
      case BookingKind.transport:
        return (b as dynamic).destinationAddress as String;
      case BookingKind.food:
        return (b as dynamic).deliveryAddress as String;
      case BookingKind.parcel:
        return (b as dynamic).receiverAddress as String;
    }
  }

  List<Widget> _kindSpecific(BookingBase b) {
    switch (b.kind) {
      case BookingKind.transport:
        return [];
      case BookingKind.food:
        final f = b as FoodDeliveryModel;
        return [
          _section('Order', [
            _detailRow('Restaurant', f.restaurantName),
            if (f.instructions.isNotEmpty) _detailRow('Instructions', f.instructions),
          ]),
        ];
      case BookingKind.parcel:
        final p = b as ParcelDeliveryModel;
        return [
          _section('Parcel', [
            _detailRow('Sender', '${p.senderName}${p.senderPhone.isEmpty ? '' : ' • ${p.senderPhone}'}'),
            _detailRow('Receiver', '${p.receiverName}${p.receiverPhone.isEmpty ? '' : ' • ${p.receiverPhone}'}'),
            _detailRow('Size', p.parcelSize),
            if (p.parcelWeight != null)
              _detailRow('Weight', '${p.parcelWeight!.toStringAsFixed(1)} kg'),
            if (p.parcelDescription.isNotEmpty) _detailRow('Description', p.parcelDescription),
            if (p.instructions.isNotEmpty) _detailRow('Instructions', p.instructions),
          ]),
        ];
    }
  }

  Widget _riderSection() {
    if (_loadingRider) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: 12),
        child: Center(child: CircularProgressIndicator(strokeWidth: 2)),
      );
    }
    final name = _riderProfile?['full_name'] as String?;
    if (name == null || name.isEmpty) return const SizedBox.shrink();

    final phone = _riderProfile?['phone'] as String?;
    return _section('Rider', [
      Row(
        children: [
          CircleAvatar(
            radius: 18,
            backgroundColor: AppColors.primary100,
            backgroundImage: (_riderProfile?['avatar_url'] as String?)?.isNotEmpty == true
                ? NetworkImage(_riderProfile!['avatar_url'] as String)
                : null,
            child: (_riderProfile?['avatar_url'] as String?)?.isNotEmpty == true
                ? null
                : Text(
                    name[0].toUpperCase(),
                    style: const TextStyle(color: AppColors.primary, fontWeight: FontWeight.w700),
                  ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(name, style: AppTypography.bodyBold),
                if (phone != null && phone.isNotEmpty)
                  Text(phone, style: AppTypography.captionDark),
              ],
            ),
          ),
        ],
      ),
    ]);
  }

  /// The right expiration copy for the booking's current stage, or null once
  /// it's past pending/accepted/expired.
  String? _expiryNotice(BookingBase b) {
    if (b.isExpired) return AppStrings.bookingExpiredMessage;
    if (b.status == 'pending') return AppStrings.pendingGracePeriodNote;
    if (b.status == 'accepted') return AppStrings.gracePeriodNote;
    return null;
  }

  Widget _noticeBanner(String message) {
    final isExpired = message == AppStrings.bookingExpiredMessage;
    final color = isExpired ? AppColors.neutral500 : AppColors.warning;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: isExpired ? AppColors.neutral100 : AppColors.warning50,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withValues(alpha: 0.3)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(
            isExpired ? Icons.timer_off_rounded : Icons.hourglass_top_rounded,
            size: 18,
            color: color,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              message,
              style: AppTypography.captionDark.copyWith(fontSize: 12.5),
            ),
          ),
        ],
      ),
    );
  }

  Widget _section(String title, List<Widget> children) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (title.isNotEmpty) ...[
            Text(title.toUpperCase(), style: AppTypography.caption.copyWith(letterSpacing: 1)),
            const SizedBox(height: 8),
          ],
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: AppColors.background,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: AppColors.cardBorder),
            ),
            child: Column(children: children),
          ),
        ],
      ),
    );
  }

  Widget _detailRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 110,
            child: Text(label, style: AppTypography.captionDark),
          ),
          Expanded(
            child: Text(value, style: AppTypography.bodyMedium.copyWith(fontSize: 14)),
          ),
        ],
      ),
    );
  }
}
