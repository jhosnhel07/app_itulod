import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../../shared/models/saved_address_model.dart';
import '../../../auth/presentation/providers/auth_provider.dart';
import '../../data/customer_repository.dart';

final savedAddressesProvider = StateNotifierProvider<SavedAddressesNotifier, AsyncValue<List<SavedAddressModel>>>((ref) {
  final repo = ref.watch(customerRepositoryProvider);
  final auth = ref.watch(authNotifierProvider);
  final userId = auth.profile?.id;
  return SavedAddressesNotifier(repo, userId);
});

class SavedAddressesNotifier extends StateNotifier<AsyncValue<List<SavedAddressModel>>> {
  final CustomerRepository _repo;
  final String? _userId;

  SavedAddressesNotifier(this._repo, this._userId) : super(const AsyncValue.loading()) {
    if (_userId != null) {
      load();
    } else {
      state = const AsyncValue.data([]);
    }
  }

  Future<void> load() async {
    if (_userId == null) return;
    state = const AsyncValue.loading();
    try {
      final addresses = await _repo.getSavedAddresses(_userId!);
      state = AsyncValue.data(addresses);
    } catch (e, s) {
      state = AsyncValue.error(e, s);
    }
  }

  Future<SavedAddressModel?> add(String label, String address, double lat, double lng) async {
    if (_userId == null) return null;
    try {
      final newAddr = await _repo.addSavedAddress(
        userId: _userId!,
        label: label,
        address: address,
        latitude: lat,
        longitude: lng,
      );
      final current = state.value ?? [];
      state = AsyncValue.data([newAddr, ...current]);
      return newAddr;
    } catch (e) {
      return null;
    }
  }

  Future<bool> delete(String id) async {
    try {
      await _repo.deleteSavedAddress(id);
      final current = state.value ?? [];
      state = AsyncValue.data(current.where((a) => a.id != id).toList());
      return true;
    } catch (e) {
      return false;
    }
  }
}
