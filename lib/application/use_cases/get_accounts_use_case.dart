import '../../domain/entities/bank_account.dart';
import '../../domain/repositories/account_repository.dart';

class GetAccountsUseCase {
  final AccountRepository repository;

  GetAccountsUseCase(this.repository);

  Future<List<BankAccount>> execute() async {
    return await repository.getAccounts();
  }
}