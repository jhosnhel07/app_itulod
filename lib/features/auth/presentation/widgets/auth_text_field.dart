import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../../../core/constants/app_colors.dart';

class AuthTextField extends StatelessWidget {
  final String label;
  final String hint;
  final FaIconData icon;
  final TextEditingController? controller;
  final bool obscureText;
  final VoidCallback? onToggleObscure;
  final TextInputType? keyboardType;
  final TextInputAction? textInputAction;
  final FormFieldValidator<String>? validator;
  final ValueChanged<String>? onChanged;
  final bool showPasswordToggle;
  final double bottomPadding;
  final List<TextInputFormatter>? inputFormatters;

  const AuthTextField({
    super.key,
    required this.label,
    required this.hint,
    required this.icon,
    this.controller,
    this.obscureText = false,
    this.onToggleObscure,
    this.keyboardType,
    this.textInputAction,
    this.validator,
    this.onChanged,
    this.showPasswordToggle = false,
    this.bottomPadding = 18,
    this.inputFormatters,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(bottom: bottomPadding),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: GoogleFonts.inter(
              fontSize: 13.3,
              fontWeight: FontWeight.w600,
              color: AppColors.neutral700,
              letterSpacing: 0.01 * 13.3,
            ),
          ),
          const SizedBox(height: 8),
          TextFormField(
            controller: controller,
            obscureText: obscureText,
            keyboardType: keyboardType,
            inputFormatters: inputFormatters,
            textInputAction: textInputAction,
            validator: validator,
            onChanged: onChanged,
            style: GoogleFonts.inter(
              fontSize: 15.2,
              color: AppColors.ink,
            ),
            decoration: InputDecoration(
              hintText: hint,
              hintStyle: GoogleFonts.inter(
                fontSize: 15.2,
                color: AppColors.placeholder,
              ),
              prefixIcon: Padding(
                padding: const EdgeInsets.only(left: 14, right: 10),
                child: FaIcon(icon, size: 15, color: AppColors.iconMuted),
              ),
              prefixIconConstraints: const BoxConstraints(minWidth: 42, minHeight: 20),
              suffixIcon: showPasswordToggle
                  ? IconButton(
                      onPressed: onToggleObscure,
                      icon: FaIcon(
                        obscureText ? FontAwesomeIcons.eye : FontAwesomeIcons.eyeSlash,
                        size: 14.5,
                        color: AppColors.iconMuted,
                      ),
                    )
                  : null,
              filled: true,
              fillColor: AppColors.inputFill,
              contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 13),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: BorderSide(color: AppColors.pick(0xFFE5E7EB, 0xFF2A384C), width: 1.5),
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: BorderSide(color: AppColors.pick(0xFFE5E7EB, 0xFF2A384C), width: 1.5),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: const BorderSide(color: AppColors.brandBlue, width: 1.5),
              ),
              errorBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: const BorderSide(color: AppColors.danger, width: 1.5),
              ),
              focusedErrorBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: const BorderSide(color: AppColors.danger, width: 1.5),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
