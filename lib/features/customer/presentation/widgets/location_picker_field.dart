import 'package:flutter/material.dart';
import '../../../../core/constants/app_colors.dart';
import '../../../../core/constants/app_typography.dart';

/// A read-only address field that opens the full-screen map pin picker on tap —
/// the same interaction "Book a Ride" uses, reused by every customer booking
/// form so setting a location always means dropping a pin on the map.
class LocationPickerField extends StatelessWidget {
  final TextEditingController controller;

  /// Optional label rendered above the field.
  final String? label;

  final String hint;

  /// Pickup fields get a green dot; drop-off fields get a red marker.
  final bool isPickup;

  /// When non-null the field validates that an address has been chosen.
  final String? emptyError;

  /// Opens the picker. The caller writes the chosen address into [controller]
  /// and stores the coordinates.
  final VoidCallback onTap;

  const LocationPickerField({
    super.key,
    required this.controller,
    required this.hint,
    required this.onTap,
    this.label,
    this.isPickup = false,
    this.emptyError,
  });

  @override
  Widget build(BuildContext context) {
    final field = TextFormField(
      controller: controller,
      readOnly: true,
      maxLines: 2,
      minLines: 1,
      autovalidateMode: AutovalidateMode.onUserInteraction,
      onTap: onTap,
      style: AppTypography.bodyMedium.copyWith(fontSize: 14),
      decoration: InputDecoration(
        hintText: hint,
        prefixIcon: Icon(
          isPickup ? Icons.trip_origin_rounded : Icons.location_on_rounded,
          color: isPickup ? AppColors.success : AppColors.danger,
          size: isPickup ? 16 : 20,
        ),
        suffixIcon: Icon(Icons.map_outlined,
            size: 20, color: AppColors.iconMuted),
      ),
      validator: emptyError == null
          ? null
          : (v) => (v == null || v.trim().isEmpty) ? emptyError : null,
    );

    if (label == null) return field;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          label!,
          style: AppTypography.bodyMedium.copyWith(
            fontSize: 14,
            color: AppColors.neutral600,
          ),
        ),
        const SizedBox(height: 6),
        field,
      ],
    );
  }
}
