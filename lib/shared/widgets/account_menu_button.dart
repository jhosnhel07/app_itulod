import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';

import '../../core/constants/app_colors.dart';
import '../../core/constants/app_typography.dart';
import '../../core/theme/theme_controller.dart';
import '../../features/auth/presentation/providers/auth_provider.dart';
import 'app_confirm_dialog.dart';
import 'avatar_widget.dart';

/// The profile picture at the top-right of the dashboards (where the
/// sun/moon button used to be). Tapping it opens the account sheet: name and
/// email, My profile, the Dark mode switch and Log out.
/// Web twin: renderAccountMenus in js/utils.js.
class AccountMenuButton extends ConsumerWidget {
  /// Opens the Profile tab/page; hides "My profile" when null.
  final VoidCallback? onOpenProfile;
  const AccountMenuButton({super.key, this.onOpenProfile});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final profile = ref.watch(authNotifierProvider).profile;
    final name = profile?.fullName ?? 'My account';
    return Semantics(
      button: true,
      label: 'Account menu',
      excludeSemantics: true,
      onTap: () => _open(context),
      child: InkWell(
        customBorder: const CircleBorder(),
        onTap: () => _open(context),
        child: Padding(
          padding: const EdgeInsets.all(4),
          child: AvatarWidget(name: name, url: profile?.avatarUrl, radius: 18, ring: true),
        ),
      ),
    );
  }

  void _open(BuildContext context) {
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: AppColors.surface,
      showDragHandle: true,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (sheetContext) => _AccountSheet(onOpenProfile: onOpenProfile),
    );
  }
}

class _AccountSheet extends ConsumerWidget {
  final VoidCallback? onOpenProfile;
  const _AccountSheet({this.onOpenProfile});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final choice = ref.watch(themeChoiceProvider);
    final profile = ref.watch(authNotifierProvider).profile;
    final name = profile?.fullName ?? 'My account';
    final dark = choice == AppThemeChoice.dark ||
        (choice == AppThemeChoice.system && MediaQuery.platformBrightnessOf(context) == Brightness.dark);

    return SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(8, 0, 8, 12),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: AvatarWidget(name: name, url: profile?.avatarUrl, radius: 22),
              title: Text(name, style: AppTypography.bodyBold, overflow: TextOverflow.ellipsis),
              subtitle: Text(profile?.email ?? '',
                  style: AppTypography.caption, overflow: TextOverflow.ellipsis),
            ),
            Divider(color: AppColors.divider, height: 12),
            if (onOpenProfile != null)
              ListTile(
                leading: const FaIcon(FontAwesomeIcons.solidUser, size: 17, color: AppColors.primary),
                title: Text('My profile', style: AppTypography.bodyMedium),
                onTap: () {
                  Navigator.pop(context);
                  onOpenProfile!();
                },
              ),
            SwitchListTile(
              secondary: const FaIcon(FontAwesomeIcons.solidMoon, size: 17, color: AppColors.primary),
              title: Text('Dark mode', style: AppTypography.bodyMedium),
              value: dark,
              activeThumbColor: Colors.white,
              activeTrackColor: AppColors.primary,
              onChanged: (_) => ref.read(themeChoiceProvider.notifier).toggle(),
            ),
            ListTile(
              leading: const FaIcon(FontAwesomeIcons.rightFromBracket, size: 17, color: AppColors.danger),
              title: Text('Log out', style: AppTypography.bodyMedium.copyWith(color: AppColors.danger)),
              onTap: () async {
                final notifier = ref.read(authNotifierProvider.notifier);
                final rootContext = Navigator.of(context, rootNavigator: true).context;
                Navigator.pop(context);
                final confirmed = await showAppConfirm(
                  rootContext,
                  title: 'Log out?',
                  message: 'You will need to log in again.',
                  confirmText: 'Log out',
                  icon: Icons.logout_rounded,
                );
                if (confirmed) notifier.signOut();
              },
            ),
          ],
        ),
      ),
    );
  }
}
