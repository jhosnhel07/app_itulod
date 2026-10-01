import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/constants/app_colors.dart';
import '../../../../core/constants/app_typography.dart';
import '../../../../shared/widgets/app_button.dart';
import '../../../auth/presentation/providers/auth_provider.dart';
import '../../../customer/data/customer_repository.dart';

class ReferralsScreen extends ConsumerStatefulWidget {
  const ReferralsScreen({super.key});

  @override
  ConsumerState<ReferralsScreen> createState() => _ReferralsScreenState();
}

class _ReferralsScreenState extends ConsumerState<ReferralsScreen> {
  final _codeController = TextEditingController();
  bool _isLoading = false;

  @override
  void dispose() {
    _codeController.dispose();
    super.dispose();
  }

  Future<void> _redeemCode() async {
    final code = _codeController.text.trim();
    if (code.isEmpty) return;

    setState(() => _isLoading = true);
    try {
      final repo = ref.read(customerRepositoryProvider);
      await repo.applyReferralCode(code);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Referral code applied successfully!'), backgroundColor: AppColors.success),
      );
      // Reload profile to reflect referredBy update and wallet balance
      ref.read(authNotifierProvider.notifier).refreshProfile();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed: ${e.toString()}'), backgroundColor: AppColors.danger),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final profile = ref.watch(authNotifierProvider).profile;
    
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(title: const Text('Referrals')),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Card(
              child: Padding(
                padding: const EdgeInsets.all(20),
                child: Column(
                  children: [
                    const Icon(Icons.group_add_rounded, size: 48, color: AppColors.primary),
                    const SizedBox(height: 16),
                    Text('Invite Friends, Earn Rewards', style: AppTypography.h3),
                    const SizedBox(height: 8),
                    Text(
                      'Share your code with friends. When they sign up and use it, you both earn rewards!',
                      textAlign: TextAlign.center,
                      style: AppTypography.bodyMedium,
                    ),
                    const SizedBox(height: 24),
                    Container(
                      padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 24),
                      decoration: BoxDecoration(
                        color: AppColors.primary.withOpacity(0.1),
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: AppColors.primary),
                      ),
                      child: Text(
                        profile?.referralCode ?? 'NONE',
                        style: AppTypography.display.copyWith(color: AppColors.primary),
                      ),
                    ),
                    const SizedBox(height: 16),
                    AppButton(
                      text: 'Copy Code',
                      icon: Icons.copy_rounded,
                      onPressed: () {
                        if (profile?.referralCode != null) {
                          Clipboard.setData(ClipboardData(text: profile!.referralCode!));
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(content: Text('Referral code copied!')),
                          );
                        }
                      },
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 24),
            Text('Redeem a Referral Code', style: AppTypography.h3),
            const SizedBox(height: 8),
            if (profile != null && profile.referredBy != null) ...[
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Row(
                    children: [
                      const Icon(Icons.check_circle_rounded, color: AppColors.success),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Text(
                          'You were referred by ${profile.referredBy}',
                          style: AppTypography.bodyBold,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ] else ...[
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    children: [
                      TextField(
                        controller: _codeController,
                        decoration: const InputDecoration(
                          labelText: 'Enter Referral Code',
                          border: OutlineInputBorder(),
                          prefixIcon: Icon(Icons.card_giftcard_rounded),
                        ),
                        textCapitalization: TextCapitalization.characters,
                      ),
                      const SizedBox(height: 16),
                      AppButton(
                        text: 'Redeem Code',
                        type: AppButtonType.secondary,
                        isLoading: _isLoading,
                        onPressed: _redeemCode,
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
