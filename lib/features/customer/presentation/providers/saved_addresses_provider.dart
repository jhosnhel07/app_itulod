import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../../core/supabase/supabase_client.dart';
import '../../../../core/utils/app_log.dart';
import '../../../../shared/models/saved_address_model.dart';
import '../../../auth/presentation/providers/auth_provider.dart';
import '../../data/customer_repository.dart';

final savedAddressesProvider =
    StateNotifierProvider<SavedAddressesNotifier, AsyncValue<List<SavedAddressModel>>>((ref) {
  if (!SupabaseConfig.isInitialized) {
    return SavedAddressesNotifier(null, null);
  }
  final repo = ref.watch(customerRepositoryProvider);
  final auth = ref.watch(authNotifierProvider);
  final userId = auth.profile?.id ?? SupabaseConfig.client.auth.currentUser?.id;
  return SavedAddressesNotifier(repo, userId);
});

class SavedAddressesNotifier extends StateNotifier<AsyncValue<List<SavedAddressModel>>> {
  final CustomerRepository? _repo;
  final String? _userId;

  SavedAddressesNotifier(this._repo, this._userId) : super(const AsyncValue.loading()) {
    final userId = _userId;
    if (_repo != null && userId != null && userId.isNotEmpty) {
      load();
    } else {
      state = const AsyncValue.data([]);
    }
  }

  Future<void> load() async {
    final repo = _repo;
    final effectiveUserId = _userId ??
        (SupabaseConfig.isInitialized ? SupabaseConfig.client.auth.currentUser?.id : null);
    if (repo == null || effectiveUserId == null || effectiveUserId.isEmpty) {
      state = const AsyncValue.data([]);
      return;
    }
    state = const AsyncValue.loading();
    try {
      final addresses = await repo.getSavedAddresses(effectiveUserId);
      state = AsyncValue.data(addresses);
    } catch (e, s) {
      AppLog.warn('Failed to load saved addresses', e, s);
      state = AsyncValue.error(e, s);
    }
  }

  Future<SavedAddressModel?> add(String label, String address, double lat, double lng) async {
    final repo = _repo;
    final effectiveUserId = _userId ??
        (SupabaseConfig.isInitialized ? SupabaseConfig.client.auth.currentUser?.id : null);
    if (repo == null || effectiveUserId == null || effectiveUserId.isEmpty) {
      AppLog.warn('Cannot add saved address', 'User not authenticated');
      throw Exception('Please sign in to save an address');
    }
    try {
      final newAddr = await repo.addSavedAddress(
        userId: effectiveUserId,
        label: label,
        address: address,
        latitude: lat,
        longitude: lng,
      );
      final current = state.value ?? [];
      state = AsyncValue.data([newAddr, ...current.where((a) => a.id != newAddr.id)]);
      return newAddr;
    } catch (e, s) {
      AppLog.warn('Failed to add saved address', e, s);
      rethrow;
    }
  }

  Future<bool> delete(String id) async {
    final repo = _repo;
    if (repo == null) return false;
    try {
      await repo.deleteSavedAddress(id);
      final current = state.value ?? [];
      state = AsyncValue.data(current.where((a) => a.id != id).toList());
      return true;
    } catch (e, s) {
      AppLog.warn('Failed to delete saved address', e, s);
      rethrow;
    }
  }
}
