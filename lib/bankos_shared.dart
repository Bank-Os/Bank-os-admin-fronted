import 'dart:async';
import 'dart:convert';
import 'dart:math';
import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

// ── DDD layers ───────────────────────────────────────────────────────────
import 'infrastructure/api/bank_os_api.dart' as infra;
import 'infrastructure/repositories/auth_repository_impl.dart';
import 'infrastructure/repositories/account_repository_impl.dart';
import 'infrastructure/repositories/bank_repository_impl.dart';
import 'infrastructure/repositories/admin_repository_impl.dart';
import 'application/use_cases/login_use_case.dart';
import 'application/use_cases/register_use_case.dart';
import 'application/use_cases/get_banks_use_case.dart';
import 'application/use_cases/get_accounts_use_case.dart';
import 'application/use_cases/create_tenant_use_case.dart';

void main() {
  runApp(const BankOsApp());
}

String defaultApiBaseUrl() {
  const configuredUrl = String.fromEnvironment('BANKOS_API_BASE_URL');
  if (configuredUrl.isNotEmpty) return configuredUrl;
  return 'https://bankos.bytecore.tech';
}

const fallbackBank = BankInstitution(
  tenantId: 'bancolombia',
  name: 'Bancolombia',
  shortName: 'Bancolombia',
  segment: 'Institucion bancaria',
  tagline: 'Tenant seleccionado desde BankOS.',
  primaryCurrency: 'COP',
  maxTransactionLimit: 0,
  transferFee: 0,
  isFeePercentage: false,
  createdAt: '',
  primaryColor: Color(0xff102c69),
  accentColor: Color(0xffffc928),
  icon: Icons.account_balance,
);

BankInstitution bankByTenantId(
  String tenantId, [
  List<BankInstitution> banks = const [],
]) {
  return banks.firstWhere(
    (bank) => bank.tenantId.toLowerCase() == tenantId.toLowerCase(),
    orElse: () => BankInstitution(
      tenantId: tenantId,
      name: tenantId,
      shortName: tenantId,
      segment: 'Institucion conectada',
      tagline: 'Sesion aislada por tenant en BankOS.',
      primaryCurrency: 'COP',
      maxTransactionLimit: 0,
      transferFee: 0,
      isFeePercentage: false,
      createdAt: '',
      primaryColor: const Color(0xff102c69),
      accentColor: const Color(0xffffc928),
      icon: Icons.account_balance,
    ),
  );
}

class BankInstitution {
  const BankInstitution({
    required this.tenantId,
    required this.name,
    required this.shortName,
    required this.segment,
    required this.tagline,
    required this.primaryCurrency,
    required this.maxTransactionLimit,
    required this.transferFee,
    required this.isFeePercentage,
    required this.createdAt,
    required this.primaryColor,
    required this.accentColor,
    required this.icon,
  });

  factory BankInstitution.fromJson(Map<String, dynamic> json) {
    final tenantId =
        '${json['id'] ?? json['Id'] ?? json['tenantId'] ?? json['TenantId'] ?? ''}'
            .trim();
    final name =
        '${json['name'] ?? json['Name'] ?? json['institutionName'] ?? tenantId}'
            .trim();
    final currency =
        '${json['primaryCurrency'] ?? json['PrimaryCurrency'] ?? json['currency'] ?? json['Currency'] ?? ''}'
            .trim();
    final maxLimit = decimalFromDynamic(
      json['maxTransactionLimit'] ?? json['MaxTransactionLimit'],
    );
    final transferFee = decimalFromDynamic(
      json['transferFee'] ?? json['TransferFee'],
    );
    final feePercentage =
        (json['isFeePercentage'] ?? json['IsFeePercentage'] ?? false) == true;
    final createdAt = '${json['createdAt'] ?? json['CreatedAt'] ?? ''}'.trim();
    return BankInstitution(
      tenantId: tenantId,
      name: name.isEmpty ? tenantId : name,
      shortName: _shortBankName(name.isEmpty ? tenantId : name),
      segment: currency.isEmpty ? 'Institucion bancaria' : 'Moneda $currency',
      tagline: 'Tenant activo en BankOS.',
      primaryCurrency: currency.isEmpty ? 'COP' : currency,
      maxTransactionLimit: maxLimit,
      transferFee: transferFee,
      isFeePercentage: feePercentage,
      createdAt: createdAt,
      primaryColor: const Color(0xff102c69),
      accentColor: const Color(0xffffc928),
      icon: Icons.account_balance,
    );
  }

  final String tenantId;
  final String name;
  final String shortName;
  final String segment;
  final String tagline;
  final String primaryCurrency;
  final double maxTransactionLimit;
  final double transferFee;
  final bool isFeePercentage;
  final String createdAt;
  final Color primaryColor;
  final Color accentColor;
  final IconData icon;
}

String _shortBankName(String value) {
  final clean = value.trim();
  if (clean.length <= 16) return clean;
  return clean.split(RegExp(r'\s+')).first;
}

class BankOsApp extends StatelessWidget {
  const BankOsApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'BankOS Mundial',
      theme: ThemeData(
        useMaterial3: true,
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xff12306f),
          primary: const Color(0xff112d6a),
          secondary: const Color(0xffffc928),
          surface: Colors.white,
        ),
        fontFamily: 'Arial',
      ),
      home: const BankOsHomePage(),
    );
  }
}

class BankOsHomePage extends StatefulWidget {
  const BankOsHomePage({super.key});

  @override
  State<BankOsHomePage> createState() => _BankOsHomePageState();
}

class _BankOsHomePageState extends State<BankOsHomePage> {
  final baseUrlController = TextEditingController(text: defaultApiBaseUrl());
  final api = BankOsApi();

  // ── DDD use cases ───────────────────────────────────────────────────────
  late final LoginUseCase loginUseCase;
  late final RegisterUseCase registerUseCase;
  late final GetBanksUseCase getBanksUseCase;
  late final GetAccountsUseCase getAccountsUseCase;

  LoginSession? session;
  BankInstitution? selectedBank;
  List<BankInstitution> banks = [];
  List<BankAccount> accounts = [];
  List<BankTransaction> transactions = [];
  String feedback = 'Listo para conectar con BankOS.';
  String? banksError;
  bool busy = false;
  bool banksLoading = true;

  @override
  void initState() {
    // ── DDD wiring ─────────────────────────────────────────────────────────
    final infraApi = infra.BankOsApi(
      baseUrl: defaultApiBaseUrl(),
      tenantId: fallbackBank.tenantId,
    );
    loginUseCase = LoginUseCase(AuthRepositoryImpl(infraApi));
    registerUseCase = RegisterUseCase(AuthRepositoryImpl(infraApi));
    getBanksUseCase = GetBanksUseCase(BankRepositoryImpl(infraApi));
    getAccountsUseCase = GetAccountsUseCase(AccountRepositoryImpl(infraApi));

    super.initState();
    unawaited(_initializeApp());
  }

  Future<void> _initializeApp() async {
    await loadBanks();
    await _tryRestoreSession();
  }

  Future<void> _tryRestoreSession() async {
    final prefs = await SharedPreferences.getInstance();
    final token = prefs.getString('session_token');
    final userId = prefs.getString('session_userId');
    final tenantId = prefs.getString('session_tenantId');
    final role = prefs.getString('session_role');
    if (token == null || userId == null || tenantId == null || role == null) return;
    if (!mounted) return;
    onLogin(LoginSession(token: token, userId: userId, tenantId: tenantId, role: role));
  }

  @override
  void dispose() {
    baseUrlController.dispose();
    super.dispose();
  }

  void configureApi() {
    api.baseUrl = baseUrlController.text.trim();
    final bank = selectedBank;
    if (bank != null) api.tenantId = bank.tenantId;
  }

  Future<void> loadBanks() async {
    setState(() {
      banksLoading = true;
      banksError = null;
    });

    try {
      api.baseUrl = baseUrlController.text.trim();
      final loadedBanks = await api.getTenants();
      if (!mounted) return;
      setState(() {
        banks = loadedBanks;
        selectedBank = loadedBanks.isEmpty ? null : loadedBanks.first;
        if (selectedBank != null) api.tenantId = selectedBank!.tenantId;
        banksLoading = false;
        feedback = loadedBanks.isEmpty
            ? 'No hay bancos publicados en BankOS.'
            : 'Bancos cargados desde BankOS.';
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        banks = [];
        selectedBank = null;
        banksLoading = false;
        banksError = error.toString().replaceFirst('Exception: ', '');
        feedback = 'No se pudo cargar la lista de bancos.';
      });
    }
  }

  Future<void> runAction(Future<void> Function() action) async {
    configureApi();
    setState(() {
      busy = true;
      feedback = 'Procesando jugada...';
    });

    try {
      await action();
    } catch (error) {
      final message = error.toString().replaceFirst('Exception: ', '');
      setState(() => feedback = message);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(message), behavior: SnackBarBehavior.floating),
        );
      }
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Future<void> loadDashboard() async {
    if (session == null) return;
    api.token = session!.token;
    final loadedAccounts = await api.getAccounts();
    final loadedTransactions = await api.getTransactions();
    setState(() {
      accounts = loadedAccounts;
      transactions = loadedTransactions;
      feedback =
          'Datos actualizados desde ${selectedBank?.shortName ?? session!.tenantId}.';
    });
  }

  void onLogin(LoginSession value) {
    setState(() {
      session = value;
      selectedBank = bankByTenantId(value.tenantId, banks);
      api.tenantId = value.tenantId;
      feedback = 'Sesion iniciada en ${selectedBank!.shortName}.';
    });
    SharedPreferences.getInstance().then((prefs) {
      prefs.setString('session_token', value.token);
      prefs.setString('session_userId', value.userId);
      prefs.setString('session_tenantId', value.tenantId);
      prefs.setString('session_role', value.role);
    });
    loadDashboard();
  }

  void onLogout() {
    setState(() {
      session = null;
      accounts = [];
      transactions = [];
      api.token = null;
      feedback = 'Sesion cerrada.';
    });
    SharedPreferences.getInstance().then((prefs) {
      prefs.remove('session_token');
      prefs.remove('session_userId');
      prefs.remove('session_tenantId');
      prefs.remove('session_role');
    });
  }

  void selectBank(BankInstitution bank) {
    if (session != null) return;
    setState(() {
      selectedBank = bank;
      api.tenantId = bank.tenantId;
      feedback = '${bank.shortName} seleccionado.';
    });
  }

  @override
  Widget build(BuildContext context) {
    final isPhone = MediaQuery.sizeOf(context).width < 520;
    return Scaffold(
      body: Stack(
        fit: StackFit.expand,
        children: [
          const MundialImageBackdrop(),
          SafeArea(
            child: SingleChildScrollView(
              padding: EdgeInsets.symmetric(
                horizontal: isPhone ? 12 : 16,
                vertical: isPhone ? 10 : 18,
              ),
              child: Center(
                child: ConstrainedBox(
                  constraints: BoxConstraints(
                    maxWidth: session == null ? 760 : 1180,
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      const _HeroHeader(),
                      SizedBox(height: isPhone ? 10 : 16),
                      AnimatedSwitcher(
                        duration: const Duration(milliseconds: 240),
                        child: session == null
                            ? AuthArena(
                                key: const ValueKey('auth'),
                                api: api,
                                banks: banks,
                                banksLoading: banksLoading,
                                banksError: banksError,
                                selectedBank: selectedBank,
                                onBankChanged: selectBank,
                                onReloadBanks: loadBanks,
                                onLogin: onLogin,
                                runAction: runAction,
                              )
                            : DashboardArena(
                                key: const ValueKey('dashboard'),
                                api: api,
                                selectedBank:
                                    selectedBank ??
                                    bankByTenantId(session!.tenantId, banks),
                                session: session!,
                                accounts: accounts,
                                transactions: transactions,
                                runAction: runAction,
                                reload: loadDashboard,
                                onLogout: onLogout,
                              ),
                      ),
                      if (session == null && !isPhone) const _MedalStrip(),
                    ],
                  ),
                ),
              ),
            ),
          ),
          if (busy && session == null) const SoccerLoginOverlay(),
        ],
      ),
    );
  }
}

class _HeroHeader extends StatelessWidget {
  const _HeroHeader();

