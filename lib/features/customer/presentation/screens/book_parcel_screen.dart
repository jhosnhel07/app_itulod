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

const List<String> _parcelSizes = [
  'Small (fits a shoebox)',
  'Medium (fits a backpack)',
  'Large (needs two hands)',
];

class BookParcelScreen extends ConsumerStatefulWidget {
  const BookParcelScreen({super.key});

  @override
  ConsumerState<BookParcelScreen> createState() => _BookParcelScreenState();
}

class _BookParcelScreenState extends ConsumerState<BookParcelScreen> {
  final _formKey = GlobalKey<FormState>();
  final _senderNameController = TextEditingController();
  final _senderPhoneController = TextEditingController();
  final _senderAddressController = TextEditingController();
  final _receiverNameController = TextEditingController();
  final _receiverPhoneController = TextEditingController();
  final _receiverAddressController = TextEditingController();
  final _weightController = TextEditingController();
  final _descriptionController = TextEditingController();
  final _instructionsController = TextEditingController();
  VehicleModel? _vehicle;
  String _parcelSize = _parcelSizes.first;
  bool _submitting = false;

  @override
  void dispose() {
    for (final c in [
      _senderNameController,
      _senderPhoneController,
      _senderAddressController,
      _receiverNameController,
      _receiverPhoneController,
      _receiverAddressController,
      _weightController,
      _descriptionController,
      _instructionsController,
    ]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate() || _vehicle == null) return;

    setState(() => _submitting = true);
    try {
      final profile = ref.read(authNotifierProvider).profile!;
      await ref.read(customerRepositoryProvider).createParcelBooking(
            customerId: profile.id,
            vehicle: _vehicle!,
            senderName: _senderNameController.text,
            senderPhone: _senderPhoneController.text,
            senderAddress: _senderAddressController.text,
            receiverName: _receiverNameController.text,
            receiverPhone: _receiverPhoneController.text,
            receiverAddress: _receiverAddressController.text,
            parcelSize: _parcelSize,
            parcelWeight: double.tryParse(_weightController.text),
            parcelDescription: _descriptionController.text,
            instructions: _instructionsController.text,
          );

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Parcel booked! Pay the rider on completion.'),
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
      appBar: AppBar(title: const Text('Send Parcel')),
      body: vehiclesAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text('Could not load vehicles.\n$e', textAlign: TextAlign.center)),
        data: (vehicles) {
          _vehicle ??= vehicles.isNotEmpty ? vehicles.first : null;
          final fare = FareEstimator.estimateFare(
            _vehicle,
            FareEstimator.simulateDistanceKm(_senderAddressController.text, _receiverAddressController.text),
          );
          final distance = FareEstimator.simulateDistanceKm(
              _senderAddressController.text, _receiverAddressController.text);

          return SingleChildScrollView(
            padding: const EdgeInsets.all(20),
            child: Form(
              key: _formKey,
              onChanged: () => setState(() {}),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  _SectionCard(
                    title: 'Sender',
                    children: [
                      TextFormField(
                        controller: _senderNameController,
                        decoration: const InputDecoration(hintText: 'Your name *'),
                        validator: (v) => v == null || v.trim().isEmpty ? 'Enter the sender name' : null,
                      ),
                      const SizedBox(height: 14),
                      TextFormField(
                        controller: _senderPhoneController,
                        keyboardType: TextInputType.phone,
                        decoration: const InputDecoration(hintText: 'Contact number'),
                      ),
                      const SizedBox(height: 14),
                      TextFormField(
                        controller: _senderAddressController,
                        maxLines: 2,
                        decoration: const InputDecoration(hintText: 'Pickup address *'),
                        validator: (v) => v == null || v.trim().isEmpty ? 'Enter a pickup address' : null,
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  _SectionCard(
                    title: 'Receiver',
                    children: [
                      TextFormField(
                        controller: _receiverNameController,
                        decoration: const InputDecoration(hintText: 'Receiver name *'),
                        validator: (v) => v == null || v.trim().isEmpty ? 'Enter the receiver name' : null,
                      ),
                      const SizedBox(height: 14),
                      TextFormField(
                        controller: _receiverPhoneController,
                        keyboardType: TextInputType.phone,
                        decoration: const InputDecoration(hintText: 'Contact number'),
                      ),
                      const SizedBox(height: 14),
                      TextFormField(
                        controller: _receiverAddressController,
                        maxLines: 2,
                        decoration: const InputDecoration(hintText: 'Drop-off address *'),
                        validator: (v) => v == null || v.trim().isEmpty ? 'Enter a drop-off address' : null,
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  Card(
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('Parcel details', style: AppTypography.bodyBold),
                          const SizedBox(height: 10),
                          RadioGroup<String>(
                            groupValue: _parcelSize,
                            onChanged: (v) => setState(() => _parcelSize = v ?? _parcelSizes.first),
                            child: Column(
                              children: [
                                ..._parcelSizes.map((size) => RadioListTile<String>(
                                      value: size,
                                      dense: true,
                                      contentPadding: EdgeInsets.zero,
                                      activeColor: AppColors.primary,
                                      title: Text(size,
                                          style: AppTypography.bodyMedium.copyWith(fontSize: 14)),
                                    )),
                              ],
                            ),
                          ),
                          const SizedBox(height: 8),
                          TextFormField(
                            controller: _weightController,
                            keyboardType:
                                const TextInputType.numberWithOptions(decimal: true),
                            decoration:
                                const InputDecoration(hintText: 'Weight in kg (optional)'),
                          ),
                          const SizedBox(height: 14),
                          TextFormField(
                            controller: _descriptionController,
                            decoration: const InputDecoration(hintText: 'What is inside? (optional)'),
                          ),
                          const SizedBox(height: 14),
                          TextFormField(
                            controller: _instructionsController,
                            maxLines: 3,
                            decoration: const InputDecoration(
                                hintText: 'Special instructions (optional)'),
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
                      color: AppColors.success.withValues(alpha: 0.08),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: AppColors.success.withValues(alpha: 0.3)),
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
                                  style: AppTypography.h3.copyWith(color: AppColors.success)),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 16),
                  AppButton(
                    text: 'Book Parcel Delivery',
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

class _SectionCard extends StatelessWidget {
  final String title;
  final List<Widget> children;

  const _SectionCard({required this.title, required this.children});

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(title, style: AppTypography.bodyBold),
            const SizedBox(height: 12),
            ...children,
          ],
        ),
      ),
    );
  }
}

