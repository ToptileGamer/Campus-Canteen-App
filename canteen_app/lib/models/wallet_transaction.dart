class WalletTransaction {
  final String id;
  final String userId;

  /// Positive = money in (topup / refund), negative = money out (order payment).
  final double amount;

  /// topup | order_payment | refund
  final String type;
  final String? orderId;
  final double balanceAfter;
  final String description;
  final DateTime createdAt;

  const WalletTransaction({
    required this.id,
    required this.userId,
    required this.amount,
    required this.type,
    this.orderId,
    required this.balanceAfter,
    this.description = '',
    required this.createdAt,
  });

  bool get isCredit => amount >= 0;

  String get typeLabel {
    switch (type) {
      case 'topup':
        return 'Top-up';
      case 'order_payment':
        return 'Order payment';
      case 'refund':
        return 'Refund';
      default:
        return type;
    }
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'user_id': userId,
        'amount': amount,
        'type': type,
        'order_id': orderId,
        'balance_after': balanceAfter,
        'description': description,
        'created_at': createdAt.toIso8601String(),
      };

  factory WalletTransaction.fromJson(Map<String, dynamic> json) =>
      WalletTransaction(
        id: json['id'],
        userId: json['user_id'],
        amount: (json['amount'] as num).toDouble(),
        type: json['type'],
        orderId: json['order_id'],
        balanceAfter: (json['balance_after'] as num).toDouble(),
        description: json['description'] ?? '',
        createdAt: DateTime.parse(json['created_at']),
      );
}
