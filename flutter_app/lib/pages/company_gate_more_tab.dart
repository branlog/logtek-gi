part of 'company_gate.dart';

// ---------------------------------------------------------------------------
// More tab
// ---------------------------------------------------------------------------

enum _MoreSectionTab { profile, members, company }

class _MoreTab extends StatefulWidget {
  const _MoreTab({
    required this.membership,
    required this.members,
    required this.joinCodes,
    required this.invites,
    required this.userProfile,
    required this.onRevokeCode,
    required this.onInviteMember,
    required this.onShowCompanyJournal,
    required this.onDeleteJoinCode,
  });

  final CompanyMembership membership;
  final List<Map<String, dynamic>> members;
  final List<CompanyJoinCode> joinCodes;
  final List<MembershipInvite> invites;
  final Map<String, dynamic>? userProfile;
  final _AsyncValueChanged<CompanyJoinCode> onRevokeCode;
  final _AsyncCallback onInviteMember;
  final _AsyncCallback onShowCompanyJournal;
  final _AsyncValueChanged<CompanyJoinCode> onDeleteJoinCode;

  @override
  State<_MoreTab> createState() => _MoreTabState();
}

class _MoreTabState extends State<_MoreTab>
    with SingleTickerProviderStateMixin {
  late final TabController _tabController;
  int _currentIndex = 0;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(
      length: _MoreSectionTab.values.length,
      vsync: this,
    )..addListener(_handleTabChange);
  }

  @override
  void dispose() {
    _tabController.removeListener(_handleTabChange);
    _tabController.dispose();
    super.dispose();
  }

  void _handleTabChange() {
    if (!mounted) return;
    if (_tabController.index != _currentIndex) {
      setState(() => _currentIndex = _tabController.index);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          TabBar(
            controller: _tabController,
            labelColor: AppColors.primary,
            unselectedLabelColor: Colors.black54,
            indicatorColor: AppColors.primary,
            tabs: const [
              Tab(
                icon: Icon(Icons.person_outline),
                text: 'Profil',
              ),
              Tab(
                icon: Icon(Icons.group_outlined),
                text: 'Membres',
              ),
              Tab(
                icon: Icon(Icons.business_outlined),
                text: 'Entreprise',
              ),
            ],
          ),
          const SizedBox(height: 20),
          AnimatedSwitcher(
            duration: const Duration(milliseconds: 200),
            child: KeyedSubtree(
              key: ValueKey<int>(_currentIndex),
              child: _buildSectionFor(_MoreSectionTab.values[_currentIndex]),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSectionFor(_MoreSectionTab section) {
    switch (section) {
      case _MoreSectionTab.profile:
        return _SectionCard(
          title: 'Profil',
          subtitle:
              'Complète ton profil pour que tes collègues te reconnaissent.',
          child: _ProfileSection(
            membership: widget.membership,
            userProfile: widget.userProfile,
          ),
        );
      case _MoreSectionTab.members:
        return _SectionCard(
          title: 'Membres',
          subtitle: 'Surveille les personnes ayant accès à l’entreprise.',
          action: OutlinedButton.icon(
            onPressed: () {
              widget.onInviteMember();
            },
            icon: const Icon(Icons.person_add_alt_1),
            label: const Text('Inviter'),
          ),
          child: _MembersSection(
            members: widget.members,
            joinCodes: widget.joinCodes,
            invites: widget.invites,
            onRevokeCode: widget.onRevokeCode,
            onDeleteCode: widget.onDeleteJoinCode,
          ),
        );
      case _MoreSectionTab.company:
        return _SectionCard(
          title: 'Entreprise',
          subtitle: 'Récapitulatif et codes de connexion à partager.',
          child: _CompanySection(
            membership: widget.membership,
            onShowJournal: widget.onShowCompanyJournal,
          ),
        );
    }
  }
}

class _SectionCard extends StatelessWidget {
  const _SectionCard({
    required this.title,
    required this.child,
    this.subtitle,
    this.action,
  });

  final String title;
  final Widget child;
  final String? subtitle;
  final Widget? action;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      margin: const EdgeInsets.only(bottom: 20),
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title,
                        style: theme.textTheme.titleMedium
                            ?.copyWith(fontWeight: FontWeight.w600),
                      ),
                      if (subtitle != null) ...[
                        const SizedBox(height: 4),
                        Text(
                          subtitle!,
                          style: theme.textTheme.bodyMedium
                              ?.copyWith(color: Colors.black54),
                        ),
                      ],
                    ],
                  ),
                ),
                if (action != null) action!,
              ],
            ),
            const SizedBox(height: 20),
            child,
          ],
        ),
      ),
    );
  }
}

