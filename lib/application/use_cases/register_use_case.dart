import '../../domain/repositories/auth_repository.dart';

class RegisterUseCase {
  final AuthRepository repository;

  RegisterUseCase(this.repository);

  Future<void> execute({
    required String email,
    required String password,
    required String role,
  }) async {
    if (email.trim().isEmpty || password.trim().isEmpty) {
      throw Exception('El correo y la contraseña son obligatorios.');
    }
    await repository.register(email: email, password: password, role: role);
  }
}