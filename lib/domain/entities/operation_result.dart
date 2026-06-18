class OperationResult {
  final String transactionId;
  final bool success;
  final double fee;
  final double finalAmount;

  const OperationResult({
    required this.transactionId,
    required this.success,
    required this.fee,
    required this.finalAmount,
  });

  factory OperationResult.fromJson(Map<String, dynamic> json) {
    return OperationResult(
      transactionId:
          '${json['transactionId'] ?? json['TransaccionId'] ?? json['id'] ?? ''}',
      success: (json['success'] ?? json['Success'] ?? true) as bool,
      fee: ((json['fee'] ?? json['Fee'] ?? json['feeAmount'] ?? 0) as num)
          .toDouble(),
      finalAmount: ((json['finalAmount'] ??
                  json['FinalAmount'] ??
                  json['convertedAmount'] ??
                  0) as num)
          .toDouble(),
    );
  }
}