  @override
  Widget build(BuildContext context) {
    final width = MediaQuery.sizeOf(context).width;
    final compact = width < 520;
    final titleSize = compact ? 38.0 : 68.0;
    final sloganSize = compact ? 16.0 : 28.0;

    return Column(
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              width: compact ? 54 : 90,
              height: compact ? 54 : 90,
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(compact ? 16 : 22),
                boxShadow: const [
                  BoxShadow(
                    color: Color(0x88000000),
                    blurRadius: 24,
                    offset: Offset(0, 12),
                  ),
                ],
              ),
              child: Icon(
                Icons.account_balance,
                color: const Color(0xff102c69),
                size: compact ? 34 : 54,
              ),
            ),
            SizedBox(width: compact ? 10 : 16),
            Text(
              'BankOS',
              style: TextStyle(
                color: Colors.white,
                fontSize: titleSize,
                fontWeight: FontWeight.w900,
                height: 0.95,
                shadows: const [
                  Shadow(
                    color: Color(0x99000000),
                    blurRadius: 16,
                    offset: Offset(0, 6),
                  ),
                ],
              ),
            ),
          ],
        ),
        const SizedBox(height: 10),
        Text(
          'Unete al campeon de la banca en la nube!',
          textAlign: TextAlign.center,
          style: TextStyle(
            color: const Color(0xffffd84d),
            fontSize: sloganSize,
            fontWeight: FontWeight.w900,
            height: 1.05,
            shadows: const [
              Shadow(
                color: Color(0xaa000000),
                blurRadius: 10,
                offset: Offset(0, 4),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class MundialImageBackdrop extends StatelessWidget {
  const MundialImageBackdrop({super.key});

  @override
  Widget build(BuildContext context) {
    return Stack(
      fit: StackFit.expand,
      children: [
        Image.asset(
          'assets/images/worldcup_bankos_background.png',
          fit: BoxFit.cover,
          alignment: Alignment.topCenter,
        ),
        DecoratedBox(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [
                const Color(0xff061735).withValues(alpha: .12),
                Colors.white.withValues(alpha: .02),
                const Color(0xff061735).withValues(alpha: .16),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

class BankOsAdminPage extends StatefulWidget {
  const BankOsAdminPage({super.key});

  @override
  State<BankOsAdminPage> createState() => _BankOsAdminPageState();
}

class _BankOsAdminPageState extends State<BankOsAdminPage> {
  final api = BankOsApi();

  // ── DDD use cases ───────────────────────────────────────────────────────
  late final LoginUseCase loginUseCase;
  late final GetBanksUseCase getBanksUseCase;
  late final CreateTenantUseCase createTenantUseCase;

  final searchController = TextEditingController();
  final tenantIdController = TextEditingController();
  final tenantNameController = TextEditingController();
  final currencyController = TextEditingController(text: 'COP');
  final limitController = TextEditingController(text: '10000000');
  final feeController = TextEditingController(text: '0.00');
  final adminEmailController = TextEditingController();
  final adminPasswordController = TextEditingController();

  List<BankInstitution> tenants = [];
  BankInstitution? selectedTenant;
  LoginSession? adminSession;
  String? error;
  String notice = 'Panel listo para administrar BankOS.';
  bool loading = false;
  bool creating = false;
  bool signingIn = false;
  String? _deletingTenantId;

  @override
  void initState() {
    // ── DDD wiring ─────────────────────────────────────────────────────────
    final infraApi = infra.BankOsApi(
      baseUrl: defaultApiBaseUrl(),
      tenantId: fallbackBank.tenantId,
    );
    loginUseCase = LoginUseCase(AuthRepositoryImpl(infraApi));
    getBanksUseCase = GetBanksUseCase(BankRepositoryImpl(infraApi));
    createTenantUseCase = CreateTenantUseCase(AdminRepositoryImpl(infraApi));

    super.initState();
    unawaited(_tryRestoreAdminSession());
  }

  Future<void> _tryRestoreAdminSession() async {
    final prefs = await SharedPreferences.getInstance();
    final token = prefs.getString('admin_session_token');
    final userId = prefs.getString('admin_session_userId');
    final tenantId = prefs.getString('admin_session_tenantId');
    final role = prefs.getString('admin_session_role');
    if (token == null || userId == null || tenantId == null || role == null) return;
    if (!mounted) return;
    setState(() {
      adminSession = LoginSession(token: token, userId: userId, tenantId: tenantId, role: role);
      api.token = token;
    });
    await loadTenants();
  }

  @override
  void dispose() {
    searchController.dispose();
    tenantIdController.dispose();
    tenantNameController.dispose();
    currencyController.dispose();
    limitController.dispose();
    feeController.dispose();
    adminEmailController.dispose();
    adminPasswordController.dispose();
    super.dispose();
  }

  bool get isAdminAuthenticated {
    final role = adminSession?.role.toLowerCase() ?? '';
    return adminSession?.token.isNotEmpty == true &&
        (role.contains('admin') ||
            role.contains('super') ||
            role.contains('master'));
  }

  List<BankInstitution> get filteredTenants {
    final query = searchController.text.trim().toLowerCase();
    if (query.isEmpty) return tenants;
    return tenants.where((tenant) {
      return tenant.name.toLowerCase().contains(query) ||
          tenant.tenantId.toLowerCase().contains(query) ||
          tenant.primaryCurrency.toLowerCase().contains(query);
    }).toList();
  }

  Future<void> loadTenants() async {
    if (!isAdminAuthenticated) {
      setState(() {
        loading = false;
        tenants = [];
        selectedTenant = null;
      });
      return;
    }

    setState(() {
      loading = true;
      error = null;
    });

    try {
      final loaded = await api.getTenants();
      if (!mounted) return;
      setState(() {
        tenants = loaded;
        if (loaded.isNotEmpty) {
          selectedTenant = selectedTenant == null
              ? loaded.first
              : loaded.firstWhere(
                  (tenant) => tenant.tenantId == selectedTenant!.tenantId,
                  orElse: () => loaded.first,
                );
        }
        loading = false;
        notice = loaded.isEmpty
            ? 'No hay tenants publicados todavia.'
            : 'Tenants actualizados desde BankOS.';
      });
    } catch (exception) {
      if (!mounted) return;
      setState(() {
        loading = false;
        error = exception.toString().replaceFirst('Exception: ', '');
      });
    }
  }

  void selectTenant(BankInstitution tenant) {
    setState(() {
      selectedTenant = tenant;
      api.tenantId = tenant.tenantId;
      notice = 'Tenant ${tenant.shortName} seleccionado.';
    });
  }

  Future<void> signInAdmin() async {
    final email = adminEmailController.text.trim();
    if (email.isEmpty || adminPasswordController.text.isEmpty) {
      setState(() => notice = 'Ingresa correo y contrasena.');
      return;
    }

    setState(() {
      signingIn = true;
      error = null;
      notice = 'Validando administrador...';
    });

    try {
      api.tenantId = fallbackBank.tenantId;
      final session = await api.loginMaster(
        email: email,
        password: adminPasswordController.text,
      );
      final role = session.role.toLowerCase();
      if (!role.contains('admin') &&
          !role.contains('super') &&
          !role.contains('master')) {
        throw Exception('El usuario no tiene permisos de administracion.');
      }
      if (!mounted) return;
      setState(() {
        adminSession = session;
        signingIn = false;
        notice = 'Sesion maestra iniciada. Sincronizando tenants...';
      });
      SharedPreferences.getInstance().then((prefs) {
        prefs.setString('admin_session_token', session.token);
        prefs.setString('admin_session_userId', session.userId);
        prefs.setString('admin_session_tenantId', session.tenantId);
        prefs.setString('admin_session_role', session.role);
      });
      await loadTenants();
    } catch (exception) {
      if (!mounted) return;
      setState(() {
        signingIn = false;
        adminSession = null;
        api.token = null;
        error = exception.toString().replaceFirst('Exception: ', '');
        notice = 'No se pudo iniciar sesion admin.';
      });
    }
  }

  void signOutAdmin() {
    setState(() {
      adminSession = null;
      api.token = null;
      notice = 'Sesion admin cerrada.';
    });
    SharedPreferences.getInstance().then((prefs) {
      prefs.remove('admin_session_token');
      prefs.remove('admin_session_userId');
      prefs.remove('admin_session_tenantId');
      prefs.remove('admin_session_role');
    });
  }

  Future<void> deleteTenant(BankInstitution tenant) async {
    if (!isAdminAuthenticated) return;

    setState(() {
      _deletingTenantId = tenant.tenantId;
      error = null;
      notice = 'Eliminando tenant ${tenant.shortName}...';
    });

    try {
      await api.deleteTenant(tenantId: tenant.tenantId);
      if (!mounted) return;
      setState(() {
        _deletingTenantId = null;
        if (selectedTenant?.tenantId == tenant.tenantId) selectedTenant = null;
        notice = 'Tenant ${tenant.shortName} eliminado.';
      });
      await loadTenants();
    } catch (exception) {
      if (!mounted) return;
      setState(() {
        _deletingTenantId = null;
        error = exception.toString().replaceFirst('Exception: ', '');
        notice = 'No se pudo eliminar el tenant.';
      });
    }
  }

  Future<void> createTenant() async {
    if (!isAdminAuthenticated) {
      setState(() => notice = 'Inicia sesion como administrador primero.');
      return;
    }

    final id = tenantIdController.text.trim();
    final name = tenantNameController.text.trim();
    final currency = currencyController.text.trim().toUpperCase();
    if (id.isEmpty || name.isEmpty || currency.isEmpty) {
      setState(() => notice = 'Completa tenant, nombre y moneda.');
      return;
    }

    setState(() {
      creating = true;
      error = null;
      notice = 'Creando tenant...';
    });

    try {
      await api.createTenant(
        id: id,
        name: name,
        currency: currency,
        maxTransactionLimit: decimalValue(limitController.text),
        transferFee: decimalValue(feeController.text),
        isFeePercentage: false,
      );
      tenantIdController.clear();
      tenantNameController.clear();
      if (!mounted) return;
      setState(() {
        notice = '$name creado correctamente.';
        creating = false;
      });
      await loadTenants();
    } catch (exception) {
      if (!mounted) return;
      setState(() {
        creating = false;
        error = exception.toString().replaceFirst('Exception: ', '');
        notice = 'No se pudo crear el tenant.';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    if (!isAdminAuthenticated) {
      return Scaffold(
        backgroundColor: const Color(0xffeef3f8),
        body: SafeArea(
          child: AdminAccessGate(
            tenants: tenants,
            tenantsLoading: loading,
            error: error,
            notice: notice,
            signingIn: signingIn,
            emailController: adminEmailController,
            passwordController: adminPasswordController,
            onSignIn: signInAdmin,
            onReloadTenants: loadTenants,
          ),
        ),
      );
    }

    return Scaffold(
      backgroundColor: const Color(0xfff4f7fb),
      body: SafeArea(
        child: LayoutBuilder(
          builder: (context, constraints) {
            final wide = constraints.maxWidth >= 1080;
            return SingleChildScrollView(
              padding: EdgeInsets.all(wide ? 24 : 16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  AdminHeader(
                    loading: loading,
                    notice: notice,
                    session: adminSession,
                    onRefresh: loadTenants,
                    onLogout: signOutAdmin,
                  ),
                  const SizedBox(height: 18),
                  if (error != null) ...[
                    AdminAlert(message: error!, onRetry: loadTenants),
                    const SizedBox(height: 18),
                  ],
                  if (wide)
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        SizedBox(
                          width: 410,
                          child: TenantDirectoryPanel(
                            loading: loading,
                            searchController: searchController,
                            tenants: filteredTenants,
                            selectedTenant: selectedTenant,
                            onSearchChanged: (_) => setState(() {}),
                            onTenantSelected: selectTenant,
                            onDeleteTenant: deleteTenant,
                            deletingTenantId: _deletingTenantId,
                          ),
                        ),
                        const SizedBox(width: 18),
                        Expanded(
                          child: Column(
                            children: [
                              AdminTenantDetail(tenant: selectedTenant),
                              const SizedBox(height: 18),
                              TenantCreationPanel(
                                enabled: isAdminAuthenticated,
                                creating: creating,
                                tenantIdController: tenantIdController,
                                tenantNameController: tenantNameController,
                                currencyController: currencyController,
                                limitController: limitController,
                                feeController: feeController,
                                onCreate: createTenant,
                              ),
                            ],
                          ),
                        ),
                      ],
                    )
                  else
                    Column(
                      children: [
                        TenantDirectoryPanel(
                          loading: loading,
                          searchController: searchController,
                          tenants: filteredTenants,
                          selectedTenant: selectedTenant,
                          onSearchChanged: (_) => setState(() {}),
                          onTenantSelected: selectTenant,
                          onDeleteTenant: deleteTenant,
                          deletingTenantId: _deletingTenantId,
                        ),
                        const SizedBox(height: 18),
                        AdminTenantDetail(tenant: selectedTenant),
                        const SizedBox(height: 18),
                        TenantCreationPanel(
                          enabled: isAdminAuthenticated,
                          creating: creating,
                          tenantIdController: tenantIdController,
                          tenantNameController: tenantNameController,
                          currencyController: currencyController,
                          limitController: limitController,
                          feeController: feeController,
                          onCreate: createTenant,
                        ),
                      ],
                    ),
                ],
              ),
            );
          },
        ),
      ),
    );
  }
}

class AdminHeader extends StatelessWidget {
  const AdminHeader({
    super.key,
    required this.loading,
    required this.notice,
    required this.session,
    required this.onRefresh,
    required this.onLogout,
  });

  final bool loading;
  final String notice;
  final LoginSession? session;
  final VoidCallback onRefresh;
  final VoidCallback onLogout;

  @override
  Widget build(BuildContext context) {
    final compact = MediaQuery.sizeOf(context).width < 720;
    return FrostedPanel(
      padding: EdgeInsets.all(compact ? 18 : 22),
      child: Wrap(
        spacing: 18,
        runSpacing: 16,
        crossAxisAlignment: WrapCrossAlignment.center,
        alignment: WrapAlignment.spaceBetween,
        children: [
          SizedBox(
            width: compact ? double.infinity : 560,
            child: Row(
              children: [
                Container(
                  width: 58,
                  height: 58,
                  decoration: BoxDecoration(
                    color: const Color(0xff102c69),
                    borderRadius: BorderRadius.circular(16),
                    boxShadow: [
                      BoxShadow(
                        color: const Color(0xff102c69).withValues(alpha: .18),
                        blurRadius: 18,
                        offset: const Offset(0, 10),
                      ),
                    ],
                  ),
                  child: const Icon(
                    Icons.admin_panel_settings,
                    color: Colors.white,
                    size: 34,
                  ),
                ),
                const SizedBox(width: 16),
                const Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'BankOS Admin',
                        style: TextStyle(
                          color: Color(0xff102c69),
                          fontSize: 28,
                          height: 1,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                      SizedBox(height: 6),
                      Text(
                        'Centro principal para gestionar tenants bancarios',
                        style: TextStyle(
                          color: Color(0xff647195),
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          Wrap(
            spacing: 10,
            runSpacing: 10,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              ProfessionalChip(
                icon: session == null
                    ? Icons.lock_outline
                    : Icons.verified_user,
                label: session == null
                    ? 'Sin sesion'
                    : roleLabel(session!.role),
                color: session == null
                    ? const Color(0xffb76b00)
                    : const Color(0xff0d7a52),
              ),
              ProfessionalChip(
                icon: loading ? Icons.sync : Icons.cloud_done,
                label: loading ? 'Sincronizando' : 'API real',
                color: const Color(0xff0d7a52),
              ),
              FilledButton.icon(
                onPressed: loading ? null : onRefresh,
                icon: const Icon(Icons.refresh),
                label: const Text('Actualizar'),
              ),
              if (session != null)
                IconButton.filledTonal(
                  tooltip: 'Cerrar sesion admin',
                  onPressed: onLogout,
                  icon: const Icon(Icons.logout),
                ),
            ],
          ),
          SizedBox(
            width: double.infinity,
            child: Text(
              notice,
              style: const TextStyle(
                color: Color(0xff273a74),
                fontWeight: FontWeight.w800,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class AdminAccessGate extends StatelessWidget {
  const AdminAccessGate({
    super.key,
    required this.tenants,
    required this.tenantsLoading,
    required this.error,
    required this.notice,
    required this.signingIn,
    required this.emailController,
    required this.passwordController,
    required this.onSignIn,
    required this.onReloadTenants,
  });

  final List<BankInstitution> tenants;
  final bool tenantsLoading;
  final String? error;
  final String notice;
  final bool signingIn;
  final TextEditingController emailController;
  final TextEditingController passwordController;
  final VoidCallback onSignIn;
  final VoidCallback onReloadTenants;

  @override
  Widget build(BuildContext context) {
    final compact = MediaQuery.sizeOf(context).width < 640;
    return Center(
      child: SingleChildScrollView(
        padding: EdgeInsets.all(compact ? 18 : 28),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 430),
          child: DecoratedBox(
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(18),
              border: Border.all(color: const Color(0xffd8e0ed)),
              boxShadow: [
                BoxShadow(
                  color: const Color(0xff102c69).withValues(alpha: .12),
                  blurRadius: 28,
                  offset: const Offset(0, 18),
                ),
              ],
            ),
            child: Padding(
              padding: EdgeInsets.all(compact ? 22 : 28),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Center(child: AdminAccessLogo()),
                  const SizedBox(height: 18),
                  const Text(
                    'BankOS Control',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color: Color(0xff0b234d),
                      fontSize: 30,
                      height: 1,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                  const SizedBox(height: 8),
                  const Text(
                    'Ingreso privado de administracion',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color: Color(0xff667085),
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 24),
                  if (error != null) ...[
                    AdminInlineMessage(
                      icon: Icons.error_outline,
                      text: error!,
                      color: const Color(0xffb42318),
                    ),
                    const SizedBox(height: 12),
                  ] else if (notice.isNotEmpty &&
                      notice.contains('sesion')) ...[
                    AdminInlineMessage(
                      icon: Icons.info_outline,
                      text: notice,
                      color: const Color(0xff175cd3),
                    ),
                    const SizedBox(height: 12),
                  ],
                  if (tenantsLoading && tenants.isEmpty) ...[
                    const LinearProgressIndicator(),
                    const SizedBox(height: 12),
                  ],
                  TextField(
                    controller: emailController,
                    enabled: !signingIn,
                    keyboardType: TextInputType.emailAddress,
                    decoration: adminInputDecoration(
                      icon: Icons.alternate_email,
                      label: 'Correo administrador',
                    ),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: passwordController,
                    enabled: !signingIn,
                    obscureText: true,
                    decoration: adminInputDecoration(
                      icon: Icons.lock,
                      label: 'Contrasena',
                    ),
                  ),
                  const SizedBox(height: 18),
                  FilledButton.icon(
                    onPressed: signingIn ? null : onSignIn,
                    icon: signingIn
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.login),
                    label: Text(signingIn ? 'Ingresando...' : 'Ingresar'),
                    style: FilledButton.styleFrom(
                      minimumSize: const Size.fromHeight(52),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                  ),
                  if (tenants.isEmpty && !tenantsLoading) ...[
                    const SizedBox(height: 10),
                    TextButton.icon(
                      onPressed: onReloadTenants,
                      icon: const Icon(Icons.refresh),
                      label: const Text('Reintentar conexion'),
                    ),
                  ],
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class AdminAccessLogo extends StatelessWidget {
  const AdminAccessLogo({super.key});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 76,
      height: 76,
      decoration: BoxDecoration(
        color: const Color(0xff0b234d),
        borderRadius: BorderRadius.circular(22),
      ),
      child: Stack(
        alignment: Alignment.center,
        children: [
          Container(
            width: 38,
            height: 38,
            decoration: BoxDecoration(
              border: Border.all(color: Colors.white, width: 3),
              borderRadius: BorderRadius.circular(10),
            ),
          ),
          const Icon(Icons.key, color: Color(0xffffc928), size: 34),
        ],
      ),
    );
  }
}

class AdminInlineMessage extends StatelessWidget {
  const AdminInlineMessage({
    super.key,
    required this.icon,
    required this.text,
    required this.color,
  });

  final IconData icon;
  final String text;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: color.withValues(alpha: .08),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withValues(alpha: .22)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: color, size: 20),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              text,
              style: TextStyle(color: color, fontWeight: FontWeight.w800),
            ),
          ),
        ],
      ),
    );
  }
}

InputDecoration adminInputDecoration({
  required IconData icon,
  required String label,
}) {
  return InputDecoration(
    prefixIcon: Icon(icon),
    labelText: label,
    filled: true,
    fillColor: const Color(0xfff8fafc),
    border: OutlineInputBorder(
      borderRadius: BorderRadius.circular(12),
      borderSide: const BorderSide(color: Color(0xffd0d7e2)),
    ),
    enabledBorder: OutlineInputBorder(
      borderRadius: BorderRadius.circular(12),
      borderSide: const BorderSide(color: Color(0xffd0d7e2)),
    ),
  );
}

class AdminLoginPanel extends StatelessWidget {
  const AdminLoginPanel({
    super.key,
    required this.tenants,
    required this.tenantsLoading,
    required this.tenant,
    required this.session,
    required this.signingIn,
    required this.emailController,
    required this.passwordController,
    required this.onTenantSelected,
    required this.onSignIn,
    required this.onSignOut,
  });

  final List<BankInstitution> tenants;
  final bool tenantsLoading;
  final BankInstitution? tenant;
  final LoginSession? session;
  final bool signingIn;
  final TextEditingController emailController;
  final TextEditingController passwordController;
  final ValueChanged<BankInstitution> onTenantSelected;
  final VoidCallback onSignIn;
  final VoidCallback onSignOut;

  bool get authenticated =>
      session != null && session!.role.toLowerCase().contains('admin');

  @override
  Widget build(BuildContext context) {
    final currentTenant = tenant;
    return FrostedPanel(
      padding: const EdgeInsets.all(18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SectionTitle(
            title: authenticated
                ? 'Sesion administrativa activa'
                : 'Acceso administrador',
            subtitle: currentTenant == null
                ? 'Selecciona un tenant para iniciar sesion'
                : 'Tenant: ${currentTenant.name}',
          ),
          const SizedBox(height: 14),
          if (authenticated)
            Row(
              children: [
                Container(
                  width: 46,
                  height: 46,
                  decoration: BoxDecoration(
                    color: const Color(0xff0d7a52).withValues(alpha: .12),
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: const Icon(
                    Icons.verified_user,
                    color: Color(0xff0d7a52),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        session!.userId,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: Color(0xff102c69),
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                      Text(
                        '${roleLabel(session!.role)} | ${session!.tenantId}',
                        style: const TextStyle(
                          color: Color(0xff647195),
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ],
                  ),
                ),
                OutlinedButton.icon(
                  onPressed: onSignOut,
                  icon: const Icon(Icons.logout),
                  label: const Text('Salir'),
                ),
              ],
            )
          else ...[
            if (tenantsLoading)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 12),
                child: LinearProgressIndicator(),
              )
            else if (tenants.isEmpty)
              const EmptyState(
                icon: Icons.account_balance,
                text:
                    'No hay bancos disponibles para iniciar sesion administrativa.',
              )
            else
              DropdownButtonFormField<String>(
                initialValue: currentTenant?.tenantId,
                decoration: InputDecoration(
                  prefixIcon: const Icon(Icons.account_balance),
                  labelText: 'Banco / tenant',
                  filled: true,
                  fillColor: Colors.white.withValues(alpha: .82),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: const BorderSide(color: Color(0xffd8def2)),
                  ),
                ),
                items: [
                  for (final tenant in tenants)
                    DropdownMenuItem(
                      value: tenant.tenantId,
                      child: Text('${tenant.name} (${tenant.tenantId})'),
                    ),
                ],
                onChanged: signingIn
                    ? null
                    : (value) {
                        final tenant = tenants.firstWhere(
                          (item) => item.tenantId == value,
                          orElse: () => tenants.first,
                        );
                        onTenantSelected(tenant);
                      },
              ),
            const SizedBox(height: 12),
            LayoutBuilder(
              builder: (context, constraints) {
                final twoColumns = constraints.maxWidth > 720;
                return Wrap(
                  spacing: 12,
                  runSpacing: 12,
                  children: [
                    SizedBox(
                      width: twoColumns
                          ? (constraints.maxWidth - 12) / 2
                          : constraints.maxWidth,
                      child: AppTextField(
                        controller: emailController,
                        icon: Icons.alternate_email,
                        label: 'Correo administrador',
                      ),
                    ),
                    SizedBox(
                      width: twoColumns
                          ? (constraints.maxWidth - 12) / 2
                          : constraints.maxWidth,
                      child: AppTextField(
                        controller: passwordController,
                        icon: Icons.lock,
                        label: 'Contrasena',
                        obscure: true,
                      ),
                    ),
                  ],
                );
              },
            ),
            const SizedBox(height: 14),
            Row(
              children: [
                Expanded(
                  child: Text(
                    currentTenant == null
                        ? 'El login usa la API real y requiere X-Tenant-ID.'
                        : 'Usuario semilla esperado: admin@${currentTenant.tenantId}.com',
                    style: const TextStyle(
                      color: Color(0xff647195),
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
                FilledButton.icon(
                  onPressed: currentTenant == null || signingIn
                      ? null
                      : onSignIn,
                  icon: signingIn
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.login),
                  label: Text(signingIn ? 'Ingresando...' : 'Ingresar'),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}

class TenantDirectoryPanel extends StatelessWidget {
  const TenantDirectoryPanel({
    super.key,
    required this.loading,
    required this.searchController,
    required this.tenants,
    required this.selectedTenant,
    required this.onSearchChanged,
    required this.onTenantSelected,
    required this.onDeleteTenant,
    required this.deletingTenantId,
  });

  final bool loading;
  final TextEditingController searchController;
  final List<BankInstitution> tenants;
  final BankInstitution? selectedTenant;
  final ValueChanged<String> onSearchChanged;
  final ValueChanged<BankInstitution> onTenantSelected;
  final ValueChanged<BankInstitution> onDeleteTenant;
  final String? deletingTenantId;

  @override
  Widget build(BuildContext context) {
    return FrostedPanel(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const SectionTitle(
            title: 'Directorio de tenants',
            subtitle: 'Bancos e instituciones registrados',
          ),
          const SizedBox(height: 14),
          TextField(
            controller: searchController,
            onChanged: onSearchChanged,
            decoration: InputDecoration(
              prefixIcon: const Icon(Icons.search),
              hintText: 'Buscar banco, tenant o moneda',
              filled: true,
              fillColor: Colors.white.withValues(alpha: .82),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: const BorderSide(color: Color(0xffd8def2)),
              ),
            ),
          ),
          const SizedBox(height: 14),
          if (loading)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 34),
              child: Center(child: CircularProgressIndicator()),
            )
          else if (tenants.isEmpty)
            const EmptyState(
              icon: Icons.account_balance,
              text:
                  'Sin tenants. Crea el primer banco para iniciar la administracion.',
            )
          else
            Column(
              children: [
                for (final tenant in tenants)
                  TenantListTile(
                    tenant: tenant,
                    selected: tenant.tenantId == selectedTenant?.tenantId,
                    deleting: deletingTenantId == tenant.tenantId,
                    onTap: () => onTenantSelected(tenant),
                    onDelete: () => onDeleteTenant(tenant),
                  ),
              ],
            ),
        ],
      ),
    );
  }
}

class TenantListTile extends StatelessWidget {
  const TenantListTile({
    super.key,
    required this.tenant,
    required this.selected,
    required this.deleting,
    required this.onTap,
    required this.onDelete,
  });

  final BankInstitution tenant;
  final bool selected;
  final bool deleting;
  final VoidCallback onTap;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    final color = selected ? const Color(0xff102c69) : const Color(0xff647195);
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Material(
        color: selected
            ? const Color(0xffe8eefb)
            : Colors.white.withValues(alpha: .72),
        borderRadius: BorderRadius.circular(14),
        child: InkWell(
          borderRadius: BorderRadius.circular(14),
          onTap: onTap,
          child: Container(
            padding: const EdgeInsets.all(13),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(14),
              border: Border.all(
                color: selected
                    ? const Color(0xff102c69)
                    : const Color(0xffd8def2),
              ),
            ),
            child: Row(
              children: [
                Container(
                  width: 42,
                  height: 42,
                  decoration: BoxDecoration(
                    color: color.withValues(alpha: .12),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Icon(Icons.account_balance, color: color),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        tenant.name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: Color(0xff102c69),
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                      const SizedBox(height: 3),
                      Text(
                        '${tenant.tenantId} | ${tenant.primaryCurrency}',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: Color(0xff647195),
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ],
                  ),
                ),
                IconButton(
                  onPressed: deleting ? null : () async {
                    final confirmed = await showDialog<bool>(
                      context: context,
                      builder: (ctx) => AlertDialog(
                        title: const Text('Eliminar tenant'),
                        content: Text(
                          '¿Seguro que deseas eliminar "${tenant.name}"? Esta accion no se puede deshacer.',
                        ),
                        actions: [
                          TextButton(
                            onPressed: () => Navigator.pop(ctx, false),
                            child: const Text('Cancelar'),
                          ),
                          FilledButton(
                            style: FilledButton.styleFrom(
                              backgroundColor: Colors.red.shade700,
                            ),
                            onPressed: () => Navigator.pop(ctx, true),
                            child: const Text('Eliminar'),
                          ),
                        ],
                      ),
                    );
                    if (confirmed == true) onDelete();
                  },
                  icon: deleting
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.delete_outline, color: Color(0xffb00020), size: 20),
                  tooltip: 'Eliminar tenant',
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class AdminTenantDetail extends StatelessWidget {
  const AdminTenantDetail({super.key, required this.tenant});

  final BankInstitution? tenant;

  @override
  Widget build(BuildContext context) {
    final current = tenant;
    return FrostedPanel(
      padding: const EdgeInsets.all(18),
      child: current == null
          ? const EmptyState(
              icon: Icons.domain_disabled,
              text:
                  'Selecciona un tenant. El detalle del banco aparecera aqui.',
            )
          : Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  children: [
                    Container(
                      width: 54,
                      height: 54,
                      decoration: BoxDecoration(
                        color: const Color(0xff102c69),
                        borderRadius: BorderRadius.circular(16),
                      ),
                      child: const Icon(
                        Icons.account_balance,
                        color: Colors.white,
                        size: 30,
                      ),
                    ),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            current.name,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              color: Color(0xff102c69),
                              fontSize: 24,
                              fontWeight: FontWeight.w900,
                            ),
                          ),
                          Text(
                            current.tenantId,
                            style: const TextStyle(
                              color: Color(0xff647195),
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                        ],
                      ),
                    ),
                    ProfessionalChip(
                      icon: Icons.verified,
                      label: 'Tenant activo',
                      color: const Color(0xff0d7a52),
                    ),
                  ],
                ),
                const SizedBox(height: 20),
                const SectionTitle(
                  title: 'Configuracion del tenant',
                  subtitle: 'Datos tecnicos visibles para administracion',
                ),
                const SizedBox(height: 12),
                AdminConfigRow(
                  icon: Icons.payments,
                  label: 'Moneda base',
                  value: current.primaryCurrency,
                ),
                AdminConfigRow(
                  icon: Icons.event_available,
                  label: 'Fecha de alta',
                  value: current.createdAt.isEmpty
                      ? 'No disponible'
                      : current.createdAt,
                ),
              ],
            ),
    );
  }
}

class AdminConfigRow extends StatelessWidget {
  const AdminConfigRow({
    super.key,
    required this.icon,
    required this.label,
    required this.value,
  });

  final IconData icon;
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: .74),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xffd8def2)),
      ),
      child: Row(
        children: [
          Icon(icon, color: const Color(0xff102c69), size: 24),
          const SizedBox(width: 12),
          SizedBox(
            width: 150,
            child: Text(
              label,
              style: const TextStyle(
                color: Color(0xff647195),
                fontWeight: FontWeight.w900,
              ),
            ),
          ),
          Expanded(
            child: Text(
              value,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                color: Color(0xff102c69),
                fontWeight: FontWeight.w900,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class TenantCreationPanel extends StatelessWidget {
  const TenantCreationPanel({
    super.key,
    required this.enabled,
    required this.creating,
    required this.tenantIdController,
    required this.tenantNameController,
    required this.currencyController,
    required this.limitController,
    required this.feeController,
    required this.onCreate,
  });

  final bool enabled;
  final bool creating;
  final TextEditingController tenantIdController;
  final TextEditingController tenantNameController;
  final TextEditingController currencyController;
  final TextEditingController limitController;
  final TextEditingController feeController;
  final VoidCallback onCreate;

  @override
  Widget build(BuildContext context) {
    return FrostedPanel(
      padding: const EdgeInsets.all(18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const SectionTitle(
            title: 'Crear nuevo tenant',
            subtitle: 'Alta inicial de un banco dentro de BankOS',
          ),
          if (!enabled) ...[
            const SizedBox(height: 12),
            const OperationNotice(
              icon: Icons.lock_outline,
              title: 'Acceso requerido',
              text:
                  'Inicia sesion como administrador para habilitar la creacion de tenants.',
            ),
          ],
          const SizedBox(height: 16),
          LayoutBuilder(
            builder: (context, constraints) {
              final twoColumns = constraints.maxWidth > 720;
              final fieldWidth = twoColumns
                  ? (constraints.maxWidth - 12) / 2
                  : constraints.maxWidth;
              return Wrap(
                spacing: 12,
                runSpacing: 12,
                children: [
                  SizedBox(
                    width: fieldWidth,
                    child: AppTextField(
                      controller: tenantIdController,
                      icon: Icons.badge,
                      label: 'ID del tenant',
                    ),
                  ),
                  SizedBox(
                    width: fieldWidth,
                    child: AppTextField(
                      controller: tenantNameController,
                      icon: Icons.account_balance,
                      label: 'Nombre del banco',
                    ),
                  ),
                  SizedBox(
                    width: fieldWidth,
                    child: AppTextField(
                      controller: currencyController,
                      icon: Icons.payments,
                      label: 'Moneda principal',
                    ),
                  ),
                  SizedBox(
                    width: fieldWidth,
                    child: AppTextField(
                      controller: limitController,
                      icon: Icons.price_check,
                      label: 'Limite por transaccion',
                    ),
                  ),
                  SizedBox(
                    width: fieldWidth,
                    child: AppTextField(
                      controller: feeController,
                      icon: Icons.percent,
                      label: 'Comision de transferencia',
                    ),
                  ),
                ],
              );
            },
          ),
          const SizedBox(height: 16),
          Align(
            alignment: Alignment.centerRight,
            child: FilledButton.icon(
              onPressed: !enabled || creating ? null : onCreate,
              icon: creating
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.add_business),
              label: Text(creating ? 'Creando...' : 'Crear tenant'),
            ),
          ),
        ],
      ),
    );
  }
}

class AdminAlert extends StatelessWidget {
  const AdminAlert({super.key, required this.message, required this.onRetry});

  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0xfffff4e6),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0xffffbf69)),
      ),
      child: Row(
        children: [
          const Icon(Icons.warning_amber, color: Color(0xffb76b00)),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              message,
              style: const TextStyle(
                color: Color(0xff7b4200),
                fontWeight: FontWeight.w800,
              ),
            ),
          ),
          TextButton.icon(
            onPressed: onRetry,
            icon: const Icon(Icons.refresh),
            label: const Text('Reintentar'),
          ),
        ],
      ),
    );
  }
}

class AuthArena extends StatefulWidget {
  const AuthArena({
    super.key,
    required this.api,
    required this.banks,
    required this.banksLoading,
    required this.banksError,
    required this.selectedBank,
    required this.onBankChanged,
    required this.onReloadBanks,
    required this.onLogin,
    required this.runAction,
  });

  final BankOsApi api;
  final List<BankInstitution> banks;
  final bool banksLoading;
  final String? banksError;
  final BankInstitution? selectedBank;
  final ValueChanged<BankInstitution> onBankChanged;
  final VoidCallback onReloadBanks;
  final ValueChanged<LoginSession> onLogin;
  final Future<void> Function(Future<void> Function() action) runAction;

  @override
  State<AuthArena> createState() => _AuthArenaState();
}

class _AuthArenaState extends State<AuthArena> {
  int tab = -1;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        if (tab == -1) {
          return BankIntroPanel(
            onLoginTap: () => setState(() => tab = 1),
            onRegisterTap: () => setState(() => tab = 0),
          );
        }

        return _AuthSurface(
          maxWidth: constraints.maxWidth,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              AuthFormHeader(
                title: tab == 0 ? 'Crear cuenta de cliente' : 'Iniciar sesion',
                subtitle: tab == 0
                    ? 'Elige tu banco y crea tu usuario'
                    : 'Elige tu banco antes de entrar',
                onBack: () => setState(() => tab = -1),
              ),
              const SizedBox(height: 18),
              SegmentedButton<int>(
                segments: const [
                  ButtonSegment(
                    value: 0,
                    icon: Icon(Icons.person_add),
                    label: Text('Registro'),
                  ),
                  ButtonSegment(
                    value: 1,
                    icon: Icon(Icons.login),
                    label: Text('Login'),
                  ),
                ],
                style: ButtonStyle(
                  backgroundColor: WidgetStateProperty.resolveWith((states) {
                    if (states.contains(WidgetState.selected)) {
                      return const Color(0xffdfe6ff);
                    }
                    return Colors.white.withValues(alpha: .42);
                  }),
                  foregroundColor: const WidgetStatePropertyAll(
                    Color(0xff102c69),
                  ),
                  textStyle: const WidgetStatePropertyAll(
                    TextStyle(fontWeight: FontWeight.w800),
                  ),
                ),
                selected: {tab},
                onSelectionChanged: (value) =>
                    setState(() => tab = value.first),
              ),
              const SizedBox(height: 24),
              if (tab == 0)
                RegisterForm(
                  api: widget.api,
                  banks: widget.banks,
                  banksLoading: widget.banksLoading,
                  banksError: widget.banksError,
                  selectedBank: widget.selectedBank,
                  onBankChanged: widget.onBankChanged,
                  onReloadBanks: widget.onReloadBanks,
                  onLogin: widget.onLogin,
                  runAction: widget.runAction,
                )
              else
                LoginForm(
                  api: widget.api,
                  banks: widget.banks,
                  banksLoading: widget.banksLoading,
                  banksError: widget.banksError,
                  selectedBank: widget.selectedBank,
                  onBankChanged: widget.onBankChanged,
                  onReloadBanks: widget.onReloadBanks,
                  onLogin: widget.onLogin,
                  runAction: widget.runAction,
                ),
            ],
          ),
        );
      },
    );
  }
}

class AuthFormHeader extends StatelessWidget {
  const AuthFormHeader({
    super.key,
    required this.title,
    required this.subtitle,
    required this.onBack,
  });

  final String title;
  final String subtitle;
  final VoidCallback onBack;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        IconButton.filledTonal(
          tooltip: 'Volver',
          onPressed: onBack,
          icon: const Icon(Icons.arrow_back),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: const TextStyle(
                  color: Color(0xff102c69),
                  fontSize: 24,
                  height: 1,
                  fontWeight: FontWeight.w900,
                ),
              ),
              const SizedBox(height: 5),
              Text(
                subtitle,
                style: const TextStyle(
                  color: Color(0xff273a74),
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class BankIntroPanel extends StatelessWidget {
  const BankIntroPanel({
    super.key,
    required this.onLoginTap,
    required this.onRegisterTap,
  });

  final VoidCallback onLoginTap;
  final VoidCallback onRegisterTap;

  @override
  Widget build(BuildContext context) {
    final width = MediaQuery.sizeOf(context).width;
    final compact = width < 520;
    return FrostedPanel(
      padding: EdgeInsets.all(compact ? 18 : 26),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            'Tus finanzas en modo mundial',
            style: TextStyle(
              color: const Color(0xff102c69),
              fontSize: compact ? 28 : 42,
              height: 1,
              fontWeight: FontWeight.w900,
            ),
          ),
          const SizedBox(height: 10),
          Text(
            'Opera cuentas, saldos, movimientos y transferencias desde una experiencia bancaria segura. Selecciona tu banco al iniciar sesion o registrarte.',
            style: TextStyle(
              color: const Color(0xff243866),
              fontSize: compact ? 14 : 17,
              height: 1.35,
              fontWeight: FontWeight.w600,
            ),
          ),
          SizedBox(height: compact ? 16 : 22),
          Wrap(
            spacing: 10,
            runSpacing: 10,
            children: [
              ProfessionalChip(
                icon: Icons.domain_verification,
                label: 'Multi-tenant',
                color: const Color(0xff174ea6),
              ),
              ProfessionalChip(
                icon: Icons.account_balance_wallet,
                label: 'Cuentas aisladas',
                color: const Color(0xff0d7a52),
              ),
              ProfessionalChip(
                icon: Icons.currency_exchange,
                label: 'Cambio de divisa',
                color: const Color(0xffb76b00),
              ),
            ],
          ),
          SizedBox(height: compact ? 18 : 24),
          if (compact)
            Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                BankActionButton(
                  onPressed: onLoginTap,
                  icon: Icons.login,
                  label: 'Iniciar sesion',
                  color: const Color(0xff102c69),
                ),
                const SizedBox(height: 10),
                BankActionButton(
                  onPressed: onRegisterTap,
                  icon: Icons.person_add_alt_1,
                  label: 'Crear cuenta de cliente',
                  color: const Color(0xffffc928),
                  outlined: true,
                ),
              ],
            )
          else
            Row(
              children: [
                Expanded(
                  child: BankActionButton(
                    onPressed: onLoginTap,
                    icon: Icons.login,
                    label: 'Iniciar sesion',
                    color: const Color(0xff102c69),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: BankActionButton(
                    onPressed: onRegisterTap,
                    icon: Icons.person_add_alt_1,
                    label: 'Crear cuenta',
                    color: const Color(0xffffc928),
                    outlined: true,
                  ),
                ),
              ],
            ),
        ],
      ),
    );
  }
}

class SelectedBankBadge extends StatelessWidget {
  const SelectedBankBadge({super.key, required this.bank});

  final BankInstitution bank;

  @override
  Widget build(BuildContext context) {
    final compact = MediaQuery.sizeOf(context).width < 520;
    return Container(
      padding: EdgeInsets.all(compact ? 12 : 14),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: .74),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: bank.primaryColor.withValues(alpha: .18)),
      ),
      child: Row(
        children: [
          Container(
            width: compact ? 46 : 54,
            height: compact ? 46 : 54,
            decoration: BoxDecoration(
              color: bank.primaryColor,
              borderRadius: BorderRadius.circular(14),
            ),
            child: Icon(
              bank.icon,
              color: Colors.white,
              size: compact ? 26 : 30,
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  bank.name,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: bank.primaryColor,
                    fontSize: compact ? 18 : 22,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                Text(
                  bank.segment,
                  style: const TextStyle(
                    color: Color(0xff415077),
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ],
            ),
          ),
          if (!compact)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
              decoration: BoxDecoration(
                color: bank.accentColor.withValues(alpha: .18),
                borderRadius: BorderRadius.circular(999),
              ),
              child: Text(
                bank.tenantId,
                style: TextStyle(
                  color: bank.primaryColor,
                  fontSize: 12,
                  fontWeight: FontWeight.w900,
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class ProfessionalChip extends StatelessWidget {
  const ProfessionalChip({
    super.key,
    required this.icon,
    required this.label,
    required this.color,
  });

  final IconData icon;
  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: .72),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: color.withValues(alpha: .25)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, color: color, size: 20),
          const SizedBox(width: 8),
          Text(
            label,
            style: const TextStyle(
              color: Color(0xff102c69),
              fontWeight: FontWeight.w900,
            ),
          ),
        ],
      ),
    );
  }
}

class BankActionButton extends StatelessWidget {
  const BankActionButton({
    super.key,
    required this.onPressed,
    required this.icon,
    required this.label,
    required this.color,
    this.outlined = false,
  });

  final VoidCallback onPressed;
  final IconData icon;
  final String label;
  final Color color;
  final bool outlined;

  @override
  Widget build(BuildContext context) {
    final style = FilledButton.styleFrom(
      minimumSize: const Size.fromHeight(56),
      backgroundColor: outlined ? Colors.white.withValues(alpha: .72) : color,
      foregroundColor: outlined ? const Color(0xff102c69) : Colors.white,
      side: outlined
          ? BorderSide(color: color.withValues(alpha: .55), width: 1.4)
          : null,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      textStyle: const TextStyle(fontSize: 16, fontWeight: FontWeight.w900),
      elevation: outlined ? 0 : 8,
      shadowColor: color.withValues(alpha: .34),
    );

    return FilledButton.icon(
      onPressed: onPressed,
      style: style,
      icon: Icon(icon),
      label: Text(label, overflow: TextOverflow.ellipsis),
    );
  }
}

class _AuthSurface extends StatelessWidget {
  const _AuthSurface({required this.child, required this.maxWidth});

  final Widget child;
  final double maxWidth;

  @override
  Widget build(BuildContext context) {
    final compact = maxWidth < 520;
    return FrostedPanel(
      padding: EdgeInsets.symmetric(
        horizontal: compact ? 18 : 34,
        vertical: compact ? 20 : 32,
      ),
      child: child,
    );
  }
}

class RegisterForm extends StatefulWidget {
  const RegisterForm({
    super.key,
    required this.api,
    required this.banks,
    required this.banksLoading,
    required this.banksError,
    required this.selectedBank,
    required this.onBankChanged,
    required this.onReloadBanks,
    required this.onLogin,
    required this.runAction,
  });

  final BankOsApi api;
  final List<BankInstitution> banks;
  final bool banksLoading;
  final String? banksError;
  final BankInstitution? selectedBank;
  final ValueChanged<BankInstitution> onBankChanged;
  final VoidCallback onReloadBanks;
  final ValueChanged<LoginSession> onLogin;
  final Future<void> Function(Future<void> Function() action) runAction;

  @override
  State<RegisterForm> createState() => _RegisterFormState();
}

class _RegisterFormState extends State<RegisterForm> {
  final fullName = TextEditingController();
  final email = TextEditingController();
  final password = TextEditingController();
  final confirmPassword = TextEditingController();
  bool acceptsTerms = true;

  @override
  void dispose() {
    fullName.dispose();
    email.dispose();
    password.dispose();
    confirmPassword.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        BankSelectionField(
          title: 'Institucion donde crearas la cuenta',
          banks: widget.banks,
          banksLoading: widget.banksLoading,
          error: widget.banksError,
          selectedBank: widget.selectedBank,
          onChanged: widget.onBankChanged,
          onRetry: widget.onReloadBanks,
        ),
        AppTextField(
          controller: fullName,
          icon: Icons.person,
          label: 'Nombre Completo',
          hint: 'Ingresa tu nombre completo',
        ),
        AppTextField(
          controller: email,
          icon: Icons.mail,
          label: 'Correo Electronico',
          hint: 'tu correo@example.com',
        ),
        AppTextField(
          controller: password,
          icon: Icons.lock,
          label: 'Contrasena',
          obscure: true,
        ),
        AppTextField(
          controller: confirmPassword,
          icon: Icons.lock,
          label: 'Confirmar Contrasena',
          obscure: true,
        ),
        Material(
          color: Colors.transparent,
          child: CheckboxListTile(
            contentPadding: EdgeInsets.zero,
            activeColor: const Color(0xff13aef5),
            checkColor: Colors.white,
            value: acceptsTerms,
            onChanged: (value) => setState(() => acceptsTerms = value ?? true),
            title: const Text(
              'Acepto los Terminos y Condiciones',
              style: TextStyle(
                color: Color(0xff102c69),
                fontWeight: FontWeight.w900,
                fontSize: 16,
              ),
            ),
            controlAffinity: ListTileControlAffinity.leading,
          ),
        ),
        const SizedBox(height: 12),
        StadiumButton(
          icon: Icons.sports_soccer,
          label: 'Registrarme',
          onPressed: () {
            widget.runAction(() async {
              final bank = widget.selectedBank;
              if (bank == null) {
                throw Exception('Selecciona un banco desde la lista.');
              }
              widget.api.tenantId = bank.tenantId;
              if (!acceptsTerms) {
                throw Exception('Debes aceptar los terminos y condiciones.');
              }
              if (password.text != confirmPassword.text) {
                throw Exception('Las contrasenas no coinciden.');
              }
              await widget.api.registerUser(
                email: email.text.trim(),
                password: password.text,
                role: 'cliente',
              );
              final results = await Future.wait([
                widget.api.login(
                  email: email.text.trim(),
                  password: password.text,
                ),
                Future<void>.delayed(const Duration(seconds: 4)),
              ]);
              widget.onLogin(results.first as LoginSession);
            });
          },
        ),
      ],
    );
  }
}

class BankReadonlyField extends StatelessWidget {
  const BankReadonlyField({super.key, required this.bank});

  final BankInstitution bank;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 15),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: .72),
        borderRadius: BorderRadius.circular(9),
        border: Border.all(color: const Color(0xffc8cbe0), width: 1.4),
      ),
      child: Row(
        children: [
          Icon(bank.icon, color: bank.primaryColor, size: 30),
          const SizedBox(width: 18),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  bank.name,
                  style: TextStyle(
                    color: bank.primaryColor,
                    fontWeight: FontWeight.w900,
                    fontSize: 16,
                  ),
                ),
                const Text(
                  'Institucion seleccionada',
                  style: TextStyle(
                    color: Color(0xff415077),
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class BankSelectionField extends StatelessWidget {
  const BankSelectionField({
    super.key,
    required this.title,
    required this.banks,
    required this.banksLoading,
    required this.error,
    required this.selectedBank,
    required this.onChanged,
    required this.onRetry,
  });

  final String title;
  final List<BankInstitution> banks;
  final bool banksLoading;
  final String? error;
  final BankInstitution? selectedBank;
  final ValueChanged<BankInstitution> onChanged;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final bank = selectedBank;
    return Container(
      margin: const EdgeInsets.only(bottom: 14),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: .72),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xffc8cbe0), width: 1.2),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Container(
                width: 38,
                height: 38,
                decoration: BoxDecoration(
                  color: bank?.primaryColor ?? const Color(0xff102c69),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(
                  bank?.icon ?? Icons.account_balance,
                  color: Colors.white,
                  size: 22,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: const TextStyle(
                        color: Color(0xff647195),
                        fontSize: 12,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                    Text(
                      bank?.name ?? 'Selecciona un banco',
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: Color(0xff102c69),
                        fontSize: 17,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          if (banksLoading)
            const LinearProgressIndicator(minHeight: 3)
          else if (error != null)
            Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  'No se pudo cargar la lista desde BankOS.',
                  style: const TextStyle(
                    color: Color(0xffb3261e),
                    fontWeight: FontWeight.w900,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  error!,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: Color(0xff415077),
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 10),
                OutlinedButton.icon(
                  onPressed: onRetry,
                  icon: const Icon(Icons.refresh),
                  label: const Text('Reintentar'),
                ),
              ],
            )
          else
            DropdownButtonFormField<String>(
              initialValue: bank?.tenantId,
              isExpanded: true,
              decoration: inputDecoration(
                Icons.account_balance,
                'Banco',
                'Selecciona tu institucion',
              ),
              items: [
                for (final item in banks)
                  DropdownMenuItem(
                    value: item.tenantId,
                    child: Text(
                      '${item.name} (${item.tenantId})',
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
              ],
              onChanged: (tenantId) {
                if (tenantId == null) return;
                final bank = banks.firstWhere(
                  (item) => item.tenantId == tenantId,
                );
                onChanged(bank);
              },
            ),
          if (bank != null) ...[
            const SizedBox(height: 10),
            Text(
              'Tu usuario y tus cuentas se consultan solo dentro de ${bank.shortName}.',
              style: const TextStyle(
                color: Color(0xff415077),
                fontSize: 13,
                fontWeight: FontWeight.w700,
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class LoginForm extends StatefulWidget {
  const LoginForm({
    super.key,
    required this.api,
    required this.banks,
    required this.banksLoading,
    required this.banksError,
    required this.selectedBank,
    required this.onBankChanged,
    required this.onReloadBanks,
    required this.onLogin,
    required this.runAction,
  });

  final BankOsApi api;
  final List<BankInstitution> banks;
  final bool banksLoading;
  final String? banksError;
  final BankInstitution? selectedBank;
  final ValueChanged<BankInstitution> onBankChanged;
  final VoidCallback onReloadBanks;
  final ValueChanged<LoginSession> onLogin;
  final Future<void> Function(Future<void> Function() action) runAction;

  @override
  State<LoginForm> createState() => _LoginFormState();
}

class _LoginFormState extends State<LoginForm> {
  final email = TextEditingController();
  final password = TextEditingController();

  @override
  void dispose() {
    email.dispose();
    password.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        BankSelectionField(
          title: 'Institucion para iniciar sesion',
          banks: widget.banks,
          banksLoading: widget.banksLoading,
          error: widget.banksError,
          selectedBank: widget.selectedBank,
          onChanged: widget.onBankChanged,
          onRetry: widget.onReloadBanks,
        ),
        AppTextField(
          controller: email,
          icon: Icons.mail,
          label: 'Correo electronico',
        ),
        AppTextField(
          controller: password,
          icon: Icons.lock,
          label: 'Contrasena',
          obscure: true,
        ),
        const SizedBox(height: 18),
        StadiumButton(
          icon: Icons.login,
          label: 'Entrar a BankOS',
          onPressed: () {
            widget.runAction(() async {
              final bank = widget.selectedBank;
              if (bank == null) {
                throw Exception('Selecciona un banco desde la lista.');
              }
              widget.api.tenantId = bank.tenantId;
              final results = await Future.wait([
                widget.api.login(
                  email: email.text.trim(),
                  password: password.text,
                ),
                Future<void>.delayed(const Duration(seconds: 4)),
              ]);
              final session = results.first as LoginSession;
              widget.onLogin(session);
            });
          },
        ),
      ],
    );
  }
}

class DashboardArena extends StatefulWidget {
  const DashboardArena({
    super.key,
    required this.api,
    required this.selectedBank,
    required this.session,
    required this.accounts,
    required this.transactions,
    required this.runAction,
    required this.reload,
    required this.onLogout,
  });

  final BankOsApi api;
  final BankInstitution selectedBank;
  final LoginSession session;
  final List<BankAccount> accounts;
  final List<BankTransaction> transactions;
  final Future<void> Function(Future<void> Function() action) runAction;
  final Future<void> Function() reload;
  final VoidCallback onLogout;

  @override
  State<DashboardArena> createState() => _DashboardArenaState();
}

class _DashboardArenaState extends State<DashboardArena> {
  int selectedIndex = 0;
  final accountNumber = TextEditingController(text: 'ACC-NUEVA-01');
  final ownerId = TextEditingController();
  final initialBalance = TextEditingController(text: '500000');
  final accountCurrency = TextEditingController(text: 'COP');

  final operationAmount = TextEditingController(text: '50000');
  final operationAccount = TextEditingController(text: 'ACC-1001');
  final targetAccount = TextEditingController(text: 'ACC-1002');
  final operationCurrency = TextEditingController(text: 'COP');
  final pin = TextEditingController(text: '1234');
  String operationType = 'deposit';
  String? operationResultMessage;

  @override
  void initState() {
    super.initState();
    ownerId.text = widget.session.userId;
  }

  @override
  void dispose() {
    accountNumber.dispose();
    ownerId.dispose();
    initialBalance.dispose();
    accountCurrency.dispose();
    operationAmount.dispose();
    operationAccount.dispose();
    targetAccount.dispose();
    operationCurrency.dispose();
    pin.dispose();
    super.dispose();
  }

  List<BankAccount> get activeAccounts =>
      widget.accounts.where((account) => account.isActive).toList();

  BankAccount? get primaryAccount =>
      activeAccounts.isEmpty ? null : activeAccounts.first;

  String get primaryCurrency => primaryAccount?.currency ?? 'COP';

  double get primaryBalance => widget.accounts
      .where((account) => account.currency == primaryCurrency)
      .fold(0, (total, account) => total + account.balance);

  void prepareOperation(String type) {
    final accounts = activeAccounts;
    setState(() {
      selectedIndex = 2;
      operationType = type;
      operationResultMessage = null;
      if (accounts.isNotEmpty) {
        operationAccount.text = accounts.first.number;
        operationCurrency.text = accounts.first.currency;
      }
      if (type == 'transfer' && accounts.length > 1) {
        targetAccount.text = accounts[1].number;
      }
    });
  }

  Future<void> createAccount() async {
    await widget.api.createAccount(
      accountNumber: accountNumber.text.trim(),
      userId: ownerId.text.trim(),
      initialBalance: decimalValue(initialBalance.text),
      currency: accountCurrency.text.trim(),
    );
    await widget.reload();
  }

  Future<void> runOperation() async {
    final result = await widget.api.sendOperation(
      type: operationType,
      accountId: operationAccount.text.trim(),
      targetAccountId: targetAccount.text.trim(),
      amount: decimalValue(operationAmount.text),
      currency: operationCurrency.text.trim(),
      pin: pin.text,
    );
    setState(() {
      operationResultMessage =
          'Comision ${money(result.fee)} | Monto final ${money(result.finalAmount)}';
    });
    await widget.reload();
  }

  Future<void> deactivateAccount(BankAccount account) async {
    await widget.api.deactivateAccount(account.number);
    await widget.reload();
  }

  bool get canManageAccounts =>
      widget.session.role.toLowerCase().contains('admin');

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final isWide = constraints.maxWidth > 920;
        final destinations = const [
          _NavDestination(Icons.home_filled, 'Inicio'),
          _NavDestination(Icons.account_balance_wallet, 'Cuentas'),
          _NavDestination(Icons.swap_horiz, 'Operar'),
          _NavDestination(Icons.receipt_long, 'Movimientos'),
          _NavDestination(Icons.person, 'Perfil'),
        ];

        final currentView = switch (selectedIndex) {
          0 => HomeBankView(
            bank: widget.selectedBank,
            accounts: widget.accounts,
            transactions: widget.transactions,
            primaryCurrency: primaryCurrency,
            primaryBalance: primaryBalance,
            onQuickOperation: prepareOperation,
            onOpenAccounts: () => setState(() => selectedIndex = 1),
            onOpenOperations: () => setState(() => selectedIndex = 2),
            onOpenMovements: () => setState(() => selectedIndex = 3),
            onOpenProfile: () => setState(() => selectedIndex = 4),
          ),
          1 => AccountsWorkspace(
            bank: widget.selectedBank,
            accounts: widget.accounts,
            canManageAccounts: canManageAccounts,
            accountNumber: accountNumber,
            ownerId: ownerId,
            initialBalance: initialBalance,
            accountCurrency: accountCurrency,
            onCreate: () => widget.runAction(createAccount),
            onDeactivate: (account) =>
                widget.runAction(() => deactivateAccount(account)),
          ),
          2 => OperationsWorkspace(
            operationType: operationType,
            operationAccount: operationAccount,
            targetAccount: targetAccount,
            operationAmount: operationAmount,
            operationCurrency: operationCurrency,
            pin: pin,
            accounts: activeAccounts,
            resultMessage: operationResultMessage,
            onTypeChanged: (value) => setState(() {
              operationType = value;
              operationResultMessage = null;
            }),
            onSubmit: () => widget.runAction(runOperation),
          ),
          3 => MovementsWorkspace(transactions: widget.transactions),
          _ => ProfileWorkspace(
            bank: widget.selectedBank,
            session: widget.session,
            accounts: widget.accounts,
            transactions: widget.transactions,
            tenantId: widget.api.tenantId,
            onRefresh: () => widget.runAction(widget.reload),
            onLogout: widget.onLogout,
          ),
        };

        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            DashboardHeader(
              bank: widget.selectedBank,
              session: widget.session,
              onLogout: widget.onLogout,
            ),
            const SizedBox(height: 16),
            if (isWide)
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  SizedBox(
                    width: 230,
                    child: _BankSideNavigation(
                      destinations: destinations,
                      selectedIndex: selectedIndex,
                      onChanged: (value) =>
                          setState(() => selectedIndex = value),
                    ),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: AnimatedSwitcher(
                      duration: const Duration(milliseconds: 220),
                      child: currentView,
                    ),
                  ),
                ],
              )
            else
              Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  _BankMobileNavigation(
                    destinations: destinations,
                    selectedIndex: selectedIndex,
                    onChanged: (value) => setState(() => selectedIndex = value),
                  ),
                  const SizedBox(height: 14),
                  AnimatedSwitcher(
                    duration: const Duration(milliseconds: 220),
                    child: currentView,
                  ),
                ],
              ),
          ],
        );
      },
    );
  }
}