class _ProfileSection extends StatelessWidget {
  const _ProfileSection({
    required this.membership,
    required this.userProfile,
  });

  final CompanyMembership membership;
  final Map<String, dynamic>? userProfile;

  @override
  Widget build(BuildContext context) {
    final user = Supa.i.auth.currentUser;
    String pickField(String key) =>
        userProfile?[key]?.toString().trim() ?? user?.email ?? '';
    final fullName = pickField('full_name');
    final displayName = pickField('display_name');
    final name = fullName.isNotEmpty ? fullName : displayName;
    final email = pickField('email');
    final role = membership.role ?? 'membre';
    final company = membership.company?['name']?.toString() ?? '';
    final initials = _buildInitials((name.isNotEmpty ? name : email).trim());

    final profileFields = [
      if (company.isNotEmpty)
        _InfoRow(icon: Icons.business, label: 'Entreprise', value: company),
      _InfoRow(icon: Icons.mail, label: 'Courriel', value: email),
    ];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            CircleAvatar(
              radius: 28,
              backgroundColor: AppColors.primary.withOpacity(0.15),
              child: Text(
                initials.isNotEmpty ? initials : '?',
                style: const TextStyle(fontWeight: FontWeight.w600),
              ),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    name.isNotEmpty ? name : email,
                    style: Theme.of(context)
                        .textTheme
                        .titleMedium
                        ?.copyWith(fontWeight: FontWeight.w600),
                  ),
                  Text('Rôle : $role'),
                ],
              ),
            ),
          ],
        ),
        const SizedBox(height: 16),
        Column(
          children: [
            for (var index = 0; index < profileFields.length; index++) ...[
              profileFields[index],
              if (index != profileFields.length - 1)
                const Divider(height: 20),
            ],
          ],
        ),
      ],
    );
  }

  String _buildInitials(String value) {
    if (value.isEmpty) return '?';
    final parts = value.split(RegExp(r'\s+')).where((part) => part.isNotEmpty);
    final buffer = StringBuffer();
    for (final part in parts.take(2)) {
      final codeUnit = part.runes.isNotEmpty ? part.runes.first : null;
      if (codeUnit != null) {
        buffer.write(String.fromCharCode(codeUnit).toUpperCase());
      }
    }
    return buffer.isEmpty ? '?' : buffer.toString();
  }
}

class _MembersSection extends StatelessWidget {
  const _MembersSection({
    required this.members,
    required this.joinCodes,
    required this.invites,
    required this.onRevokeCode,
    required this.onDeleteCode,
  });

  final List<Map<String, dynamic>> members;
  final List<CompanyJoinCode> joinCodes;
  final List<MembershipInvite> invites;
  final _AsyncValueChanged<CompanyJoinCode> onRevokeCode;
  final _AsyncValueChanged<CompanyJoinCode> onDeleteCode;

  @override
  Widget build(BuildContext context) {
    final highlighted = members.take(4).toList(growable: false);
    final remaining = members.length - highlighted.length;

    final memberList = members.isEmpty
        ? const _EmptyStateCard(
            title: 'Aucun membre',
            subtitle: 'Invite tes collègues pour collaborer.',
          )
        : Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              for (var index = 0; index < highlighted.length; index++) ...[
                _MemberTile(member: highlighted[index]),
                if (index != highlighted.length - 1)
                  const Divider(height: 24),
              ],
              if (remaining > 0) ...[
                const SizedBox(height: 12),
                Text(
                  '+$remaining membre${remaining > 1 ? 's' : ''} '
                  'supplémentaire${remaining > 1 ? 's' : ''}',
                  style: Theme.of(context)
                      .textTheme
                      .bodyMedium
                      ?.copyWith(color: Colors.black54),
                ),
              ],
            ],
          );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        memberList,
        const SizedBox(height: 24),
        Text('Codes de connexion',
            style: Theme.of(context)
                .textTheme
                .titleSmall
                ?.copyWith(fontWeight: FontWeight.w600)),
        const SizedBox(height: 12),
        if (joinCodes.isEmpty)
          const _EmptyStateCard(
            title: 'Aucun code',
            subtitle: 'Crée un code pour faciliter les nouvelles entrées.',
          )
        else
          Column(
            children: joinCodes
                .take(3)
                .map(
                  (code) => _JoinCodeCard(
                    code: code,
                    onRevoke: onRevokeCode,
                    onDelete: onDeleteCode,
                  ),
                )
                .toList(),
          ),
        if (joinCodes.length > 3) ...[
          const SizedBox(height: 8),
          Text(
            '+${joinCodes.length - 3} code${joinCodes.length - 3 > 1 ? 's' : ''} '
            'supplémentaires',
            style: Theme.of(context)
                .textTheme
                .bodyMedium
                ?.copyWith(color: Colors.black54),
          ),
        ],
        const SizedBox(height: 24),
        Text('Invitations en cours',
            style: Theme.of(context)
                .textTheme
                .titleSmall
                ?.copyWith(fontWeight: FontWeight.w600)),
        const SizedBox(height: 12),
        if (invites.isEmpty)
          const _EmptyStateCard(
            title: 'Aucune invitation',
            subtitle: 'Tu n’as envoyé aucune invitation récemment.',
          )
        else
          Column(
            children: invites
                .take(4)
                .map((invite) => _InviteTile(invite: invite))
                .toList(),
          ),
      ],
    );
  }
}

