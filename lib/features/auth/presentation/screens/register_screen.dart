import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:image_picker/image_picker.dart';
import '../../../../core/constants/app_colors.dart';
import '../../../../core/constants/app_strings.dart';
import '../../../../core/constants/vehicle_catalog.dart';
import '../../../../core/utils/validators.dart';
import '../../../../shared/models/profile_model.dart';
import '../../data/auth_repository.dart';
import '../providers/auth_provider.dart';
import '../widgets/auth_gradient_button.dart';
import '../widgets/auth_logo_row.dart';
import '../widgets/auth_text_field.dart';
import '../widgets/register_step_indicator.dart';

class RegisterScreen extends ConsumerStatefulWidget {
  final int initialStep;

  const RegisterScreen({super.key, this.initialStep = 0});

  @override
  ConsumerState<RegisterScreen> createState() => _RegisterScreenState();
}

class _RegisterScreenState extends ConsumerState<RegisterScreen> {
  int _step = 0;
  UserRole _selectedRole = UserRole.customer;

  final _personalFormKey = GlobalKey<FormState>();
  final _fullNameController = TextEditingController();
  final _emailController = TextEditingController();
  final _phoneController = TextEditingController();
  final _licenseNumberController = TextEditingController();
  final _passwordController = TextEditingController();
  final _confirmPasswordController = TextEditingController();
  bool _obscurePassword = true;
  bool _obscureConfirmPassword = true;
  bool _agreedToTerms = false;
  int _passwordScore = 0;

  bool _isCheckingEmail = false;
  bool? _isEmailAvailable;
  Timer? _emailDebounceTimer;

  final _vehicleFormKey = GlobalKey<FormState>();
  String _selectedVehicleType = 'Motorcycle';
  String? _selectedVehicleModel;
  final _vehiclePlateController = TextEditingController();
  final _vehicleColorController = TextEditingController();

  File? _licensePhoto;
  File? _orCrPhoto;
  File? _selfiePhoto;
  File? _vehiclePhoto;
  File? _nbiPhoto;

  /// Customer's optional profile photo (riders use [_selfiePhoto]).
  File? _customerPhoto;

  bool _customerSuccess = false;
  bool _riderSuccess = false;

  final ImagePicker _picker = ImagePicker();

  @override
  void initState() {
    super.initState();
    _step = widget.initialStep;
    _selectedVehicleModel = vehicleModelsByType[_selectedVehicleType]?.first;
  }

  @override
  void dispose() {
    _fullNameController.dispose();
    _emailController.dispose();
    _phoneController.dispose();
    _licenseNumberController.dispose();
    _passwordController.dispose();
    _confirmPasswordController.dispose();
    _vehiclePlateController.dispose();
    _vehicleColorController.dispose();
    _emailDebounceTimer?.cancel();
    super.dispose();
  }

  int get _indicatorIndex {
    if (_customerSuccess || _riderSuccess) return 4;
    if (_selectedRole != UserRole.rider) return _step.clamp(0, 1);
    return _step.clamp(0, 4);
  }

