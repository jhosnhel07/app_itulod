import 'package:flutter/material.dart';
import '../../../../core/constants/ilocos_norte.dart';
import '../../../../shared/widgets/booking_stepper.dart';
import 'booking_confirmation_screen.dart' show paymentMethodLabel;
import '../../../../shared/widgets/success_moment.dart';
import '../../../../shared/widgets/loading_skeleton.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:latlong2/latlong.dart';
import '../../../../core/constants/app_colors.dart';
import '../../../../core/constants/app_typography.dart';
import '../../../../core/services/last_place.dart';
import '../../../../core/services/route_service.dart';
import '../../../../core/utils/fare_estimator.dart';
import '../../../../core/utils/formatters.dart';
import '../../../../core/utils/phone_input_formatter.dart';
import '../../../../core/utils/validators.dart';
import '../../../../shared/models/booking_models.dart';
import '../../../../shared/models/vehicle_model.dart';
import '../../../auth/presentation/providers/auth_provider.dart';
import '../../data/customer_repository.dart';
import '../widgets/location_picker_field.dart';
import '../widgets/payment_method_selector.dart';
import '../widgets/riders_near_you_map.dart';
import '../widgets/route_preview_map.dart';
import 'map_picker_screen.dart';
import '../widgets/active_booking_banner.dart';

const Map<String, IconData> _categoryIcons = {
  'furniture': Icons.chair_rounded,
  'appliances': Icons.kitchen_rounded,
  'moving': Icons.house_rounded,
  'construction': Icons.construction_rounded,
  'goods': Icons.inventory_rounded,
  'other': Icons.category_rounded,
};

/// Book a hauling job — big / heavy items with a hauling vehicle and
/// optional helpers. Mirrors the web's Hauling form (customer.js
/// wireHaulingForm): the estimate is vehicle fare + helpers, and the driver
/// confirms the real fare at pickup before any online payment is charged.
class BookHaulingScreen extends ConsumerStatefulWidget {
  const BookHaulingScreen({super.key});

  @override
  ConsumerState<BookHaulingScreen> createState() => _BookHaulingScreenState();
}

