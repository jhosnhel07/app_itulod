import 'dart:async';
import 'dart:io';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../../../core/utils/app_log.dart';
import '../../../../shared/models/profile_model.dart';
import '../../../../shared/models/rider_application_model.dart';
import '../../../../shared/models/vehicle_model.dart';
import '../../data/auth_repository.dart';

enum AuthStatus {
  initial,
  loading,
  authenticated,
  unauthenticated,
  error,
}

class AppAuthState {
  final AuthStatus status;
  final ProfileModel? profile;
  final RiderApplicationModel? riderApplication;
  final String? errorMessage;

  const AppAuthState({
    this.status = AuthStatus.initial,
    this.profile,
    this.riderApplication,
    this.errorMessage,
  });

  bool get isAuthenticated => status == AuthStatus.authenticated && profile != null;
  bool get isLoading => status == AuthStatus.loading;

  AppAuthState copyWith({
    AuthStatus? status,
    ProfileModel? profile,
    RiderApplicationModel? riderApplication,
    String? errorMessage,
    bool clearError = false,
  }) {
    return AppAuthState(
      status: status ?? this.status,
      profile: profile ?? this.profile,
      riderApplication: riderApplication ?? this.riderApplication,
      errorMessage: clearError ? null : (errorMessage ?? this.errorMessage),
    );
  }
}

final vehiclesListProvider = FutureProvider<List<VehicleModel>>((ref) async {
  final repo = ref.watch(authRepositoryProvider);
  return repo.getAvailableVehicles();
});

final authNotifierProvider = StateNotifierProvider<AuthNotifier, AppAuthState>((ref) {
  final repo = ref.watch(authRepositoryProvider);
  return AuthNotifier(repo);
});

class AuthNotifier extends StateNotifier<AppAuthState> {
  final AuthRepository _repo;

  /// True when the most recent signup returned no session, meaning Supabase
  /// requires email confirmation before the account can log in.
  bool lastSignupNeedsEmailConfirm = false;

  final Completer<void> _bootstrapped = Completer<void>();

  /// Completes once the very first auth resolution has landed — the state has
  /// moved to `authenticated` or `unauthenticated`. The splash screen awaits
  /// this so it can route to a definite destination with no flash.
  Future<void> get bootstrapped => _bootstrapped.future;

  AuthNotifier(this._repo) : super(const AppAuthState()) {
    _init();
  }

  @override
  set state(AppAuthState value) {
    super.state = value;
    if (!_bootstrapped.isCompleted &&
        (value.status == AuthStatus.authenticated ||
            value.status == AuthStatus.unauthenticated)) {
      _bootstrapped.complete();
    }
  }

  void _init() {
    _repo.authStateChanges.listen((data) async {
      final session = data.session;
      if (session == null) {
        state = const AppAuthState(status: AuthStatus.unauthenticated);
      } else {
        await refreshProfile();
      }
    });

    // Check current state immediately
    if (_repo.currentUser != null) {
      refreshProfile();
    } else {
      state = const AppAuthState(status: AuthStatus.unauthenticated);
    }
  }

  Future<void> refreshProfile() async {
    try {
      final profile = await _repo.getCurrentProfile();
      if (profile == null) {
        state = const AppAuthState(status: AuthStatus.unauthenticated);
        return;
      }

      RiderApplicationModel? riderApp;
      if (profile.role == UserRole.rider) {
        riderApp = await _repo.getRiderApplication(profile.id);
      }

      state = AppAuthState(
        status: AuthStatus.authenticated,
        profile: profile,
        riderApplication: riderApp,
      );
    } catch (e) {
      state = AppAuthState(
        status: AuthStatus.unauthenticated,
        errorMessage: e.toString(),
      );
    }
  }

  void updateProfileLocally(ProfileModel profile) {
    state = state.copyWith(profile: profile);
  }

  Future<bool> signIn({
    required String emailOrUsername,
    required String password,
  }) async {
    state = state.copyWith(status: AuthStatus.loading, clearError: true);
    try {
      final profile = await _repo.signIn(
        emailOrUsername: emailOrUsername,
        password: password,
      );

      RiderApplicationModel? riderApp;
      if (profile.role == UserRole.rider) {
        riderApp = await _repo.getRiderApplication(profile.id);
      }

      state = AppAuthState(
        status: AuthStatus.authenticated,
        profile: profile,
        riderApplication: riderApp,
      );
      return true;
    } on AuthException catch (e) {
      state = state.copyWith(
        status: AuthStatus.unauthenticated,
        errorMessage: e.message,
      );
      return false;
    } catch (e) {
      state = state.copyWith(
        status: AuthStatus.unauthenticated,
        errorMessage: e.toString().replaceAll('Exception: ', ''),
      );
      return false;
    }
  }

