part of 'company_gate.dart';

// ---------------------------------------------------------------------------
// More tab
// ---------------------------------------------------------------------------

enum _MoreSectionTab { profile, members, company }

class _MoreTab extends StatefulWidget {
  const _MoreTab({
    required this.membership,
    required this.members,
    required this.equipment,
    required this.joinCodes,
    required this.invites,
    required this.userProfile,
    required this.onRevokeCode,
    required this.onInviteMember,
    required this.onShowCompanyJournal,
    required this.onDeleteJoinCode,
    required this.onAssignEquipment,
    required this.onChangeMemberRole,
    required this.onRemoveMember,
    required this.onDeleteAccount,
    required this.isDeletingAccount,
  });

  final CompanyMembership membership;
  final List<Map<String, dynamic>> members;
  final List<Map<String, dynamic>> equipment;
  final List<CompanyJoinCode> joinCodes;
  final List<MembershipInvite> invites;
  final Map<String, dynamic>? userProfile;
  final _AsyncValueChanged<CompanyJoinCode> onRevokeCode;
  final _AsyncCallback onInviteMember;
  final _AsyncCallback onShowCompanyJournal;
  final _AsyncValueChanged<CompanyJoinCode> onDeleteJoinCode;
  final _AsyncValueChanged<Map<String, dynamic>> onAssignEquipment;
  final _AsyncValueChanged<Map<String, dynamic>> onChangeMemberRole;
  final _AsyncValueChanged<Map<String, dynamic>> onRemoveMember;
  final _AsyncCallback onDeleteAccount;
  final bool isDeletingAccount;

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
            onDeleteAccount: widget.onDeleteAccount,
            isDeletingAccount: widget.isDeletingAccount,
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
            membership: widget.membership,
            equipment: widget.equipment,
            joinCodes: widget.joinCodes,
            invites: widget.invites,
            onRevokeCode: widget.onRevokeCode,
            onDeleteCode: widget.onDeleteJoinCode,
            onAssignEquipment: widget.onAssignEquipment,
            onChangeRole: widget.onChangeMemberRole,
            onRemoveMember: widget.onRemoveMember,
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

class _ProfileSection extends StatefulWidget {
  const _ProfileSection({
    required this.membership,
    required this.userProfile,
    required this.onDeleteAccount,
    required this.isDeletingAccount,
  });

  final CompanyMembership membership;
  final Map<String, dynamic>? userProfile;
  final _AsyncCallback onDeleteAccount;
  final bool isDeletingAccount;

  @override
  State<_ProfileSection> createState() => _ProfileSectionState();
}

class _ProfileSectionState extends State<_ProfileSection> {
  Map<String, dynamic>? _localProfile;
  User? _authUser = Supa.i.auth.currentUser;
  bool _saving = false;

  String _pickField(String key, {bool allowEmailFallback = true}) {
    final source = _localProfile ?? widget.userProfile;
    final user = _authUser ?? Supa.i.auth.currentUser;
    final direct = source?[key]?.toString().trim();
    if (direct != null && direct.isNotEmpty) return direct;
    final meta = user?.userMetadata?[key]?.toString().trim();
    if (meta != null && meta.isNotEmpty) return meta;
    if (key == 'email' || allowEmailFallback) {
      final email = user?.email?.trim();
      if (email != null && email.isNotEmpty) return email;
    }
    return '';
  }

