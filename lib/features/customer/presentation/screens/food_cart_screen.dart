import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../../core/constants/app_typography.dart';
import '../../../../core/constants/app_colors.dart';
import '../../../../core/services/geocoding_service.dart';
import '../../../auth/presentation/providers/auth_provider.dart';
import '../../data/customer_repository.dart';
import '../providers/cart_provider.dart';
import '../widgets/location_picker_field.dart';
import 'map_picker_screen.dart';
import 'package:latlong2/latlong.dart';
import '../../../../core/utils/fare_estimator.dart';
import '../../../../core/utils/formatters.dart';
import '../../../../shared/models/vehicle_model.dart';

class FoodCartScreen extends ConsumerStatefulWidget {
  const FoodCartScreen({super.key});

  @override
  ConsumerState<FoodCartScreen> createState() => _FoodCartScreenState();
}

class _FoodCartScreenState extends ConsumerState<FoodCartScreen> {
  final _addressController = TextEditingController();
  final _instructionsController = TextEditingController();
  final _promoCodeController = TextEditingController();
  DateTime? _scheduledFor;
  LatLng? _deliveryPoint;
  bool _submitting = false;
  double? _distanceKm;
  double? _fare;
  VehicleModel? _vehicle;

  void _pickLocation() async {
    if (!mounted) return;
    final loc = await Navigator.of(context).push<LatLng>(
      MaterialPageRoute(
        builder: (_) => MapPickerScreen(
          title: 'Select Delivery Location',
          initialCenter: _deliveryPoint,
        ),
      ),
    );
    if (loc != null) {
      final name = await ref.read(geocodingServiceProvider).reverseGeocode(loc);
      setState(() {
        _deliveryPoint = loc;
        _addressController.text = name ?? '${loc.latitude}, ${loc.longitude}';
      });
      _refreshFare();
    }
  }

  void _refreshFare() {
    final cartState = ref.read(cartProvider);
    if (cartState.restaurant == null || _addressController.text.isEmpty) {
      setState(() {
        _distanceKm = null;
        _fare = null;
      });
      return;
    }
    
    final vehicles = ref.read(vehiclesListProvider).value ?? [];
    if (vehicles.isEmpty) return;
    _vehicle ??= vehicles.firstWhere((v) => v.name.toLowerCase().contains('motor'), orElse: () => vehicles.first);

    setState(() {
      _distanceKm = FareEstimator.simulateDistanceKm(cartState.restaurant!.address, _addressController.text);
      _fare = FareEstimator.estimateFare(_vehicle, _distanceKm!);
    });
  }
  
  Future<void> _pickSchedule() async {
    final date = await showDatePicker(
      context: context,
      initialDate: DateTime.now(),
      firstDate: DateTime.now(),
      lastDate: DateTime.now().add(const Duration(days: 7)),
    );
    if (date != null && mounted) {
      final time = await showTimePicker(
        context: context,
        initialTime: TimeOfDay.now(),
      );
      if (time != null) {
        setState(() {
          _scheduledFor = DateTime(date.year, date.month, date.day, time.hour, time.minute);
        });
      }
    }
  }

  Future<void> _submit() async {
    if (_deliveryPoint == null) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Please select delivery address')));
      return;
    }

    final cartState = ref.read(cartProvider);
    if (cartState.restaurant == null || cartState.items.isEmpty) return;
    
    final user = ref.read(authNotifierProvider).profile;
    if (user == null) return;

    setState(() => _submitting = true);
    
