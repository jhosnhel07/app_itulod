import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../../../core/constants/app_colors.dart';
import '../../../../core/constants/app_strings.dart';
import '../../../../core/utils/validators.dart';
import '../providers/auth_provider.dart';
import '../widgets/auth_card_scaffold.dart';
import '../widgets/auth_gradient_button.dart';
import '../widgets/auth_logo_row.dart';
import '../widgets/auth_text_field.dart';

class LoginScreen extends ConsumerStatefulWidget {
  const LoginScreen({super.key});

  @override
  ConsumerState<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends ConsumerState<LoginScreen> {
  final _formKey = GlobalKey<FormState>();
  final _identifierController = TextEditingController();
  final _passwordController = TextEditingController();
  bool _obscurePassword = true;
  bool _rememberMe = false;

  static const _rememberKey = 'itulod_remember_identifier';

  @override
  void initState() {
    super.initState();
    _loadRemembered();
  }

  Future<void> _loadRemembered() async {
    final prefs = await SharedPreferences.getInstance();
    final saved = prefs.getString(_rememberKey);
    if (saved != null && saved.isNotEmpty && mounted) {
      setState(() {
        _identifierController.text = saved;
        _rememberMe = true;
      });
    }
  }

  @override
  void dispose() {
    _identifierController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  Future<void> _handleLogin() async {
    if (!_formKey.currentState!.validate()) return;

    FocusScope.of(context).unfocus();

    final prefs = await SharedPreferences.getInstance();
    if (_rememberMe) {
      await prefs.setString(_rememberKey, _identifierController.text.trim());
    } else {
      await prefs.remove(_rememberKey);
    }

    final success = await ref.read(authNotifierProvider.notifier).signIn(
          emailOrUsername: _identifierController.text.trim(),
          password: _passwordController.text,
        );

    if (!success && mounted) {
      final error = ref.read(authNotifierProvider).errorMessage ??
          'Login failed. Please check your credentials.';
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Row(
            children: [
              const Icon(Icons.error_outline, color: Colors.white),
              const SizedBox(width: 10),
              Expanded(child: Text(error)),
            ],
          ),
          backgroundColor: AppColors.danger,
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        ),
      );
    }
  }

