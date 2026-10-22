import 'dart:async';
import 'dart:io';
import 'package:flutter/widgets.dart' show AppLifecycleListener;
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

/// The vehicles a booking form may offer: 'ride', 'food' or 'parcel'
/// (vehicles.services, web sql/040 — e.g. Bicycle is food only).
final vehiclesForServiceProvider = Provider.family<AsyncValue<List<VehicleModel>>, String>((ref, service) {
  return ref.watch(vehiclesListProvider).whenData((list) => list.where((v) => v.allows(service)).toList());
});

final haulingVehiclesProvider = FutureProvider<List<VehicleModel>>((ref) async {
  final repo = ref.watch(authRepositoryProvider);
  return repo.getHaulingVehicles();
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
    _authSub = _repo.authStateChanges.listen((data) async {
      final session = data.session;
      if (session == null) {
        _stopProfileSync();
        state = const AppAuthState(status: AuthStatus.unauthenticated);
      } else {
        await refreshProfile();
      }
    });

    // Back from the background: pick up anything changed on the web meanwhile.
    _lifecycle = AppLifecycleListener(onResume: _syncProfileQuietly);

    // Check current state immediately
    if (_repo.currentUser != null) {
      refreshProfile();
    } else {
      state = const AppAuthState(status: AuthStatus.unauthenticated);
    }
  }

  StreamSubscription<AuthState>? _authSub;
  AppLifecycleListener? _lifecycle;
  RealtimeChannel? _profileChannel;
  String? _syncedProfileId;

  /// Live profile sync with the web app: when this account's profile changes
  /// anywhere (name, phone, photo, a rider's capital on hand), realtime pushes
  /// the new row (web sql/029 adds profiles to the realtime publication).
  void _startProfileSync(String profileId) {
    if (_syncedProfileId == profileId && _profileChannel != null) return;
    _stopProfileSync();
    _syncedProfileId = profileId;
    _profileChannel = Supabase.instance.client
        .channel('profile-sync-$profileId')
        .onPostgresChanges(
          event: PostgresChangeEvent.update,
          schema: 'public',
          table: 'profiles',
          filter: PostgresChangeFilter(
            type: PostgresChangeFilterType.eq,
            column: 'id',
            value: profileId,
          ),
          callback: (payload) {
            if (!mounted || state.status != AuthStatus.authenticated) return;
            try {
              state = state.copyWith(profile: ProfileModel.fromJson(payload.newRecord));
            } catch (e, s) {
              AppLog.warn('profile sync: bad payload', e, s);
            }
          },
        )
        .subscribe();
  }

  void _stopProfileSync() {
    final channel = _profileChannel;
    _profileChannel = null;
    _syncedProfileId = null;
    if (channel != null) Supabase.instance.client.removeChannel(channel);
  }

  /// Re-reads the profile (and a rider's application, e.g. a vehicle change
  /// by the admin) without ever logging the user out on a network hiccup.
  Future<void> _syncProfileQuietly() async {
    if (state.status != AuthStatus.authenticated) return;
    try {
      final profile = await _repo.getCurrentProfile();
      if (profile == null || !mounted) return;
      final riderApp = profile.role == UserRole.rider
          ? await _repo.getRiderApplication(profile.id)
          : state.riderApplication;
      if (!mounted) return;
      state = state.copyWith(profile: profile, riderApplication: riderApp);
    } catch (e, s) {
      AppLog.warn('profile sync on resume failed', e, s);
    }
  }

  @override
  void dispose() {
    _authSub?.cancel();
    _lifecycle?.dispose();
    _stopProfileSync();
    super.dispose();
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
      _startProfileSync(profile.id);
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
    File? photo,
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

      final newUser = authResponse.user;
      if (photo != null && newUser != null && authResponse.session != null) {
        try {
          await _repo.setSignupPhoto(newUser.id, photo);
        } catch (e, s) {
          // The photo is optional — never fail the sign-up over it.
          AppLog.warn('signUpCustomer: photo upload failed', e, s);
        }
      }

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
      // The face photo is also the rider's profile picture (reviewed by the
      // admin with the rest of the application).
      if (selfiePhoto != null) {
        try {
          await _repo.setSignupPhoto(user.id, selfiePhoto);
        } catch (e, s) {
          AppLog.warn('signUpRider: profile photo upload failed', e, s);
        }
      }
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