  Future<bool> signUpCustomer({
    required String fullName,
    required String email,
    required String password,
    String? phone,
  }) async {
    state = state.copyWith(status: AuthStatus.loading, clearError: true);
    lastSignupNeedsEmailConfirm = false;
    try {
      final authResponse = await _repo.signUp(
        email: email,
        password: password,
        fullName: fullName,
        role: UserRole.customer,
        phone: phone,
      );

      if (authResponse.session != null) {
        // Match the web wizard: always end at the login screen, never
        // auto-login straight into the dashboard after registration.
        await _repo.signOut();
        state = const AppAuthState(status: AuthStatus.unauthenticated);
      } else {
        lastSignupNeedsEmailConfirm = true;
        state = const AppAuthState(status: AuthStatus.unauthenticated);
      }
      return true;
    } on AuthException catch (e) {
      state = state.copyWith(
        status: AuthStatus.unauthenticated,
        errorMessage: e.message,
      );
      return false;
    } catch (e) {
      state = state.copyWith(
        status: AuthStatus.unauthenticated,
        errorMessage: e.toString().replaceAll('Exception: ', ''),
      );
      return false;
    }
  }

  Future<bool> signUpRider({
    required String fullName,
    required String email,
    required String password,
    required String phone,
    required String vehicleType,
    required String vehiclePlate,
    required String vehicleModel,
    required String licenseNumber,
    File? licensePhoto,
    File? orCrPhoto,
    File? selfiePhoto,
    File? vehiclePhoto,
    File? nbiPhoto,
  }) async {
    state = state.copyWith(status: AuthStatus.loading, clearError: true);
    lastSignupNeedsEmailConfirm = false;
    try {
      final authResponse = await _repo.signUp(
        email: email,
        password: password,
        fullName: fullName,
        role: UserRole.rider,
        phone: phone,
      );

      final user = authResponse.user;
      if (user == null) {
        throw const AuthException('Could not create rider account');
      }

      String? licenseUrl;
      String? orCrUrl;
      String? selfieUrl;
      String? vehicleUrl;
      String? nbiUrl;

      Future<String?> upload(File? file, String kind) async {
        if (file == null) return null;
        try {
          return await _repo.uploadRiderDocument(
            userId: user.id,
            file: file,
            kind: kind,
          );
        } catch (e, s) {
          AppLog.warn('signUpRider: "$kind" document upload failed', e, s);
          return null;
        }
      }

      licenseUrl = await upload(licensePhoto, 'license');
      orCrUrl = await upload(orCrPhoto, 'orcr');
      selfieUrl = await upload(selfiePhoto, 'selfie');
      vehicleUrl = await upload(vehiclePhoto, 'vehicle');
      nbiUrl = await upload(nbiPhoto, 'nbi');

      await _repo.createRiderApplication(
        riderId: user.id,
        vehicleType: vehicleType,
        vehiclePlate: vehiclePlate,
        vehicleModel: vehicleModel,
        licenseNumber: licenseNumber,
        licenseUrl: licenseUrl,
        orCrUrl: orCrUrl,
        selfieUrl: selfieUrl,
        vehicleUrl: vehicleUrl,
        nbiUrl: nbiUrl,
      );

      // Match the web wizard: riders always land on the "Pending Approval"
      // success panel, then log in explicitly — never straight into the app.
      await _repo.signOut();
      if (authResponse.session == null) {
        lastSignupNeedsEmailConfirm = true;
      }
      state = const AppAuthState(status: AuthStatus.unauthenticated);

      return true;
    } on AuthException catch (e) {
      state = state.copyWith(
        status: AuthStatus.unauthenticated,
        errorMessage: e.message,
      );
      return false;
    } catch (e) {
      state = state.copyWith(
        status: AuthStatus.unauthenticated,
        errorMessage: e.toString().replaceAll('Exception: ', ''),
      );
      return false;
    }
  }

  Future<bool> resetPassword(String emailOrUsername) async {
    try {
      await _repo.resetPasswordForEmail(emailOrUsername);
      return true;
    } on AuthException catch (e) {
      state = state.copyWith(errorMessage: e.message);
      return false;
    } catch (e) {
      state = state.copyWith(errorMessage: e.toString().replaceAll('Exception: ', ''));
      return false;
    }
  }

  Future<void> signOut() async {
    state = state.copyWith(status: AuthStatus.loading);
    await _repo.signOut();
    state = const AppAuthState(status: AuthStatus.unauthenticated);
  }
}
