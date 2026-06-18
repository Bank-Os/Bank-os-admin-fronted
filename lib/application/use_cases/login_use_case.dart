import '../../domain/entities/login_session.dart';
import '../../domain/repositories/auth_repository.dart';

class LoginUseCase {
  final AuthRepository repository;

  LoginUseCase(this.repository);

  Future<LoginSession> execute({
    required String email,
    required String password,
  }) async {
    if (email.trim().isEmpty || password.trim().isEmpty) {
      throw Exception('El correo y la contraseña son obligatorios.');
    }
    return await repository.login(email: email, password: password);
  }
}