  void _showError(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: AppColors.danger,
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  int _scorePassword(String pw) {
    var score = 0;
    if (pw.length >= 6) score++;
    if (pw.length >= 10) score++;
    if (RegExp(r'[A-Z]').hasMatch(pw) && RegExp(r'[a-z]').hasMatch(pw)) score++;
    if (RegExp(r'[0-9]').hasMatch(pw) && RegExp(r'[^A-Za-z0-9]').hasMatch(pw)) score++;
    return score;
  }

  /// [face]: a profile photo — opens the front camera and keeps it smaller.
  /// Documents are capped too, so phone photos upload on weak signal.
  Future<void> _pickFile(void Function(File file) assign, {bool face = false}) async {
    final maxSide = face ? 1024.0 : 1600.0;
    final picked = await showModalBottomSheet<XFile?>(
      context: context,
      backgroundColor: AppColors.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 12),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ListTile(
                leading: const FaIcon(FontAwesomeIcons.camera, color: AppColors.brandBlue, size: 18),
                title: const Text('Take a photo'),
                onTap: () async {
                  final file = await _picker.pickImage(
                    source: ImageSource.camera,
                    imageQuality: 80,
                    maxWidth: maxSide,
                    maxHeight: maxSide,
                    preferredCameraDevice: face ? CameraDevice.front : CameraDevice.rear,
                  );
                  if (context.mounted) Navigator.pop(context, file);
                },
              ),
              ListTile(
                leading: const FaIcon(FontAwesomeIcons.image, color: AppColors.brandBlue, size: 18),
                title: const Text('Choose from gallery'),
                onTap: () async {
                  final file = await _picker.pickImage(
                    source: ImageSource.gallery,
                    imageQuality: 80,
                    maxWidth: maxSide,
                    maxHeight: maxSide,
                  );
                  if (context.mounted) Navigator.pop(context, file);
                },
              ),
            ],
          ),
        ),
      ),
    );
    if (picked != null) {
      setState(() => assign(File(picked.path)));
    }
  }

  void _onEmailChanged(String val) {
    if (val.trim().isEmpty || Validators.email(val) != null) {
      if (_isCheckingEmail || _isEmailAvailable != null) {
        setState(() {
          _isCheckingEmail = false;
          _isEmailAvailable = null;
        });
      }
      _emailDebounceTimer?.cancel();
      return;
    }
    
    setState(() {
      _isCheckingEmail = true;
      _isEmailAvailable = null;
    });

    _emailDebounceTimer?.cancel();
    _emailDebounceTimer = Timer(const Duration(milliseconds: 600), () async {
      final exists = await ref.read(authRepositoryProvider).checkEmailExists(val);
      if (mounted) {
        setState(() {
          _isCheckingEmail = false;
          _isEmailAvailable = exists == null ? null : !exists;
        });
      }
    });
  }

  Widget _buildEmailFeedback() {
    if (_isCheckingEmail) {
      return Padding(
        padding: const EdgeInsets.only(top: 4, bottom: 18),
        child: Row(
          children: [
            const SizedBox(
              width: 14,
              height: 14,
              child: CircularProgressIndicator(strokeWidth: 2, color: AppColors.brandBlue),
            ),
            const SizedBox(width: 8),
            Flexible(
              child: Text('Checking availability...',
                  overflow: TextOverflow.ellipsis,
                  style: GoogleFonts.inter(fontSize: 12, color: AppColors.slate)),
            ),
          ],
        ),
      );
    }

    if (_isEmailAvailable == true) {
      return Padding(
        padding: const EdgeInsets.only(top: 4, bottom: 18),
        child: Row(
          children: [
            const FaIcon(FontAwesomeIcons.check, size: 14, color: AppColors.success),
            const SizedBox(width: 8),
            Text('Available', style: GoogleFonts.inter(fontSize: 12, color: AppColors.success, fontWeight: FontWeight.w600)),
          ],
        ),
      );
    }

    if (_isEmailAvailable == false) {
      return Padding(
        padding: const EdgeInsets.only(top: 4, bottom: 18),
        child: Row(
          children: [
            const FaIcon(FontAwesomeIcons.triangleExclamation, size: 14, color: AppColors.danger),
            const SizedBox(width: 8),
            GestureDetector(
              onTap: () => context.go('/login'),
              child: Text(
                'This email is already registered — log in instead',
                style: GoogleFonts.inter(
                  fontSize: 12,
                  color: AppColors.brandBlue,
                  fontWeight: FontWeight.w600,
                  decoration: TextDecoration.underline,
                  decorationColor: AppColors.brandBlue,
                ),
              ),
            ),
          ],
        ),
      );
    }
    
    return const SizedBox.shrink();
  }

  Future<void> _submitPersonal() async {
    if (!_personalFormKey.currentState!.validate()) return;
    if (_isCheckingEmail) {
      _showError('Please wait while we check email availability.');
      return;
    }
    if (_isEmailAvailable == false) {
      _showError('This email is already registered. Please log in instead.');
      return;
    }
    if (!_agreedToTerms) {
      _showError('Please accept the Terms & Privacy Policy.');
      return;
    }
    if (_selectedRole == UserRole.rider) {
      setState(() => _step = 2);
      return;
    }

    final success = await ref.read(authNotifierProvider.notifier).signUpCustomer(
          fullName: _fullNameController.text.trim(),
          email: _emailController.text.trim(),
          password: _passwordController.text,
          phone: _phoneController.text.trim(),
          photo: _customerPhoto,
        );

    if (!success && mounted) {
      _showError(ref.read(authNotifierProvider).errorMessage ?? 'Registration failed');
      return;
    }
    if (mounted) setState(() => _customerSuccess = true);
  }

  /// Labels of the required uploads that are still missing. NBI clearance is
  /// optional, so it is never listed here.
  List<String> get _missingDocuments => <String>[
        if (_licensePhoto == null) "Driver's License",
        if (_orCrPhoto == null) 'OR / CR Paper',
        if (_selfiePhoto == null) 'Profile Photo',
        if (_vehiclePhoto == null) 'Vehicle Photo',
      ];

  Future<void> _submitRider() async {
    final missing = _missingDocuments;
    if (missing.isNotEmpty) {
      _showError('Please upload: ${missing.join(', ')}.');
      setState(() => _step = 3);
      return;
    }

    final success = await ref.read(authNotifierProvider.notifier).signUpRider(
          fullName: _fullNameController.text.trim(),
          email: _emailController.text.trim(),
          password: _passwordController.text,
          phone: _phoneController.text.trim(),
          vehicleType: _selectedVehicleType,
          vehiclePlate: _vehiclePlateController.text.trim(),
          vehicleModel: _selectedVehicleModel ?? '',
          licenseNumber: _licenseNumberController.text.trim(),
          licensePhoto: _licensePhoto,
          orCrPhoto: _orCrPhoto,
          selfiePhoto: _selfiePhoto,
          vehiclePhoto: _vehiclePhoto,
          nbiPhoto: _nbiPhoto,
        );

    if (!success && mounted) {
      _showError(ref.read(authNotifierProvider).errorMessage ?? 'Rider registration failed');
      return;
    }
    if (mounted) setState(() => _riderSuccess = true);
  }

  @override
  Widget build(BuildContext context) {
    final actions = _stepActions();

    return Scaffold(
      backgroundColor: AppColors.background,
      body: SafeArea(
        child: Column(
          children: [
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(16, 24, 16, 8),
                child: Center(
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 540),
                    child: Container(
                      width: double.infinity,
                      padding: const EdgeInsets.fromLTRB(18, 24, 18, 18),
                      decoration: BoxDecoration(
                        color: AppColors.surface,
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(color: const Color(0x0A0F172A)),
                        boxShadow: const [
                          BoxShadow(
                            color: Color(0x0A0F172A),
                            blurRadius: 6,
                            offset: Offset(0, 4),
                          ),
                          BoxShadow(
                            color: Color(0x1A0F172A),
                            blurRadius: 40,
                            offset: Offset(0, 16),
                          ),
                        ],
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          const AuthLogoRow(),
                          if (!_customerSuccess && !_riderSuccess)
                            RegisterStepIndicator(
                              activeIndex: _indicatorIndex,
                              isRider: _selectedRole == UserRole.rider,
                            ),
                          if (_customerSuccess)
                            _buildCustomerSuccess()
                          else if (_riderSuccess)
                            _buildRiderSuccess()
                          else if (_step == 0)
                            _buildRoleStep()
                          else if (_step == 1)
                            _buildPersonalStep()
                          else if (_step == 2)
                            _buildVehicleStep()
                          else if (_step == 3)
                            _buildDocumentsStep()
                          else
                            _buildReviewStep(),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),
            // Pinned action bar — always visible without scrolling.
            if (actions != null)
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 4, 20, 12),
                child: actions,
              ),
          ],
        ),
      ),
    );
  }

  /// Navigation buttons pinned below the card for the current step.
  Widget? _stepActions() {
    if (_customerSuccess || _riderSuccess) return null;
    final isRider = _selectedRole == UserRole.rider;

    switch (_step) {
      case 1:
        return Row(
          children: [
            AuthBackButton(onPressed: () => setState(() => _step = 0)),
            const SizedBox(width: 12),
            Expanded(
              child: AuthGradientButton(
                text: AppStrings.continueLabel,
                orange: isRider,
                trailingIcon: FontAwesomeIcons.arrowRight,
                isLoading: ref.watch(authNotifierProvider).isLoading,
                onPressed: _submitPersonal,
              ),
            ),
          ],
        );
      case 2:
        return Row(
          children: [
            AuthBackButton(onPressed: () => setState(() => _step = 1)),
            const SizedBox(width: 12),
            Expanded(
              child: AuthGradientButton(
                text: AppStrings.continueLabel,
                orange: true,
                trailingIcon: FontAwesomeIcons.arrowRight,
                onPressed: () {
                  if (!_vehicleFormKey.currentState!.validate()) return;
                  setState(() => _step = 3);
                },
              ),
            ),
          ],
        );
      case 3:
        return Row(
          children: [
            AuthBackButton(onPressed: () => setState(() => _step = 2)),
            const SizedBox(width: 12),
            Expanded(
              child: AuthGradientButton(
                text: 'Continue to Review',
                orange: true,
                trailingIcon: FontAwesomeIcons.arrowRight,
                onPressed: () {
                  final missing = _missingDocuments;
                  if (missing.isNotEmpty) {
                    _showError('Please upload: ${missing.join(', ')}.');
                    return;
                  }
                  setState(() => _step = 4);
                },
              ),
            ),
          ],
        );
      case 4:
        return Row(
          children: [
            AuthBackButton(onPressed: () => setState(() => _step = 3)),
            const SizedBox(width: 12),
            Expanded(
              child: AuthGradientButton(
                text: 'Submit Application',
                orange: true,
                trailingIcon: FontAwesomeIcons.paperPlane,
                isLoading: ref.watch(authNotifierProvider).isLoading,
                onPressed: _submitRider,
              ),
            ),
          ],
        );
      default:
        return null;
    }
  }

  Widget _panelTitle(String title, String sub) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title,
          style: GoogleFonts.poppins(
            fontWeight: FontWeight.w700,
            fontSize: 21.6,
            color: AppColors.ink,
          ),
        ),
        const SizedBox(height: 6),
        Text(
          sub,
          style: GoogleFonts.inter(
            fontSize: 14.1,
            height: 1.6,
            color: AppColors.slate,
          ),
        ),
        const SizedBox(height: 28),
      ],
    );
  }

  Widget _buildRoleStep() {
    final isRider = _selectedRole == UserRole.rider;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _panelTitle(AppStrings.selectRoleTitle, AppStrings.selectRoleSubtitle),
        Row(
          children: [
            Expanded(
              child: _RoleCard(
                isCustomer: true,
                selected: !isRider,
                title: AppStrings.customerRoleTitle,
                description: AppStrings.customerRoleDesc,
                icon: FontAwesomeIcons.user,
                onTap: () => setState(() => _selectedRole = UserRole.customer),
              ),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: _RoleCard(
                isCustomer: false,
                selected: isRider,
                title: AppStrings.riderRoleTitle,
                description: AppStrings.riderRoleDesc,
                icon: FontAwesomeIcons.motorcycle,
                onTap: () => setState(() => _selectedRole = UserRole.rider),
              ),
            ),
          ],
        ),
        const SizedBox(height: 28),
        AuthGradientButton(
          text: AppStrings.continueLabel,
          orange: isRider,
          trailingIcon: FontAwesomeIcons.arrowRight,
          onPressed: () => setState(() => _step = 1),
        ),
        const SizedBox(height: 20),
        _loginLink(),
      ],
    );
  }

  Widget _buildPersonalStep() {
    final isRider = _selectedRole == UserRole.rider;
    return Form(
      key: _personalFormKey,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _panelTitle(
            AppStrings.personalInfoTitle,
            isRider ? AppStrings.personalInfoRiderSub : AppStrings.personalInfoCustomerSub,
          ),
          if (!isRider)
            _SignupPhotoPicker(
              file: _customerPhoto,
              onPick: () => _pickFile((f) => _customerPhoto = f, face: true),
              onRemove: () => setState(() => _customerPhoto = null),
            ),
          AuthTextField(
            label: 'Full Name',
            hint: 'Juan dela Cruz',
            icon: FontAwesomeIcons.user,
            controller: _fullNameController,
            textInputAction: TextInputAction.next,
            validator: (val) => Validators.required(val, 'Full Name'),
          ),
          AuthTextField(
            label: 'Phone Number',
            hint: '09XX XXX XXXX',
            icon: FontAwesomeIcons.phone,
            controller: _phoneController,
            keyboardType: TextInputType.phone,
            textInputAction: TextInputAction.next,
            validator: Validators.phone,
          ),
          AuthTextField(
            label: 'Email Address',
            hint: 'juandelacruz@email.com',
            icon: FontAwesomeIcons.envelope,
            controller: _emailController,
            keyboardType: TextInputType.emailAddress,
            textInputAction: TextInputAction.next,
            validator: Validators.email,
            onChanged: _onEmailChanged,
            bottomPadding: (_isCheckingEmail || _isEmailAvailable != null) ? 0 : 18,
          ),
          if (_emailController.text.isNotEmpty && (_isCheckingEmail || _isEmailAvailable != null))
            _buildEmailFeedback(),
          if (isRider)
            AuthTextField(
              label: "Driver's License Number",
              hint: 'e.g. N01-23-456789',
              icon: FontAwesomeIcons.idCard,
              controller: _licenseNumberController,
              textInputAction: TextInputAction.next,
              validator: (val) => Validators.required(val, 'License number'),
            ),
          AuthTextField(
            label: 'Password',
            hint: 'Create a password',
            icon: FontAwesomeIcons.lock,
            controller: _passwordController,
            obscureText: _obscurePassword,
            showPasswordToggle: true,
            onToggleObscure: () => setState(() => _obscurePassword = !_obscurePassword),
            validator: Validators.password,
            onChanged: (v) => setState(() => _passwordScore = _scorePassword(v)),
          ),
          if (_passwordController.text.isNotEmpty) _passwordStrength(),
          AuthTextField(
            label: 'Confirm Password',
            hint: 'Repeat password',
            icon: FontAwesomeIcons.lock,
            controller: _confirmPasswordController,
            obscureText: _obscureConfirmPassword,
            showPasswordToggle: true,
            onToggleObscure: () => setState(() => _obscureConfirmPassword = !_obscureConfirmPassword),
            validator: (val) => Validators.confirmPassword(val, _passwordController.text),
          ),
          Container(
            margin: const EdgeInsets.only(bottom: 24),
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
            decoration: BoxDecoration(
              color: AppColors.inputFill,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: const Color(0xFFE5E7EB), width: 1.5),
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SizedBox(
                  width: 18,
                  height: 18,
                  child: Checkbox(
                    value: _agreedToTerms,
                    onChanged: (v) => setState(() => _agreedToTerms = v ?? false),
                    activeColor: AppColors.brandBlue,
                    materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    visualDensity: VisualDensity.compact,
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text.rich(
                    TextSpan(
                      style: GoogleFonts.inter(fontSize: 13.6, color: AppColors.slate, height: 1.5),
                      children: [
                        const TextSpan(text: '${AppStrings.termsPrefix} '),
                        TextSpan(
                          text: AppStrings.termsOfService,
                          style: GoogleFonts.inter(
                            fontSize: 13.6,
                            fontWeight: FontWeight.w600,
                            color: AppColors.brandBlue,
                          ),
                        ),
                        const TextSpan(text: ' and '),
                        TextSpan(
                          text: AppStrings.privacyPolicy,
                          style: GoogleFonts.inter(
                            fontSize: 13.6,
                            fontWeight: FontWeight.w600,
                            color: AppColors.brandBlue,
                          ),
                        ),
                        const TextSpan(text: ' ${AppStrings.termsSuffix}'),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _passwordStrength() {
    const labels = ['', 'Weak', 'Fair', 'Good', 'Strong'];
    const colors = [
      Color(0xFFE5E7EB),
      Color(0xFFEF4444),
      Color(0xFFF59E0B),
      Color(0xFF3B82F6),
      Color(0xFF22C55E),
    ];
    final color = colors[_passwordScore];
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: List.generate(4, (i) {
              return Expanded(
                child: Container(
                  margin: EdgeInsets.only(right: i == 3 ? 0 : 4),
                  height: 4,
                  decoration: BoxDecoration(
                    color: i < _passwordScore ? color : const Color(0xFFE5E7EB),
                    borderRadius: BorderRadius.circular(99),
                  ),
                ),
              );
            }),
          ),
          const SizedBox(height: 5),
          Text(
            labels[_passwordScore],
            style: GoogleFonts.inter(fontSize: 12, fontWeight: FontWeight.w500, color: color),
          ),
        ],
      ),
    );
  }

  Widget _buildVehicleStep() {
    final models = vehicleModelsByType[_selectedVehicleType] ?? [];
    return Form(
      key: _vehicleFormKey,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _panelTitle(AppStrings.vehicleTitle, AppStrings.vehicleSub),
          GridView.count(
            crossAxisCount: 3,
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            mainAxisSpacing: 10,
            crossAxisSpacing: 10,
            // Tall enough for the icon plus a wrapped label at 360dp.
            childAspectRatio: 0.85,
            children: vehicleTypes.map((type) {
              final selected = _selectedVehicleType == type;
              return GestureDetector(
                onTap: () {
                  setState(() {
                    _selectedVehicleType = type;
                    final next = vehicleModelsByType[type] ?? [];
                    _selectedVehicleModel = next.isEmpty ? null : next.first;
                  });
                },
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 14),
                  decoration: BoxDecoration(
                    color: selected ? const Color(0xFFEFF4FF) : const Color(0xFFFAFAFA),
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(
                      color: selected ? AppColors.brandBlue : const Color(0xFFE5E7EB),
                      width: 2,
                    ),
                    boxShadow: selected
                        ? [
                            BoxShadow(
                              color: AppColors.brandBlue.withValues(alpha: 0.12),
                              blurRadius: 0,
                              spreadRadius: 3,
                            ),
                          ]
                        : null,
                  ),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      _vehicleIcon(type, selected),
                      const SizedBox(height: 6),
                      Text(
                        type,
                        textAlign: TextAlign.center,
                        style: GoogleFonts.inter(
                          fontSize: 11.5,
                          fontWeight: FontWeight.w600,
                          color: selected ? AppColors.brandBlue : AppColors.slate,
                        ),
                      ),
                    ],
                  ),
                ),
              );
            }).toList(),
          ),
          const SizedBox(height: 24),
          AuthTextField(
            label: 'Plate Number',
            hint: 'e.g. ABC 1234',
            icon: FontAwesomeIcons.hashtag,
            controller: _vehiclePlateController,
            validator: (val) => Validators.required(val, 'Plate number'),
          ),
          AuthTextField(
            label: 'Vehicle Color',
            hint: 'e.g. Red',
            icon: FontAwesomeIcons.palette,
            controller: _vehicleColorController,
          ),
          Padding(
            padding: const EdgeInsets.only(bottom: 18),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Vehicle Model',
                  style: GoogleFonts.inter(
                    fontSize: 13.3,
                    fontWeight: FontWeight.w600,
                    color: AppColors.neutral700,
                  ),
                ),
                const SizedBox(height: 8),
                DropdownButtonFormField<String>(
                  initialValue: models.contains(_selectedVehicleModel) ? _selectedVehicleModel : models.firstOrNull,
                  // Without this the selected model is laid out at its natural
                  // width and long names overflow the field.
                  isExpanded: true,
                  items: models
                      .map((m) => DropdownMenuItem(value: m, child: Text(m, overflow: TextOverflow.ellipsis)))
                      .toList(),
                  onChanged: (v) => setState(() => _selectedVehicleModel = v),
                  decoration: InputDecoration(
                    prefixIcon: Padding(
                      padding: EdgeInsets.only(left: 14, right: 10),
                      child: FaIcon(FontAwesomeIcons.tag, size: 15, color: AppColors.iconMuted),
                    ),
                    prefixIconConstraints: const BoxConstraints(minWidth: 42),
                    filled: true,
                    fillColor: AppColors.inputFill,
                    contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 13),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: const BorderSide(color: Color(0xFFE5E7EB), width: 1.5),
                    ),
                    enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: const BorderSide(color: Color(0xFFE5E7EB), width: 1.5),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _vehicleIcon(String type, bool selected) {
    final color = selected ? AppColors.brandBlue : AppColors.iconMuted;
    switch (type) {
      case 'Motorcycle':
        return FaIcon(FontAwesomeIcons.motorcycle, size: 22, color: color);
      case 'Tricycle':
        return Text('🛺', style: TextStyle(fontSize: 22, color: color));
      case 'Car':
        return FaIcon(FontAwesomeIcons.car, size: 22, color: color);
      case 'SUV':
        return FaIcon(FontAwesomeIcons.carSide, size: 22, color: color);
      case 'Van':
        return FaIcon(FontAwesomeIcons.vanShuttle, size: 22, color: color);
      case 'Pickup':
        return FaIcon(FontAwesomeIcons.truckPickup, size: 22, color: color);
      default:
        return FaIcon(FontAwesomeIcons.truck, size: 22, color: color);
    }
  }

  Widget _buildDocumentsStep() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _panelTitle(AppStrings.documentsTitle, AppStrings.documentsSub),
        _UploadZone(
          label: "Driver's License",
          hint: "Upload your valid driver's license photo or PDF",
          icon: FontAwesomeIcons.idCard,
          file: _licensePhoto,
          onTap: () => _pickFile((f) => _licensePhoto = f),
        ),
        const SizedBox(height: 14),
        _UploadZone(
          label: 'OR / CR Paper',
          hint: 'Upload your official receipt or registration paper',
          icon: FontAwesomeIcons.fileLines,
          file: _orCrPhoto,
          onTap: () => _pickFile((f) => _orCrPhoto = f),
        ),
        const SizedBox(height: 14),
        _UploadZone(
          label: 'Profile Photo (your face)',
          hint: 'Face clearly visible — no sunglasses, helmet or mask. Customers see this photo when you accept their booking.',
          icon: FontAwesomeIcons.camera,
          file: _selfiePhoto,
          onTap: () => _pickFile((f) => _selfiePhoto = f, face: true),
        ),
        const SizedBox(height: 14),
        _UploadZone(
          label: 'Vehicle Photo',
          hint: 'Upload a clear photo of your vehicle',
          icon: FontAwesomeIcons.motorcycle,
          file: _vehiclePhoto,
          onTap: () => _pickFile((f) => _vehiclePhoto = f),
        ),
        const SizedBox(height: 14),
        _UploadZone(
          label: 'NBI Clearance',
          hint: 'Upload your clearance if you have one',
          icon: FontAwesomeIcons.shieldHalved,
          file: _nbiPhoto,
          optional: true,
          onTap: () => _pickFile((f) => _nbiPhoto = f),
        ),
      ],
    );
  }

  Widget _buildReviewStep() {
    final rows = <(String, String)>[
      ('Full Name', _fullNameController.text.trim().isEmpty ? 'Not provided' : _fullNameController.text.trim()),
      ('Phone', _phoneController.text.trim().isEmpty ? 'Not provided' : _phoneController.text.trim()),
      ('Email', _emailController.text.trim().isEmpty ? 'Not provided' : _emailController.text.trim()),
      ('Account Type', 'Rider'),
      ("Driver's License Number", _licenseNumberController.text.trim().isEmpty ? 'Not provided' : _licenseNumberController.text.trim()),
      ('Vehicle Type', _selectedVehicleType),
      ('Vehicle Model', _selectedVehicleModel ?? 'Not selected'),
      ('Vehicle Color', _vehicleColorController.text.trim().isEmpty ? 'Not provided' : _vehicleColorController.text.trim()),
      ('Plate Number', _vehiclePlateController.text.trim().isEmpty ? 'Not provided' : _vehiclePlateController.text.trim()),
      ("Driver's License", _licensePhoto?.path.split(Platform.pathSeparator).last ?? 'Not uploaded'),
      ('OR / CR Paper', _orCrPhoto?.path.split(Platform.pathSeparator).last ?? 'Not uploaded'),
      ('Profile Photo', _selfiePhoto?.path.split(Platform.pathSeparator).last ?? 'Not uploaded'),
      ('Vehicle Photo', _vehiclePhoto?.path.split(Platform.pathSeparator).last ?? 'Not uploaded'),
      ('NBI Clearance', _nbiPhoto?.path.split(Platform.pathSeparator).last ?? 'Optional'),
    ];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _panelTitle(AppStrings.reviewTitle, AppStrings.reviewSub),
        Container(
          padding: const EdgeInsets.fromLTRB(18, 16, 18, 16),
          decoration: BoxDecoration(
            color: AppColors.inputFill,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: const Color(0xFFE2E8F0)),
          ),
          child: Column(
            children: rows
                .map(
                  (row) => Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(
                          child: Text(
                            '${row.$1}:',
                            style: GoogleFonts.inter(
                              fontSize: 13.1,
                              fontWeight: FontWeight.w600,
                              color: AppColors.ink,
                            ),
                          ),
                        ),
                        Expanded(
                          child: Text(
                            row.$2,
                            textAlign: TextAlign.right,
                            style: GoogleFonts.inter(fontSize: 13.1, color: const Color(0xFF475569)),
                          ),
                        ),
                      ],
                    ),
                  ),
                )
                .toList(),
          ),
        ),
        const SizedBox(height: 16),
        Text(
          AppStrings.riderNotifyNote,
          textAlign: TextAlign.center,
          style: GoogleFonts.inter(fontSize: 13.1, color: AppColors.iconMuted),
        ),
      ],
    );
  }

  Widget _buildCustomerSuccess() {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 20),
      child: Column(
        children: [
          Container(
            width: 100,
            height: 100,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              gradient: const LinearGradient(colors: [Color(0xFF22C55E), Color(0xFF16A34A)]),
              boxShadow: [
                BoxShadow(color: const Color(0xFF22C55E).withValues(alpha: 0.35), blurRadius: 32, offset: const Offset(0, 8)),
              ],
            ),
            child: const Center(child: FaIcon(FontAwesomeIcons.check, size: 40, color: Colors.white)),
          ),
          const SizedBox(height: 24),
          Text(
            AppStrings.customerSuccessTitle,
            style: GoogleFonts.poppins(fontWeight: FontWeight.w800, fontSize: 22.4, color: AppColors.ink),
          ),
          const SizedBox(height: 10),
          Text(
            AppStrings.customerSuccessMessage,
            textAlign: TextAlign.center,
            style: GoogleFonts.inter(fontSize: 14.7, height: 1.7, color: AppColors.slate),
          ),
          if (ref.watch(authNotifierProvider.notifier).lastSignupNeedsEmailConfirm) ...[
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: AppColors.brandBlue.withValues(alpha: 0.08),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: AppColors.brandBlue.withValues(alpha: 0.3)),
              ),
              child: Row(
                children: [
                  const FaIcon(FontAwesomeIcons.envelopeCircleCheck,
                      size: 15, color: AppColors.brandBlue),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      'We sent a verification link to your email. Please verify before logging in.',
                      style: GoogleFonts.inter(fontSize: 12.8, height: 1.5, color: AppColors.slate),
                    ),
                  ),
                ],
              ),
            ),
          ],
          const SizedBox(height: 28),
          AuthGradientButton(
            text: AppStrings.loginNow,
            leadingIcon: FontAwesomeIcons.rightToBracket,
            onPressed: () => context.go('/login'),
          ),
        ],
      ),
    );
  }

  Widget _buildRiderSuccess() {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 20),
      child: Column(
        children: [
          Container(
            width: 120,
            height: 120,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              gradient: LinearGradient(colors: [AppColors.brandOrange, AppColors.brandOrangeDark]),
              boxShadow: [
                BoxShadow(color: AppColors.brandOrange.withValues(alpha: 0.35), blurRadius: 32, offset: const Offset(0, 8)),
              ],
            ),
            child: const Center(child: FaIcon(FontAwesomeIcons.motorcycle, size: 44, color: Colors.white)),
          ),
          const SizedBox(height: 24),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 8),
            decoration: BoxDecoration(
              color: AppColors.secondary50,
              borderRadius: BorderRadius.circular(99),
              border: Border.all(color: AppColors.blushBorder, width: 1.5),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                FaIcon(FontAwesomeIcons.clock, size: 13, color: AppColors.brandOrangeDark),
                const SizedBox(width: 8),
                Text(
                  AppStrings.pendingApproval,
                  style: GoogleFonts.inter(
                    fontSize: 13.1,
                    fontWeight: FontWeight.w600,
                    color: AppColors.brandOrangeDark,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          Text(
            AppStrings.riderSuccessTitle,
            textAlign: TextAlign.center,
            style: GoogleFonts.poppins(fontWeight: FontWeight.w800, fontSize: 22.4, color: AppColors.ink),
          ),
          const SizedBox(height: 10),
          Text(
            AppStrings.riderSuccessMessage,
            textAlign: TextAlign.center,
            style: GoogleFonts.inter(fontSize: 14.7, height: 1.7, color: AppColors.slate),
          ),
          if (ref.watch(authNotifierProvider.notifier).lastSignupNeedsEmailConfirm) ...[
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: AppColors.brandOrange.withValues(alpha: 0.08),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: AppColors.brandOrange.withValues(alpha: 0.3)),
              ),
              child: Row(
                children: [
                  FaIcon(FontAwesomeIcons.envelopeCircleCheck,
                      size: 15, color: AppColors.brandOrangeDark),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      'We sent a verification link to your email. Please verify before logging in.',
                      style: GoogleFonts.inter(fontSize: 12.8, height: 1.5, color: AppColors.slate),
                    ),
                  ),
                ],
              ),
            ),
          ],
          const SizedBox(height: 28),
          AuthGradientButton(
            text: AppStrings.goToLogin,
            leadingIcon: FontAwesomeIcons.rightToBracket,
            onPressed: () => context.go('/login'),
          ),
          const SizedBox(height: 20),
          Text(
            'You will receive an SMS and email notification once approved.',
            textAlign: TextAlign.center,
            style: GoogleFonts.inter(fontSize: 13.1, color: AppColors.iconMuted),
          ),
        ],
      ),
    );
  }

  Widget _loginLink() {
    return Wrap(
      alignment: WrapAlignment.center,
      children: [
        Text(
          '${AppStrings.alreadyHaveAccount} ',
          style: GoogleFonts.inter(fontSize: 14.1, color: AppColors.slate),
        ),
        GestureDetector(
          onTap: () => context.go('/login'),
          child: Text(
            AppStrings.signIn,
            style: GoogleFonts.inter(
              fontSize: 14.1,
              fontWeight: FontWeight.w700,
              color: AppColors.brandBlue,
            ),
          ),
        ),
      ],
    );
  }
}

