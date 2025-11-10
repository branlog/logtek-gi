class CompanyRoles {
  CompanyRoles._();

  static const String owner = 'owner';
  static const String admin = 'admin';
  static const String employee = 'employee';
  static const String viewer = 'viewer';

  static const List<String> values = <String>[
    owner,
    admin,
    employee,
    viewer,
  ];

  static bool isValid(String? value) {
    if (value == null) return false;
    final normalized = value.trim().toLowerCase();
    return values.contains(normalized);
  }
}

enum CompanyRole {
  owner,
  admin,
  employee,
  viewer,
  unknown,
}

CompanyRole companyRoleFromString(String? value) {
  if (value == null) return CompanyRole.unknown;
  switch (value.trim().toLowerCase()) {
    case CompanyRoles.owner:
      return CompanyRole.owner;
    case CompanyRoles.admin:
      return CompanyRole.admin;
    case CompanyRoles.employee:
      return CompanyRole.employee;
    case CompanyRoles.viewer:
      return CompanyRole.viewer;
    default:
      return CompanyRole.unknown;
  }
}

extension CompanyRoleValue on CompanyRole {
  String get value {
    switch (this) {
      case CompanyRole.owner:
        return CompanyRoles.owner;
      case CompanyRole.admin:
        return CompanyRoles.admin;
      case CompanyRole.employee:
        return CompanyRoles.employee;
      case CompanyRole.viewer:
        return CompanyRoles.viewer;
      case CompanyRole.unknown:
        return 'unknown';
    }
  }

  String get label {
    switch (this) {
      case CompanyRole.owner:
        return 'Owner';
      case CompanyRole.admin:
        return 'Admin';
      case CompanyRole.employee:
        return 'Employé';
      case CompanyRole.viewer:
        return 'Viewer';
      case CompanyRole.unknown:
        return 'Rôle inconnu';
    }
  }

  bool get canManageMembers =>
      this == CompanyRole.owner || this == CompanyRole.admin;

  bool get canManageRoles => canManageMembers;

  bool get canPromoteToOwner => this == CompanyRole.owner;

  bool get canManageInventory =>
      this == CompanyRole.owner ||
      this == CompanyRole.admin ||
      this == CompanyRole.employee;

  bool get canManagePurchases => canManageInventory;

  bool get canManageEquipment => canManageInventory;

  bool get canManageCompany =>
      this == CompanyRole.owner || this == CompanyRole.admin;

  bool get hasWriteAccess =>
      this != CompanyRole.viewer && this != CompanyRole.unknown;

  bool get isReadOnly => !hasWriteAccess;

  List<CompanyRole> get assignableRoles {
    switch (this) {
      case CompanyRole.owner:
        return const <CompanyRole>[
          CompanyRole.owner,
          CompanyRole.admin,
          CompanyRole.employee,
          CompanyRole.viewer,
        ];
      case CompanyRole.admin:
        return const <CompanyRole>[
          CompanyRole.admin,
          CompanyRole.employee,
          CompanyRole.viewer,
        ];
      default:
        return const <CompanyRole>[];
    }
  }
}

String companyRoleLabel(String? value) {
  return companyRoleFromString(value).label;
}
