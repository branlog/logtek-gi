class CompanyJoinCode {
  const CompanyJoinCode({
    required this.id,
    required this.companyId,
    required this.role,
    required this.uses,
    required this.createdAt,
    this.codeHint,
    this.label,
    this.maxUses,
    this.expiresAt,
    this.revokedAt,
  });

  final String id;
  final String companyId;
  final String role;
  final int uses;
  final DateTime createdAt;
  final String? codeHint;
  final String? label;
  final int? maxUses;
  final DateTime? expiresAt;
  final DateTime? revokedAt;

  bool get isRevoked => revokedAt != null;
  bool get isExpired =>
      expiresAt != null && expiresAt!.isBefore(DateTime.now().toUtc());
  bool get hasLimit => maxUses != null;

  int? get remainingUses {
    if (maxUses == null) return null;
    final remaining = maxUses! - uses;
    return remaining < 0 ? 0 : remaining;
  }

  CompanyJoinCode copyWith({
    int? uses,
    DateTime? revokedAt,
  }) {
    return CompanyJoinCode(
      id: id,
      companyId: companyId,
      role: role,
      uses: uses ?? this.uses,
      createdAt: createdAt,
      codeHint: codeHint,
      label: label,
      maxUses: maxUses,
      expiresAt: expiresAt,
      revokedAt: revokedAt ?? this.revokedAt,
    );
  }

  factory CompanyJoinCode.fromMap(Map<String, dynamic> map) {
    DateTime? parseDate(dynamic value) {
      if (value == null) return null;
      if (value is DateTime) return value.toUtc();
      if (value is String) return DateTime.tryParse(value)?.toUtc();
      return null;
    }

    return CompanyJoinCode(
      id: map['id']?.toString() ?? '',
      companyId: map['company_id']?.toString() ?? '',
      role: map['role']?.toString() ?? '',
      uses: (map['uses'] as num?)?.toInt() ?? 0,
      createdAt: parseDate(map['created_at']) ?? DateTime.now().toUtc(),
      codeHint: map['code_hint']?.toString(),
      label: map['label']?.toString(),
      maxUses: (map['max_uses'] as num?)?.toInt(),
      expiresAt: parseDate(map['expires_at']),
      revokedAt: parseDate(map['revoked_at']),
    );
  }
}
