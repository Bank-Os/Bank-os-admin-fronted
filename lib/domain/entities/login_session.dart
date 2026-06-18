class LoginSession {
  final String token;
  final String userId;
  final String role;
  // final String tenantId;

  const LoginSession({
    required this.token,
    required this.userId,
    required this.role,
    // required this.tenantId,
  });

  factory LoginSession.fromJson(Map<String, dynamic> json) {
    return LoginSession(
      token: '${json['token'] ?? json['Token'] ?? ''}',
      userId: '${json['userId'] ?? json['UserId'] ?? ''}',
      role: '${json['role'] ?? json['UserRole'] ?? 'cliente'}',
      // tenantId: '${json['tenantId'] ?? json['TenantId'] ?? ''}',
    );
  }
}
