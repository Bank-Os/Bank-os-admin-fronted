abstract class AdminRepository {
  Future<void> createTenant({
    required String id,
    required String name,
    required String currency,
    required double maxTransactionLimit,
    required double transferFee,
    required bool isFeePercentage,
  });
}