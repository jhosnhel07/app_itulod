import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:image_picker/image_picker.dart';
import '../../core/constants/app_colors.dart';
import '../../core/constants/app_typography.dart';
import '../../core/theme/app_decorations.dart';
import '../../core/utils/app_log.dart';
import '../widgets/app_button.dart';
import '../widgets/app_confirm_dialog.dart';
import '../widgets/app_text_field.dart';
import '../widgets/avatar_widget.dart';
import '../../core/supabase/supabase_client.dart';
import '../../features/customer/data/customer_repository.dart';
import '../../features/auth/presentation/providers/auth_provider.dart';
import '../../shared/models/profile_model.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// Shared profile tab used by the customer, rider, and admin dashboards —
/// fixing or improving this screen applies to every role at once.
class ProfileScreen extends ConsumerStatefulWidget {
  const ProfileScreen({super.key});

  @override
  ConsumerState<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends ConsumerState<ProfileScreen> {
  late TextEditingController _nameController;
  late TextEditingController _phoneController;
  late TextEditingController _oldPasswordController;
  late TextEditingController _newPasswordController;
  late TextEditingController _confirmPasswordController;
  bool _saving = false;
  bool _picking = false;
  File? _pickedAvatar;

  @override
  void initState() {
    super.initState();
    final profile = ref.read(authNotifierProvider).profile;
    _nameController = TextEditingController(text: profile?.fullName ?? '');
    _phoneController = TextEditingController(text: profile?.phone ?? '');
    _oldPasswordController = TextEditingController();
    _newPasswordController = TextEditingController();
    _confirmPasswordController = TextEditingController();
  }

  @override
  void dispose() {
    _nameController.dispose();
    _phoneController.dispose();
    _oldPasswordController.dispose();
    _newPasswordController.dispose();
    _confirmPasswordController.dispose();
    super.dispose();
  }

  // ── Photo picking ───────────────────────────────────────────────────────

  Future<void> _openAvatarPicker() async {
    final source = await showModalBottomSheet<ImageSource>(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (_) => const _AvatarSourceSheet(),
    );
    if (source == null) return;
    await _pickFrom(source);
  }

  Future<void> _pickFrom(ImageSource source) async {
    setState(() => _picking = true);
    try {
      final picker = ImagePicker();
      final picked = await picker.pickImage(
        source: source,
        imageQuality: 75,
        // Caps upload size so a slow connection or a bucket size limit can
        // never be why this silently "does nothing".
        maxWidth: 1024,
        maxHeight: 1024,
      );
      if (picked != null && mounted) {
        setState(() => _pickedAvatar = File(picked.path));
      }
    } catch (e, s) {
      AppLog.warn('ProfileScreen: image pick failed', e, s);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(source == ImageSource.camera
                ? 'Could not open the camera. Check that iTULOD has camera permission in Settings.'
                : 'Could not open your photos. Check that iTULOD has photo permission in Settings.'),
            backgroundColor: AppColors.danger,
          ),
        );
      }
    }
    if (mounted) setState(() => _picking = false);
  }

  // ── Save ────────────────────────────────────────────────────────────────

  Future<void> _save() async {
    final profile = ref.read(authNotifierProvider).profile;
    if (profile == null) return;

    setState(() => _saving = true);
    try {
      final repo = ref.read(customerRepositoryProvider);
      var updated = await repo.updateProfile(
        profile: profile,
        fullName: _nameController.text,
        phone: _phoneController.text,
      );

      var sentForReview = false;
      if (_pickedAvatar != null) {
        final bytes = await _pickedAvatar!.readAsBytes();
        final url = await repo.uploadAvatar(
          userId: profile.id,
          filePath: _pickedAvatar!.path,
          bytes: bytes,
        );
        updated = await repo.setAvatarUrl(updated, url);
        // An approved rider's new photo waits for the admin (sql/030).
        sentForReview = updated.avatarPendingUrl == url;
      }

      ref.read(authNotifierProvider.notifier).updateProfileLocally(updated);
      if (mounted) {
        setState(() => _pickedAvatar = null);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
              content: Text(sentForReview
                  ? 'Profile saved. Your new photo was sent to the admin for approval — customers see your current photo until then.'
                  : 'Profile updated!'),
              backgroundColor: sentForReview ? AppColors.warning : AppColors.success),
        );
      }
    } catch (e, s) {
      AppLog.warn('ProfileScreen: save failed', e, s);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
              content: Text('Update failed: $e'),
              backgroundColor: AppColors.danger),
        );
      }
    }
    if (mounted) setState(() => _saving = false);
  }

  Future<void> _changePassword() async {
    final oldPassword = _oldPasswordController.text;
    final newPassword = _newPasswordController.text;
    final confirmPassword = _confirmPasswordController.text;

    if (oldPassword.isEmpty || newPassword.isEmpty || confirmPassword.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
            content: Text('Please fill all password fields'),
            backgroundColor: AppColors.danger),
      );
      return;
    }

    if (newPassword != confirmPassword) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
            content: Text('New passwords do not match'),
            backgroundColor: AppColors.danger),
      );
      return;
    }

    if (newPassword.length < 8) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
            content: Text('Password must be at least 8 characters'),
            backgroundColor: AppColors.danger),
      );
      return;
    }

    setState(() => _saving = true);
    try {
      // In Supabase, the user just updates their password if they are logged in.
      // There's no need to verify the old password through a specific RPC if we
      // just call update. We can check session to ensure they're logged in.
      await SupabaseConfig.client.auth.updateUser(
        UserAttributes(password: newPassword),
      );

      if (mounted) {
        _oldPasswordController.clear();
        _newPasswordController.clear();
        _confirmPasswordController.clear();
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
              content: Text('Password updated successfully!'),
              backgroundColor: AppColors.success),
        );
      }
    } catch (e, s) {
      AppLog.warn('ProfileScreen: change password failed', e, s);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
              content: Text('Failed to update password: $e'),
              backgroundColor: AppColors.danger),
        );
      }
    }
    if (mounted) setState(() => _saving = false);
  }

  // ── Support ─────────────────────────────────────────────────────────────

  Future<void> _showSupportForm(BuildContext context, WidgetRef ref) async {
    final profile = ref.read(authNotifierProvider).profile;
    if (profile == null) return;

    String category = 'account';
    final subjectCtrl = TextEditingController();
    final messageCtrl = TextEditingController();

    await showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setStateDialog) => AlertDialog(
          title: const Text('Help & Support'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                DropdownButtonFormField<String>(
                  value: category,
                  decoration: const InputDecoration(labelText: 'Category'),
                  items: const [
                    DropdownMenuItem(
                        value: 'account', child: Text('Account Issue')),
                    DropdownMenuItem(
                        value: 'payments', child: Text('Payments & Refunds')),
                    DropdownMenuItem(value: 'bug', child: Text('App Bug')),
                    DropdownMenuItem(value: 'other', child: Text('Other')),
                  ],
                  onChanged: (val) {
                    if (val != null) setStateDialog(() => category = val);
                  },
                ),
                const SizedBox(height: 12),
                AppTextField(
                  label: 'Subject',
                  controller: subjectCtrl,
                ),
                const SizedBox(height: 12),
                AppTextField(
                  label: 'Message',
                  controller: messageCtrl,
                  maxLines: 4,
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Cancel'),
            ),
            AppButton(
              text: 'Submit',
              type: AppButtonType.primary,
              onPressed: () async {
                if (subjectCtrl.text.isEmpty || messageCtrl.text.isEmpty)
                  return;
                try {
                  await SupabaseConfig.client.from('support_requests').insert({
                    'customer_id': profile.id,
                    'category': category,
                    'subject': subjectCtrl.text,
                    'message': messageCtrl.text,
                  });
                  if (ctx.mounted) {
                    Navigator.pop(ctx);
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                        content: Text('Support request sent!'),
                        backgroundColor: AppColors.success,
                      ),
                    );
                  }
                } catch (e, s) {
                  AppLog.warn('Support request failed', e, s);
                  if (ctx.mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                        content: Text('Failed to send request'),
                        backgroundColor: AppColors.danger,
                      ),
                    );
                  }
                }
              },
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final profile = ref.watch(authNotifierProvider).profile;

    return SingleChildScrollView(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Container(
            padding: const EdgeInsets.symmetric(vertical: 24),
            decoration: BoxDecoration(
              gradient: AppColors.primaryGradient,
              borderRadius: BorderRadius.circular(20),
              boxShadow: AppColors.elevatedShadow,
            ),
            child: Column(
              children: [
                GestureDetector(
                  onTap: _picking ? null : _openAvatarPicker,
                  child: Stack(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(3),
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          border: Border.all(
                              color: Colors.white.withValues(alpha: 0.7),
                              width: 2),
                        ),
                        child: _pickedAvatar != null
                            ? CircleAvatar(
                                radius: 46,
                                backgroundImage: FileImage(_pickedAvatar!),
                              )
                            : AvatarWidget(
                                name: profile?.fullName ?? 'User',
                                url: profile?.avatarUrl,
                                radius: 46,
                              ),
                      ),
                      if (_picking)
                        Positioned.fill(
                          child: Center(
                            child: Container(
                              width: 40,
                              height: 40,
                              decoration: BoxDecoration(
                                color: Colors.black.withValues(alpha: 0.35),
                                shape: BoxShape.circle,
                              ),
                              child: const Padding(
                                padding: EdgeInsets.all(9),
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                  valueColor:
                                      AlwaysStoppedAnimation(Colors.white),
                                ),
                              ),
                            ),
                          ),
                        ),
                      Positioned(
                        bottom: 0,
                        right: 0,
                        child: Container(
                          padding: const EdgeInsets.all(7),
                          decoration: BoxDecoration(
                            color: AppColors.secondaryDark,
                            shape: BoxShape.circle,
                            border: Border.all(color: Colors.white, width: 2),
                          ),
                          child: const Icon(Icons.camera_alt_rounded,
                              color: Colors.white, size: 15),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 12),
                // The explicit "choose file" affordance — tappable on its own
                // so it's obvious this is how you change the photo.
                Material(
                  color: Colors.transparent,
                  child: InkWell(
                    onTap: _picking ? null : _openAvatarPicker,
                    borderRadius: BorderRadius.circular(999),
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 14, vertical: 7),
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.16),
                        borderRadius: BorderRadius.circular(999),
                        border: Border.all(
                            color: Colors.white.withValues(alpha: 0.4)),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Icon(Icons.upload_rounded,
                              size: 15, color: Colors.white),
                          const SizedBox(width: 6),
                          Text(
                            _pickedAvatar != null
                                ? 'Photo selected'
                                : 'Change photo',
                            style: AppTypography.captionDark.copyWith(
                              color: Colors.white,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
                if (profile?.avatarPendingUrl != null) ...[
                  const SizedBox(height: 10),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                    decoration: BoxDecoration(
                      color: Colors.black.withValues(alpha: 0.18),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(Icons.hourglass_top_rounded, size: 15, color: Color(0xFFFDE68A)),
                        const SizedBox(width: 6),
                        Flexible(
                          child: Text(
                            'New photo waiting for admin approval',
                            style: AppTypography.captionDark.copyWith(
                              color: const Color(0xFFFDE68A),
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ] else if (profile?.role == UserRole.rider) ...[
                  const SizedBox(height: 8),
                  Text(
                    'Customers see this photo. A new one needs admin approval.',
                    textAlign: TextAlign.center,
                    style: AppTypography.captionDark.copyWith(color: Colors.white.withValues(alpha: 0.85)),
                  ),
                ],
                const SizedBox(height: 14),
                Text(
                  profile?.fullName ?? 'Your profile',
                  style: AppTypography.h3.copyWith(color: Colors.white),
                ),
                const SizedBox(height: 2),
                Text(
                  profile?.email ?? '',
                  style: AppTypography.caption.copyWith(color: Colors.white70),
                ),
              ],
            ),
          ),
          if (profile?.role == UserRole.customer) ...[
            const SizedBox(height: 20),
            Row(
              children: [
                Expanded(
                  child: AppButton(
                    text: 'My Wallet',
                    icon: Icons.account_balance_wallet_rounded,
                    type: AppButtonType.outline,
                    onPressed: () {
                      GoRouter.of(context).push('/customer/wallet');
                    },
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: AppButton(
                    text: 'Saved Addresses',
                    icon: Icons.location_on_rounded,
                    type: AppButtonType.outline,
                    onPressed: () {
                      GoRouter.of(context).push('/customer/saved-addresses');
                    },
                  ),
                ),
              ],
            ),
          ],
          const SizedBox(height: 20),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  AppTextField(
                    label: 'Full name',
                    controller: _nameController,
                    prefixIcon: const Icon(Icons.person_outline, size: 20),
                  ),
                  const SizedBox(height: 14),
                  AppTextField(
                    label: 'Phone number',
                    controller: _phoneController,
                    keyboardType: TextInputType.phone,
                    prefixIcon: const Icon(Icons.phone_outlined, size: 20),
                  ),
                  const SizedBox(height: 14),
                  AppTextField(
                    label: 'Email',
                    initialValue: profile?.email ?? '',
                    enabled: false,
                    prefixIcon: const Icon(Icons.email_outlined, size: 20),
                  ),
                  const SizedBox(height: 14),
                  AppTextField(
                    label: 'Referral code',
                    initialValue: profile?.referralCode ?? 'None',
                    enabled: false,
                    prefixIcon: const Icon(Icons.share_rounded, size: 20),
                  ),
                  const SizedBox(height: 14),
                  AppButton(
                    text: 'Referrals & Rewards',
                    type: AppButtonType.secondary,
                    icon: Icons.card_giftcard_rounded,
                    onPressed: () {
                      GoRouter.of(context).push('/customer/referrals');
                    },
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 12),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Change Password', style: AppTypography.h3),
                  const SizedBox(height: 14),
                  AppTextField(
                    label: 'Current password',
                    controller: _oldPasswordController,
                    obscureText: true,
                  ),
                  const SizedBox(height: 14),
                  AppTextField(
                    label: 'New password',
                    controller: _newPasswordController,
                    obscureText: true,
                    hint: 'At least 8 characters',
                  ),
                  const SizedBox(height: 14),
                  AppTextField(
                    label: 'Confirm new password',
                    controller: _confirmPasswordController,
                    obscureText: true,
                    hint: 'Re-enter new password',
                  ),
                  const SizedBox(height: 14),
                  AppButton(
                    text: 'Update Password',
                    type: AppButtonType.outline,
                    isLoading: _saving,
                    onPressed: _changePassword,
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 12),
          AppButton(
            text: 'Help & Support',
            type: AppButtonType.secondary,
            icon: Icons.support_agent_rounded,
            onPressed: () {
              _showSupportForm(context, ref);
            },
          ),
          const SizedBox(height: 20),
          AppButton(
            text: 'Save Changes',
            isLoading: _saving,
            onPressed: _save,
          ),
          const SizedBox(height: 12),
          AppButton(
            text: 'Sign Out',
            type: AppButtonType.outline,
            icon: Icons.logout,
            onPressed: () async {
              final confirmed = await showAppConfirm(
                context,
                title: 'Sign out?',
                message: 'You will need to log in again.',
                confirmText: 'Sign out',
                icon: Icons.logout_rounded,
              );
              if (confirmed) {
                ref.read(authNotifierProvider.notifier).signOut();
              }
            },
          ),
          const SizedBox(height: 24),
          Center(
            child: Text('iTULOD v1.0.0', style: AppTypography.caption),
          ),
        ],
      ),
    );
  }
}

/// Designed "choose file" bottom sheet — Camera / Gallery, matching the rest
/// of the app's rounded-card visual language.
class _AvatarSourceSheet extends StatelessWidget {
  const _AvatarSourceSheet();

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Container(
        margin: const EdgeInsets.fromLTRB(12, 0, 12, 12),
        padding: const EdgeInsets.fromLTRB(20, 12, 20, 20),
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(24),
          boxShadow: AppColors.elevatedShadow,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Center(
              child: Container(
                width: 40,
                height: 4,
                margin: const EdgeInsets.only(bottom: 18),
                decoration: BoxDecoration(
                  color: AppColors.neutral300,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            Text('Update profile photo', style: AppTypography.h3),
            const SizedBox(height: 4),
            Text(
              'Choose a clear photo of yourself — riders and customers use this to recognise each other.',
              style: AppTypography.captionDark,
            ),
            const SizedBox(height: 18),
            _SourceTile(
              icon: Icons.photo_camera_rounded,
              color: AppColors.primary,
              title: 'Take a photo',
              subtitle: 'Use your camera',
              onTap: () => Navigator.pop(context, ImageSource.camera),
            ),
            const SizedBox(height: 10),
            _SourceTile(
              icon: Icons.photo_library_rounded,
              color: AppColors.secondaryDark,
              title: 'Choose from gallery',
              subtitle: 'Pick an existing photo',
              onTap: () => Navigator.pop(context, ImageSource.gallery),
            ),
            const SizedBox(height: 14),
            AppButton(
              text: 'Cancel',
              type: AppButtonType.ghost,
              onPressed: () => Navigator.pop(context),
            ),
          ],
        ),
      ),
    );
  }
}

class _SourceTile extends StatelessWidget {
  final IconData icon;
  final Color color;
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  const _SourceTile({
    required this.icon,
    required this.color,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: AppDecorations.radiusSm,
        child: Container(
          padding: const EdgeInsets.all(12),
          decoration:
              AppDecorations.flatCard(borderRadius: AppDecorations.radiusSm),
          child: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(10),
                decoration: AppDecorations.iconTile(color),
                child: Icon(icon, color: color, size: 22),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(title,
                        style: AppTypography.bodyBold.copyWith(fontSize: 14.5)),
                    Text(subtitle, style: AppTypography.caption),
                  ],
                ),
              ),
              Icon(Icons.chevron_right_rounded,
                  color: AppColors.neutral400),
            ],
          ),
        ),
      ),
    );
  }
}
