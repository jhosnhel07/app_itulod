import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';
import '../../core/constants/app_colors.dart';
import '../../core/constants/app_typography.dart';
import '../widgets/app_button.dart';
import '../widgets/app_text_field.dart';
import '../widgets/avatar_widget.dart';
import '../../features/customer/data/customer_repository.dart';
import '../../features/auth/presentation/providers/auth_provider.dart';

/// Shared profile tab used by both customer and rider dashboards.
class ProfileScreen extends ConsumerStatefulWidget {
  const ProfileScreen({super.key});

  @override
  ConsumerState<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends ConsumerState<ProfileScreen> {
  late TextEditingController _nameController;
  late TextEditingController _phoneController;
  bool _saving = false;
  File? _pickedAvatar;

  @override
  void initState() {
    super.initState();
    final profile = ref.read(authNotifierProvider).profile;
    _nameController = TextEditingController(text: profile?.fullName ?? '');
    _phoneController = TextEditingController(text: profile?.phone ?? '');
  }

  Future<void> _pickAvatar() async {
    final picker = ImagePicker();
    final picked = await picker.pickImage(source: ImageSource.gallery, imageQuality: 70);
    if (picked != null) {
      setState(() => _pickedAvatar = File(picked.path));
    }
  }

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

      if (_pickedAvatar != null) {
        final bytes = await _pickedAvatar!.readAsBytes();
        final url = await repo.uploadAvatar(
          userId: profile.id,
          filePath: _pickedAvatar!.path,
          bytes: bytes,
        );
        updated = await repo.setAvatarUrl(updated, url);
      }

      ref.read(authNotifierProvider.notifier).updateProfileLocally(updated);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Profile updated!'), backgroundColor: AppColors.success),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Update failed: $e'), backgroundColor: AppColors.danger),
        );
      }
    }
    if (mounted) setState(() => _saving = false);
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
                Stack(
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
                    Positioned(
                      bottom: 0,
                      right: 0,
                      child: GestureDetector(
                        onTap: _pickAvatar,
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
                    ),
                  ],
                ),
                const SizedBox(height: 14),
                Text(
                  profile?.fullName ?? 'Your profile',
                  style: AppTypography.h3.copyWith(color: Colors.white),
                ),
                const SizedBox(height: 2),
                Text(
                  profile?.email ?? '',
                  style:
                      AppTypography.caption.copyWith(color: Colors.white70),
                ),
              ],
            ),
          ),
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
                ],
              ),
            ),
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
              final confirmed = await showDialog<bool>(
                context: context,
                builder: (ctx) => AlertDialog(
                  title: const Text('Sign out?'),
                  content: const Text('You will need to log in again.'),
                  actions: [
                    TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
                    TextButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Sign out')),
                  ],
                ),
              );
              if (confirmed == true) {
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
