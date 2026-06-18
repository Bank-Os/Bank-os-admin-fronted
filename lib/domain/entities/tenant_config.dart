  class TenantConfig {
  final String id;
  final String name;
  final String primaryCurrency;
  final double maxTransactionLimit;
  final double transferFee;

  const TenantConfig({
    required this.id,
    required this.name,
    required this.primaryCurrency,
    required this.maxTransactionLimit,
    required this.transferFee,
  });

  factory TenantConfig.fromJson(Map<String, dynamic> json) {
    return TenantConfig(
      id: '${json['id'] ?? json['Id'] ?? ''}',
      name: '${json['name'] ?? json['Name'] ?? ''}',
      primaryCurrency:
          '${json['primaryCurrency'] ?? json['PrimaryCurrency'] ?? 'COP'}',
      maxTransactionLimit: ((json['maxTransactionLimit'] ??
                  json['MaxTransactionLimit'] ??
                  0) as num)
          .toDouble(),
      transferFee:
          ((json['transferFee'] ?? json['TransferFee'] ?? 0) as num)
              .toDouble(),
    );
  }
}