class _BookHaulingScreenState extends ConsumerState<BookHaulingScreen>
    with BookingDraftMixin<BookHaulingScreen> {
  final _senderName = TextEditingController();
  final _senderPhone = TextEditingController();
  final _pickupAddress = TextEditingController();
  final _receiverName = TextEditingController();
  final _receiverPhone = TextEditingController();
  final _dropoffAddress = TextEditingController();
  final _description = TextEditingController();
  final _weight = TextEditingController();
  final _instructions = TextEditingController();

  LatLng? _pickupPoint;
  LatLng? _dropoffPoint;
  RouteResult? _route;
  bool _routing = false;
  int _routeToken = 0;

  VehicleModel? _vehicle;
  String _category = 'furniture';
  int _helpers = 0;
  double _helperFee = 250;
  DateTime? _scheduledFor;
  String _paymentMethod = 'cash';
  bool _submitting = false;
  ({int drivers, int onlineNow})? _availability;

  // ── Draft: reopened here after Android closed the app (LastPlace) ─────

  @override
  String get draftForm => 'hauling';

  String? _draftVehicleId;

  Map<String, TextEditingController> get _draftFields => {
        'senderName': _senderName,
        'senderPhone': _senderPhone,
        'pickupAddress': _pickupAddress,
        'receiverName': _receiverName,
        'receiverPhone': _receiverPhone,
        'dropoffAddress': _dropoffAddress,
        'description': _description,
        'weight': _weight,
        'instructions': _instructions,
      };

  @override
  Map<String, dynamic> draftToJson() => {
        for (final e in _draftFields.entries) e.key: e.value.text,
        'pickupPoint': LastPlace.pointToJson(_pickupPoint),
        'dropoffPoint': LastPlace.pointToJson(_dropoffPoint),
        'category': _category,
        'helpers': _helpers,
        'vehicleId': _vehicle?.id,
        'payment': _paymentMethod,
        'scheduledFor': _scheduledFor?.toIso8601String(),
      };

  @override
  void draftFromJson(Map<String, dynamic> d) {
    for (final e in _draftFields.entries) {
      e.value.text = d[e.key] as String? ?? '';
    }
    _pickupPoint = LastPlace.pointFromJson(d['pickupPoint']);
    _dropoffPoint = LastPlace.pointFromJson(d['dropoffPoint']);
    final category = d['category'] as String?;
    if (_categoryIcons.containsKey(category)) _category = category!;
    _helpers = ((d['helpers'] as num?)?.toInt() ?? 0).clamp(0, 4);
    _draftVehicleId = d['vehicleId'] as String?;
    _paymentMethod = d['payment'] as String? ?? 'cash';
    final at = DateTime.tryParse(d['scheduledFor'] as String? ?? '');
    _scheduledFor = at != null && at.isAfter(DateTime.now()) ? at : null;
  }

  @override
  void afterDraftRestored() => _refreshRoute();

  @override
  void initState() {
    super.initState();
    initDraft();
    ref.read(customerRepositoryProvider).fetchHaulingHelperFee().then((fee) {
      if (mounted) setState(() => _helperFee = fee);
    });
    ref.read(customerRepositoryProvider).fetchHaulingAvailability().then((a) {
      if (mounted) setState(() => _availability = a);
    });
  }

  @override
  void dispose() {
    disposeDraft();
    for (final c in [
      _senderName, _senderPhone, _pickupAddress, _receiverName, _receiverPhone,
      _dropoffAddress, _description, _weight, _instructions,
    ]) {
      c.dispose();
    }
    super.dispose();
  }

  bool get _hasBothPoints => _pickupPoint != null && _dropoffPoint != null;

  double? get _distanceKm {
    if (_route != null) return _route!.distanceKm;
    final a = _pickupPoint, b = _dropoffPoint;
    if (a == null || b == null) return null;
    return FareEstimator.roadDistanceKm(a, b);
  }

  double? get _vehicleFare {
    final km = _distanceKm;
    if (km == null || _vehicle == null) return null;
    return FareEstimator.estimateFare(_vehicle, km);
  }

  double get _helpersFare => _helpers * _helperFee;

  // ── Location ──────────────────────────────────────────────────────────

  /// Pickup and drop-off share the web-style map ("1 Set Pickup /
  /// 2 Set Drop-off").
  Future<void> _pickLocation({required bool isPickup}) async {
    final a = _pickupPoint, b = _dropoffPoint;
    final result = await MapPickerScreen.showRoute(
      context,
      pickup: a == null ? null : PickedPlace(point: a, address: _pickupAddress.text),
      dropoff: b == null ? null : PickedPlace(point: b, address: _dropoffAddress.text),
      startWith: isPickup ? PinMode.pickup : PinMode.dropoff,
    );
    if (result == null || !mounted) return;
    setState(() {
      if (result.pickup != null) {
        _pickupAddress.text = result.pickup!.address;
        _pickupPoint = result.pickup!.point;
      }
      if (result.dropoff != null) {
        _dropoffAddress.text = result.dropoff!.address;
        _dropoffPoint = result.dropoff!.point;
      }
    });
    _refreshRoute();
  }

  Future<void> _refreshRoute() async {
    final a = _pickupPoint, b = _dropoffPoint;
    final token = ++_routeToken;
    if (a == null || b == null) return;
    setState(() {
      _route = null;
      _routing = true;
    });
    final result = await ref.read(routeServiceProvider).fetchRoute(a, b);
    if (!mounted || token != _routeToken) return;
    setState(() {
      _route = result;
      _routing = false;
    });
  }

  Future<void> _pickSchedule() async {
    final now = DateTime.now();
    final date = await showDatePicker(
      context: context,
      initialDate: now,
      firstDate: now,
      lastDate: now.add(const Duration(days: 14)),
    );
    if (date == null || !mounted) return;
    final time = await showTimePicker(context: context, initialTime: TimeOfDay.fromDateTime(now.add(const Duration(hours: 1))));
    if (time == null) return;
    setState(() => _scheduledFor = DateTime(date.year, date.month, date.day, time.hour, time.minute));
  }

  // ── Validation (same rules as the web form) ───────────────────────────

  static String? _optionalMobile(String? value) {
    final raw = (value ?? '').replaceAll(RegExp(r'[\s-]'), '');
    if (raw.isEmpty) return null;
    final local = raw.startsWith('+63') ? '0${raw.substring(3)}' : raw;
    return RegExp(r'^09\d{9}$').hasMatch(local) ? null : 'Enter a valid mobile number (09XX XXX XXXX)';
  }

  static String? _personName(String? value, String label) {
    final v = (value ?? '').trim();
    if (v.isEmpty) return 'Enter the $label name';
    return RegExp(r"^[A-Za-zÀ-ÿñÑ .'-]+$").hasMatch(v) ? null : '$label name should be letters only';
  }

  Future<void> _submit() async {
    if (!checkServiceArea(context, {'Pickup address': _pickupPoint, 'Drop-off address': _dropoffPoint})) return;
    final vehicle = _vehicle;
    if (vehicle == null) return;
    final scheduled = _scheduledFor;
    if (scheduled != null) {
      final now = DateTime.now();
      String? problem;
      if (scheduled.isBefore(now.add(const Duration(minutes: 30)))) {
        problem = 'Scheduled pickup must be at least 30 minutes from now.';
      } else if (scheduled.isAfter(now.add(const Duration(days: 14)))) {
        problem = 'Scheduled pickup can be at most 14 days from now.';
      }
      if (problem != null) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(problem), backgroundColor: AppColors.danger));
        return;
      }
    }

    if (!await okToBookAgain(context, ref, BookingKind.hauling) || !mounted) return;
    setState(() => _submitting = true);
    final messenger = ScaffoldMessenger.of(context);
    try {
      final profile = ref.read(authNotifierProvider).profile!;
      await ref.read(customerRepositoryProvider).createHaulingBooking(
            customerId: profile.id,
            vehicle: vehicle,
            pickupAddress: _pickupAddress.text,
            dropoffAddress: _dropoffAddress.text,
            pickupPoint: _pickupPoint,
            dropoffPoint: _dropoffPoint,
            senderName: _senderName.text,
            senderPhone: Validators.normalizePhone(_senderPhone.text),
            receiverName: _receiverName.text,
            receiverPhone: Validators.normalizePhone(_receiverPhone.text),
            itemCategory: _category,
            itemDescription: _description.text,
            estimatedWeightKg: double.tryParse(_weight.text.trim()),
            helpers: _helpers,
            helperFee: _helperFee,
            instructions: _instructions.text,
            scheduledFor: scheduled,
            paymentMethod: _paymentMethod,
            distanceKm: _distanceKm,
          );
      finishDraft(); // booked — nothing to come back to
      if (!mounted) return;
      await showSuccessMoment(
        context,
        title: scheduled != null ? 'Hauling scheduled' : 'Hauling booked!',
        message: scheduled != null
            ? 'For ${Formatters.date(scheduled)}. We\'ll find a driver closer to the time.'
            : _paymentMethod == 'cash'
                ? 'Waiting for a driver to accept.'
                : 'You can pay as soon as a driver accepts.',
      );
      if (!mounted) return;
      Navigator.pop(context);
    } catch (e) {
      messenger.showSnackBar(SnackBar(
        content: Text('Booking failed: ${e.toString().replaceFirst('Exception: ', '')}'),
        backgroundColor: AppColors.danger,
      ));
    }
    if (mounted) setState(() => _submitting = false);
  }

  // ── UI ────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final vehiclesAsync = ref.watch(haulingVehiclesProvider);
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(title: const Text('Book Hauling')),
      body: vehiclesAsync.when(
        loading: () => const SkeletonList(count: 3),
        error: (e, _) => Center(child: Text('Could not load vehicles.\n$e', textAlign: TextAlign.center)),
        data: (vehicles) {
          final wantId = _draftVehicleId;
          if (wantId != null && vehicles.isNotEmpty) {
            _vehicle = vehicles.where((v) => v.id == wantId).firstOrNull ?? _vehicle;
            _draftVehicleId = null;
          }
          _vehicle ??= vehicles.isNotEmpty ? vehicles.first : null;
          final vehicleFare = _vehicleFare;
          final fareLabel = vehicleFare == null ? '—' : Formatters.currency(vehicleFare + _helpersFare);
          return BookingStepper(
            key: ValueKey('hauling-steps-$draftGeneration'),
            initialStep: draftStep,
            onStepChanged: onDraftStep,
            fare: fareLabel,
            finishLabel: 'Book Hauling',
            finishLoading: _submitting,
            onFinish: vehicles.isEmpty ? null : _submit,
            onChanged: () => setState(() {}),
            summary: () => [
              ('Pickup', _pickupAddress.text),
              ('Drop-off', _dropoffAddress.text),
              ('Items', _description.text),
              ('Helpers', _helpers == 0 ? 'None — driver only' : '$_helpers'),
              ('Vehicle', _vehicle?.name ?? ''),
              if (_scheduledFor != null) ('Scheduled for', Formatters.date(_scheduledFor!)),
              ('Payment', paymentMethodLabel(_paymentMethod)),
              ('Estimated fare', fareLabel),
            ],
            steps: [
              BookingStep('Where', [
                  // a booking you still have going (+ View / Chat / Cancel)
                  const ActiveBookingBanner(),
                  _section('Pickup', Icons.location_on_rounded, [
                    TextFormField(
                      controller: _senderName,
                      decoration: const InputDecoration(hintText: 'Contact name *'),
                      validator: (v) => _personName(v, 'Contact'),
                    ),
                    const SizedBox(height: 12),
                    TextFormField(
                      controller: _senderPhone,
                      keyboardType: TextInputType.phone,
                      inputFormatters: const [PhPhoneInputFormatter()],
                      decoration: const InputDecoration(hintText: 'Contact number (09XX XXX XXXX)'),
                      validator: _optionalMobile,
                    ),
                    const SizedBox(height: 12),
                    LocationPickerField(
                      controller: _pickupAddress,
                      hint: 'Tap to set the pickup point on the map',
                      isPickup: true,
                      emptyError: 'Set a pickup address',
                      onTap: () => _pickLocation(isPickup: true),
                    ),
                  ]),
                  const SizedBox(height: 14),
                  _section('Drop-off', Icons.flag_rounded, [
                    TextFormField(
                      controller: _receiverName,
                      decoration: const InputDecoration(hintText: 'Receiver name *'),
                      validator: (v) => _personName(v, 'Receiver'),
                    ),
                    const SizedBox(height: 12),
                    TextFormField(
                      controller: _receiverPhone,
                      keyboardType: TextInputType.phone,
                      inputFormatters: const [PhPhoneInputFormatter()],
                      decoration: const InputDecoration(hintText: 'Contact number (09XX XXX XXXX)'),
                      validator: _optionalMobile,
                    ),
                    const SizedBox(height: 12),
                    LocationPickerField(
                      controller: _dropoffAddress,
                      hint: 'Tap to set the drop-off point on the map',
                      isPickup: false,
                      emptyError: 'Set a drop-off address',
                      onTap: () => _pickLocation(isPickup: false),
                    ),
                  ]),
                  if (_hasBothPoints) ...[
                    const SizedBox(height: 14),
                    RoutePreviewMap(pickup: _pickupPoint!, destination: _dropoffPoint!, routePoints: _route?.points),
                  ],
              ]),
              BookingStep('Load', [
                  _section('What are we moving?', Icons.inventory_2_rounded, [
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        for (final entry in haulingCategories.entries)
                          ChoiceChip(
                            avatar: Icon(_categoryIcons[entry.key], size: 16,
                                color: _category == entry.key ? Colors.white : AppColors.primary),
                            label: Text(entry.value),
                            selected: _category == entry.key,
                            showCheckmark: false,
                            selectedColor: AppColors.primary,
                            labelStyle: TextStyle(color: _category == entry.key ? Colors.white : null, fontSize: 12.5),
                            onSelected: (_) => setState(() => _category = entry.key),
                          ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    TextFormField(
                      controller: _description,
                      maxLines: 2,
                      decoration: const InputDecoration(
                          hintText: 'Items to move * (e.g. 1 refrigerator, 1 queen bed, 6 boxes)'),
                      validator: (v) => (v == null || v.trim().isEmpty) ? 'Describe what we\'re moving' : null,
                    ),
                    const SizedBox(height: 12),
                    TextFormField(
                      controller: _weight,
                      keyboardType: const TextInputType.numberWithOptions(decimal: true),
                      decoration: const InputDecoration(hintText: 'Approx. total weight in kg (optional)'),
                    ),
                    const SizedBox(height: 14),
                    Row(
                      children: [
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text('Helpers to load & unload', style: AppTypography.bodyBold.copyWith(fontSize: 14)),
                              Text('${Formatters.currency(_helperFee)} per helper', style: AppTypography.caption),
                            ],
                          ),
                        ),
                        _Stepper(
                          value: _helpers,
                          min: 0,
                          max: 4,
                          onChanged: (v) => setState(() => _helpers = v),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    TextFormField(
                      controller: _instructions,
                      maxLines: 2,
                      decoration: const InputDecoration(hintText: 'Instructions (e.g. 2nd floor, narrow stairs)'),
                    ),
                  ]),
              ]),
              BookingStep('Vehicle', [
                  DropdownButtonFormField<VehicleModel>(
                    initialValue: _vehicle,
                    isExpanded: true,
                    decoration: const InputDecoration(
                      labelText: 'Vehicle *',
                      prefixIcon: Icon(Icons.local_shipping_rounded),
                    ),
                    items: [
                      for (final v in vehicles)
                        DropdownMenuItem(
                          value: v,
                          child: Text('${v.name} — ${Formatters.currency(v.baseFare)} + ${Formatters.currency(v.perKmRate)}/km',
                              overflow: TextOverflow.ellipsis),
                        ),
                    ],
                    onChanged: (v) => setState(() => _vehicle = v),
                    validator: (v) => v == null ? 'Choose a vehicle' : null,
                  ),
                  const SizedBox(height: 12),
                  // Drivers with the chosen vehicle within 10 km of the pickup
                  RidersNearYouMap(vehicleName: _vehicle?.name, origin: _pickupPoint, hauling: true),
                  const SizedBox(height: 14),
                  Card(
                    child: ListTile(
                      leading: const Icon(Icons.schedule_rounded),
                      title: Text(_scheduledFor == null
                          ? 'Schedule for later (optional)'
                          : 'Scheduled for ${Formatters.date(_scheduledFor!)}'),
                      trailing: _scheduledFor == null
                          ? const Icon(Icons.chevron_right_rounded)
                          : IconButton(
                              icon: const Icon(Icons.close_rounded),
                              onPressed: () => setState(() => _scheduledFor = null),
                            ),
                      onTap: _pickSchedule,
                    ),
                  ),
                  const SizedBox(height: 14),
                  _fareBox(),
              ]),
              BookingStep('Payment', [
                  PaymentMethodSelector(
                    value: _paymentMethod,
                    onChanged: (v) => setState(() => _paymentMethod = v),
                    onlineNote: 'The total shown is the total you pay. You can pay once a driver accepts.',
                  ),
                  if (_availability != null) ...[
                    const SizedBox(height: 12),
                    _availabilityNotice(_availability!),
                  ],
              ]),
            ],
          );
        },
      ),
    );
  }

  /// Warns when no hauling driver could take the job right now (sql/025).
  Widget _availabilityNotice(({int drivers, int onlineNow}) a) {
    final none = a.drivers == 0 || a.onlineNow == 0;
    final text = a.drivers == 0
        ? 'No hauling drivers have joined iTULOD yet, so this request may not be accepted. We\'re onboarding Van / Pickup / Truck drivers now.'
        : a.onlineNow == 0
            ? '${a.drivers} hauling driver${a.drivers == 1 ? '' : 's'} on iTULOD, none online right now — they\'re notified of your request, or schedule it for later.'
            : '${a.onlineNow} hauling driver${a.onlineNow == 1 ? '' : 's'} online now.';
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: none ? AppColors.blush : AppColors.primary50,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(none ? Icons.warning_amber_rounded : Icons.local_shipping_rounded,
              size: 18, color: none ? AppColors.secondaryDark : AppColors.primaryDark),
          const SizedBox(width: 8),
          Expanded(
            child: Text(text,
                style: AppTypography.caption.copyWith(
                    fontSize: 12.5, color: none ? AppColors.secondaryDark : AppColors.primaryDark)),
          ),
        ],
      ),
    );
  }

  Widget _section(String title, IconData icon, List<Widget> children) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Icon(icon, size: 18, color: AppColors.primary),
                const SizedBox(width: 8),
                Text(title, style: AppTypography.bodyBold),
              ],
            ),
            const SizedBox(height: 12),
            ...children,
          ],
        ),
      ),
    );
  }

  Widget _fareBox() {
    final vehicleFare = _vehicleFare;
    final total = vehicleFare == null ? null : vehicleFare + _helpersFare;
    Widget line(String label, String value, {bool bold = false}) => Padding(
          padding: const EdgeInsets.symmetric(vertical: 3),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(label, style: bold ? AppTypography.bodyBold : AppTypography.caption.copyWith(color: AppColors.neutral600)),
              Text(value, style: bold
                  ? AppTypography.h3.copyWith(color: AppColors.primary)
                  : AppTypography.caption.copyWith(color: AppColors.neutral700)),
            ],
          ),
        );
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.primary50,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.primary.withValues(alpha: 0.25)),
      ),
      child: Column(
        children: [
          line('Distance', Formatters.distance(_distanceKm)),
          line('Vehicle fare', vehicleFare == null ? '—' : Formatters.currency(vehicleFare)),
          line('Helpers ($_helpers × ${Formatters.currency(_helperFee)})', Formatters.currency(_helpersFare)),
          const Divider(height: 18),
          line('Estimated total', total == null ? '—' : Formatters.currency(total), bold: true),
          const SizedBox(height: 6),
          Row(
            children: [
              Icon(_routing ? Icons.sync_rounded : Icons.info_outline_rounded, size: 13, color: AppColors.neutral500),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  !_hasBothPoints
                      ? 'Set both locations on the map to see the fare.'
                      : _routing
                          ? 'Measuring the road route…'
                          : 'This is the total you pay — vehicle plus helpers.',
                  style: AppTypography.caption.copyWith(fontSize: 11),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _Stepper extends StatelessWidget {
  final int value;
  final int min;
  final int max;
  final ValueChanged<int> onChanged;

  const _Stepper({required this.value, required this.min, required this.max, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: AppColors.cardBorder),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          IconButton(
            visualDensity: VisualDensity.compact,
            onPressed: value > min ? () => onChanged(value - 1) : null,
            icon: const Icon(Icons.remove_rounded, size: 18),
            color: AppColors.primary,
          ),
          Text('$value', style: AppTypography.bodyBold),
          IconButton(
            visualDensity: VisualDensity.compact,
            onPressed: value < max ? () => onChanged(value + 1) : null,
            icon: const Icon(Icons.add_rounded, size: 18),
            color: AppColors.primary,
          ),
        ],
      ),
    );
  }
}
