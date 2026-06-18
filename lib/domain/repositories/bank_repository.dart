import '../entities/bank_institution.dart';

abstract class BankRepository {
  Future<List<BankInstitution>> getBanks();
}