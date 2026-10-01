import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../../../core/constants/app_colors.dart';
import '../../../../core/constants/app_typography.dart';
import '../../../../core/utils/formatters.dart';
import '../../../../shared/widgets/app_button.dart';
import '../providers/wallet_provider.dart';

class WalletScreen extends ConsumerWidget {
  const WalletScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final walletAsync = ref.watch(walletProvider);
    final transactionsAsync = ref.watch(walletTransactionsProvider);

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(title: const Text('My Wallet')),
      body: walletAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text('Error loading wallet: $e')),
        data: (wallet) {
          if (wallet == null) return const Center(child: Text('No wallet found.'));

          return RefreshIndicator(
            onRefresh: () async {
              ref.invalidate(walletProvider);
              ref.invalidate(walletTransactionsProvider);
            },
            child: ListView(
              padding: const EdgeInsets.all(20),
              children: [
                _buildBalanceCard(context, ref, wallet.balance),
                const SizedBox(height: 24),
                Text('Transaction History', style: AppTypography.h3),
                const SizedBox(height: 12),
                transactionsAsync.when(
                  loading: () => const Center(child: CircularProgressIndicator()),
                  error: (e, _) => Text('Error loading transactions: $e'),
                  data: (transactions) {
                    if (transactions.isEmpty) {
                      return Padding(
                        padding: const EdgeInsets.symmetric(vertical: 40),
                        child: Text(
                          'No transactions yet.',
                          style: AppTypography.captionDark,
                          textAlign: TextAlign.center,
                        ),
                      );
                    }
                    return Column(
                      children: transactions.map((t) {
                        final isAdd = t.type == 'topup' || t.type == 'refund';
                        final color = isAdd ? AppColors.success : AppColors.danger;
                        final prefix = isAdd ? '+' : '-';
                        return ListTile(
                          contentPadding: EdgeInsets.zero,
                          leading: CircleAvatar(
                            backgroundColor: color.withValues(alpha: 0.1),
                            child: Icon(
                              isAdd ? Icons.arrow_downward_rounded : Icons.arrow_upward_rounded,
                              color: color,
                            ),
                          ),
                          title: Text(t.type.toUpperCase(), style: AppTypography.bodyBold),
                          subtitle: Text(DateFormat('MMM d, yyyy h:mm a').format(t.createdAt.toLocal()), style: AppTypography.caption),
                          trailing: Text('$prefix${Formatters.currency(t.amount)}', style: AppTypography.bodyBold.copyWith(color: color)),
                        );
                      }).toList(),
                    );
                  },
                ),
              ],
            ),
          );
        },
      ),
    );
  }

  Widget _buildBalanceCard(BuildContext context, WidgetRef ref, double balance) {
    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [AppColors.primary, AppColors.primaryDark],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(20),
        boxShadow: const [
          BoxShadow(color: Color(0x33000000), blurRadius: 10, offset: Offset(0, 4)),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Available Balance', style: AppTypography.caption.copyWith(color: Colors.white70)),
          const SizedBox(height: 8),
          Text(Formatters.currency(balance), style: AppTypography.h1.copyWith(color: Colors.white)),
          const SizedBox(height: 24),
          Row(
            children: [
              Expanded(
                child: AppButton(
                  text: 'Top Up',
                  icon: Icons.add_circle_outline_rounded,
                  type: AppButtonType.secondary,
                  onPressed: () => _showTopUpDialog(context, ref),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  void _showTopUpDialog(BuildContext context, WidgetRef ref) {
    final amountController = TextEditingController();
    bool isLoading = false;

    showDialog(
      context: context,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setState) {
            return AlertDialog(
              backgroundColor: AppColors.surface,
              title: const Text('Top Up Wallet'),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Text('Enter the amount you want to top up via GCash.'),
                  const SizedBox(height: 16),
                  TextField(
                    controller: amountController,
                    keyboardType: const TextInputType.numberWithOptions(decimal: true),
                    decoration: const InputDecoration(
                      labelText: 'Amount (PHP)',
                      border: OutlineInputBorder(),
                      prefixText: '₱ ',
                    ),
                  ),
                ],
              ),
              actions: [
                TextButton(
                  onPressed: isLoading ? null : () => Navigator.pop(context),
                  child: const Text('Cancel'),
                ),
                ElevatedButton(
                  onPressed: isLoading
                      ? null
                      : () async {
                          final amount = double.tryParse(amountController.text);
                          if (amount == null || amount <= 0) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(content: Text('Please enter a valid amount')),
                            );
                            return;
                          }

                          setState(() => isLoading = true);
                          try {
                            final url = await ref.read(walletProvider.notifier).topUpWallet(amount);
                            if (url != null) {
                              final uri = Uri.parse(url);
                              if (await canLaunchUrl(uri)) {
                                await launchUrl(uri, mode: LaunchMode.externalApplication);
                                if (context.mounted) Navigator.pop(context);
                              } else {
                                throw Exception('Could not open GCash payment page');
                              }
                            }
                          } catch (e) {
                            if (context.mounted) {
                              ScaffoldMessenger.of(context).showSnackBar(
                                SnackBar(content: Text('Error: ${e.toString()}')),
                              );
                            }
                          } finally {
                            if (context.mounted) {
                              setState(() => isLoading = false);
                            }
                          }
                        },
                  child: isLoading
                      ? const SizedBox(height: 16, width: 16, child: CircularProgressIndicator(strokeWidth: 2))
                      : const Text('Proceed to GCash'),
                ),
              ],
            );
          },
        );
      },
    );
  }
}