  Future<void> _editPersonalInfo(BuildContext context) async {
    final fullNameCtrl =
        TextEditingController(text: _pickField('full_name', allowEmailFallback: false));
    final phoneCtrl =
        TextEditingController(text: _pickField('phone', allowEmailFallback: false));
    final addressCtrl =
        TextEditingController(text: _pickField('address', allowEmailFallback: false));
    final formKey = GlobalKey<FormState>();

    final confirmed = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.white,
      builder: (context) => Padding(
        padding: EdgeInsets.only(
          left: 20,
          right: 20,
          top: 16,
          bottom: MediaQuery.of(context).viewInsets.bottom + 16,
        ),
        child: Form(
          key: formKey,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text(
                    'Infos personnelles',
                    style: TextStyle(fontWeight: FontWeight.w700, fontSize: 18),
                  ),
                  IconButton(
                    icon: const Icon(Icons.close),
                    onPressed: () => Navigator.of(context).pop(false),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: fullNameCtrl,
                decoration: const InputDecoration(labelText: 'Nom complet'),
                validator: (value) {
                  if (value == null || value.trim().isEmpty) {
                    return 'Nom requis';
                  }
                  return null;
                },
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: phoneCtrl,
                decoration:
                    const InputDecoration(labelText: 'Téléphone (optionnel)'),
                keyboardType: TextInputType.phone,
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: addressCtrl,
                readOnly: true,
                onTap: () async {
                  final selected = await _pickAddressFromSearch(context);
                  if (selected != null && mounted) {
                    setState(() => addressCtrl.text = selected);
                  }
                },
                decoration: InputDecoration(
                  labelText: 'Adresse (optionnel)',
                  suffixIcon: IconButton(
                    icon: const Icon(Icons.search),
                    tooltip: 'Rechercher une adresse',
                    onPressed: () async {
                      final selected = await _pickAddressFromSearch(context);
                      if (selected != null && mounted) {
                        setState(() => addressCtrl.text = selected);
                      }
                    },
                  ),
                ),
                keyboardType: TextInputType.streetAddress,
              ),
              const SizedBox(height: 16),
              SizedBox(
                width: double.infinity,
                child: FilledButton(
                  onPressed: () {
                    if (formKey.currentState?.validate() != true) return;
                    Navigator.of(context).pop(true);
                  },
                  child: const Text('Enregistrer'),
                ),
              ),
            ],
          ),
        ),
      ),
    );

    if (confirmed != true) return;

    final fullName = fullNameCtrl.text.trim();
    final phone = phoneCtrl.text.trim();
    final address = addressCtrl.text.trim();

    setState(() => _saving = true);
    try {
      final response = await Supa.i.auth.updateUser(
        UserAttributes(
          data: {
            'full_name': fullName,
            'phone': phone.isEmpty ? null : phone,
            'address': address.isEmpty ? null : address,
          },
        ),
      );
      _authUser = response.user ?? _authUser;
      _localProfile = {
        ...(widget.userProfile ?? const {}),
        'full_name': fullName,
        if (phone.isNotEmpty) 'phone': phone,
        if (address.isNotEmpty) 'address': address,
      };
      if (mounted) {
        setState(() => _saving = false);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Infos personnelles mises à jour.')),
        );
      }
    } catch (e) {
      if (mounted) {
        setState(() => _saving = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Erreur lors de la mise à jour: $e'),
            backgroundColor: Theme.of(context).colorScheme.error,
          ),
        );
      }
    }
  }

  Future<String?> _pickAddressFromSearch(BuildContext context) async {
    final queryCtrl = TextEditingController();
    List<dynamic> predictions = const [];
    bool loading = false;
    Timer? debounce;
    return showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.white,
      builder: (sheetContext) {
        return StatefulBuilder(
          builder: (ctx, setSheetState) => Padding(
            padding: EdgeInsets.only(
              left: 20,
              right: 20,
              top: 16,
              bottom: MediaQuery.of(ctx).viewInsets.bottom + 16,
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Text(
                      'Rechercher une adresse',
                      style:
                          TextStyle(fontWeight: FontWeight.w700, fontSize: 18),
                    ),
                    IconButton(
                      icon: const Icon(Icons.close),
                      onPressed: () => Navigator.of(ctx).pop(),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: queryCtrl,
                  decoration: const InputDecoration(
                    labelText: 'Adresse',
                    hintText: 'Ex: 123 rue Principale, Montréal',
                  ),
                  textInputAction: TextInputAction.search,
                  onChanged: (value) {
                    debounce?.cancel();
                    debounce = Timer(const Duration(milliseconds: 350), () {
                      _performSearch(
                        ctx,
                        value.trim(),
                        setSheetState,
                        (items) => predictions = items,
                        (state) => loading = state,
                      );
                    });
                  },
                ),
                const SizedBox(height: 12),
                if (loading)
                  const Padding(
                    padding: EdgeInsets.symmetric(vertical: 8.0),
                    child: Center(child: CircularProgressIndicator(strokeWidth: 2)),
                  ),
                if (predictions.isNotEmpty)
                  ...predictions.map((p) {
                    final desc = p['description']?.toString() ?? '';
                    return ListTile(
                      title: Text(desc),
                      onTap: () => Navigator.of(ctx).pop(desc),
                    );
                  }),
              ],
            ),
          ),
        );
      },
    );
  }

  Future<void> _performSearch(
    BuildContext context,
    String query,
    void Function(void Function()) setSheetState,
    void Function(List<dynamic>) setPredictions,
    void Function(bool) setLoading,
  ) async {
    if (query.isEmpty) return;
    setSheetState(() {
      setLoading(true);
      setPredictions(const []);
    });
    try {
      final response = await Supa.i.functions.invoke(
        'google-places-autocomplete',
        body: {'query': query},
      );
      final data = response.data;
      if (data is List) {
        setSheetState(() {
          setPredictions(data);
        });
      } else if (data is Map && data['predictions'] is List) {
        setSheetState(() {
          setPredictions(List<dynamic>.from(data['predictions'] as List));
        });
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Erreur de recherche: $e'),
            backgroundColor: Theme.of(context).colorScheme.error,
          ),
        );
      }
    } finally {
      setSheetState(() {
        setLoading(false);
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final name = _pickField('full_name').isNotEmpty
        ? _pickField('full_name')
        : _pickField('display_name');
    final email = _pickField('email');
    final role = widget.membership.role ?? 'membre';
    final company = widget.membership.company?['name']?.toString() ?? '';
    final initials = _buildInitials((name.isNotEmpty ? name : email).trim());

    final profileFields = [
      if (company.isNotEmpty)
        _InfoRow(icon: Icons.business, label: 'Entreprise', value: company),
      _InfoRow(icon: Icons.mail, label: 'Courriel', value: email),
      if (_pickField('phone').isNotEmpty)
        _InfoRow(icon: Icons.phone, label: 'Téléphone', value: _pickField('phone')),
      if (_pickField('address').isNotEmpty)
        _InfoRow(icon: Icons.home_outlined, label: 'Adresse', value: _pickField('address')),
    ];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            CircleAvatar(
              radius: 28,
              backgroundColor: AppColors.primary.withValues(alpha: 0.15),
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
        Wrap(
          spacing: 12,
          runSpacing: 8,
          children: [
            OutlinedButton.icon(
              onPressed: _saving ? null : () => _editPersonalInfo(context),
              icon: const Icon(Icons.badge_outlined),
              label: Text(_saving ? 'Enregistrement...' : 'Infos personnelles'),
            ),
            OutlinedButton.icon(
              onPressed: () {
                Navigator.of(context).push(
                  MaterialPageRoute(
                    builder: (_) => const NotificationSettingsPage(),
                  ),
                );
              },
              icon: const Icon(Icons.notifications_outlined),
              label: const Text('Paramètres de notifications'),
            ),
          ],
        ),
        const SizedBox(height: 16),
        Column(
          children: [
            for (var index = 0; index < profileFields.length; index++) ...[
              profileFields[index],
              if (index != profileFields.length - 1) const Divider(height: 20),
            ],
          ],
        ),
        const SizedBox(height: 24),
        Text(
          'Tu peux supprimer ton compte et tes données personnelles à tout moment.',
          style: Theme.of(context)
              .textTheme
              .bodySmall
              ?.copyWith(color: Colors.black54),
        ),
        const SizedBox(height: 8),
        // Guideline 5.1.1(v): allow account deletion directly in the app.
        FilledButton(
          style: FilledButton.styleFrom(
            backgroundColor: Colors.red.shade50,
            foregroundColor: Colors.red.shade800,
          ),
          onPressed: widget.isDeletingAccount ? null : widget.onDeleteAccount,
          child: widget.isDeletingAccount
              ? const SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Text('Supprimer mon compte'),
        ),
      ],
    );
  }

  String _buildInitials(String value) {
    if (value.isEmpty) return '?';
    final parts = value.split(RegExp(r'\\s+')).where((part) => part.isNotEmpty);
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
    required this.membership,
    required this.equipment,
    required this.joinCodes,
    required this.invites,
    required this.onRevokeCode,
    required this.onDeleteCode,
    required this.onAssignEquipment,
    required this.onChangeRole,
    required this.onRemoveMember,
  });

  final List<Map<String, dynamic>> members;
  final CompanyMembership membership;
  final List<Map<String, dynamic>> equipment;
  final List<CompanyJoinCode> joinCodes;
  final List<MembershipInvite> invites;
  final _AsyncValueChanged<CompanyJoinCode> onRevokeCode;
  final _AsyncValueChanged<CompanyJoinCode> onDeleteCode;
  final _AsyncValueChanged<Map<String, dynamic>> onAssignEquipment;
  final _AsyncValueChanged<Map<String, dynamic>> onChangeRole;
  final _AsyncValueChanged<Map<String, dynamic>> onRemoveMember;

  @override
  Widget build(BuildContext context) {
    final assignments = <String, List<Map<String, dynamic>>>{};
    for (final item in equipment) {
      final assignedUid = _equipmentAssignedUserId(item);
      if (assignedUid == null) continue;
      assignments
          .putIfAbsent(assignedUid, () => <Map<String, dynamic>>[])
          .add(item);
    }
    final sortedMembers = members.toList()
      ..sort(
        (a, b) => _memberDisplayName(a)
            .toLowerCase()
            .compareTo(_memberDisplayName(b).toLowerCase()),
      );
    final role = companyRoleFromString(membership.role);
    final canManageMembers = role.canManageMembers;
    final canManageRoles = role.assignableRoles.isNotEmpty;

    final memberList = sortedMembers.isEmpty
        ? const _EmptyStateCard(
            title: 'Aucun membre',
            subtitle: 'Invite tes collègues pour collaborer.',
          )
        : Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              for (var index = 0; index < sortedMembers.length; index++) ...[
                _MemberTile(
                  member: sortedMembers[index],
                  assignedEquipment: assignments[
                          sortedMembers[index]['user_uid']?.toString()] ??
                      const <Map<String, dynamic>>[],
                  onAssignEquipment: canManageMembers
                      ? () => onAssignEquipment(sortedMembers[index])
                      : null,
                  onChangeRole: canManageRoles
                      ? () => onChangeRole(sortedMembers[index])
                      : null,
                  onRemoveMember: canManageMembers
                      ? () => onRemoveMember(sortedMembers[index])
                      : null,
                ),
                if (index != sortedMembers.length - 1)
                  const Divider(height: 24),
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

enum _MemberTileAction { assignEquipment, changeRole, remove }

class _MemberTile extends StatelessWidget {
  const _MemberTile({
    required this.member,
    required this.assignedEquipment,
    this.onAssignEquipment,
    this.onChangeRole,
    this.onRemoveMember,
  });

  final Map<String, dynamic> member;
  final List<Map<String, dynamic>> assignedEquipment;
  final VoidCallback? onAssignEquipment;
  final VoidCallback? onChangeRole;
  final VoidCallback? onRemoveMember;

  bool get _hasActions =>
      onAssignEquipment != null ||
      onChangeRole != null ||
      onRemoveMember != null;

  @override
  Widget build(BuildContext context) {
    final name = _memberDisplayName(member);
    final email = _memberEmail(member);
    final role = member['role']?.toString().trim() ?? '';
    final status = member['status']?.toString().trim() ?? '';
    final initials = _buildInitials((name.isNotEmpty ? name : email).trim());
    final assignedNames = assignedEquipment
        .map((item) => item['name']?.toString().trim() ?? '')
        .where((label) => label.isNotEmpty)
        .toList();
    final displayAssignments = assignedNames.take(3).toList();
    final extraAssignments = assignedNames.length - displayAssignments.length;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            CircleAvatar(
              backgroundColor: AppColors.primary.withValues(alpha: 0.15),
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
                  if (email.isNotEmpty)
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
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (role.isNotEmpty)
                      Text(
                        role,
                        style: const TextStyle(fontWeight: FontWeight.w600),
                      ),
                    if (_hasActions)
                      PopupMenuButton<_MemberTileAction>(
                        icon: const Icon(Icons.more_vert),
                        onSelected: (action) {
                          switch (action) {
                            case _MemberTileAction.assignEquipment:
                              onAssignEquipment?.call();
                              break;
                            case _MemberTileAction.changeRole:
                              onChangeRole?.call();
                              break;
                            case _MemberTileAction.remove:
                              onRemoveMember?.call();
                              break;
                          }
                        },
                        itemBuilder: (context) => [
                          if (onAssignEquipment != null)
                            const PopupMenuItem<_MemberTileAction>(
                              value: _MemberTileAction.assignEquipment,
                              child: Text('Attribuer un équipement'),
                            ),
                          if (onChangeRole != null)
                            const PopupMenuItem<_MemberTileAction>(
                              value: _MemberTileAction.changeRole,
                              child: Text('Changer le rôle'),
                            ),
                          if (onRemoveMember != null)
                            PopupMenuItem<_MemberTileAction>(
                              value: _MemberTileAction.remove,
                              child: Text(
                                'Retirer',
                                style: TextStyle(color: Colors.red.shade700),
                              ),
                            ),
                        ],
                      ),
                  ],
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
            ),
          ],
        ),
        if (displayAssignments.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(top: 8, left: 56),
            child: Wrap(
              spacing: 8,
              runSpacing: 4,
              children: [
                for (final label in displayAssignments)
                  _AssignmentChip(label: label),
                if (extraAssignments > 0)
                  _AssignmentChip(label: '+$extraAssignments autre(s)'),
              ],
            ),
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

class _AssignmentChip extends StatelessWidget {
  const _AssignmentChip({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: AppColors.primary.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Text(
        label,
        style: const TextStyle(fontWeight: FontWeight.w600),
      ),
    );
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
      buildInfoRow(
          Icons.calendar_today, 'Début année fiscale', fiscalYearStart),
    ].whereType<Widget>().toList();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: AppColors.primary.withValues(alpha: 0.08),
            borderRadius: BorderRadius.circular(16),
          ),
          child: Row(
            children: [
              const Icon(Icons.business_center_outlined,
                  color: AppColors.primary),
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
              trailing: IconButton(
                icon: const Icon(Icons.copy_outlined),
                tooltip: 'Copier l\'ID',
                onPressed: () => Clipboard.setData(
                    ClipboardData(text: membership.companyId ?? '')),
              ),
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
    this.trailing,
  });

  final IconData icon;
  final String label;
  final String value;
  final Widget? trailing;

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
        if (trailing != null) trailing!,
      ],
    );
  }
}
