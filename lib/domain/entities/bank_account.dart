class BankAccount {
  final String id;
  final String number;
  final String currency;
  final double balance;
  final bool isActive;

  const BankAccount({
    required this.id,
    required this.number,
    required this.currency,
    required this.balance,
    required this.isActive,
  });

  factory BankAccount.fromJson(Map<String, dynamic> json) {
    return BankAccount(
      id: '${json['id'] ?? json['Id']}',
      number:
          '${json['number'] ?? json['Number'] ?? json['id'] ?? json['Id']}',
      currency: '${json['currency'] ?? json['Currency'] ?? 'COP'}',
      balance:
          ((json['balance'] ?? json['Balance'] ?? 0) as num).toDouble(),
      isActive: (json['isActive'] ?? json['IsActive'] ?? true) as bool,
    );
  }
}