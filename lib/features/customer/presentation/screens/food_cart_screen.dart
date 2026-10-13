import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:latlong2/latlong.dart';
import '../../../../core/constants/app_colors.dart';
import '../../../../core/constants/app_typography.dart';
import '../../../../core/services/route_service.dart';
import '../../../../core/utils/fare_estimator.dart';
import '../../../../core/utils/formatters.dart';
import '../../../../shared/models/vehicle_model.dart';
import '../../../../shared/widgets/app_button.dart';
import '../../../auth/presentation/providers/auth_provider.dart';
import '../../data/customer_repository.dart';
import '../providers/cart_provider.dart';
import '../providers/saved_addresses_provider.dart';
import '../widgets/location_picker_field.dart';
import '../widgets/payment_method_selector.dart';
import 'map_picker_screen.dart';

/// Checkout for a cart-based food order — mirrors the web's food form
/// (customer.js wireFoodForm): items + distance-based delivery fee, a vehicle,
/// and a payment method. GCash/wallet is charged only once the rider confirms
/// the fare at pickup, never at checkout.
class FoodCartScreen extends ConsumerStatefulWidget {
  const FoodCartScreen({super.key});

  @override
  ConsumerState<FoodCartScreen> createState() => _FoodCartScreenState();
}

class _FoodCartScreenState extends ConsumerState<FoodCartScreen> {
  final _addressController = TextEditingController();
  final _instructionsController = TextEditingController();
  LatLng? _deliveryPoint;
  bool _submitting = false;
  VehicleModel? _vehicle;
  String _paymentMethod = 'cash';

  /// Road distance from OSRM when the restaurant has coordinates; otherwise
  /// the straight-line / address estimate stands in.
  double? _routeKm;
  int _routeToken = 0;

