import '../../domain/repositories/admin_repository.dart';
import '../api/bank_os_api.dart';

class AdminRepositoryImpl implements AdminRepository {
  final BankOsApi api;

  AdminRepositoryImpl(this.api);

  @override
  Future<void> createTenant({
    required String id,
    required String name,
    required String currency,
    required double maxTransactionLimit,
    required double transferFee,
    required bool isFeePercentage,
  }) async {
    await api.createTenant(
      id: id,
      name: name,
      currency: currency,
      maxTransactionLimit: maxTransactionLimit,
      transferFee: transferFee,
      isFeePercentage: isFeePercentage,
    );
  }
}