class _NavDestination {
  const _NavDestination(this.icon, this.label);

  final IconData icon;
  final String label;
}

class DashboardHeader extends StatelessWidget {
  const DashboardHeader({
    super.key,
    required this.bank,
    required this.session,
    required this.onLogout,
  });

  final BankInstitution bank;
  final LoginSession session;
  final VoidCallback onLogout;

  @override
  Widget build(BuildContext context) {
    return FrostedPanel(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      child: Row(
        children: [
          Container(
            width: 42,
            height: 42,
            decoration: BoxDecoration(
              color: bank.primaryColor,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(bank.icon, color: Colors.white, size: 24),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  bank.name,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: Color(0xff102c69),
                    fontSize: 18,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                Text(
                  roleLabel(session.role),
                  style: const TextStyle(
                    color: Color(0xff647195),
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ],
            ),
          ),
          IconButton.filledTonal(
            tooltip: 'Cerrar sesion',
            onPressed: onLogout,
            icon: const Icon(Icons.logout),
          ),
        ],
      ),
    );
  }
}

class _BankSideNavigation extends StatelessWidget {
  const _BankSideNavigation({
    required this.destinations,
    required this.selectedIndex,
    required this.onChanged,
  });

  final List<_NavDestination> destinations;
  final int selectedIndex;
  final ValueChanged<int> onChanged;