class _RoleCard extends StatelessWidget {
  final bool isCustomer;
  final bool selected;
  final String title;
  final String description;
  final FaIconData icon;
  final VoidCallback onTap;

  const _RoleCard({
    required this.isCustomer,
    required this.selected,
    required this.title,
    required this.description,
    required this.icon,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final accent = isCustomer ? AppColors.brandBlue : AppColors.brandOrange;
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 220),
        padding: const EdgeInsets.fromLTRB(12, 28, 12, 20),
        decoration: BoxDecoration(
          color: const Color(0xFFFAFAFA),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: selected ? accent : const Color(0xFFE5E7EB), width: 2),
          boxShadow: selected
              ? [
                  BoxShadow(color: accent.withValues(alpha: 0.12), blurRadius: 0, spreadRadius: 4),
                  BoxShadow(color: accent.withValues(alpha: 0.15), blurRadius: 24, offset: const Offset(0, 8)),
                ]
              : null,
        ),
        child: Stack(
          children: [
            Column(
              children: [
                AnimatedContainer(
                  duration: const Duration(milliseconds: 220),
                  width: 64,
                  height: 64,
                  decoration: BoxDecoration(
                    color: selected
                        ? accent
                        : isCustomer
                            ? AppColors.primary50
                            : AppColors.secondary50,
                    borderRadius: BorderRadius.circular(18),
                    boxShadow: selected
                        ? [BoxShadow(color: accent.withValues(alpha: 0.35), blurRadius: 16, offset: const Offset(0, 8))]
                        : null,
                  ),
                  child: Center(
                    child: FaIcon(icon, size: 22, color: selected ? Colors.white : accent),
                  ),
                ),
                const SizedBox(height: 14),
                Text(
                  title,
                  style: GoogleFonts.poppins(fontWeight: FontWeight.w700, fontSize: 16, color: AppColors.ink),
                ),
                const SizedBox(height: 6),
                Text(
                  description,
                  textAlign: TextAlign.center,
                  style: GoogleFonts.inter(fontSize: 12.8, height: 1.5, color: AppColors.slate),
                ),
              ],
            ),
            Positioned(
              top: 0,
              right: 0,
              child: AnimatedScale(
                scale: selected ? 1 : 0,
                duration: const Duration(milliseconds: 220),
                child: Container(
                  width: 22,
                  height: 22,
                  decoration: BoxDecoration(color: accent, shape: BoxShape.circle),
                  child: const Center(child: FaIcon(FontAwesomeIcons.check, size: 10, color: Colors.white)),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Customer's optional profile photo on the Personal step (web: the
/// #customer-photo-group circle on register.html).
class _SignupPhotoPicker extends StatelessWidget {
  final File? file;
  final VoidCallback onPick;
  final VoidCallback onRemove;

  const _SignupPhotoPicker({required this.file, required this.onPick, required this.onRemove});

  @override
  Widget build(BuildContext context) {
    final picked = file;
    return Container(
      margin: const EdgeInsets.only(bottom: 20),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: const Color(0xFFFFFDFC),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0xFFECDEDD), width: 1.5),
      ),
      child: Row(
        children: [
          GestureDetector(
            onTap: onPick,
            child: Container(
              width: 60,
              height: 60,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: const Color(0xFFE8F3FE),
                border: Border.all(color: const Color(0xFFCFE5FB), width: 2),
                image: picked != null ? DecorationImage(image: FileImage(picked), fit: BoxFit.cover) : null,
              ),
              alignment: Alignment.center,
              child: picked == null
                  ? const FaIcon(FontAwesomeIcons.camera, size: 18, color: AppColors.brandBlue)
                  : null,
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                GestureDetector(
                  onTap: onPick,
                  child: Wrap(
                    crossAxisAlignment: WrapCrossAlignment.center,
                    spacing: 8,
                    children: [
                      Text(
                        picked == null ? 'Add a profile photo' : 'Change photo',
                        style: GoogleFonts.inter(fontSize: 14, fontWeight: FontWeight.w700, color: AppColors.brandBlue),
                      ),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                        decoration: BoxDecoration(
                          color: const Color(0xFFF3EEED),
                          borderRadius: BorderRadius.circular(999),
                        ),
                        child: Text('Optional',
                            style: GoogleFonts.inter(fontSize: 10.5, fontWeight: FontWeight.w600, color: AppColors.slate)),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  'Helps your rider recognise you at pickup. You can skip this.',
                  style: GoogleFonts.inter(fontSize: 12, color: AppColors.slate),
                ),
                if (picked != null)
                  GestureDetector(
                    onTap: onRemove,
                    child: Padding(
                      padding: const EdgeInsets.only(top: 4),
                      child: Text('Remove photo',
                          style: GoogleFonts.inter(fontSize: 12, fontWeight: FontWeight.w600, color: AppColors.danger)),
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

class _UploadZone extends StatelessWidget {
  final String label;
  final String hint;
  final FaIconData icon;
  final File? file;
  final bool optional;
  final VoidCallback onTap;

  const _UploadZone({
    required this.label,
    required this.hint,
    required this.icon,
    required this.file,
    required this.onTap,
    this.optional = false,
  });

  @override
  Widget build(BuildContext context) {
    final hasFile = file != null;
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: double.infinity,
        constraints: const BoxConstraints(minHeight: 130),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 22),
        decoration: BoxDecoration(
          color: hasFile ? const Color(0xFFF0FDF4) : const Color(0xFFFAFAFA),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: hasFile ? AppColors.success : const Color(0xFFE5E7EB),
            width: 2,
            style: hasFile ? BorderStyle.solid : BorderStyle.solid,
          ),
        ),
        child: Stack(
          children: [
            Column(
              children: [
                if (hasFile)
                  ClipRRect(
                    borderRadius: BorderRadius.circular(8),
                    child: Image.file(file!, height: 70, width: double.infinity, fit: BoxFit.cover),
                  )
                else
                  FaIcon(icon, size: 26, color: AppColors.iconMuted),
                const SizedBox(height: 8),
                Text(
                  label,
                  style: GoogleFonts.inter(fontSize: 12.5, fontWeight: FontWeight.w600, color: AppColors.neutral700),
                ),
                const SizedBox(height: 3),
                Text(
                  hasFile ? file!.path.split(Platform.pathSeparator).last : hint,
                  textAlign: TextAlign.center,
                  style: GoogleFonts.inter(fontSize: 11.2, color: AppColors.iconMuted),
                ),
                const SizedBox(height: 8),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
                  decoration: BoxDecoration(
                    color: const Color(0xFFEFF6FF),
                    borderRadius: BorderRadius.circular(99),
                    border: Border.all(color: const Color(0xFFDBEAFE)),
                  ),
                  child: Text(
                    'Choose file',
                    style: GoogleFonts.inter(
                      fontSize: 11.5,
                      fontWeight: FontWeight.w700,
                      color: AppColors.brandBlue,
                    ),
                  ),
                ),
                if (optional) ...[
                  const SizedBox(height: 4),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                    decoration: BoxDecoration(
                      color: const Color(0xFFF1F5F9),
                      borderRadius: BorderRadius.circular(99),
                    ),
                    child: Text(
                      'Optional',
                      style: GoogleFonts.inter(fontSize: 10.9, color: AppColors.iconMuted),
                    ),
                  ),
                ],
              ],
            ),
            if (hasFile)
              const Positioned(
                top: 0,
                right: 0,
                child: CircleAvatar(
                  radius: 11,
                  backgroundColor: AppColors.success,
                  child: FaIcon(FontAwesomeIcons.check, size: 10, color: Colors.white),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
