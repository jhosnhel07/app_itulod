import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../../core/constants/app_colors.dart';
import '../../../../core/constants/app_typography.dart';
import '../../../../shared/widgets/app_button.dart';
import '../providers/saved_addresses_provider.dart';
import 'map_picker_screen.dart';

class SavedAddressesScreen extends ConsumerWidget {
  const SavedAddressesScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final asyncAddresses = ref.watch(savedAddressesProvider);

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(title: const Text('Saved Addresses')),
      body: asyncAddresses.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text('Error: $e')),
        data: (addresses) {
          if (addresses.isEmpty) {
            return Center(
              child: Text(
                'No saved addresses yet.\nAdd one to quickly book rides.',
                textAlign: TextAlign.center,
                style: AppTypography.body.copyWith(color: AppColors.textLight),
              ),
            );
          }
          return ListView.builder(
            padding: const EdgeInsets.all(20),
            itemCount: addresses.length,
            itemBuilder: (context, index) {
              final addr = addresses[index];
              return Card(
                margin: const EdgeInsets.only(bottom: 12),
                child: ListTile(
                  leading: const Icon(Icons.location_on_rounded, color: AppColors.primary),
                  title: Text(addr.label, style: AppTypography.bodyBold),
                  subtitle: Text(
                    addr.address,
                    style: AppTypography.caption,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                  trailing: IconButton(
                    icon: const Icon(Icons.delete_outline_rounded, color: AppColors.danger),
                    onPressed: () async {
                      final confirmed = await showDialog<bool>(
                        context: context,
                        builder: (ctx) => AlertDialog(
                          title: const Text('Delete Address?'),
                          content: Text('Are you sure you want to delete ${addr.label}?'),
                          actions: [
                            TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
                            TextButton(
                              onPressed: () => Navigator.pop(ctx, true),
                              style: TextButton.styleFrom(foregroundColor: AppColors.danger),
                              child: const Text('Delete'),
                            ),
                          ],
                        ),
                      );
                      if (confirmed == true) {
                        ref.read(savedAddressesProvider.notifier).delete(addr.id);
                      }
                    },
                  ),
                ),
              );
            },
          );
        },
      ),
      bottomNavigationBar: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: AppButton(
            text: 'Add New Address',
            icon: Icons.add_location_alt_rounded,
            onPressed: () async {
              final picked = await MapPickerScreen.show(
                context,
                title: 'Set Location',
                pinColor: AppColors.primary,
              );
              if (picked == null || !context.mounted) return;
              
              String label = '';
              final labelResult = await showDialog<String>(
                context: context,
                builder: (ctx) {
                  final ctrl = TextEditingController();
                  return AlertDialog(
                    title: const Text('Label Address'),
                    content: TextField(
                      controller: ctrl,
                      decoration: const InputDecoration(hintText: 'e.g. Home, Work'),
                      autofocus: true,
                    ),
                    actions: [
                      TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
                      TextButton(onPressed: () => Navigator.pop(ctx, ctrl.text.trim()), child: const Text('Save')),
                    ],
                  );
                },
              );
              
              if (labelResult == null || labelResult.isEmpty) return;
              
              ref.read(savedAddressesProvider.notifier).add(
                labelResult,
                picked.address,
                picked.point.latitude,
                picked.point.longitude,
              );
            },
          ),
        ),
      ),
    );
  }
}
