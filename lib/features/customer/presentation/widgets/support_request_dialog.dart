import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../../core/constants/app_colors.dart';
import '../../../../core/constants/app_typography.dart';
import '../../../../shared/models/booking_models.dart';
import '../../data/customer_repository.dart';

/// "Report an issue" — a refund, dispute or other request, optionally about a
/// specific booking. Same form and `support_requests` table as the web's
/// support-request modal; admins answer it from the web Support tab.
Future<void> showSupportRequestDialog(
  BuildContext context,
  WidgetRef ref, {
  BookingBase? booking,
}) async {
  final subjectController = TextEditingController();
  final messageController = TextEditingController();
  String category = 'refund';

  final submitted = await showDialog<bool>(
    context: context,
    builder: (dialogContext) => StatefulBuilder(
      builder: (context, setDialogState) => AlertDialog(
        title: const Text('Report an issue'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (booking != null) ...[
                Text(
                  'About your ${booking.kind.label.toLowerCase()} booking #${booking.id.substring(0, 8)}.',
                  style: AppTypography.captionDark,
                ),
                const SizedBox(height: 12),
              ],
              DropdownButtonFormField<String>(
                initialValue: category,
                decoration: const InputDecoration(labelText: 'Category', isDense: true),
                items: const [
                  DropdownMenuItem(value: 'refund', child: Text('Refund request')),
                  DropdownMenuItem(value: 'dispute', child: Text('Dispute a charge')),
                  DropdownMenuItem(value: 'other', child: Text('Something else')),
                ],
                onChanged: (v) => setDialogState(() => category = v ?? 'other'),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: subjectController,
                decoration: const InputDecoration(labelText: 'Subject', isDense: true),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: messageController,
                maxLines: 4,
                decoration: const InputDecoration(
                  labelText: 'Details',
                  hintText: 'Rider was late, item damaged, overcharged…',
                  isDense: true,
                ),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () {
              if (subjectController.text.trim().isEmpty ||
                  messageController.text.trim().isEmpty) {
                ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
                  content: Text('Add a subject and details.'),
                  backgroundColor: AppColors.danger,
                ));
                return;
              }
              Navigator.pop(dialogContext, true);
            },
            child: const Text('Send'),
          ),
        ],
      ),
    ),
  );

  if (submitted != true) return;
  try {
    await ref.read(customerRepositoryProvider).createSupportRequest(
          category: category,
          subject: subjectController.text,
          message: messageController.text,
          booking: booking,
        );
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text("Sent! We'll get back to you soon."),
        backgroundColor: AppColors.success,
      ));
    }
  } catch (e) {
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text('Could not send your request: $e'),
        backgroundColor: AppColors.danger,
      ));
    }
  }
}
