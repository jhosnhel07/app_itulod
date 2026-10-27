import 'package:flutter/material.dart';
import '../../../../shared/widgets/account_menu_button.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../../core/constants/app_colors.dart';
import '../../../../core/constants/app_strings.dart';
import '../../../../core/constants/app_typography.dart';
import '../../../../shared/screens/profile_screen.dart';
import '../../../../shared/widgets/app_button.dart';
import '../../../../shared/widgets/avatar_widget.dart';
import '../../../../shared/widgets/status_badge.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../../auth/presentation/providers/auth_provider.dart';

/// Admin tools (analytics, rider approvals, bookings, vehicles, restaurants,
/// payments, announcements, support) live in the web console only.
const String _webAdminUrl = AppStrings.webAdminUrl;

class AdminDashboardScreen extends ConsumerWidget {
  const AdminDashboardScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final profile = ref.watch(authNotifierProvider).profile;

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: const Text('Admin Console'),
        actions: [
          // Profile picture → My profile, Dark mode, Log out.
          AccountMenuButton(onOpenProfile: () => _openProfile(context)),
          const SizedBox(width: 8),
        ],
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Container(
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(
                  gradient: AppColors.primaryGradient,
                  borderRadius: BorderRadius.circular(20),
                  boxShadow: AppColors.elevatedShadow,
                ),
                child: Row(
                  children: [
                    AvatarWidget(
                      name: profile?.fullName ?? 'Admin',
                      url: profile?.avatarUrl,
                      radius: 28,
                      ring: true,
                      onTap: () => _openProfile(context),
                    ),
                    const SizedBox(width: 16),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(profile?.fullName ?? 'Administrator',
                              style:
                                  AppTypography.h3.copyWith(color: Colors.white)),
                          const SizedBox(height: 4),
                          Text(
                            profile?.email ?? '',
                            style: AppTypography.caption
                                .copyWith(color: Colors.white70),
                          ),
                          const SizedBox(height: 8),
                          const StatusBadge(status: 'System Admin'),
                        ],
                      ),
                    ),
                    IconButton(
                      icon: const Icon(Icons.chevron_right_rounded,
                          color: Colors.white70),
                      tooltip: 'Edit profile',
                      onPressed: () => _openProfile(context),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 24),
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(20),
                  child: Column(
                    children: [
                      const Icon(Icons.admin_panel_settings_outlined, color: AppColors.primary, size: 48),
                      const SizedBox(height: 12),
                      Text('Admin tools are on the web', style: AppTypography.h3),
                      const SizedBox(height: 6),
                      Text(
                        'Rider approvals, bookings, customers, vehicles, restaurants, payments, announcements and support requests are managed from the web admin console.',
                        style: AppTypography.body.copyWith(color: AppColors.neutral600),
                        textAlign: TextAlign.center,
                      ),
                      const SizedBox(height: 16),
                      AppButton(
                        text: 'Open web admin console',
                        icon: Icons.open_in_new_rounded,
                        onPressed: () => launchUrl(
                          Uri.parse(_webAdminUrl),
                          mode: LaunchMode.externalApplication,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 20),
              AppButton(
                text: 'Edit Profile',
                type: AppButtonType.outline,
                icon: Icons.edit_outlined,
                onPressed: () => _openProfile(context),
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
    );
  }

  void _openProfile(BuildContext context) {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => Scaffold(
          appBar: AppBar(title: const Text('My Profile')),
          body: const ProfileScreen(),
        ),
      ),
    );
  }
}
