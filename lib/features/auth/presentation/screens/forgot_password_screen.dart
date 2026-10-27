import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:supabase_flutter/supabase_flutter.dart' show AuthException;

import '../../../../core/constants/app_colors.dart';
import '../../../../core/utils/validators.dart';
import '../../../../shared/widgets/password_checklist.dart';
import '../../data/auth_repository.dart';
import '../providers/auth_provider.dart';
import '../widgets/auth_card_scaffold.dart';
import '../widgets/auth_gradient_button.dart';
import '../widgets/auth_logo_row.dart';
import '../widgets/auth_text_field.dart';

/// Forgot password (web twin: login.html's reset steps, js/auth.js):
/// email or mobile number → the 6-digit code from the email → new password →
/// straight into the dashboard. A number's code goes to that account's email
/// (password-reset-code Edge Function, web sql/049). The router leaves this
/// screen alone while it signs in with the code; it sends the user on itself.
class ForgotPasswordScreen extends ConsumerStatefulWidget {
  final String initialIdentifier;
  const ForgotPasswordScreen({super.key, this.initialIdentifier = ''});

  @override
  ConsumerState<ForgotPasswordScreen> createState() => _ForgotPasswordScreenState();
}

class _ForgotPasswordScreenState extends ConsumerState<ForgotPasswordScreen> {
  late final _identifier = TextEditingController(text: widget.initialIdentifier);
  final _code = TextEditingController();
  final _password = TextEditingController();
  final _confirm = TextEditingController();
  final _formKey = GlobalKey<FormState>();
  int _step = 1;
  bool _busy = false;
  bool _hidePassword = true;
  bool _hideConfirm = true;
  String _sentTo = '';
  String _usedIdentifier = '';
  int _resendIn = 0;
  Timer? _resendTimer;

  @override
  void dispose() {
    _resendTimer?.cancel();
    for (final c in [_identifier, _code, _password, _confirm]) {
      c.dispose();
    }
    super.dispose();
  }

