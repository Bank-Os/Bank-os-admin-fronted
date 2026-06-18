import '../../domain/repositories/admin_repository.dart';

class CreateTenantUseCase {
  final AdminRepository repository;

  CreateTenantUseCase(this.repository);

  Future<void> execute({
    required String id,
    required String name,
    required String currency,
    required double maxTransactionLimit,
    required double transferFee,
    required bool isFeePercentage,
  }) async {
    if (id.trim().isEmpty || name.trim().isEmpty) {
      throw Exception('El ID y el nombre del tenant son obligatorios.');
    }
    if (maxTransactionLimit <= 0) {
      throw Exception('El límite de transacción debe ser mayor a cero.');
    }
    await repository.createTenant(
      id: id,
      name: name,
      currency: currency,
      maxTransactionLimit: maxTransactionLimit,
      transferFee: transferFee,
      isFeePercentage: isFeePercentage,
    );
  }
}