import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../../core/constants/app_colors.dart';
import '../../../../core/constants/app_strings.dart';
import '../../../../core/constants/app_typography.dart';
import '../../../../shared/models/rider_application_model.dart';
import '../../../../shared/widgets/app_button.dart';
import '../../../../shared/widgets/status_badge.dart';
import '../providers/auth_provider.dart';

class RiderUnderReviewScreen extends ConsumerWidget {
  const RiderUnderReviewScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final authState = ref.watch(authNotifierProvider);
    final application = authState.riderApplication;
    final isRejected = application?.status == ApplicationStatus.rejected;

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: const Text('Rider Application Status'),
        actions: [
          IconButton(
            icon: const Icon(Icons.logout),
            onPressed: () => ref.read(authNotifierProvider.notifier).signOut(),
          ),
        ],
      ),
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 440),
              child: Card(
                child: Padding(
                  padding: const EdgeInsets.all(24),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Container(
                        padding: const EdgeInsets.all(20),
                        decoration: BoxDecoration(
                          color: isRejected ? AppColors.danger50 : AppColors.warning50,
                          shape: BoxShape.circle,
                        ),
                        child: Icon(
                          isRejected ? Icons.warning_amber_rounded : Icons.pending_actions_rounded,
                          size: 56,
                          color: isRejected ? AppColors.danger : AppColors.warning,
                        ),
                      ),
                      const SizedBox(height: 20),
                      Text(
                        isRejected ? AppStrings.rejectedTitle : AppStrings.pendingReviewTitle,
                        style: AppTypography.h2,
                        textAlign: TextAlign.center,
                      ),
                      const SizedBox(height: 12),
                      StatusBadge(
                        status: application?.status.toDbString() ?? 'pending',
                        fontSize: 13,
                      ),
                      const SizedBox(height: 16),
                      Text(
                        isRejected
                            ? (application?.notes != null && application!.notes!.isNotEmpty
                                ? 'Feedback from Administrator:\n\n""'
                                : 'Your application could not be approved at this time. Please contact support or reapply with updated documents.')
                            : AppStrings.pendingReviewDesc,
                        style: AppTypography.body.copyWith(
                          color: isRejected ? AppColors.danger : AppColors.neutral600,
                        ),
                        textAlign: TextAlign.center,
                      ),
                      const SizedBox(height: 32),
                      AppButton(
                        text: 'Refresh Status',
                        isLoading: authState.isLoading,
                        onPressed: () => ref.read(authNotifierProvider.notifier).refreshProfile(),
                      ),
                      const SizedBox(height: 12),
                      AppButton(
                        text: 'Log Out',
                        type: AppButtonType.outline,
                        onPressed: () => ref.read(authNotifierProvider.notifier).signOut(),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
