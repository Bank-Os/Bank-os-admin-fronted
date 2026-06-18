import 'package:bankos_admin_fronted/bankos_shared.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

void main() {
  runApp(const BankOsAdminWebApp());
}

class BankOsAdminWebApp extends StatelessWidget {
  const BankOsAdminWebApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'BankOS Control',
      theme: ThemeData(
        useMaterial3: true,
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xff0b234d),
          primary: const Color(0xff0b234d),
          secondary: const Color(0xffffc928),
          surface: Colors.white,
        ),
        textTheme: GoogleFonts.dmSansTextTheme(),
      ),
      home: const BankOsAdminPage(),
    );
  }
}
