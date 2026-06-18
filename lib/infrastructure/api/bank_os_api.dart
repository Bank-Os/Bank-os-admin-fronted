import 'dart:async';
import 'dart:convert';
import 'package:http/http.dart' as http;
import '../../domain/entities/bank_institution.dart';
import '../../domain/entities/login_session.dart';
import '../../domain/entities/bank_account.dart';
import '../../domain/entities/bank_transaction.dart';
import '../../domain/entities/operation_result.dart';

class BankOsApi {
  String baseUrl;
  String tenantId;
  String? token;

  BankOsApi({required this.baseUrl, required this.tenantId});

  // ── URI builder ──────────────────────────────────────────────────────────

  Uri uri(String path, [Map<String, String?> query = const {}]) {
    var cleanBase = baseUrl.endsWith('/')
        ? baseUrl.substring(0, baseUrl.length - 1)
        : baseUrl;
    if (cleanBase.toLowerCase().endsWith('/api/v1')) {
      cleanBase = cleanBase.substring(0, cleanBase.length - '/api/v1'.length);
    }
    final rawPath = path.startsWith('/') ? path : '/$path';
    final cleanPath = rawPath.startsWith('/api/v1')
        ? rawPath
        : '/api/v1$rawPath';
    final params = <String, String>{};
    for (final entry in query.entries) {
      if (entry.value != null && entry.value!.isNotEmpty) {
        params[entry.key] = entry.value!;
      }
    }
    return Uri.parse(
      '$cleanBase$cleanPath',
    ).replace(queryParameters: params.isEmpty ? null : params);
  }

  // ── Headers ──────────────────────────────────────────────────────────────

  Map<String, String> headers({bool auth = false, bool mutation = false}) {
    return {
      'Content-Type': 'application/json',
      'X-Tenant-ID': tenantId,
      'X-Correlation-ID': _newId(),
      if (mutation) 'Idempotency-Key': _newId(),
      if (auth && token != null) 'Authorization': 'Bearer $token',
    };
  }

  // ── HTTP primitives ──────────────────────────────────────────────────────

  Future<Map<String, dynamic>> post(
    String path,
    Map<String, dynamic> body, {
    bool auth = false,
    bool mutation = false,
  }) async {
    final response = await _withTimeout(
      http.post(
        uri(path),
        headers: headers(auth: auth, mutation: mutation),
        body: jsonEncode(body),
      ),
    );
    return _decodeResponse(response);
  }

  Future<Map<String, dynamic>> get(
    String path, {
    Map<String, String?> query = const {},
    bool auth = true,
  }) async {
    final response = await _withTimeout(
      http.get(uri(path, query), headers: headers(auth: auth)),
    );
    return _decodeResponse(response);
  }

  Future<Map<String, dynamic>> getOptional(
    String path, {
    Map<String, String?> query = const {},
  }) async {
    try {
      return await get(path, query: query);
    } catch (_) {
      return <String, dynamic>{};
    }
  }

  Future<Map<String, dynamic>> delete(String path, {bool auth = false}) async {
    final response = await _withTimeout(
      http.delete(uri(path), headers: headers(auth: auth, mutation: true)),
    );
    return _decodeResponse(response);
  }

  // ── Tenants ──────────────────────────────────────────────────────────────

  Future<void> createTenant({
    required String id,
    required String name,
    required String currency,
    required double maxTransactionLimit,
    required double transferFee,
    required bool isFeePercentage,
  }) async {
    await post('/Tenants', {
      'id': id,
      'name': name,
      'currency': currency,
      'primaryCurrency': currency,
      'maxTransactionLimit': maxTransactionLimit,
      'transferFee': transferFee,
      'isFeePercentage': isFeePercentage,
    });
  }

  Future<List<BankInstitution>> getTenants() async {
    final data = await get('/Tenants', auth: false);
    final raw =
        data['tenants'] ??
        data['Tenants'] ??
        data['data'] ??
        data['Data'] ??
        data['items'] ??
        data['Items'] ??
        [];
    if (raw is List) {
      return raw
          .whereType<Map<String, dynamic>>()
          .map(BankInstitution.fromJson)
          .where((b) => b.tenantId.isNotEmpty)
          .toList();
    }
    if (raw is Map<String, dynamic>) {
      return raw.values
          .whereType<Map<String, dynamic>>()
          .map(BankInstitution.fromJson)
          .where((b) => b.tenantId.isNotEmpty)
          .toList();
    }
    return [];
  }

