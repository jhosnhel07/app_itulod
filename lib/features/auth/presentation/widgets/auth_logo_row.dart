import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../../../core/constants/app_colors.dart';

class AuthLogoRow extends StatelessWidget {
  const AuthLogoRow({super.key});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 28),
      child: Row(
        children: [
          Image.asset(
            'assets/images/logo.png',
            width: 38,
            height: 38,
            fit: BoxFit.contain,
          ),
          const SizedBox(width: 10),
          Text.rich(
            TextSpan(
              text: 'iTULOD',
              style: GoogleFonts.poppins(
                fontWeight: FontWeight.w800,
                fontSize: 19.2,
                color: AppColors.ink,
                height: 1,
              ),
              children: [
                TextSpan(
                  text: '.',
                  style: GoogleFonts.poppins(
                    fontWeight: FontWeight.w800,
                    fontSize: 19.2,
                    color: AppColors.brandOrange,
                    height: 1,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
