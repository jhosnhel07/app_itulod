import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../../shared/models/wallet_models.dart';
import '../../../auth/presentation/providers/auth_provider.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../data/customer_repository.dart';

final walletProvider = StateNotifierProvider<WalletNotifier, AsyncValue<WalletModel?>>((ref) {
  final repo = ref.watch(customerRepositoryProvider);
  final auth = ref.watch(authNotifierProvider);
  final userId = auth.profile?.id;
  return WalletNotifier(repo, userId);
});

class WalletNotifier extends StateNotifier<AsyncValue<WalletModel?>> {
  final CustomerRepository _repo;
  final String? _userId;

  WalletNotifier(this._repo, this._userId) : super(const AsyncValue.loading()) {
    if (_userId != null) {
      load();
    } else {
      state = const AsyncValue.data(null);
    }
  }

  Future<void> load() async {
    if (_userId == null) return;
    state = const AsyncValue.loading();
    try {
      var wallet = await _repo.getWallet(_userId!);
      if (wallet == null) {
        wallet = await _repo.createWallet(_userId!);
      }
      state = AsyncValue.data(wallet);
    } catch (e, s) {
      state = AsyncValue.error(e, s);
    }
  }

  Future<String?> topUpWallet(double amount) async {
    if (_userId == null) return null;
    try {
      final response = await Supabase.instance.client.functions.invoke(
        'wallet-topup',
        body: {'amount': amount},
      );

      final data = response.data as Map<String, dynamic>;
      if (data.containsKey('checkout_url')) {
        return data['checkout_url'] as String;
      }
      if (data.containsKey('error')) {
        throw Exception(data['error']);
      }
      return null;
    } catch (e) {
      rethrow;
    }
  }
}

final walletTransactionsProvider = FutureProvider<List<WalletTransactionModel>>((ref) async {
  final auth = ref.watch(authNotifierProvider);
  final userId = auth.profile?.id;
  if (userId == null) return [];
  
  final repo = ref.watch(customerRepositoryProvider);
  return repo.getWalletTransactions(userId);
});