    try {
      final repo = ref.read(customerRepositoryProvider);
      
      final vehicles = ref.read(vehiclesListProvider).value ?? [];
      final vehicle = _vehicle ?? (vehicles.isNotEmpty 
          ? vehicles.firstWhere((v) => v.name.toLowerCase().contains('motor'), orElse: () => vehicles.first)
          : throw Exception('No vehicles available'));

      final itemsList = cartState.items.values.map((i) => {
        'menu_item_id': i.menuItem.id,
        'name': i.menuItem.name,
        'quantity': i.quantity,
        'price': i.menuItem.price,
      }).toList();

      await repo.createFoodBooking(
        customerId: user.id,
        vehicle: vehicle,
        restaurantName: cartState.restaurant!.name,
        pickupAddress: cartState.restaurant!.address,
        deliveryAddress: _addressController.text,
        instructions: _instructionsController.text,
        scheduledFor: _scheduledFor,
        promoCode: _promoCodeController.text.isNotEmpty ? _promoCodeController.text : null,
        restaurantId: cartState.restaurant!.id,
        distanceKm: _distanceKm,
        items: itemsList,
        totalItemsPrice: cartState.totalPrice,
      );

      ref.read(cartProvider.notifier).clearCart();
      if (mounted) {
        Navigator.of(context).popUntil((route) => route.isFirst);
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Error: $e')));
        setState(() => _submitting = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final cartState = ref.watch(cartProvider);
    
    return Scaffold(
      appBar: AppBar(title: const Text('Checkout')),
      body: cartState.items.isEmpty
          ? const Center(child: Text('Cart is empty'))
          : ListView(
              padding: const EdgeInsets.all(16),
              children: [
                Text('Order Summary', style: AppTypography.h3),
                const SizedBox(height: 8),
                ...cartState.items.values.map((item) => ListTile(
                  title: Text('${item.quantity}x ${item.menuItem.name}'),
                  trailing: Text('\$${item.totalPrice.toStringAsFixed(2)}'),
                )),
                const Divider(),
                ListTile(
                  title: const Text('Items Total', style: TextStyle(fontWeight: FontWeight.bold)),
                  trailing: Text('\$${cartState.totalPrice.toStringAsFixed(2)}', style: const TextStyle(fontWeight: FontWeight.bold)),
                ),
                const SizedBox(height: 24),
                Text('Delivery Details', style: AppTypography.h3),
                const SizedBox(height: 8),
                LocationPickerField(
                  controller: _addressController,
                  hint: 'Tap to set your delivery address',
                  isPickup: false,
                  emptyError: 'Set a delivery address',
                  onTap: _pickLocation,
                ),
                const SizedBox(height: 16),
                TextField(
                  controller: _instructionsController,
                  decoration: const InputDecoration(labelText: 'Instructions for driver'),
                ),
                const SizedBox(height: 16),
                TextField(
                  controller: _promoCodeController,
                  decoration: const InputDecoration(labelText: 'Promo Code (Optional)'),
                ),
                const SizedBox(height: 16),
                ListTile(
                  title: const Text('Schedule for later?'),
                  subtitle: Text(_scheduledFor != null ? _scheduledFor!.toString() : 'Optional'),
                  trailing: IconButton(
                    icon: const Icon(Icons.edit_calendar),
                    onPressed: _pickSchedule,
                  ),
                ),
                const SizedBox(height: 16),
                _fareBox(),
                const SizedBox(height: 16),
                ElevatedButton(
                  onPressed: _submitting ? null : _submit,
                  child: _submitting ? const CircularProgressIndicator() : const Text('Place Order'),
                ),
              ],
            ),
    );
  }

  Widget _fareBox() {
    if (_fare == null) return const SizedBox.shrink();

    final baseFare = _vehicle?.baseFare ?? 0.0;
    final distanceFare = _fare! - baseFare;
    final cartTotal = ref.read(cartProvider).totalPrice;
    final total = cartTotal + _fare!;

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.primary50,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.primary.withValues(alpha: 0.3)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text('ESTIMATED TOTAL', style: AppTypography.caption),
          Text(Formatters.currency(total), style: AppTypography.h3.copyWith(color: AppColors.primary)),
          const SizedBox(height: 12),
          Container(height: 1, color: AppColors.cardBorder),
          const SizedBox(height: 12),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text('Items Total', style: AppTypography.caption.copyWith(color: AppColors.neutral500)),
              Text(Formatters.currency(cartTotal), style: AppTypography.caption.copyWith(color: AppColors.neutral700)),
            ],
          ),
          const SizedBox(height: 4),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text('Base Delivery Fee', style: AppTypography.caption.copyWith(color: AppColors.neutral500)),
              Text(Formatters.currency(baseFare), style: AppTypography.caption.copyWith(color: AppColors.neutral700)),
            ],
          ),
          const SizedBox(height: 4),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text('Distance Charge (${Formatters.distance(_distanceKm)})', style: AppTypography.caption.copyWith(color: AppColors.neutral500)),
              Text(Formatters.currency(distanceFare), style: AppTypography.caption.copyWith(color: AppColors.neutral700)),
            ],
          ),
        ],
      ),
    );
  }
}
