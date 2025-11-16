part of 'company_gate.dart';

// ---------------------------------------------------------------------------
// More tab
// ---------------------------------------------------------------------------

class _MoreTab extends StatelessWidget {
  const _MoreTab({
    required this.membership,
    required this.members,
    required this.joinCodes,
    required this.invites,
    required this.onRevokeCode,
    required this.onInviteMember,
  });

  final CompanyMembership membership;
  final List<Map<String, dynamic>> members;
  final List<CompanyJoinCode> joinCodes;
  final List<MembershipInvite> invites;
  final Future<void> Function(CompanyJoinCode code) onRevokeCode;
  final VoidCallback onInviteMember;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Card(
            child: ListTile(
              leading: const CircleAvatar(child: Icon(Icons.person_outline)),
              title:
                  Text(membership.company?['name']?.toString() ?? 'Entreprise'),
              subtitle: Text('Rôle : ${membership.role ?? '—'}'),
            ),
          ),
          const SizedBox(height: 24),
          Text('Codes de connexion',
              style: Theme.of(context)
                  .textTheme
                  .titleMedium
                  ?.copyWith(fontWeight: FontWeight.w700)),
          const SizedBox(height: 4),
          Text(
            'Utilise le bouton + pour inviter de nouveaux membres.',
            style: Theme.of(context).textTheme.bodySmall,
          ),
          const SizedBox(height: 12),
          if (joinCodes.isEmpty)
            const _EmptyCard(
              title: 'Aucun code',
              subtitle:
                  'Crée un code depuis le dashboard Supabase pour partager l’accès.',
            )
          else
            Column(
              children: joinCodes
                  .map((code) =>
                      _JoinCodeCard(code: code, onRevoke: onRevokeCode))
                  .toList(),
            ),
          const SizedBox(height: 24),
          Text('Invitations envoyées',
              style: Theme.of(context)
                  .textTheme
                  .titleMedium
                  ?.copyWith(fontWeight: FontWeight.w700)),
          const SizedBox(height: 12),
          if (invites.isEmpty)
            const _EmptyCard(
              title: 'Aucune invitation',
              subtitle:
                  'Envoie une invitation par e-mail pour accorder un accès.',
            )
          else
            Column(
              children:
                  invites.map((invite) => _InviteCard(invite: invite)).toList(),
            ),
          const SizedBox(height: 24),
          Text('Membres actuels',
              style: Theme.of(context)
                  .textTheme
                  .titleMedium
                  ?.copyWith(fontWeight: FontWeight.w700)),
          const SizedBox(height: 12),
          if (members.isEmpty)
            const _EmptyCard(
              title: 'Aucun membre',
              subtitle: 'Les membres apparaîtront ici une fois ajoutés.',
            )
          else
            Column(
              children:
                  members.map((member) => _MemberTile(member: member)).toList(),
            ),
        ],
      ),
    );
  }
}

class _JoinCodeCard extends StatelessWidget {
  const _JoinCodeCard({required this.code, required this.onRevoke});

  final CompanyJoinCode code;
  final Future<void> Function(CompanyJoinCode code) onRevoke;

  @override
  Widget build(BuildContext context) {
    final created = _formatDate(code.createdAt);
    final active = !code.isRevoked && !code.isExpired;
    final uses = '${code.uses}/${code.maxUses ?? '∞'}';

    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Text('Code ${code.codeHint ?? '####'}',
                    style: Theme.of(context)
                        .textTheme
                        .titleMedium
                        ?.copyWith(fontWeight: FontWeight.w700)),
                const Spacer(),
                _Badge(
                  label: active ? 'Actif' : 'Révoqué',
                  color: active ? AppColors.primary : Colors.red,
                ),
              ],
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                _Pill(label: 'Rôle ${code.role}'),
                _Pill(label: 'Utilisations $uses'),
                if (created != null) _Pill(label: 'Créé le $created'),
              ],
            ),
            const SizedBox(height: 12),
            Align(
              alignment: Alignment.centerRight,
              child: TextButton(
                onPressed: active ? () => onRevoke(code) : null,
                child: const Text('Révoquer'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _InviteCard extends StatelessWidget {
  const _InviteCard({required this.invite});

  final MembershipInvite invite;

  @override
  Widget build(BuildContext context) {
    final created = _formatDate(invite.createdAt);
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: ListTile(
        leading: const CircleAvatar(child: Icon(Icons.mail_outline)),
        title: Text(invite.email),
        subtitle: Text('Rôle ${invite.role} • Créé le ${created ?? '—'}'),
        trailing: _Badge(
          label: invite.status,
          color: invite.status == 'accepted' ? Colors.green : AppColors.primary,
        ),
      ),
    );
  }
}

class _MemberTile extends StatelessWidget {
  const _MemberTile({required this.member});

  final Map<String, dynamic> member;

  @override
  Widget build(BuildContext context) {
    final displayName = member['display_name']?.toString() ??
        member['full_name']?.toString() ??
        'Utilisateur';
    final email = member['email']?.toString();
    final role = member['role']?.toString() ?? '—';
    final created = _formatDate(member['created_at']);

    final subtitleParts = <String>[
      if (email != null && email.isNotEmpty) email,
      'Rôle $role',
      if (created != null) 'Depuis $created',
    ];

    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: ListTile(
        leading: CircleAvatar(
          child: Text(displayName.characters.first.toUpperCase()),
        ),
        title: Text(displayName),
        subtitle: Text(subtitleParts.join(' • ')),
      ),
    );
  }
}