  // ── Auth ─────────────────────────────────────────────────────────────────

  Future<void> registerUser({
    required String email,
    required String password,
    required String role,
  }) async {
    await post('/Auth/register', {
      'email': email,
      'password': password,
      'role': role,
    });
  }

  Future<LoginSession> login({
    required String email,
    required String password,
  }) async {
    final data = await post('/SuperAuth/login-master', {
      'email': email,
      'password': password,
    });
    token = (data['token'] ?? data['Token']) as String?;
    if (token == null || token!.isEmpty) {
      throw Exception('El banco no retornó una sesión válida.');
    }
    return LoginSession(
      token: token!,
      userId: (data['userId'] ?? data['UserId'] ?? '') as String,
      // tenantId: (data['tenantId'] ?? data['TenantId'] ?? tenantId) as String,
      role: (data['role'] ?? data['UserRole'] ?? 'cliente') as String,
    );
  }

  // ── Accounts ─────────────────────────────────────────────────────────────

  Future<List<BankAccount>> getAccounts() async {
    final data = await get('/Accounts');
    final raw =
        (data['accounts'] ?? data['Accounts'] ?? data['data'] ?? [])
            as List<dynamic>;
    return raw
        .map((item) => BankAccount.fromJson(item as Map<String, dynamic>))
        .toList();
  }

  Future<void> createAccount({
    required String accountNumber,
    required String userId,
    required double initialBalance,
    required String currency,
  }) async {
    await post(
      '/Accounts',
      {
        'accountNumber': accountNumber,
        'userId': userId,
        'initialBalance': initialBalance,
        'currency': currency,
      },
      auth: true,
      mutation: true,
    );
  }

  Future<void> deactivateAccount(String accountNumber) async {
    await delete('/Accounts/${Uri.encodeComponent(accountNumber)}', auth: true);
  }

  // ── Operations ───────────────────────────────────────────────────────────

  Future<OperationResult> sendOperation({
    required String type,
    required String accountId,
    required String targetAccountId,
    required double amount,
    required String currency,
    required String pin,
  }) async {
    final path = switch (type) {
      'withdrawal' => '/Transactions/withdraw',
      'transfer' => '/Transactions/transfer',
      _ => '/Transactions/deposit',
    };
    final body = switch (type) {
      'transfer' => {
        'sourceAccountNumber': accountId,
        'targetAccountNumber': targetAccountId,
        'amount': amount,
      },
      _ => {'accountNumber': accountId, 'amount': amount},
    };
    final data = await post(path, body, auth: true, mutation: true);
    return OperationResult.fromJson(data);
  }

  // ── Transactions ─────────────────────────────────────────────────────────

  Future<List<BankTransaction>> getTransactions() async {
    final data = await get(
      '/Transactions/history',
      query: {'page': '1', 'pageSize': '20'},
    );
    final raw =
        (data['transactions'] ?? data['Transactions'] ?? data['data'] ?? [])
            as List<dynamic>;
    return raw
        .map((item) => BankTransaction.fromJson(item as Map<String, dynamic>))
        .toList();
  }

  // ── Internals ────────────────────────────────────────────────────────────

  Future<http.Response> _withTimeout(Future<http.Response> request) async {
    try {
      return await request.timeout(const Duration(seconds: 12));
    } on TimeoutException {
      throw Exception(
        'No se pudo conectar con el servidor. Verifica que el backend esté encendido.',
      );
    }
  }

  Map<String, dynamic> _decodeResponse(http.Response response) {
    final body = _decodeJsonBody(response.body);
    if (response.statusCode < 200 || response.statusCode >= 300) {
      final message =
          body['errorMessage'] ??
          body['Error'] ??
          body['error'] ??
          body['Mensaje'] ??
          response.reasonPhrase;
      throw Exception(message);
    }
    return body;
  }

  Map<String, dynamic> _decodeJsonBody(String rawBody) {
    if (rawBody.isEmpty) return <String, dynamic>{};
    final decoded = jsonDecode(rawBody);
    if (decoded is Map<String, dynamic>) return decoded;
    return <String, dynamic>{};
  }

  String _newId() => DateTime.now().microsecondsSinceEpoch.toString();
}
