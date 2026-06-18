import '../entities/bank_account.dart';

abstract class AccountRepository {
  Future<List<BankAccount>> getAccounts();

  Future<void> createAccount({
    required String accountNumber,
    required String userId,
    required double initialBalance,
    required String currency,
  });

  Future<void> deactivateAccount(String accountNumber);
}