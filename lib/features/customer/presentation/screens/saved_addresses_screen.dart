import 'package:flutter/material.dart';
import '../../../../shared/widgets/loading_skeleton.dart';
import '../../../../shared/widgets/empty_state.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../../core/constants/app_colors.dart';
import '../../../../core/constants/app_typography.dart';
import '../../../../shared/widgets/app_button.dart';
import '../../../../shared/widgets/app_confirm_dialog.dart';
import '../providers/saved_addresses_provider.dart';
import 'map_picker_screen.dart';

class SavedAddressesScreen extends ConsumerWidget {
  const SavedAddressesScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final asyncAddresses = ref.watch(savedAddressesProvider);

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: const Text('Saved Addresses'),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh_rounded),
            tooltip: 'Refresh',
            onPressed: () => ref.read(savedAddressesProvider.notifier).load(),
          ),
        ],
      ),
      body: asyncAddresses.when(
        loading: () => const SkeletonList(),
        error: (e, _) => Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.error_outline_rounded, size: 48, color: AppColors.danger),
                const SizedBox(height: 12),
                Text(
                  'Failed to load saved addresses',
                  style: AppTypography.h3,
                ),
                const SizedBox(height: 8),
                Text(
                  '$e',
                  style: AppTypography.caption,
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 20),
                AppButton(
                  text: 'Retry',
                  icon: Icons.refresh_rounded,
                  type: AppButtonType.outline,
                  onPressed: () => ref.read(savedAddressesProvider.notifier).load(),
                ),
              ],
            ),
          ),
        ),
        data: (addresses) {
          if (addresses.isEmpty) {
            return RefreshIndicator(
              onRefresh: () => ref.read(savedAddressesProvider.notifier).load(),
              child: ListView(
                physics: const AlwaysScrollableScrollPhysics(),
                children: [
                  SizedBox(
                    height: MediaQuery.of(context).size.height * 0.6,
                    child: const Center(
                      child: EmptyState(
                        icon: Icons.bookmark_border_rounded,
                        title: 'No saved addresses yet',
                        message: 'Add one to book rides faster.',
                      ),
                    ),
                  ),
                ],
              ),
            );
          }
          return RefreshIndicator(
            onRefresh: () => ref.read(savedAddressesProvider.notifier).load(),
            child: ListView.builder(
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
                        final confirmed = await showAppConfirm(
                          context,
                          title: 'Remove ${addr.label}?',
                          message: 'You can save it again any time.',
                          confirmText: 'Remove',
                          danger: true,
                          icon: Icons.location_off_rounded,
                        );
                        if (confirmed && context.mounted) {
                          try {
                            await ref.read(savedAddressesProvider.notifier).delete(addr.id);
                            if (context.mounted) {
                              ScaffoldMessenger.of(context).showSnackBar(
                                const SnackBar(content: Text('Address deleted')),
                              );
                            }
                          } catch (e) {
                            if (context.mounted) {
                              ScaffoldMessenger.of(context).showSnackBar(
                                SnackBar(content: Text('Failed to delete: $e')),
                              );
                            }
                          }
                        }
                      },
                    ),
                  ),
                );
              },
            ),
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
              );
              if (picked == null || !context.mounted) return;

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
                      TextButton(
                        onPressed: () => Navigator.pop(ctx, ctrl.text.trim()),
                        child: const Text('Save'),
                      ),
                    ],
                  );
                },
              );

              if (labelResult == null || labelResult.isEmpty || !context.mounted) return;

              try {
                final saved = await ref.read(savedAddressesProvider.notifier).add(
                  labelResult,
                  picked.address,
                  picked.point.latitude,
                  picked.point.longitude,
                );
                if (!context.mounted) return;
                if (saved != null) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('Address saved')),
                  );
                }
              } catch (e) {
                if (!context.mounted) return;
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(content: Text('Failed to save address: $e')),
                );
              }
            },
          ),
        ),
      ),
    );
  }
}
