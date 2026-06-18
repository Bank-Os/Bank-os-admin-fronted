class BankTransaction {
  final String id;
  final String type;
  final String status;
  final double amount;
  final String currency;
  final String accountId;
  final String description;

  const BankTransaction({
    required this.id,
    required this.type,
    required this.status,
    required this.amount,
    required this.currency,
    required this.accountId,
    required this.description,
  });

  factory BankTransaction.fromJson(Map<String, dynamic> json) {
    return BankTransaction(
      id: '${json['id'] ?? json['Id']}',
      type: '${json['type'] ?? json['Type'] ?? 'transfer'}',
      status: '${json['status'] ?? json['Status'] ?? 'completed'}',
      amount: ((json['amount'] ??
                  json['OriginalAmount'] ??
                  json['originalAmount'] ??
                  0) as num)
          .toDouble(),
      currency:
          '${json['currency'] ?? json['FromCurrency'] ?? json['fromCurrency'] ?? 'COP'}',
      accountId:
          '${json['accountId'] ?? json['SourceAccountId'] ?? json['sourceAccountId'] ?? ''}',
      description:
          '${json['description'] ?? json['Description'] ?? 'Operacion financiera'}',
    );
  }
}