class MembershipInvite {
  const MembershipInvite({
    required this.id,
    required this.companyId,
    required this.email,
    required this.role,
    required this.status,
    required this.createdAt,
    this.userUid,
    this.invitedBy,
    this.respondedAt,
  });

  final String id;
  final String companyId;
  final String email;
  final String role;
  final String status;
  final DateTime createdAt;
  final String? userUid;
  final String? invitedBy;
  final DateTime? respondedAt;

  bool get isPending => status == 'pending';
  bool get isAccepted => status == 'accepted';
  bool get isCancelled => status == 'cancelled';
  bool get isFailed => status == 'failed';

  MembershipInvite copyWith({
    String? status,
    DateTime? respondedAt,
  }) {
    return MembershipInvite(
      id: id,
      companyId: companyId,
      email: email,
      role: role,
      status: status ?? this.status,
      createdAt: createdAt,
      userUid: userUid,
      invitedBy: invitedBy,
      respondedAt: respondedAt ?? this.respondedAt,
    );
  }

  factory MembershipInvite.fromMap(Map<String, dynamic> map) {
    DateTime? parseDate(dynamic value) {
      if (value == null) return null;
      if (value is DateTime) return value.toUtc();
      if (value is String) return DateTime.tryParse(value)?.toUtc();
      return null;
    }

    return MembershipInvite(
      id: map['id']?.toString() ?? '',
      companyId: map['company_id']?.toString() ?? '',
      email: (map['email'] as String? ?? '').toLowerCase(),
      role: map['role']?.toString() ?? '',
      status: map['status']?.toString() ?? 'pending',
      createdAt: parseDate(map['created_at']) ?? DateTime.now().toUtc(),
      userUid: map['user_uid']?.toString(),
      invitedBy: map['invited_by']?.toString(),
      respondedAt: parseDate(map['responded_at']),
    );
  }
}
