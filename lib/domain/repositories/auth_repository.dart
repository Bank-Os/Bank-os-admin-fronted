import '../entities/login_session.dart';

abstract class AuthRepository {
  Future<void> register({
    required String email,
    required String password,
    required String role,
  });

  Future<LoginSession> login({
    required String email,
    required String password,
  });
} 