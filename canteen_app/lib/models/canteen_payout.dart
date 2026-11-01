class CanteenPayout {
  final String id;
  final double amount;
  final String note;
  final String createdBy;
  final DateTime createdAt;

  const CanteenPayout({
    required this.id,
    required this.amount,
    this.note = '',
    required this.createdBy,
    required this.createdAt,
  });

  Map<String, dynamic> toJson() => {
        'id': id,
        'amount': amount,
        'note': note,
        'created_by': createdBy,
        'created_at': createdAt.toIso8601String(),
      };

  factory CanteenPayout.fromJson(Map<String, dynamic> json) => CanteenPayout(
        id: json['id'],
        amount: (json['amount'] as num).toDouble(),
        note: json['note'] ?? '',
        createdBy: json['created_by'] ?? '',
        createdAt: DateTime.parse(json['created_at']),
      );
}