  @override
  Widget build(BuildContext context) {
    return FrostedPanel(
      padding: const EdgeInsets.all(10),
      child: Column(
        children: [
          for (var index = 0; index < destinations.length; index++)
            _NavigationButton(
              destination: destinations[index],
              selected: selectedIndex == index,
              onTap: () => onChanged(index),
            ),
        ],
      ),
    );
  }
}

class _BankMobileNavigation extends StatelessWidget {
  const _BankMobileNavigation({
    required this.destinations,
    required this.selectedIndex,
    required this.onChanged,
  });

  final List<_NavDestination> destinations;
  final int selectedIndex;
  final ValueChanged<int> onChanged;

  @override
  Widget build(BuildContext context) {
    return FrostedPanel(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 10),
      child: SizedBox(
        height: 48,
        child: ListView.separated(
          scrollDirection: Axis.horizontal,
          itemBuilder: (context, index) => _NavigationButton(
            destination: destinations[index],
            selected: selectedIndex == index,
            compact: true,
            onTap: () => onChanged(index),
          ),
          separatorBuilder: (context, index) => const SizedBox(width: 8),
          itemCount: destinations.length,
        ),
      ),
    );
  }
}

class _NavigationButton extends StatelessWidget {
  const _NavigationButton({
    required this.destination,
    required this.selected,
    required this.onTap,
    this.compact = false,
  });

