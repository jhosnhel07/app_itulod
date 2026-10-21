import 'package:flutter/material.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';

import '../../core/constants/app_colors.dart';
import '../../core/constants/app_typography.dart';
import '../../core/utils/validators.dart';

/// The password rules with a tick or a cross each, updated as the user types
/// (web twin: attachPasswordChecklist in js/utils.js).
class PasswordChecklist extends StatelessWidget {
  final String password;
  const PasswordChecklist({super.key, required this.password});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: 6, bottom: 14, left: 2),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          for (final rule in Validators.passwordRules)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 2),
              child: _RuleRow(label: rule.label, met: rule.test(password)),
            ),
        ],
      ),
    );
  }
}

class _RuleRow extends StatelessWidget {
  final String label;
  final bool met;
  const _RuleRow({required this.label, required this.met});

  @override
  Widget build(BuildContext context) {
    final color = met ? AppColors.success : AppColors.warning;
    return Semantics(
      label: '$label: ${met ? 'done' : 'missing'}',
      excludeSemantics: true,
      child: Row(
        children: [
          SizedBox(
            width: 18,
            child: FaIcon(met ? FontAwesomeIcons.solidCircleCheck : FontAwesomeIcons.solidCircleXmark,
                size: 13, color: color),
          ),
          const SizedBox(width: 6),
          Flexible(
            child: Text(label,
                style: AppTypography.caption.copyWith(
                  fontSize: 12.5,
                  color: met ? const Color(0xFF137A4D) : AppColors.neutral600,
                )),
          ),
        ],
      ),
    );
  }
}