  @override
  void initState() {
    super.initState();
    // Start from the "Deliver to" chosen on the restaurant list (or the first
    // saved address with a pin, the same default that list used).
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || _deliveryPoint != null) return;
      var place = ref.read(foodDeliverToProvider);
      if (place == null) {
        for (final a in ref.read(savedAddressesProvider).valueOrNull ?? const []) {
          if (a.hasLocation) {
            place = PickedPlace(point: a.point, address: a.address);
            break;
          }
        }
      }
      if (place == null) return;
      setState(() {
        _deliveryPoint = place!.point;
        _addressController.text = place.address;
      });
      _refreshRoute();
    });
  }

  @override
  void dispose() {
    _addressController.dispose();
    _instructionsController.dispose();
    super.dispose();
  }

  LatLng? get _restaurantPoint {
    final r = ref.read(cartProvider).restaurant;
    return (r != null && r.hasLocation) ? LatLng(r.lat!, r.lng!) : null;
  }

  double? get _distanceKm {
    final restaurant = ref.read(cartProvider).restaurant;
    if (restaurant == null || _addressController.text.trim().isEmpty) return null;
    if (_routeKm != null) return _routeKm;
    final from = _restaurantPoint;
    final to = _deliveryPoint;
    if (from != null && to != null) return FareEstimator.roadDistanceKm(from, to);
    return FareEstimator.simulateDistanceKm(restaurant.address, _addressController.text);
  }

  double? get _deliveryFee {
    final km = _distanceKm;
    if (km == null || _vehicle == null) return null;
    return FareEstimator.estimateFare(_vehicle, km);
  }

  Future<void> _pickLocation() async {
    final picked = await MapPickerScreen.show(
      context,
      title: 'Set delivery location',
      pinColor: AppColors.danger,
      initialCenter: _deliveryPoint,
      initialAddress: _addressController.text.trim().isEmpty ? null : _addressController.text,
    );
    if (picked == null || !mounted) return;
    ref.read(foodDeliverToProvider.notifier).state = picked;
    setState(() {
      _deliveryPoint = picked.point;
      _addressController.text = picked.address;
      _routeKm = null;
    });
    _refreshRoute();
  }

  Future<void> _refreshRoute() async {
    final from = _restaurantPoint;
    final to = _deliveryPoint;
    final token = ++_routeToken;
    if (from == null || to == null) return;
    final result = await ref.read(routeServiceProvider).fetchRoute(from, to);
    if (!mounted || token != _routeToken) return;
    setState(() => _routeKm = result?.distanceKm);
  }

  Future<void> _submit() async {
    final cart = ref.read(cartProvider);
    final restaurant = cart.restaurant;
    if (restaurant == null || cart.items.isEmpty) {
      _toast('Choose a restaurant and add at least one item.', AppColors.danger);
      return;
    }
    if (_addressController.text.trim().isEmpty) {
      _toast('Set a delivery address.', AppColors.danger);
      return;
    }
    final vehicle = _vehicle;
    if (vehicle == null) {
      _toast('Choose a vehicle.', AppColors.danger);
      return;
    }
    final user = ref.read(authNotifierProvider).profile;
    if (user == null) return;

    setState(() => _submitting = true);
    try {
      final order = await ref.read(customerRepositoryProvider).createFoodBooking(
            customerId: user.id,
            vehicle: vehicle,
            restaurantId: restaurant.id,
            restaurantName: restaurant.name,
            restaurantAddress: restaurant.address,
            deliveryAddress: _addressController.text,
            instructions: _instructionsController.text,
            distanceKm: _distanceKm,
            paymentMethod: _paymentMethod,
            items: [
              for (final i in cart.items.values)
                (
                  menuItemId: i.menuItem.id,
                  name: i.menuItem.name,
                  unitPrice: i.menuItem.price,
                  quantity: i.quantity,
                ),
            ],
          );

      ref.read(cartProvider.notifier).clearCart();
      if (!mounted) return;
      _toast(
        _paymentMethod == 'cash'
            ? 'Order placed! You\'ll pay ${order.displayFare} cash on delivery.'
            : 'Order placed (${order.displayFare})! We\'ll ask you to pay once the rider confirms the fare at pickup.',
        AppColors.success,
      );
      Navigator.of(context).popUntil((route) => route.isFirst);
    } catch (e) {
      if (mounted) {
        _toast(e.toString().replaceFirst('Exception: ', ''), AppColors.danger);
        setState(() => _submitting = false);
      }
    }
  }

  void _toast(String message, Color color) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message), backgroundColor: color),
    );
  }

  @override
  Widget build(BuildContext context) {
    final cart = ref.watch(cartProvider);
    final vehiclesAsync = ref.watch(vehiclesListProvider);

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(title: const Text('Checkout')),
      body: cart.items.isEmpty
          ? const Center(child: Text('Your cart is empty'))
          : vehiclesAsync.when(
              loading: () => const Center(child: CircularProgressIndicator()),
              error: (e, _) => Center(child: Text('Could not load vehicles.\n$e', textAlign: TextAlign.center)),
              data: (vehicles) {
                _vehicle ??= vehicles.isEmpty
                    ? null
                    : vehicles.firstWhere((v) => v.name.toLowerCase().contains('motor'),
                        orElse: () => vehicles.first);
                return ListView(
                  padding: const EdgeInsets.all(20),
                  children: [
                    Text(cart.restaurant?.name ?? 'Order summary', style: AppTypography.h3),
                    const SizedBox(height: 8),
                    Card(
                      child: Column(
                        children: [
                          for (final item in cart.items.values)
                            ListTile(
                              dense: true,
                              title: Text('${item.quantity} × ${item.menuItem.name}'),
                              trailing: Text(Formatters.currency(item.totalPrice)),
                            ),
                          const Divider(height: 1),
                          ListTile(
                            dense: true,
                            title: Text('Item subtotal', style: AppTypography.bodyBold),
                            trailing: Text(Formatters.currency(cart.totalPrice),
                                style: AppTypography.bodyBold),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 20),
                    Text('Delivery details', style: AppTypography.h3),
                    const SizedBox(height: 8),
                    LocationPickerField(
                      controller: _addressController,
                      hint: 'Tap to set your delivery address',
                      isPickup: false,
                      emptyError: 'Set a delivery address',
                      onTap: _pickLocation,
                    ),
                    const SizedBox(height: 14),
                    TextField(
                      controller: _instructionsController,
                      decoration: const InputDecoration(
                        labelText: 'Instructions for the rider (optional)',
                      ),
                    ),
                    const SizedBox(height: 14),
                    DropdownButtonFormField<VehicleModel>(
                      initialValue: _vehicle,
                      isExpanded: true,
                      decoration: const InputDecoration(
                        labelText: 'Vehicle type',
                        prefixIcon: Icon(Icons.directions_rounded),
                      ),
                      items: [
                        for (final v in vehicles)
                          DropdownMenuItem(
                            value: v,
                            child: Text('${v.name} — from ${Formatters.currency(v.baseFare)}'),
                          ),
                      ],
                      onChanged: (v) => setState(() => _vehicle = v),
                    ),
                    const SizedBox(height: 14),
                    PaymentMethodSelector(
                      value: _paymentMethod,
                      onChanged: (v) => setState(() => _paymentMethod = v),
                      onlineNote: 'You\'ll be asked to pay once the rider confirms the fare at pickup.',
                    ),
                    const SizedBox(height: 16),
                    _fareBox(cart.totalPrice),
                    const SizedBox(height: 20),
                    AppButton(
                      text: 'Place Order',
                      icon: Icons.check_rounded,
                      isLoading: _submitting,
                      onPressed: vehicles.isEmpty ? null : _submit,
                    ),
                  ],
                );
              },
            ),
    );
  }

  Widget _fareBox(double subtotal) {
    final fee = _deliveryFee;
    final km = _distanceKm;
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
          Text(Formatters.currency(subtotal + (fee ?? 0)),
              style: AppTypography.h3.copyWith(color: AppColors.primary)),
          const SizedBox(height: 12),
          Container(height: 1, color: AppColors.cardBorder),
          const SizedBox(height: 12),
          _line('Item subtotal', Formatters.currency(subtotal)),
          const SizedBox(height: 4),
          _line('Delivery fee${km == null ? '' : ' (${Formatters.distance(km)}${_routeKm == null ? ', est.' : ''})'}',
              fee == null ? '—' : Formatters.currency(fee)),
        ],
      ),
    );
  }

  Widget _line(String label, String value) => Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Flexible(child: Text(label, style: AppTypography.caption.copyWith(color: AppColors.neutral500))),
          Text(value, style: AppTypography.caption.copyWith(color: AppColors.neutral700)),
        ],
      );
}