  final _NavDestination destination;
  final bool selected;
  final bool compact;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: destination.label,
      child: Material(
        color: selected
            ? const Color(0xff102c69)
            : Colors.white.withValues(alpha: .58),
        borderRadius: BorderRadius.circular(8),
        child: InkWell(
          borderRadius: BorderRadius.circular(8),
          onTap: onTap,
          child: Container(
            width: compact ? 128 : double.infinity,
            padding: EdgeInsets.symmetric(
              horizontal: compact ? 12 : 14,
              vertical: compact ? 10 : 14,
            ),
            child: Row(
              mainAxisSize: compact ? MainAxisSize.min : MainAxisSize.max,
              children: [
                Icon(
                  destination.icon,
                  color: selected ? Colors.white : const Color(0xff102c69),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    destination.label,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: selected ? Colors.white : const Color(0xff102c69),
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class HomeBankView extends StatelessWidget {
  const HomeBankView({
    super.key,
    required this.bank,
    required this.accounts,
    required this.transactions,
    required this.primaryCurrency,
    required this.primaryBalance,
    required this.onQuickOperation,
    required this.onOpenAccounts,
    required this.onOpenOperations,
    required this.onOpenMovements,
    required this.onOpenProfile,
  });

  final BankInstitution bank;
  final List<BankAccount> accounts;
  final List<BankTransaction> transactions;
  final String primaryCurrency;
  final double primaryBalance;
  final ValueChanged<String> onQuickOperation;
  final VoidCallback onOpenAccounts;
  final VoidCallback onOpenOperations;
  final VoidCallback onOpenMovements;
  final VoidCallback onOpenProfile;

  @override
  Widget build(BuildContext context) {
    return Column(
      key: const ValueKey('home-view'),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        FrostedPanel(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Bienvenido',
                style: const TextStyle(
                  color: Color(0xff647195),
                  fontWeight: FontWeight.w900,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                '$primaryCurrency ${money(primaryBalance)}',
                style: const TextStyle(
                  color: Color(0xff102c69),
                  fontSize: 44,
                  height: 1,
                  fontWeight: FontWeight.w900,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                'Saldo consolidado disponible en ${bank.shortName}.',
                style: const TextStyle(
                  color: Color(0xff415077),
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 18),
              Wrap(
                spacing: 10,
                runSpacing: 10,
                children: [
                  ActionShortcut(
                    icon: Icons.add,
                    label: 'Depositar',
                    onTap: () => onQuickOperation('deposit'),
                  ),
                  ActionShortcut(
                    icon: Icons.remove,
                    label: 'Retirar',
                    onTap: () => onQuickOperation('withdrawal'),
                  ),
                  ActionShortcut(
                    icon: Icons.compare_arrows,
                    label: 'Transferir',
                    onTap: () => onQuickOperation('transfer'),
                  ),
                ],
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),
        LayoutBuilder(
          builder: (context, constraints) {
            final twoColumns = constraints.maxWidth > 680;
            final cards = [
              HomeSectionCard(
                icon: Icons.account_balance_wallet,
                title: 'Mis cuentas',
                subtitle: 'Ver saldos y productos',
                onTap: onOpenAccounts,
              ),
              HomeSectionCard(
                icon: Icons.swap_horiz,
                title: 'Operar',
                subtitle: 'Depositar, retirar o transferir',
                onTap: onOpenOperations,
              ),
              HomeSectionCard(
                icon: Icons.receipt_long,
                title: 'Movimientos',
                subtitle: 'Historial de transacciones',
                onTap: onOpenMovements,
              ),
              HomeSectionCard(
                icon: Icons.person,
                title: 'Perfil',
                subtitle: 'Banco, usuario y sesion',
                onTap: onOpenProfile,
              ),
            ];

            if (!twoColumns) {
              return Column(
                children: [
                  for (final card in cards) ...[
                    card,
                    const SizedBox(height: 10),
                  ],
                ],
              );
            }

            return Wrap(
              spacing: 12,
              runSpacing: 12,
              children: [
                for (final card in cards)
                  SizedBox(width: (constraints.maxWidth - 12) / 2, child: card),
              ],
            );
          },
        ),
      ],
    );
  }
}

class HomeSectionCard extends StatelessWidget {
  const HomeSectionCard({
    super.key,
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.white.withValues(alpha: .72),
      borderRadius: BorderRadius.circular(14),
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: const Color(0xffd8def2)),
          ),
          child: Row(
            children: [
              Container(
                width: 48,
                height: 48,
                decoration: BoxDecoration(
                  color: const Color(0xff102c69),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(icon, color: Colors.white, size: 26),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: const TextStyle(
                        color: Color(0xff102c69),
                        fontSize: 18,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      subtitle,
                      style: const TextStyle(
                        color: Color(0xff647195),
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ],
                ),
              ),
              const Icon(Icons.chevron_right, color: Color(0xff102c69)),
            ],
          ),
        ),
      ),
    );
  }
}

class AccountsWorkspace extends StatelessWidget {
  const AccountsWorkspace({
    super.key,
    required this.bank,
    required this.accounts,
    required this.canManageAccounts,
    required this.accountNumber,
    required this.ownerId,
    required this.initialBalance,
    required this.accountCurrency,
    required this.onCreate,
    required this.onDeactivate,
  });

  final BankInstitution bank;
  final List<BankAccount> accounts;
  final bool canManageAccounts;
  final TextEditingController accountNumber;
  final TextEditingController ownerId;
  final TextEditingController initialBalance;
  final TextEditingController accountCurrency;
  final VoidCallback onCreate;
  final ValueChanged<BankAccount> onDeactivate;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      key: const ValueKey('accounts-view'),
      builder: (context, constraints) {
        final wide = constraints.maxWidth > 760;
        final list = AccountsPanel(
          accounts: accounts,
          onDeactivate: canManageAccounts ? onDeactivate : null,
        );
        final form = FrostedPanel(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (canManageAccounts) ...[
                const SectionTitle(
                  title: 'Nueva cuenta',
                  subtitle: 'Creacion para usuarios administradores',
                ),
                AppTextField(
                  controller: accountNumber,
                  icon: Icons.tag,
                  label: 'Numero de cuenta',
                ),
                AppTextField(
                  controller: ownerId,
                  icon: Icons.person,
                  label: 'UserId titular',
                ),
                Row(
                  children: [
                    Expanded(
                      child: AppTextField(
                        controller: initialBalance,
                        icon: Icons.savings,
                        label: 'Saldo inicial',
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: AppTextField(
                        controller: accountCurrency,
                        icon: Icons.attach_money,
                        label: 'Moneda',
                      ),
                    ),
                  ],
                ),
                StadiumButton(
                  icon: Icons.add_card,
                  label: 'Crear cuenta',
                  onPressed: onCreate,
                ),
                const SizedBox(height: 14),
                const ValidationList(
                  items: [
                    'No permite saldo inicial negativo.',
                    'No duplica numeros de cuenta.',
                    'La cuenta queda activa por defecto.',
                    'Desactivar usa soft delete, no borra registros.',
                  ],
                ),
              ] else ...[
                SectionTitle(
                  title: 'Mis cuentas',
                  subtitle: 'Productos activos de ${bank.shortName}',
                ),
                const ValidationList(
                  items: [
                    'Tus cuentas se cargan segun tu usuario.',
                    'Solo puedes mover dinero desde cuentas propias.',
                    'Las cuentas inactivas no permiten operaciones.',
                    'Tu banco conserva el historial de movimientos.',
                  ],
                ),
              ],
            ],
          ),
        );

        if (!wide) {
          return Column(children: [list, const SizedBox(height: 16), form]);
        }

        return Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(flex: 6, child: list),
            const SizedBox(width: 16),
            Expanded(flex: 4, child: form),
          ],
        );
      },
    );
  }
}

class OperationsWorkspace extends StatelessWidget {
  const OperationsWorkspace({
    super.key,
    required this.operationType,
    required this.operationAccount,
    required this.targetAccount,
    required this.operationAmount,
    required this.operationCurrency,
    required this.pin,
    required this.accounts,
    required this.resultMessage,
    required this.onTypeChanged,
    required this.onSubmit,
  });

