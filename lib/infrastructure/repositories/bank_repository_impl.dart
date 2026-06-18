import '../../domain/entities/bank_institution.dart';
import '../../domain/repositories/bank_repository.dart';
import '../api/bank_os_api.dart';

class BankRepositoryImpl implements BankRepository {
  final BankOsApi api;

  BankRepositoryImpl(this.api);

  @override
  Future<List<BankInstitution>> getBanks() async {
    return await api.getTenants();
  }
}