class _MemberTile extends StatelessWidget {
  const _MemberTile({required this.member});

  final Map<String, dynamic> member;

  @override
  Widget build(BuildContext context) {
    String pickField(String key) => member[key]?.toString().trim() ?? '';
    final fullName = pickField('full_name');
    final displayName = pickField('display_name');
    final name = fullName.isNotEmpty ? fullName : displayName;
    final email = pickField('email');
    final role = pickField('role');
    final status = pickField('status');
    final initials = _buildInitials((name.isNotEmpty ? name : email).trim());

    return Row(
      children: [
        CircleAvatar(
          backgroundColor: AppColors.primary.withOpacity(0.15),
          child: Text(
            initials.isNotEmpty ? initials : '?',
            style: const TextStyle(fontWeight: FontWeight.w600),
          ),
        ),
        const SizedBox(width: 16),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                name.isNotEmpty ? name : email,
                style: Theme.of(context)
                    .textTheme
                    .bodyLarge
                    ?.copyWith(fontWeight: FontWeight.w600),
              ),
              Text(
                email,
                style: Theme.of(context)
                    .textTheme
                    .bodySmall
                    ?.copyWith(color: Colors.black54),
              ),
            ],
          ),
        ),
        Column(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            if (role.isNotEmpty)
              Text(
                role,
                style: const TextStyle(fontWeight: FontWeight.w600),
              ),
            if (status.isNotEmpty)
              Text(
                status,
                style: Theme.of(context)
                    .textTheme
                    .bodySmall
                    ?.copyWith(color: Colors.black54),
              ),
          ],
        )
      ],
    );
  }

  String _buildInitials(String value) {
    if (value.isEmpty) return '?';
    final parts = value.split(RegExp(r'\s+')).where((part) => part.isNotEmpty);
    final buffer = StringBuffer();
    for (final part in parts.take(2)) {
      final codeUnit = part.runes.isNotEmpty ? part.runes.first : null;
      if (codeUnit != null) {
        buffer.write(String.fromCharCode(codeUnit).toUpperCase());
      }
    }
    return buffer.isEmpty ? '?' : buffer.toString();
  }
}

class _CompanySection extends StatelessWidget {
  const _CompanySection({
    required this.membership,
    required this.onShowJournal,
  });

  final CompanyMembership membership;
  final _AsyncCallback onShowJournal;

