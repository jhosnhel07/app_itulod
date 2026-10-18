import 'package:flutter/material.dart';
import '../../core/constants/app_colors.dart';
import '../../core/constants/app_typography.dart';

/// Branded yes/no dialog — the app twin of the web's appConfirm()
/// (js/utils.js). Resolves true on confirm, false on cancel / back / tap
/// outside. [danger] turns the icon and confirm button red for destructive
/// actions (delete, cancel booking, no-show).
Future<bool> showAppConfirm(
  BuildContext context, {
  required String title,
  required String message,
  String confirmText = 'Confirm',
  String cancelText = 'Cancel',
  bool danger = false,
  IconData? icon,
}) async {
  final ok = await showGeneralDialog<bool>(
    context: context,
    barrierDismissible: true,
    barrierLabel: cancelText,
    barrierColor: const Color(0x800B1A2F),
    transitionDuration: const Duration(milliseconds: 220),
    pageBuilder: (ctx, _, __) => _AppConfirmDialog(
      title: title,
      message: message,
      confirmText: confirmText,
      cancelText: cancelText,
      danger: danger,
      icon: icon ?? (danger ? Icons.warning_amber_rounded : Icons.help_outline_rounded),
    ),
    transitionBuilder: (ctx, anim, _, child) {
      final curved = CurvedAnimation(parent: anim, curve: Curves.easeOutBack);
      return FadeTransition(
        opacity: anim,
        child: ScaleTransition(scale: Tween(begin: 0.94, end: 1.0).animate(curved), child: child),
      );
    },
  );
  return ok == true;
}

class _AppConfirmDialog extends StatelessWidget {
  final String title;
  final String message;
  final String confirmText;
  final String cancelText;
  final bool danger;
  final IconData icon;

  const _AppConfirmDialog({
    required this.title,
    required this.message,
    required this.confirmText,
    required this.cancelText,
    required this.danger,
    required this.icon,
  });

  @override
  Widget build(BuildContext context) {
    final accent = danger ? AppColors.danger : AppColors.primary;
    final tint = danger ? AppColors.danger50 : AppColors.primary50;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Material(
          color: Colors.transparent,
          borderRadius: BorderRadius.circular(22),
          elevation: 0,
          child: Container(
            constraints: const BoxConstraints(maxWidth: 400),
            padding: const EdgeInsets.fromLTRB(22, 26, 22, 20),
            decoration: BoxDecoration(
              color: AppColors.surface,
              borderRadius: BorderRadius.circular(22),
              border: Border.all(color: AppColors.cardBorder),
              boxShadow: AppColors.elevatedShadow,
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 56,
                  height: 56,
                  decoration: BoxDecoration(
                    color: tint,
                    shape: BoxShape.circle,
                    boxShadow: [BoxShadow(color: tint.withValues(alpha: 0.6), spreadRadius: 8)],
                  ),
                  child: Icon(icon, color: accent, size: 26),
                ),
                const SizedBox(height: 18),
                Text(title, textAlign: TextAlign.center, style: AppTypography.h3),
                const SizedBox(height: 6),
                Text(message,
                    textAlign: TextAlign.center,
                    style: AppTypography.body.copyWith(fontSize: 14, height: 1.5)),
                const SizedBox(height: 22),
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton(
                        onPressed: () => Navigator.pop(context, false),
                        style: OutlinedButton.styleFrom(
                          minimumSize: const Size.fromHeight(46),
                          shape: const StadiumBorder(),
                        ),
                        child: Text(cancelText),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: FilledButton(
                        onPressed: () => Navigator.pop(context, true),
                        style: FilledButton.styleFrom(
                          backgroundColor: accent,
                          foregroundColor: Colors.white,
                          minimumSize: const Size.fromHeight(46),
                          shape: const StadiumBorder(),
                        ),
                        child: Text(confirmText),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
