import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../../core/constants/app_colors.dart';
import '../../../../core/constants/app_typography.dart';
import '../../../../shared/widgets/app_button.dart';
import '../../../../shared/widgets/avatar_widget.dart';
import '../../../../shared/widgets/status_badge.dart';
import '../../../auth/presentation/providers/auth_provider.dart';

class RiderHomeScreen extends ConsumerWidget {
  const RiderHomeScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final profile = ref.watch(authNotifierProvider).profile;
    final application = ref.watch(authNotifierProvider).riderApplication;

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: const Text('Rider Dashboard'),
        actions: [
          IconButton(
            icon: const Icon(Icons.logout),
            onPressed: () => ref.read(authNotifierProvider.notifier).signOut(),
          ),
        ],
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(20),
                  child: Row(
                    children: [
                      AvatarWidget(
                        name: profile?.fullName ?? 'Rider',
                        url: profile?.avatarUrl,
                        radius: 28,
                      ),
                      const SizedBox(width: 16),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(profile?.fullName ?? 'Rider Partner', style: AppTypography.h3),
                            const SizedBox(height: 4),
                            Text(
                              profile?.email ?? '',
                              style: AppTypography.captionDark,
                            ),
                            const SizedBox(height: 6),
                            Row(
                              children: [
                                const StatusBadge(status: 'Approved Rider'),
                                if (application != null) ...[
                                  const SizedBox(width: 8),
                                  Text(
                                    application.vehicleType,
                                    style: AppTypography.captionDark,
                                  ),
                                ],
                              ],
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 24),
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(20),
                  child: Column(
                    children: [
                      const Icon(Icons.check_circle_outline, color: AppColors.success, size: 48),
                      const SizedBox(height: 12),
                      Text('Ready for Jobs', style: AppTypography.h3),
                      const SizedBox(height: 6),
                      Text(
                        'You are an approved iTULOD partner. The live job feed and dispatch module is ready for connection.',
                        style: AppTypography.body.copyWith(color: AppColors.neutral600),
                        textAlign: TextAlign.center,
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 32),
              AppButton(
                text: 'Log Out',
                type: AppButtonType.outline,
                onPressed: () => ref.read(authNotifierProvider.notifier).signOut(),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
