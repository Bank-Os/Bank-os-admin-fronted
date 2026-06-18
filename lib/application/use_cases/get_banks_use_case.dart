import '../../domain/entities/bank_institution.dart';
import '../../domain/repositories/bank_repository.dart';

class GetBanksUseCase {
  final BankRepository repository;

  GetBanksUseCase(this.repository);

  Future<List<BankInstitution>> execute() async {
    return await repository.getBanks();
  }
}