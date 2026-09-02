import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../../core/constants/app_colors.dart';
import '../../../../core/constants/app_typography.dart';
import '../../../../core/utils/fare_estimator.dart';
import '../../../../core/utils/formatters.dart';
import '../../../../shared/models/vehicle_model.dart';
import '../../../../shared/widgets/app_button.dart';
import '../../../auth/presentation/providers/auth_provider.dart';
import '../../data/customer_repository.dart';

class BookFoodScreen extends ConsumerStatefulWidget {
  const BookFoodScreen({super.key});

  @override
  ConsumerState<BookFoodScreen> createState() => _BookFoodScreenState();
}

class _BookFoodScreenState extends ConsumerState<BookFoodScreen> {
  final _formKey = GlobalKey<FormState>();
  final _restaurantController = TextEditingController();
  final _pickupController = TextEditingController();
  final _addressController = TextEditingController();
  final _instructionsController = TextEditingController();
  VehicleModel? _vehicle;
  bool _submitting = false;

  @override
  void dispose() {
    _restaurantController.dispose();
    _pickupController.dispose();
    _addressController.dispose();
    _instructionsController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate() || _vehicle == null) return;

    setState(() => _submitting = true);
    try {
      final profile = ref.read(authNotifierProvider).profile!;
      await ref.read(customerRepositoryProvider).createFoodBooking(
            customerId: profile.id,
            vehicle: _vehicle!,
            restaurantName: _restaurantController.text,
            pickupAddress: _pickupController.text,
            deliveryAddress: _addressController.text,
            instructions: _instructionsController.text,
          );

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Food delivery booked! Pay the rider on completion.'),
          backgroundColor: AppColors.success,
        ),
      );
      Navigator.pop(context);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Booking failed: $e'), backgroundColor: AppColors.danger),
        );
      }
    }
    if (mounted) setState(() => _submitting = false);
  }

  @override
  Widget build(BuildContext context) {
    final vehiclesAsync = ref.watch(vehiclesListProvider);

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(title: const Text('Food Delivery')),
      body: vehiclesAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text('Could not load vehicles.\n$e', textAlign: TextAlign.center)),
        data: (vehicles) {
          _vehicle ??= vehicles.isNotEmpty ? vehicles.first : null;
          final fare = FareEstimator.estimateFare(
            _vehicle,
            FareEstimator.simulateDistanceKm(_pickupController.text, _addressController.text),
          );
          final distance = FareEstimator.simulateDistanceKm(_pickupController.text, _addressController.text);

          return SingleChildScrollView(
            padding: const EdgeInsets.all(20),
            child: Form(
              key: _formKey,
              onChanged: () => setState(() {}),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Card(
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Column(
                        children: [
                          TextFormField(
                            controller: _restaurantController,
                            decoration: const InputDecoration(
                              hintText: 'Restaurant name *',
                              prefixIcon: Icon(Icons.storefront_rounded, size: 20),
                            ),
                            validator: (v) =>
                                v == null || v.trim().isEmpty ? 'Enter the restaurant name' : null,
                          ),
                          const SizedBox(height: 14),
                          TextFormField(
                            controller: _pickupController,
                            decoration: const InputDecoration(
                              hintText: 'Pickup address (restaurant location) *',
                              prefixIcon: Icon(Icons.circle_outlined, size: 20),
                            ),
                            validator: (v) =>
                                v == null || v.trim().isEmpty ? 'Enter a pickup address' : null,
                          ),
                          const SizedBox(height: 14),
                          TextFormField(
                            controller: _addressController,
                            maxLines: 2,
                            decoration: const InputDecoration(
                              hintText: 'Deliver to (your address) *',
                              prefixIcon: Icon(Icons.home_outlined, size: 20),
                            ),
                            validator: (v) =>
                                v == null || v.trim().isEmpty ? 'Enter a delivery address' : null,
                          ),
                          const SizedBox(height: 14),
                          TextFormField(
                            controller: _instructionsController,
                            maxLines: 3,
                            decoration: const InputDecoration(
                              hintText: 'Special instructions (optional)',
                              prefixIcon: Icon(Icons.notes_rounded, size: 20),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),
                  DropdownButtonFormField<VehicleModel>(
                    initialValue: _vehicle,
                    isExpanded: true,
                    decoration: const InputDecoration(
                      labelText: 'Vehicle type *',
                      prefixIcon: Icon(Icons.directions_rounded),
                    ),
                    items: vehicles
                        .map((v) => DropdownMenuItem(value: v, child: Text(v.name)))
                        .toList(),
                    onChanged: (v) => setState(() => _vehicle = v),
                  ),
                  const SizedBox(height: 16),
                  Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: AppColors.secondary.withValues(alpha: 0.08),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: AppColors.secondary.withValues(alpha: 0.3)),
                    ),
                    child: Row(
                      children: [
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text('ESTIMATED DISTANCE', style: AppTypography.caption),
                              Text(Formatters.distance(distance), style: AppTypography.h3),
                            ],
                          ),
                        ),
                        Container(width: 1, height: 36, color: AppColors.cardBorder),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.end,
                            children: [
                              Text('ESTIMATED FARE', style: AppTypography.caption),
                              Text(Formatters.currency(fare),
                                  style: AppTypography.h3.copyWith(color: AppColors.secondaryDark)),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 8),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 4),
                    child: Text(
                      'Food deliveries are paid in cash when your order arrives.',
                      style: AppTypography.captionDark,
                      textAlign: TextAlign.center,
                    ),
                  ),
                  const SizedBox(height: 16),
                  AppButton(
                    text: 'Book Food Delivery',
                    isLoading: _submitting,
                    onPressed: vehicles.isEmpty ? null : _submit,
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }
}

