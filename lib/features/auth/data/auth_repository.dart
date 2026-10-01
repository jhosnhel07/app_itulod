import 'dart:io';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../../core/supabase/supabase_client.dart';
import '../../../core/utils/app_log.dart';
import '../../../shared/models/profile_model.dart';
import '../../../shared/models/rider_application_model.dart';
import '../../../shared/models/vehicle_model.dart';

final authRepositoryProvider = Provider<AuthRepository>((ref) {
  return AuthRepository(SupabaseConfig.client);
});

class AuthRepository {
  final SupabaseClient _supabase;

  AuthRepository(this._supabase);

  User? get currentUser => _supabase.auth.currentUser;
  Session? get currentSession => _supabase.auth.currentSession;
  Stream<AuthState> get authStateChanges => _supabase.auth.onAuthStateChange;

  String _resolveEmail(String identifier) {
    final trimmed = identifier.trim();
    if (trimmed.toLowerCase() == 'admin') {
      return 'admin@itulod.local';
    }
    return trimmed;
  }

  Future<ProfileModel?> getCurrentProfile() async {
    final user = currentUser;
    if (user == null) return null;

    final response = await _supabase
        .from('profiles')
        .select()
        .eq('id', user.id)
        .maybeSingle();

    if (response == null) return null;
    return ProfileModel.fromJson(response);
  }

  Future<ProfileModel> signIn({
    required String emailOrUsername,
    required String password,
  }) async {
    final email = _resolveEmail(emailOrUsername);

    final authResponse = await _supabase.auth.signInWithPassword(
      email: email,
      password: password,
    );

    final user = authResponse.user;
    if (user == null) {
      throw const AuthException('User could not be authenticated');
    }

    final profileResponse = await _supabase
        .from('profiles')
        .select()
        .eq('id', user.id)
        .maybeSingle();

    if (profileResponse == null) {
      throw const AuthException('No profile found. Please contact support.');
    }

    final profile = ProfileModel.fromJson(profileResponse);

    if (!profile.isActive) {
      await _supabase.auth.signOut();
      throw const AuthException('This account has been deactivated. Please contact support.');
    }

    return profile;
  }

  Future<AuthResponse> signUp({
    required String email,
    required String password,
    required String fullName,
    required UserRole role,
    String? phone,
  }) async {
    final response = await _supabase.auth.signUp(
      email: email.trim(),
      password: password,
      data: {
        'full_name': fullName.trim(),
        'role': role.toDbString(),
      },
    );

    final user = response.user;
    if (user != null && phone != null && phone.trim().isNotEmpty) {
      try {
        await _supabase.from('profiles').update({
          'phone': phone.trim(),
        }).eq('id', user.id);
      } catch (e, s) {
        // The handle_new_user trigger may not have created the profile row yet.
        AppLog.warn('signUp: phone update retrying after trigger delay', e, s);
        await Future.delayed(const Duration(milliseconds: 600));
        await _supabase.from('profiles').update({
          'phone': phone.trim(),
        }).eq('id', user.id);
      }
    }

    return response;
  }

  Future<String> uploadRiderDocument({
    required String userId,
    required File file,
    required String kind,
  }) async {
    final fileExt = file.path.split('.').last;
    final timestamp = DateTime.now().millisecondsSinceEpoch;
    final storagePath = '$userId/$kind-$timestamp.$fileExt';

    await _supabase.storage.from('rider-documents').upload(
      storagePath,
      file,
      fileOptions: const FileOptions(cacheControl: '3600', upsert: true),
    );

    final publicUrl = _supabase.storage.from('rider-documents').getPublicUrl(storagePath);
    return publicUrl;
  }

  Future<RiderApplicationModel> createRiderApplication({
    required String riderId,
    required String vehicleType,
    String? vehiclePlate,
    String? vehicleModel,
    String? licenseNumber,
    String? licenseUrl,
    String? orCrUrl,
    String? selfieUrl,
    String? vehicleUrl,
    String? nbiUrl,
  }) async {
    final payload = <String, dynamic>{
      'rider_id': riderId,
      'vehicle_type': vehicleType,
      'vehicle_plate': vehiclePlate?.trim(),
      'vehicle_model': vehicleModel?.trim(),
      'license_number': licenseNumber?.trim(),
      'license_url': licenseUrl,
      'or_cr_url': orCrUrl,
      'status': 'pending',
    };
    if (selfieUrl != null) payload['selfie_url'] = selfieUrl;
    if (vehicleUrl != null) payload['vehicle_url'] = vehicleUrl;
    if (nbiUrl != null) payload['nbi_url'] = nbiUrl;

    final response = await _supabase.from('rider_applications').insert(payload).select().single();

    return RiderApplicationModel.fromJson(response);
  }

  Future<RiderApplicationModel?> getRiderApplication(String riderId) async {
    final response = await _supabase
        .from('rider_applications')
        .select()
        .eq('rider_id', riderId)
        .order('created_at', ascending: false)
        .limit(1)
        .maybeSingle();

    if (response == null) return null;
    return RiderApplicationModel.fromJson(response);
  }

  Future<List<VehicleModel>> getAvailableVehicles() async {
    final response = await _supabase
        .from('vehicles')
        .select()
        .eq('is_available', true)
        .order('name');

    return (response as List).map((json) => VehicleModel.fromJson(json)).toList();
  }

  Future<void> resetPasswordForEmail(String emailOrUsername) async {
    final email = _resolveEmail(emailOrUsername);
    if (emailOrUsername.trim().toLowerCase() == 'admin') {
      throw const AuthException('The system admin account cannot be reset via email.');
    }
    await _supabase.auth.resetPasswordForEmail(email);
  }

  Future<bool> checkEmailExists(String email) async {
    final response = await _supabase.rpc('check_email_exists', params: {
      'lookup_email': email.trim().toLowerCase(),
    });
    return response as bool? ?? false;
  }

  Future<void> signOut() async {
    await _supabase.auth.signOut();
  }
}