  void _toast(String message, {bool error = true}) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(message),
      backgroundColor: error ? AppColors.danger : AppColors.success,
      behavior: SnackBarBehavior.floating,
    ));
  }

  Future<void> _run(Future<void> Function() job) async {
    setState(() => _busy = true);
    try {
      await job();
    } on AuthException catch (e) {
      if (mounted) _toast(e.message);
    } catch (e) {
      if (mounted) _toast(e.toString().replaceFirst('Exception: ', ''));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _startResendTimer() {
    _resendTimer?.cancel();
    setState(() => _resendIn = 60);
    _resendTimer = Timer.periodic(const Duration(seconds: 1), (t) {
      if (!mounted) return t.cancel();
      setState(() => _resendIn -= 1);
      if (_resendIn <= 0) t.cancel();
    });
  }

  Future<void> _send({String? identifier}) => _run(() async {
        final id = (identifier ?? _identifier.text).trim();
        if (id.isEmpty) throw const AuthException('Enter your email or mobile number.');
        final sentTo = await ref.read(authRepositoryProvider).sendResetCode(id);
        if (!mounted) return;
        setState(() {
          _usedIdentifier = id;
          _sentTo = sentTo;
          _code.clear();
          _step = 2;
        });
        _startResendTimer();
      });

  Future<void> _verify() => _run(() async {
        final code = _code.text.replaceAll(RegExp(r'\s'), '');
        if (!RegExp(r'^\d{6,10}$').hasMatch(code)) throw const AuthException('Enter the 6-digit code from the email.');
        await ref.read(authRepositoryProvider).verifyResetCode(_usedIdentifier, code);
        _resendTimer?.cancel();
        if (mounted) setState(() => _step = 3);
      });

  Future<void> _save() => _run(() async {
        if (!(_formKey.currentState?.validate() ?? false)) return;
        await ref.read(authRepositoryProvider).updatePassword(_password.text);
        // signed in already: load the profile, then the router picks the
        // dashboard (customer / rider) from /login
        await ref.read(authNotifierProvider.notifier).refreshProfile();
        if (!mounted) return;
        _toast('Password changed — welcome back!', error: false);
        context.go('/login');
      });

  @override
  Widget build(BuildContext context) {
    return AuthCardScaffold(
      child: Form(
        key: _formKey,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const AuthLogoRow(),
            Align(
              alignment: Alignment.centerLeft,
              child: TextButton.icon(
                key: const Key('fp-back'),
                onPressed: _busy ? null : () => _step == 2 ? setState(() => _step = 1) : context.go('/login'),
                icon: const Icon(Icons.arrow_back_rounded, size: 18),
                label: Text(_step == 2 ? 'Use a different email or number' : 'Back to login'),
              ),
            ),
            Text('Reset your password',
                style: GoogleFonts.poppins(fontWeight: FontWeight.w800, fontSize: 24, color: AppColors.ink)),
            const SizedBox(height: 12),
            _StepDots(step: _step),
            const SizedBox(height: 14),
            Text(
              switch (_step) {
                1 => "Enter the email or mobile number on your account. We'll email you a 6-digit code.",
                2 => 'We sent a 6-digit code to $_sentTo. The email is from Supabase Auth, titled “Confirm reauthentication” — check your inbox (and spam).',
                _ => 'Code accepted. Create your new password.',
              },
              key: const Key('fp-sub'),
              style: GoogleFonts.inter(fontSize: 14, height: 1.5, color: AppColors.slate),
            ),
            const SizedBox(height: 20),
            if (_step == 1) ...[
              AuthTextField(
                label: 'Email or mobile number',
                hint: 'you@gmail.com or 0917 123 4567',
                icon: FontAwesomeIcons.user,
                controller: _identifier,
                keyboardType: TextInputType.emailAddress,
                textInputAction: TextInputAction.send,
              ),
              AuthGradientButton(
                key: const Key('fp-send'),
                text: 'Send code',
                leadingIcon: FontAwesomeIcons.paperPlane,
                isLoading: _busy,
                onPressed: _busy ? null : () => _send(),
              ),
            ] else if (_step == 2) ...[
              AuthTextField(
                label: '6-digit code',
                hint: '123456',
                icon: FontAwesomeIcons.key,
                controller: _code,
                keyboardType: TextInputType.number,
                inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[\d ]')), LengthLimitingTextInputFormatter(12)],
              ),
              AuthGradientButton(
                key: const Key('fp-verify'),
                text: 'Verify code',
                leadingIcon: FontAwesomeIcons.check,
                isLoading: _busy,
                onPressed: _busy ? null : _verify,
              ),
              const SizedBox(height: 8),
              Center(
                child: TextButton(
                  key: const Key('fp-resend'),
                  onPressed: _busy || _resendIn > 0 ? null : () => _send(identifier: _usedIdentifier),
                  child: Text(_resendIn > 0 ? 'Resend code (${_resendIn}s)' : 'Resend code'),
                ),
              ),
            ] else ...[
              AuthTextField(
                label: 'New password',
                hint: 'Create a new password',
                icon: FontAwesomeIcons.lock,
                controller: _password,
                obscureText: _hidePassword,
                showPasswordToggle: true,
                onToggleObscure: () => setState(() => _hidePassword = !_hidePassword),
                onChanged: (_) => setState(() {}),
                validator: Validators.password,
                bottomPadding: 8,
              ),
              PasswordChecklist(password: _password.text),
              const SizedBox(height: 14),
              AuthTextField(
                label: 'Confirm new password',
                hint: 'Type it again',
                icon: FontAwesomeIcons.lock,
                controller: _confirm,
                obscureText: _hideConfirm,
                showPasswordToggle: true,
                onToggleObscure: () => setState(() => _hideConfirm = !_hideConfirm),
                validator: (v) => Validators.confirmPassword(v, _password.text),
              ),
              AuthGradientButton(
                key: const Key('fp-save'),
                text: 'Save and continue',
                leadingIcon: FontAwesomeIcons.floppyDisk,
                isLoading: _busy,
                onPressed: _busy ? null : _save,
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _StepDots extends StatelessWidget {
  final int step;
  const _StepDots({required this.step});

  @override
  Widget build(BuildContext context) {
    const labels = ['Account', 'Code', 'New password'];
    return Row(
      children: [
        for (var i = 0; i < 3; i++) ...[
          if (i > 0) const SizedBox(width: 6),
          Expanded(
            child: Container(
              padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 6),
              decoration: BoxDecoration(
                color: i + 1 == step ? AppColors.primary50 : AppColors.neutral100,
                borderRadius: BorderRadius.circular(999),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  CircleAvatar(
                    radius: 9,
                    backgroundColor: i + 1 < step
                        ? AppColors.success
                        : i + 1 == step
                            ? AppColors.primary
                            : AppColors.neutral300,
                    child: Text('${i + 1}', style: const TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.w700)),
                  ),
                  const SizedBox(width: 5),
                  Flexible(
                    child: Text(labels[i],
                        overflow: TextOverflow.ellipsis,
                        style: GoogleFonts.inter(
                            fontSize: 11.5,
                            fontWeight: FontWeight.w600,
                            color: i + 1 == step ? AppColors.primaryDark : AppColors.slate)),
                  ),
                ],
              ),
            ),
          ),
        ],
      ],
    );
  }
}