  final String operationType;
  final TextEditingController operationAccount;
  final TextEditingController targetAccount;
  final TextEditingController operationAmount;
  final TextEditingController operationCurrency;
  final TextEditingController pin;
  final List<BankAccount> accounts;
  final String? resultMessage;
  final ValueChanged<String> onTypeChanged;
  final VoidCallback onSubmit;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      key: const ValueKey('operations-view'),
      builder: (context, constraints) {
        final wide = constraints.maxWidth > 820;
        final form = FrostedPanel(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const SectionTitle(
                title: 'Operaciones',
                subtitle: 'Depositos, retiros y transferencias internas',
              ),
              SegmentedButton<String>(
                segments: const [
                  ButtonSegment(
                    value: 'deposit',
                    icon: Icon(Icons.add),
                    label: Text('Deposito'),
                  ),
                  ButtonSegment(
                    value: 'withdrawal',
                    icon: Icon(Icons.remove),
                    label: Text('Retiro'),
                  ),
                  ButtonSegment(
                    value: 'transfer',
                    icon: Icon(Icons.compare_arrows),
                    label: Text('Enviar'),
                  ),
                ],
                showSelectedIcon: false,
                style: const ButtonStyle(
                  textStyle: WidgetStatePropertyAll(
                    TextStyle(fontWeight: FontWeight.w900, fontSize: 13),
                  ),
                  visualDensity: VisualDensity.compact,
                ),
                selected: {operationType},
                onSelectionChanged: (value) => onTypeChanged(value.first),
              ),
              const SizedBox(height: 16),
              AppTextField(
                controller: operationAccount,
                icon: Icons.account_balance_wallet,
                label: operationType == 'deposit'
                    ? 'Cuenta destino'
                    : 'Cuenta origen',
              ),
              if (operationType == 'transfer')
                AppTextField(
                  controller: targetAccount,
                  icon: Icons.outbound,
                  label: 'Cuenta destino',
                ),
              Row(
                children: [
                  Expanded(
                    child: AppTextField(
                      controller: operationAmount,
                      icon: Icons.payments,
                      label: 'Monto',
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: AppTextField(
                      controller: operationCurrency,
                      icon: Icons.monetization_on,
                      label: 'Moneda',
                    ),
                  ),
                ],
              ),
              if (operationType != 'deposit')
                AppTextField(
                  controller: pin,
                  icon: Icons.pin,
                  label: 'PIN',
                  obscure: true,
                ),
              if (operationType == 'transfer') ...[
                const OperationNotice(
                  icon: Icons.currency_exchange,
                  title: 'Comision y divisa',
                  text:
                      'El backend calcula la comision del tenant y convierte el monto si las cuentas usan monedas distintas.',
                ),
                const SizedBox(height: 10),
              ],
              if (resultMessage != null) ...[
                OperationNotice(
                  icon: Icons.check_circle,
                  title: 'Operacion procesada',
                  text: resultMessage!,
                  success: true,
                ),
                const SizedBox(height: 10),
              ],
              StadiumButton(
                icon: Icons.sports_score,
                label: 'Confirmar operacion',
                onPressed: onSubmit,
              ),
            ],
          ),
        );

        final guide = FrostedPanel(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const SectionTitle(
                title: 'Cuentas disponibles',
                subtitle: 'Selecciona IDs para operar',
              ),
              if (accounts.isEmpty)
                const EmptyState(
                  icon: Icons.account_balance_wallet,
                  text: 'No hay cuentas activas para operar.',
                )
              else
                ...accounts.map(
                  (account) => Padding(
                    padding: const EdgeInsets.only(bottom: 10),
                    child: InsightRow(
                      icon: Icons.account_balance,
                      title: account.number,
                      value: '${account.currency} ${money(account.balance)}',
                    ),
                  ),
                ),
              const SizedBox(height: 10),
              const ValidationList(
                items: [
                  'Montos deben ser positivos.',
                  'Retiros validan saldo disponible.',
                  'Transferencias requieren cuenta origen y destino.',
                  'Todas las operaciones envian Idempotency-Key.',
                ],
              ),
            ],
          ),
        );

        if (!wide) {
          return Column(children: [form, const SizedBox(height: 16), guide]);
        }

        return Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(flex: 5, child: form),
            const SizedBox(width: 16),
            Expanded(flex: 4, child: guide),
          ],
        );
      },
    );
  }
}

class OperationNotice extends StatelessWidget {
  const OperationNotice({
    super.key,
    required this.icon,
    required this.title,
    required this.text,
    this.success = false,
  });

  final IconData icon;
  final String title;
  final String text;
  final bool success;

