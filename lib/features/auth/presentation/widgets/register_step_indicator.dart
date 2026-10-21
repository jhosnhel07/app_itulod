import 'package:flutter/material.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../../../core/constants/app_colors.dart';

class RegisterStepIndicator extends StatelessWidget {
  final int activeIndex;
  final bool isRider;

  const RegisterStepIndicator({
    super.key,
    required this.activeIndex,
    required this.isRider,
  });

  static const labels = ['Role', 'Personal', 'Vehicle', 'Documents', 'Review'];

  /// Vehicle / Documents / Review are rider-only — a customer's progress is
  /// just Role → Personal (web: updateStepIndicator in js/register.js).
  int get _count => isRider ? labels.length : 2;

  /// Progress accent follows the chosen role: iTULOD blue for a customer
  /// sign-up, warm rose for a rider application.
  static const Color _customerAccent = Color(0xFF2196F3);
  static const Color _riderAccent = Color(0xFFB06B79);
  Color get _accent => isRider ? _riderAccent : _customerAccent;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 28),
      child: Row(
        children: List.generate(_count, (i) {
          final completed = i < activeIndex;
          final active = i == activeIndex;

          return Expanded(
            child: Column(
              children: [
                SizedBox(
                  height: 40,
                  child: Stack(
                    alignment: Alignment.center,
                    children: [
                      if (i < _count - 1)
                        Align(
                          alignment: Alignment.centerRight,
                          child: FractionallySizedBox(
                            widthFactor: 1,
                            child: Container(
                              margin: const EdgeInsets.only(left: 18),
                              height: 2,
                              color: completed
                                  ? _accent
                                  : active
                                      ? _accent.withValues(alpha: 0.45)
                                      : AppColors.pick(0xFFE5E7EB, 0xFF2A384C),
                            ),
                          ),
                        ),
                      Container(
                        width: 36,
                        height: 36,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: completed
                              ? _accent
                              : active
                                  ? _accent
                                  : AppColors.surface,
                          border: Border.all(
                            color: completed || active ? _accent : AppColors.pick(0xFFE5E7EB, 0xFF2A384C),
                            width: 2,
                          ),
                          boxShadow: active
                              ? [
                                  BoxShadow(
                                    color: _accent.withValues(alpha: 0.15),
                                    blurRadius: 0,
                                    spreadRadius: 4,
                                  ),
                                ]
                              : null,
                        ),
                        alignment: Alignment.center,
                        child: completed
                            ? const FaIcon(FontAwesomeIcons.check, size: 12, color: Colors.white)
                            : Text(
                                '${i + 1}',
                                style: GoogleFonts.inter(
                                  fontSize: 13,
                                  fontWeight: FontWeight.w700,
                                  color: active ? Colors.white : AppColors.iconMuted,
                                ),
                              ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  labels[i],
                  textAlign: TextAlign.center,
                  style: GoogleFonts.inter(
                    fontSize: 9.5,
                    fontWeight: FontWeight.w600,
                    letterSpacing: 0.3,
                    color: completed || active ? _accent : AppColors.iconMuted,
                  ),
                ),
              ],
            ),
          );
        }),
      ),
    );
  }
}
