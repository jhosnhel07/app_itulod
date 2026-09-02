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

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 28),
      child: Row(
        children: List.generate(labels.length, (i) {
          final completed = i < activeIndex;
          final active = i == activeIndex;
          final faded = !isRider && i >= 2 && activeIndex < 4;

          return Expanded(
            child: Opacity(
              opacity: faded ? 0.3 : 1,
              child: Column(
                children: [
                  SizedBox(
                    height: 40,
                    child: Stack(
                      alignment: Alignment.center,
                      children: [
                        if (i < labels.length - 1)
                          Align(
                            alignment: Alignment.centerRight,
                            child: FractionallySizedBox(
                              widthFactor: 1,
                              child: Container(
                                margin: const EdgeInsets.only(left: 18),
                                height: 2,
                                color: completed
                                    ? AppColors.success
                                    : active
                                        ? AppColors.brandBlue.withValues(alpha: 0.45)
                                        : const Color(0xFFE5E7EB),
                              ),
                            ),
                          ),
                        Container(
                          width: 36,
                          height: 36,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: completed
                                ? AppColors.success
                                : active
                                    ? AppColors.brandBlue
                                    : Colors.white,
                            border: Border.all(
                              color: completed
                                  ? AppColors.success
                                  : active
                                      ? AppColors.brandBlue
                                      : const Color(0xFFE5E7EB),
                              width: 2,
                            ),
                            boxShadow: active
                                ? [
                                    BoxShadow(
                                      color: AppColors.brandBlue.withValues(alpha: 0.15),
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
                      color: completed
                          ? AppColors.success
                          : active
                              ? AppColors.brandBlue
                              : AppColors.iconMuted,
                    ),
                  ),
                ],
              ),
            ),
          );
        }),
      ),
    );
  }
}