  @override
  Widget build(BuildContext context) {
    final color = success ? const Color(0xff0d7a52) : const Color(0xff174ea6);
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: color.withValues(alpha: .09),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: color.withValues(alpha: .22)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: color, size: 22),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: TextStyle(color: color, fontWeight: FontWeight.w900),
                ),
                const SizedBox(height: 3),
                Text(
                  text,
                  style: const TextStyle(
                    color: Color(0xff415077),
                    fontWeight: FontWeight.w700,
                    height: 1.25,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class MovementsWorkspace extends StatelessWidget {
  const MovementsWorkspace({super.key, required this.transactions});

  final List<BankTransaction> transactions;

  @override
  Widget build(BuildContext context) {
    final deposits = transactions.where((tx) => tx.type == 'deposit').length;
    final withdrawals = transactions
        .where((tx) => tx.type == 'withdrawal')
        .length;
    final transfers = transactions.where((tx) => tx.type == 'transfer').length;

    return Column(
      key: const ValueKey('movements-view'),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        FrostedPanel(
          child: Wrap(
            spacing: 10,
            runSpacing: 10,
            children: [
              StatusPill(
                icon: Icons.add_circle,
                label: '$deposits depositos',
                color: Colors.green,
              ),
              StatusPill(
                icon: Icons.remove_circle,
                label: '$withdrawals retiros',
                color: Colors.orange,
              ),
              StatusPill(
                icon: Icons.compare_arrows,
                label: '$transfers transferencias',
                color: const Color(0xff174ea6),
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),
        TransactionsPanel(transactions: transactions),
      ],
    );
  }
}

class ProfileWorkspace extends StatelessWidget {
  const ProfileWorkspace({
    super.key,
    required this.bank,
    required this.session,
    required this.accounts,
    required this.transactions,
    required this.tenantId,
    required this.onRefresh,
    required this.onLogout,
  });

  final BankInstitution bank;
  final LoginSession session;
  final List<BankAccount> accounts;
  final List<BankTransaction> transactions;
  final String tenantId;
  final VoidCallback onRefresh;
  final VoidCallback onLogout;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      key: const ValueKey('profile-view'),
      builder: (context, constraints) {
        final wide = constraints.maxWidth > 760;
        final profile = FrostedPanel(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const SectionTitle(
                title: 'Perfil',
                subtitle: 'Tu relacion con el banco',
              ),
              ProfileLine(label: 'Banco', value: bank.name),
              ProfileLine(label: 'Rol', value: roleLabel(session.role)),
              ProfileLine(label: 'Cliente', value: session.userId),
              ProfileLine(label: 'Institucion', value: tenantId),
              const SizedBox(height: 14),
              Row(
                children: [
                  Expanded(
                    child: FilledButton.icon(
                      onPressed: onRefresh,
                      icon: const Icon(Icons.sync),
                      label: const Text('Actualizar'),
                    ),
                  ),
                  const SizedBox(width: 10),
                  IconButton.filledTonal(
                    tooltip: 'Cerrar sesion',
                    onPressed: onLogout,
                    icon: const Icon(Icons.logout),
                  ),
                ],
              ),
            ],
          ),
        );

        final scope = FrostedPanel(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const SectionTitle(
                title: 'Alcance',
                subtitle: 'Servicios disponibles en tu banco',
              ),
              const ValidationList(
                items: [
                  'Consulta de productos y saldos.',
                  'Depositos, retiros y transferencias internas.',
                  'Validaciones de saldo y estado activo.',
                  'Historial de movimientos por cliente.',
                  'Seguridad por institucion bancaria.',
                ],
              ),
              const SizedBox(height: 14),
              InsightRow(
                icon: Icons.account_balance_wallet,
                title: 'Cuentas cargadas',
                value: '${accounts.length}',
              ),
              const SizedBox(height: 10),
              InsightRow(
                icon: Icons.receipt_long,
                title: 'Movimientos cargados',
                value: '${transactions.length}',
              ),
            ],
          ),
        );

        if (!wide) {
          return Column(children: [profile, const SizedBox(height: 16), scope]);
        }

        return Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(child: profile),
            const SizedBox(width: 16),
            Expanded(child: scope),
          ],
        );
      },
    );
  }
}

class StatusPill extends StatelessWidget {
  const StatusPill({
    super.key,
    required this.icon,
    required this.label,
    required this.color,
  });

  final IconData icon;
  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
      decoration: BoxDecoration(
        color: color.withValues(alpha: .11),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: color.withValues(alpha: .34)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, color: color, size: 18),
          const SizedBox(width: 7),
          Text(
            label,
            style: const TextStyle(
              color: Color(0xff102c69),
              fontWeight: FontWeight.w900,
            ),
          ),
        ],
      ),
    );
  }
}

class ActionShortcut extends StatelessWidget {
  const ActionShortcut({
    super.key,
    required this.icon,
    required this.label,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: label,
      child: Material(
        color: const Color(0xff102c69),
        borderRadius: BorderRadius.circular(8),
        child: InkWell(
          borderRadius: BorderRadius.circular(8),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(icon, color: Colors.white),
                const SizedBox(width: 8),
                Text(
                  label,
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class InsightRow extends StatelessWidget {
  const InsightRow({
    super.key,
    required this.icon,
    required this.title,
    required this.value,
    this.onTap,
  });

  final IconData icon;
  final String title;
  final String value;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.white.withValues(alpha: .72),
      borderRadius: BorderRadius.circular(8),
      child: InkWell(
        borderRadius: BorderRadius.circular(8),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Row(
            children: [
              Icon(icon, color: const Color(0xff102c69)),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  title,
                  style: const TextStyle(
                    color: Color(0xff102c69),
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ),
              const SizedBox(width: 10),
              Flexible(
                child: Text(
                  value,
                  textAlign: TextAlign.end,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: Color(0xff26396e),
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class ValidationList extends StatelessWidget {
  const ValidationList({super.key, required this.items});

  final List<String> items;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (final item in items)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Icon(Icons.check_circle, color: Colors.green, size: 18),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    item,
                    style: const TextStyle(
                      color: Color(0xff1c326a),
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ],
            ),
          ),
      ],
    );
  }
}

class ProfileLine extends StatelessWidget {
  const ProfileLine({super.key, required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 78,
            child: Text(
              label,
              style: const TextStyle(
                color: Color(0xff647195),
                fontWeight: FontWeight.w900,
              ),
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: const TextStyle(
                color: Color(0xff102c69),
                fontWeight: FontWeight.w800,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class AccountsPanel extends StatelessWidget {
  const AccountsPanel({super.key, required this.accounts, this.onDeactivate});

  final List<BankAccount> accounts;
  final ValueChanged<BankAccount>? onDeactivate;

  @override
  Widget build(BuildContext context) {
    return FrostedPanel(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const SectionTitle(
            title: 'Marcador de cuentas',
            subtitle: 'Saldos y estados en tiempo real',
          ),
          if (accounts.isEmpty)
            const EmptyState(
              icon: Icons.account_balance_wallet,
              text: 'No hay cuentas cargadas.',
            )
          else
            Wrap(
              spacing: 12,
              runSpacing: 12,
              children: accounts
                  .map(
                    (account) => AccountTile(
                      account: account,
                      onDeactivate: onDeactivate == null
                          ? null
                          : () => onDeactivate!(account),
                    ),
                  )
                  .toList(),
            ),
        ],
      ),
    );
  }
}

class AccountTile extends StatelessWidget {
  const AccountTile({super.key, required this.account, this.onDeactivate});

  final BankAccount account;
  final VoidCallback? onDeactivate;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 250,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: account.isActive
            ? const Color(0xffeef6ff)
            : const Color(0xffffeeee),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: account.isActive
              ? const Color(0xff2a64bc)
              : const Color(0xffd64545),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                account.isActive ? Icons.check_circle : Icons.block,
                color: account.isActive ? Colors.green : Colors.red,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  account.number,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontWeight: FontWeight.w900,
                    color: Color(0xff102c69),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          Text(
            '${account.currency} ${account.balance.toStringAsFixed(2)}',
            style: const TextStyle(
              fontSize: 22,
              fontWeight: FontWeight.w900,
              color: Color(0xff102c69),
            ),
          ),
          const SizedBox(height: 4),
          Text(account.isActive ? 'Activa' : 'Inactiva'),
          if (onDeactivate != null && account.isActive) ...[
            const SizedBox(height: 12),
            OutlinedButton.icon(
              onPressed: onDeactivate,
              icon: const Icon(Icons.block),
              label: const Text('Desactivar'),
            ),
          ],
        ],
      ),
    );
  }
}

class TransactionsPanel extends StatelessWidget {
  const TransactionsPanel({super.key, required this.transactions});

  final List<BankTransaction> transactions;

  @override
  Widget build(BuildContext context) {
    return FrostedPanel(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const SectionTitle(
            title: 'Historial',
            subtitle: 'Ultimas jugadas financieras',
          ),
          if (transactions.isEmpty)
            const EmptyState(
              icon: Icons.receipt_long,
              text: 'No hay transacciones cargadas.',
            )
          else
            ...transactions
                .take(8)
                .map((tx) => TransactionRow(transaction: tx)),
        ],
      ),
    );
  }
}

class TransactionRow extends StatelessWidget {
  const TransactionRow({super.key, required this.transaction});

  final BankTransaction transaction;

  @override
  Widget build(BuildContext context) {
    final isCredit = transaction.type == 'deposit';
    final color = switch (transaction.type) {
      'deposit' => const Color(0xff0d7a52),
      'withdrawal' => const Color(0xffb76b00),
      _ => const Color(0xff174ea6),
    };
    final typeIcon = switch (transaction.type) {
      'deposit' => Icons.arrow_downward_rounded,
      'withdrawal' => Icons.arrow_upward_rounded,
      _ => Icons.compare_arrows_rounded,
    };

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(8),
        border: Border(left: BorderSide(color: color, width: 4)),
      ),
      child: Row(
        children: [
          Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(
              color: color.withValues(alpha: .1),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Icon(typeIcon, color: color, size: 18),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  transaction.description,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: Color(0xff102c69),
                    fontWeight: FontWeight.w800,
                    fontSize: 14,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  '${movementLabel(transaction.type)} · ${statusLabel(transaction.status)}',
                  style: const TextStyle(
                    color: Color(0xff647195),
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          Text(
            '${isCredit ? '+' : '−'} ${transaction.currency} ${money(transaction.amount)}',
            style: TextStyle(
              fontWeight: FontWeight.w900,
              color: color,
              fontSize: 14,
            ),
          ),
        ],
      ),
    );
  }
}

class _MedalStrip extends StatelessWidget {
  const _MedalStrip();

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: 18, bottom: 12),
      child: FrostedPanel(
        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 16),
        child: Row(
          children: const [
            Expanded(
              child: _MedalItem(
                icon: Icons.workspace_premium,
                title: 'Servicio de Primera',
              ),
            ),
            _DividerLine(),
            Expanded(
              child: _MedalItem(
                icon: Icons.support_agent,
                title: 'Atencion 24/7',
              ),
            ),
            _DividerLine(),
            Expanded(
              child: _MedalItem(icon: Icons.public, title: 'Tu Dinero Global'),
            ),
          ],
        ),
      ),
    );
  }
}

class SoccerLoginOverlay extends StatefulWidget {
  const SoccerLoginOverlay({super.key});

  @override
  State<SoccerLoginOverlay> createState() => _SoccerLoginOverlayState();
}

class _SoccerLoginOverlayState extends State<SoccerLoginOverlay>
    with SingleTickerProviderStateMixin {
  late final AnimationController controller;

  @override
  void initState() {
    super.initState();
    controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1150),
    )..repeat();
  }

  @override
  void dispose() {
    controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Positioned.fill(
      child: ColoredBox(
        color: const Color(0xaa061735),
        child: Center(
          child: FrostedPanel(
            padding: const EdgeInsets.symmetric(horizontal: 30, vertical: 28),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                SizedBox(
                  width: 220,
                  height: 86,
                  child: AnimatedBuilder(
                    animation: controller,
                    builder: (context, _) {
                      final t = controller.value;
                      final x = lerpDouble(
                        -74,
                        74,
                        Curves.easeInOut.transform(t),
                      )!;
                      final y = -sin(t * pi) * 26;
                      return Stack(
                        alignment: Alignment.center,
                        children: [
                          Positioned(
                            left: 24,
                            right: 24,
                            bottom: 18,
                            child: Container(
                              height: 5,
                              decoration: BoxDecoration(
                                color: const Color(
                                  0xff102c69,
                                ).withValues(alpha: .18),
                                borderRadius: BorderRadius.circular(99),
                              ),
                            ),
                          ),
                          Positioned(
                            left: 78 + x,
                            top: 28 + y,
                            child: Transform.rotate(
                              angle: t * pi * 5,
                              child: const Icon(
                                Icons.sports_soccer,
                                color: Color(0xff102c69),
                                size: 42,
                              ),
                            ),
                          ),
                          Positioned(
                            left: 84 + x - 42,
                            top: 48 + y,
                            child: Container(
                              width: 42,
                              height: 4,
                              decoration: BoxDecoration(
                                gradient: LinearGradient(
                                  colors: [
                                    const Color(
                                      0xffffd23f,
                                    ).withValues(alpha: .05),
                                    const Color(
                                      0xffffd23f,
                                    ).withValues(alpha: .82),
                                  ],
                                ),
                                borderRadius: BorderRadius.circular(99),
                              ),
                            ),
                          ),
                        ],
                      );
                    },
                  ),
                ),
                const SizedBox(height: 8),
                const Text(
                  'Entrando a BankOS',
                  style: TextStyle(
                    color: Color(0xff102c69),
                    fontSize: 24,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                const SizedBox(height: 8),
                const Text(
                  'Autenticando usuario y cargando finanzas...',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: Color(0xff273a74),
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _MedalItem extends StatelessWidget {
  const _MedalItem({required this.icon, required this.title});

  final IconData icon;
  final String title;

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 58,
          height: 58,
          decoration: BoxDecoration(
            color: const Color(0xffffd84d),
            borderRadius: BorderRadius.circular(29),
            boxShadow: const [
              BoxShadow(
                color: Color(0x33000000),
                blurRadius: 12,
                offset: Offset(0, 6),
              ),
            ],
          ),
          child: Icon(icon, color: const Color(0xff102c69), size: 34),
        ),
        const SizedBox(height: 8),
        Text(
          title,
          textAlign: TextAlign.center,
          style: const TextStyle(
            color: Color(0xff102c69),
            fontWeight: FontWeight.w900,
          ),
        ),
      ],
    );
  }
}

class _DividerLine extends StatelessWidget {
  const _DividerLine();

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 1,
      height: 72,
      margin: const EdgeInsets.symmetric(horizontal: 8),
      color: const Color(0xffd6dae8),
    );
  }
}

class FrostedPanel extends StatelessWidget {
  const FrostedPanel({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(18),
  });

  final Widget child;
  final EdgeInsets padding;

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(18),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 14, sigmaY: 14),
        child: Container(
          padding: padding,
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: .68),
            borderRadius: BorderRadius.circular(18),
            border: Border.all(
              color: Colors.white.withValues(alpha: .72),
              width: 1.4,
            ),
            boxShadow: const [
              BoxShadow(
                color: Color(0x55030a1c),
                blurRadius: 34,
                offset: Offset(0, 18),
              ),
              BoxShadow(
                color: Color(0x33ffffff),
                blurRadius: 8,
                offset: Offset(0, -2),
              ),
            ],
          ),
          child: child,
        ),
      ),
    );
  }
}