  @override
  Widget build(BuildContext context) {
    final company = membership.company ?? const <String, dynamic>{};
    final companyName = company['name']?.toString() ?? 'Mon entreprise';
    final role = membership.role ?? 'membre';
    final legalName = company['legal_name']?.toString();
    final registration = company['registration_number']?.toString();
    final vat = company['vat_number']?.toString();
    final timezone = company['timezone']?.toString();
    final locale = company['locale']?.toString();
    final currency = company['currency']?.toString();
    final contactEmail = company['contact_email']?.toString();
    final phone = company['phone']?.toString();
    final website = company['website']?.toString();
    final address = company['address']?.toString();
    final region = company['region']?.toString();
    final fiscalYearStart = company['fiscal_year_start']?.toString();
    final createdAt = _formatDate(company['created_at']);

    final theme = Theme.of(context);
    final tags = <String>[
      if (timezone != null && timezone.isNotEmpty) 'TZ $timezone',
      if (currency != null && currency.isNotEmpty) 'Devise $currency',
      if (locale != null && locale.isNotEmpty) locale,
    ];

    Widget? buildInfoRow(IconData icon, String label, String? value) {
      if (value == null || value.isEmpty) return null;
      return _InfoRow(icon: icon, label: label, value: value);
    }

    final infoRows = [
      buildInfoRow(Icons.badge_outlined, 'Nom légal', legalName ?? companyName),
      buildInfoRow(Icons.confirmation_number, 'Enregistrement', registration),
      buildInfoRow(Icons.numbers, 'N° de TVA', vat),
      buildInfoRow(Icons.mail_outline, 'Contact', contactEmail),
      buildInfoRow(Icons.call, 'Téléphone', phone),
      buildInfoRow(Icons.public, 'Site web', website),
      buildInfoRow(Icons.location_city, 'Région', region),
      buildInfoRow(Icons.calendar_today, 'Début année fiscale', fiscalYearStart),
    ].whereType<Widget>().toList();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: AppColors.primary.withOpacity(0.08),
            borderRadius: BorderRadius.circular(16),
          ),
          child: Row(
            children: [
              const Icon(Icons.business_center_outlined, color: AppColors.primary),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      companyName,
                      style: theme.textTheme.titleMedium
                          ?.copyWith(fontWeight: FontWeight.w600),
                    ),
                    Text('Rôle : $role'),
                    if (createdAt != null)
                      Text('Depuis $createdAt',
                          style: theme.textTheme.bodySmall),
                  ],
                ),
              ),
              OutlinedButton.icon(
                onPressed: onShowJournal,
                icon: const Icon(Icons.history),
                label: const Text('Journal'),
              ),
            ],
          ),
        ),
        const SizedBox(height: 20),
        Text('Identifiants',
            style: theme.textTheme.titleSmall
                ?.copyWith(fontWeight: FontWeight.w600)),
        const SizedBox(height: 12),
        Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _InfoRow(
              icon: Icons.fingerprint,
              label: 'Entreprise ID',
              value: membership.companyId ?? '—',
            ),
            const SizedBox(height: 12),
            _InfoRow(
              icon: Icons.perm_identity,
              label: 'Membre ID',
              value: membership.id ?? '—',
            ),
          ],
        ),
        if (tags.isNotEmpty) ...[
          const SizedBox(height: 16),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: tags.map((tag) => _Pill(label: tag)).toList(),
          ),
        ],
        if (address != null && address.isNotEmpty) ...[
          const SizedBox(height: 16),
          _InfoRow(
            icon: Icons.location_on_outlined,
            label: 'Adresse',
            value: address,
          ),
        ],
        if (infoRows.isNotEmpty) ...[
          const SizedBox(height: 20),
          Text('Paramètres',
              style: theme.textTheme.titleSmall
                  ?.copyWith(fontWeight: FontWeight.w600)),
          const SizedBox(height: 12),
          Column(
            children: [
              for (var index = 0; index < infoRows.length; index++) ...[
                infoRows[index],
                if (index != infoRows.length - 1) const Divider(height: 20),
              ],
            ],
          ),
        ],
      ],
    );
  }
}

class _JoinCodeCard extends StatelessWidget {
  const _JoinCodeCard({
    required this.code,
    required this.onRevoke,
    this.onDelete,
  });

  final CompanyJoinCode code;
  final _AsyncValueChanged<CompanyJoinCode> onRevoke;
  final _AsyncValueChanged<CompanyJoinCode>? onDelete;

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
              child: Wrap(
                spacing: 8,
                children: [
                  if (!active && onDelete != null)
                    TextButton.icon(
                      onPressed: () => onDelete!(code),
                      icon: const Icon(Icons.delete_outline),
                      label: const Text('Supprimer'),
                      style: TextButton.styleFrom(
                        foregroundColor: Colors.red,
                      ),
                    ),
                  TextButton.icon(
                    onPressed: active
                        ? () {
                            onRevoke(code);
                          }
                        : null,
                    icon: const Icon(Icons.block),
                    label: const Text('Révoquer'),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _InviteTile extends StatelessWidget {
  const _InviteTile({required this.invite});

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

class _InfoRow extends StatelessWidget {
  const _InfoRow({
    required this.icon,
    required this.label,
    required this.value,
  });

  final IconData icon;
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, color: AppColors.primary),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                label,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: Colors.black54,
                ),
              ),
              Text(
                value,
                style: theme.textTheme.bodyLarge,
              ),
            ],
          ),
        ),
      ],
    );
  }
}
