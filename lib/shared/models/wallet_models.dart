class WalletModel {
  final String userId;
  final double balance;
  final DateTime updatedAt;

  const WalletModel({
    required this.userId,
    required this.balance,
    required this.updatedAt,
  });

  factory WalletModel.fromJson(Map<String, dynamic> json) {
    return WalletModel(
      userId: json['customer_id'] as String,
      balance: (json['balance'] as num).toDouble(),
      updatedAt: DateTime.parse(json['updated_at'] as String),
    );
  }
}

class WalletTransactionModel {
  final String id;
  final String userId;
  final double amount;
  final String type; // 'topup', 'payment', 'refund'
  final String? referenceId;
  final DateTime createdAt;

  const WalletTransactionModel({
    required this.id,
    required this.userId,
    required this.amount,
    required this.type,
    this.referenceId,
    required this.createdAt,
  });

  factory WalletTransactionModel.fromJson(Map<String, dynamic> json) {
    return WalletTransactionModel(
      id: json['id'] as String,
      userId: json['customer_id'] as String,
      amount: (json['amount'] as num).toDouble(),
      type: json['type'] as String,
      referenceId: json['reference_id'] as String?,
      createdAt: DateTime.parse(json['created_at'] as String),
    );
  }
}
