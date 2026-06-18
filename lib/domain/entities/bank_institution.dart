import 'package:flutter/material.dart';

class BankInstitution {
  final String tenantId;
  final String name;
  final String shortName;
  final String segment;
  final String tagline;
  final Color primaryColor;
  final Color accentColor;
  final IconData icon;

  const BankInstitution({
    required this.tenantId,
    required this.name,
    required this.shortName,
    required this.segment,
    required this.tagline,
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
    return BankInstitution(
      tenantId: tenantId,
      name: name,
      shortName: name,
      segment: 'Institución bancaria',
      tagline: 'Tenant administrado desde BankOS Admin.',
      primaryColor: const Color(0xff102c69),
      accentColor: const Color(0xffffc928),
      icon: Icons.account_balance,
    );
  }
}