  void _showForgotPasswordSheet() {
    final resetController = TextEditingController(text: _identifierController.text.trim());
    bool isResetting = false;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: AppColors.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (sheetContext) => StatefulBuilder(
        builder: (context, setSheetState) => Padding(
          padding: EdgeInsets.only(
            left: 24,
            right: 24,
            top: 24,
            bottom: MediaQuery.of(context).viewInsets.bottom + 24,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    'Reset Password',
                    style: GoogleFonts.poppins(fontWeight: FontWeight.w700, fontSize: 18),
                  ),
                  IconButton(
                    icon: Icon(Icons.close, color: AppColors.neutral500),
                    onPressed: () => Navigator.pop(sheetContext),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Text(
                'Enter your registered email address to receive password reset instructions.',
                style: GoogleFonts.inter(color: AppColors.slate, fontSize: 14),
              ),
              const SizedBox(height: 20),
              AuthTextField(
                label: 'Email address',
                hint: 'name@example.com',
                icon: FontAwesomeIcons.envelope,
                controller: resetController,
                keyboardType: TextInputType.emailAddress,
              ),
              AuthGradientButton(
                text: 'Send Reset Link',
                isLoading: isResetting,
                leadingIcon: FontAwesomeIcons.paperPlane,
                onPressed: () async {
                  final email = resetController.text.trim();
                  if (email.isEmpty) return;

                  final messenger = ScaffoldMessenger.of(context);
                  setSheetState(() => isResetting = true);
                  final sent = await ref.read(authNotifierProvider.notifier).resetPassword(email);
                  setSheetState(() => isResetting = false);

                  if (sheetContext.mounted) {
                    Navigator.pop(sheetContext);
                  }
                  messenger.showSnackBar(
                    SnackBar(
                      content: Text(
                        sent
                            ? 'Password reset email sent! Check your inbox.'
                            : 'Could not send reset email. Please try again.',
                      ),
                      backgroundColor: sent ? AppColors.success : AppColors.danger,
                      behavior: SnackBarBehavior.floating,
                    ),
                  );
                },
              ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final authState = ref.watch(authNotifierProvider);

    return AuthCardScaffold(
      child: Form(
        key: _formKey,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const AuthLogoRow(),
            Text(
              AppStrings.welcomeBack,
              style: GoogleFonts.poppins(
                fontWeight: FontWeight.w800,
                fontSize: 28,
                color: AppColors.ink,
                height: 1.15,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              AppStrings.loginSubtitle,
              style: GoogleFonts.inter(
                fontSize: 15.2,
                color: AppColors.slate,
              ),
            ),
            const SizedBox(height: 32),
            AuthTextField(
              label: AppStrings.emailOrUsername,
              hint: AppStrings.emailPlaceholder,
              icon: FontAwesomeIcons.envelope,
              controller: _identifierController,
              textInputAction: TextInputAction.next,
              keyboardType: TextInputType.emailAddress,
              validator: (val) => Validators.required(val, 'Email or username'),
            ),
            AuthTextField(
              label: AppStrings.password,
              hint: AppStrings.passwordPlaceholder,
              icon: FontAwesomeIcons.lock,
              controller: _passwordController,
              obscureText: _obscurePassword,
              showPasswordToggle: true,
              onToggleObscure: () => setState(() => _obscurePassword = !_obscurePassword),
              textInputAction: TextInputAction.done,
              validator: (val) => Validators.required(val, 'Password'),
            ),
            Padding(
              padding: const EdgeInsets.only(bottom: 24),
              child: Row(
                children: [
                  SizedBox(
                    width: 20,
                    height: 20,
                    child: Checkbox(
                      value: _rememberMe,
                      onChanged: (v) => setState(() => _rememberMe = v ?? false),
                      activeColor: AppColors.brandBlue,
                      materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                      visualDensity: VisualDensity.compact,
                    ),
                  ),
                  const SizedBox(width: 8),
                  GestureDetector(
                    onTap: () => setState(() => _rememberMe = !_rememberMe),
                    child: Text(
                      AppStrings.rememberMe,
                      style: GoogleFonts.inter(fontSize: 13.6, color: AppColors.slate),
                    ),
                  ),
                  const Spacer(),
                  GestureDetector(
                    onTap: _showForgotPasswordSheet,
                    child: Text(
                      AppStrings.forgotPassword,
                      style: GoogleFonts.inter(
                        fontSize: 13.6,
                        fontWeight: FontWeight.w600,
                        color: AppColors.brandBlue,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            AuthGradientButton(
              text: AppStrings.loginButton,
              leadingIcon: FontAwesomeIcons.rightToBracket,
              isLoading: authState.isLoading,
              onPressed: _handleLogin,
            ),
            const SizedBox(height: 24),
            Row(
              children: [
                const Expanded(child: Divider(color: Color(0xFFE5E7EB))),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 14),
                  child: Text(
                    AppStrings.orContinueWith,
                    style: GoogleFonts.inter(
                      fontSize: 13.1,
                      fontWeight: FontWeight.w500,
                      color: AppColors.iconMuted,
                    ),
                  ),
                ),
                const Expanded(child: Divider(color: Color(0xFFE5E7EB))),
              ],
            ),
            const SizedBox(height: 16),
            Wrap(
              alignment: WrapAlignment.center,
              children: [
                Text(
                  "${AppStrings.dontHaveAccount} ",
                  style: GoogleFonts.inter(fontSize: 14.1, color: AppColors.slate),
                ),
                GestureDetector(
                  onTap: () => context.push('/register'),
                  child: Text(
                    AppStrings.createOne,
                    style: GoogleFonts.inter(
                      fontSize: 14.1,
                      fontWeight: FontWeight.w700,
                      color: AppColors.brandBlue,
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