class SectionTitle extends StatelessWidget {
  const SectionTitle({super.key, required this.title, required this.subtitle});

  final String title;
  final String subtitle;

  @override
  Widget build(BuildContext context) {
    final compact = MediaQuery.sizeOf(context).width < 520;
    return Padding(
      padding: EdgeInsets.only(bottom: compact ? 12 : 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: TextStyle(
              color: const Color(0xff102c69),
              fontSize: compact ? 20 : 24,
              height: 1.1,
              fontWeight: FontWeight.w900,
              letterSpacing: -0.3,
            ),
          ),
          const SizedBox(height: 3),
          Text(
            subtitle,
            style: TextStyle(
              color: const Color(0xff647195),
              fontSize: compact ? 13 : 14,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}

class AppTextField extends StatefulWidget {
  const AppTextField({
    super.key,
    required this.controller,
    required this.icon,
    required this.label,
    this.hint,
    this.obscure = false,
    this.keyboardType,
    this.textInputAction,
  });

  final TextEditingController controller;
  final IconData icon;
  final String label;
  final String? hint;
  final bool obscure;
  final TextInputType? keyboardType;
  final TextInputAction? textInputAction;

  @override
  State<AppTextField> createState() => _AppTextFieldState();
}

class _AppTextFieldState extends State<AppTextField> {
  bool _hidden = true;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: TextField(
        controller: widget.controller,
        obscureText: widget.obscure && _hidden,
        keyboardType: widget.keyboardType,
        textInputAction: widget.textInputAction,
        style: const TextStyle(
          color: Color(0xff132b63),
          fontSize: 18,
          fontWeight: FontWeight.w600,
        ),
        decoration: inputDecoration(widget.icon, widget.label, widget.hint).copyWith(
          suffixIcon: widget.obscure
              ? IconButton(
                  icon: Icon(
                    _hidden ? Icons.visibility_off : Icons.visibility,
                    color: const Color(0xff647195),
                  ),
                  onPressed: () => setState(() => _hidden = !_hidden),
                  tooltip: _hidden ? 'Mostrar contrasena' : 'Ocultar contrasena',
                )
              : null,
        ),
      ),
    );
  }
}

InputDecoration inputDecoration(IconData icon, String label, [String? hint]) {
  return InputDecoration(
    prefixIcon: Padding(
      padding: const EdgeInsets.only(left: 16, right: 14),
      child: Icon(icon, color: const Color(0xff102c69), size: 30),
    ),
    prefixIconConstraints: const BoxConstraints(minWidth: 70),
    labelText: label,
    hintText: hint,
    floatingLabelBehavior: FloatingLabelBehavior.auto,
    labelStyle: const TextStyle(
      color: Color(0xff102c69),
      fontWeight: FontWeight.w900,
      fontSize: 17,
    ),
    hintStyle: const TextStyle(
      color: Color(0xff415077),
      fontWeight: FontWeight.w500,
      fontSize: 16,
    ),
    filled: true,
    fillColor: Colors.white.withValues(alpha: .72),
    contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 18),
    border: OutlineInputBorder(borderRadius: BorderRadius.circular(9)),
    enabledBorder: OutlineInputBorder(
      borderRadius: BorderRadius.circular(9),
      borderSide: const BorderSide(color: Color(0xffc8cbe0), width: 1.4),
    ),
    focusedBorder: OutlineInputBorder(
      borderRadius: BorderRadius.circular(9),
      borderSide: const BorderSide(color: Color(0xff12306f), width: 2.2),
    ),
  );
}

class StadiumButton extends StatelessWidget {
  const StadiumButton({
    super.key,
    required this.icon,
    required this.label,
    required this.onPressed,
    this.isLoading = false,
  });

  final IconData icon;
  final String label;
  final VoidCallback onPressed;
  final bool isLoading;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 62,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(14),
        gradient: isLoading
            ? null
            : const LinearGradient(
                begin: Alignment.centerLeft,
                end: Alignment.centerRight,
                colors: [
                  Color(0xff0b234d),
                  Color(0xff1a4fa8),
                  Color(0xff1976d2),
                  Color(0xffffc928),
                ],
              ),
        color: isLoading ? const Color(0xff8899bb) : null,
        boxShadow: isLoading
            ? null
            : const [
                BoxShadow(
                  color: Color(0x66030a1c),
                  blurRadius: 22,
                  offset: Offset(0, 10),
                ),
              ],
      ),
      child: FilledButton.icon(
        onPressed: isLoading ? null : onPressed,
        style: FilledButton.styleFrom(
          backgroundColor: Colors.transparent,
          shadowColor: Colors.transparent,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
          ),
        ),
        icon: isLoading
            ? const SizedBox(
                width: 22,
                height: 22,
                child: CircularProgressIndicator(
                  strokeWidth: 2.5,
                  color: Colors.white,
                ),
              )
            : Icon(icon, color: Colors.white),
        label: Text(
          label,
          style: const TextStyle(
            fontSize: 24,
            fontWeight: FontWeight.w900,
            color: Colors.white,
          ),
        ),
      ),
    );
  }
}

class EmptyState extends StatelessWidget {
  const EmptyState({super.key, required this.icon, required this.text});

  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: const Color(0xffeef2fb),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        children: [
          Icon(icon, color: const Color(0xff102c69)),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              text,
              style: const TextStyle(fontWeight: FontWeight.w700),
            ),
          ),
        ],
      ),
    );
  }
}

class BankOsApi {
  String baseUrl = defaultApiBaseUrl();
  String tenantId = fallbackBank.tenantId;
  String? token;

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

  Map<String, String> headers({bool auth = false, bool mutation = false}) {
    return {
      'Content-Type': 'application/json',
      'X-Tenant-ID': tenantId,
      'X-Correlation-ID': newId(),
      if (mutation) 'Idempotency-Key': newId(),
      if (auth && token != null) 'Authorization': 'Bearer $token',
    };
  }

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
    return decodeResponse(response);
  }

  Future<Map<String, dynamic>> get(
    String path, {
    Map<String, String?> query = const {},
    bool auth = true,
  }) async {
    final response = await _withTimeout(
      http.get(uri(path, query), headers: headers(auth: auth)),
    );
    return decodeResponse(response);
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
    return decodeResponse(response);
  }

  Future<Map<String, dynamic>> patch(
    String path,
    Map<String, dynamic> body, {
    bool auth = false,
    bool mutation = false,
  }) async {
    final response = await _withTimeout(
      http.patch(
        uri(path),
        headers: headers(auth: auth, mutation: mutation),
        body: jsonEncode(body),
      ),
    );
    return decodeResponse(response);
  }

  Future<http.Response> _withTimeout(Future<http.Response> request) async {
    try {
      return await request.timeout(const Duration(seconds: 12));
    } on TimeoutException {
      final bank = bankByTenantId(tenantId);
      throw Exception(
        'No pudimos conectar con ${bank.shortName}. Verifica que el backend este encendido.',
      );
    }
  }

  Future<void> createTenant({
    required String id,
    required String name,
    required String currency,
    required double maxTransactionLimit,
    required double transferFee,
    required bool isFeePercentage,
  }) async {
    await post(
      '/Tenants',
      {
        'id': id,
        'name': name,
        'primaryCurrency': currency,
        'maxTransactionLimit': maxTransactionLimit,
        'transferFee': transferFee,
        'isFeePercentage': isFeePercentage,
      },
      auth: true,
      mutation: true,
    );
  }

  Future<void> deleteTenant({required String tenantId}) async {
    await delete(
      '/Tenants/${Uri.encodeComponent(tenantId)}',
      auth: true,
    );
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
          .where((bank) => bank.tenantId.isNotEmpty)
          .toList();
    }
    if (raw is Map<String, dynamic>) {
      return raw.values
          .whereType<Map<String, dynamic>>()
          .map(BankInstitution.fromJson)
          .where((bank) => bank.tenantId.isNotEmpty)
          .toList();
    }
    return [];
  }

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
    final data = await post('/Auth/login', {
      'email': email,
      'password': password,
    });
    token = (data['token'] ?? data['Token']) as String?;
    if (token == null || token!.isEmpty) {
      throw Exception('El banco no retorno una sesion valida.');
    }
    return LoginSession(
      token: token!,
      userId: (data['userId'] ?? data['UserId'] ?? '') as String,
      tenantId: (data['tenantId'] ?? data['TenantId'] ?? tenantId) as String,
      role: (data['role'] ?? data['UserRole'] ?? 'cliente') as String,
    );
  }

  Future<LoginSession> loginMaster({
    required String email,
    required String password,
  }) async {
    final data = await post('/SuperAuth/login-master', {
      'email': email,
      'password': password,
    });
    token = (data['token'] ?? data['Token']) as String?;
    if (token == null || token!.isEmpty) {
      throw Exception('BankOS no retorno una sesion maestra valida.');
    }
    return LoginSession(
      token: token!,
      userId: '${data['userId'] ?? data['UserId'] ?? email}',
      tenantId: '${data['tenantId'] ?? data['TenantId'] ?? 'master'}',
      role: '${data['role'] ?? data['UserRole'] ?? 'superadmin'}',
    );
  }

  Future<List<BankAccount>> getAccounts() async {
    final data = await get('/Accounts');
    final rawAccounts =
        (data['accounts'] ?? data['Accounts'] ?? data['data'] ?? [])
            as List<dynamic>;
    return rawAccounts
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

  Future<List<BankTransaction>> getTransactions() async {
    final data = await get(
      '/Transactions/history',
      query: {'page': '1', 'pageSize': '20'},
    );
    final rawTransactions =
        (data['transactions'] ?? data['Transactions'] ?? data['data'] ?? [])
            as List<dynamic>;
    return rawTransactions
        .map((item) => BankTransaction.fromJson(item as Map<String, dynamic>))
        .toList();
  }

  Map<String, dynamic> decodeResponse(http.Response response) {
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
    return <String, dynamic>{'data': decoded};
  }
}

class LoginSession {
  const LoginSession({
    required this.token,
    required this.userId,
    required this.tenantId,
    required this.role,
  });

  final String token;
  final String userId;
  final String tenantId;
  final String role;
}

class OperationResult {
  const OperationResult({
    required this.transactionId,
    required this.success,
    required this.fee,
    required this.finalAmount,
  });

  factory OperationResult.fromJson(Map<String, dynamic> json) {
    return OperationResult(
      transactionId:
          '${json['transactionId'] ?? json['TransaccionId'] ?? json['id'] ?? ''}',
      success: (json['success'] ?? json['Success'] ?? true) as bool,
      fee: ((json['fee'] ?? json['Fee'] ?? json['feeAmount'] ?? 0) as num)
          .toDouble(),
      finalAmount:
          ((json['finalAmount'] ??
                      json['FinalAmount'] ??
                      json['convertedAmount'] ??
                      0)
                  as num)
              .toDouble(),
    );
  }

  final String transactionId;
  final bool success;
  final double fee;
  final double finalAmount;
}

class BankAccount {
  const BankAccount({
    required this.id,
    required this.number,
    required this.currency,
    required this.balance,
    required this.isActive,
  });

  factory BankAccount.fromJson(Map<String, dynamic> json) {
    return BankAccount(
      id: '${json['id'] ?? json['Id']}',
      number: '${json['number'] ?? json['Number'] ?? json['id'] ?? json['Id']}',
      currency: '${json['currency'] ?? json['Currency'] ?? 'COP'}',
      balance: ((json['balance'] ?? json['Balance'] ?? 0) as num).toDouble(),
      isActive: (json['isActive'] ?? json['IsActive'] ?? true) as bool,
    );
  }

  final String id;
  final String number;
  final String currency;
  final double balance;
  final bool isActive;
}

class BankTransaction {
  const BankTransaction({
    required this.id,
    required this.type,
    required this.status,
    required this.amount,
    required this.currency,
    required this.accountId,
    required this.description,
  });

  factory BankTransaction.fromJson(Map<String, dynamic> json) {
    return BankTransaction(
      id: '${json['id'] ?? json['Id']}',
      type: '${json['type'] ?? json['Type'] ?? 'transfer'}',
      status: '${json['status'] ?? json['Status'] ?? 'completed'}',
      amount:
          ((json['amount'] ??
                      json['OriginalAmount'] ??
                      json['originalAmount'] ??
                      0)
                  as num)
              .toDouble(),
      currency:
          '${json['currency'] ?? json['FromCurrency'] ?? json['fromCurrency'] ?? 'COP'}',
      accountId:
          '${json['accountId'] ?? json['SourceAccountId'] ?? json['sourceAccountId'] ?? ''}',
      description:
          '${json['description'] ?? json['Description'] ?? 'Operacion financiera'}',
    );
  }

  final String id;
  final String type;
  final String status;
  final double amount;
  final String currency;
  final String accountId;
  final String description;
}

String newId() {
  final random = Random.secure();
  String part(int length) =>
      List.generate(length, (_) => random.nextInt(16).toRadixString(16)).join();
  return '${part(8)}-${part(4)}-4${part(3)}-${(8 + random.nextInt(4)).toRadixString(16)}${part(3)}-${part(12)}';
}

double decimalValue(String value) {
  return double.tryParse(value.replaceAll(',', '.')) ?? 0;
}

double decimalFromDynamic(Object? value) {
  if (value is num) return value.toDouble();
  if (value is String) return decimalValue(value);
  return 0;
}

String money(double value) {
  final rounded = value.toStringAsFixed(2);
  final parts = rounded.split('.');
  final whole = parts.first;
  final buffer = StringBuffer();
  for (var i = 0; i < whole.length; i++) {
    final fromEnd = whole.length - i;
    buffer.write(whole[i]);
    if (fromEnd > 1 && fromEnd % 3 == 1) {
      buffer.write('.');
    }
  }
  return '${buffer.toString()},${parts.last}';
}

String roleLabel(String role) {
  return role.toLowerCase().contains('admin') ? 'Administrador' : 'Cliente';
}

String movementLabel(String type) {
  return switch (type) {
    'deposit' => 'Deposito',
    'withdrawal' => 'Retiro',
    'transfer' => 'Transferencia',
    _ => 'Operacion',
  };
}

String statusLabel(String status) {
  return switch (status) {
    'completed' => 'Completada',
    'pending' => 'Pendiente',
    'failed' => 'Fallida',
    'cancelled' => 'Cancelada',
    _ => status,
  };
}
