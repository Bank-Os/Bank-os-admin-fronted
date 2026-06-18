import '../../domain/entities/bank_account.dart';
import '../../domain/repositories/account_repository.dart';
import '../api/bank_os_api.dart';

class AccountRepositoryImpl implements AccountRepository {
  final BankOsApi api;

  AccountRepositoryImpl(this.api);

  @override
  Future<List<BankAccount>> getAccounts() async {
    return await api.getAccounts();
  }

  @override
  Future<void> createAccount({
    required String accountNumber,
    required String userId,
    required double initialBalance,
    required String currency,
  }) async {
    await api.createAccount(
      accountNumber: accountNumber,
      userId: userId,
      initialBalance: initialBalance,
      currency: currency,
    );
  }

  @override
  Future<void> deactivateAccount(String accountNumber) async {
    await api.deactivateAccount(accountNumber);
  }
}