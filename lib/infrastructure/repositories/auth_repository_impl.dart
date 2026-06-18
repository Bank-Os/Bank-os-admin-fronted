import '../../domain/entities/login_session.dart';
import '../../domain/repositories/auth_repository.dart';
import '../api/bank_os_api.dart';

class AuthRepositoryImpl implements AuthRepository {
  final BankOsApi api;

  AuthRepositoryImpl(this.api);

  @override
  Future<void> register({
    required String email,
    required String password,
    required String role,
  }) async {
    await api.registerUser(email: email, password: password, role: role);
  }

  @override
  Future<LoginSession> login({
    required String email,
    required String password,
  }) async {
    return await api.login(email: email, password: password);
  }
}