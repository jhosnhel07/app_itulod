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
      // Wallet rows are only ever created server-side (wallet-topup,
      // apply-referral-code); RLS has no client insert policy. No row yet
      // just means a ₱0 balance — same as the web dashboard.
      final wallet = await _repo.getWallet(_userId);
      state = AsyncValue.data(wallet ??
          WalletModel(userId: _userId, balance: 0, updatedAt: DateTime.now()));
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

      final data = response.data;
      if (response.status != 200 || data is! Map) {
        final error = data is Map ? data['error'] : 'Unknown error';
        throw Exception(error ?? 'Could not start GCash checkout');
      }

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
