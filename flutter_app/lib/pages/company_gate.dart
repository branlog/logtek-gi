import 'dart:async';

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../models/company_join_code.dart';
import '../models/membership_invite.dart';
import '../services/company_commands.dart';
import '../services/company_repository.dart';
import '../services/connectivity_service.dart';
import '../services/supabase_service.dart';
import '../theme/app_colors.dart';

class CompanyGatePage extends StatefulWidget {
  const CompanyGatePage({super.key});

  @override
  State<CompanyGatePage> createState() => _CompanyGatePageState();
}

enum _GateTab { home, list, inventory, equipment, more }

class _CompanyGatePageState extends State<CompanyGatePage> {
  late final CompanyRepository _repository;
  late final CompanyCommands _commands;

  StreamSubscription<bool>? _connectivitySub;
  bool _isOnline = true;
  bool _isLoading = true;
  bool _isRefreshing = false;
  String? _fatalError;
  String? _transientError;

  _GateTab _currentTab = _GateTab.home;

  CompanyOverview? _overview;
  List<Map<String, dynamic>> _warehouses = const <Map<String, dynamic>>[];
  List<InventoryEntry> _inventory = const <InventoryEntry>[];
  List<Map<String, dynamic>> _equipment = const <Map<String, dynamic>>[];
  List<Map<String, dynamic>> _purchaseRequests = const <Map<String, dynamic>>[];
  List<CompanyJoinCode> _joinCodes = const <CompanyJoinCode>[];
  List<MembershipInvite> _invites = const <MembershipInvite>[];
  Map<String, dynamic>? _userProfile;
  List<String> _missingTables = const <String>[];

  final TextEditingController _companyNameCtrl = TextEditingController();
  final TextEditingController _joinCodeCtrl = TextEditingController();
  bool _creatingCompany = false;
  bool _joiningCompany = false;

  @override
  void initState() {
    super.initState();
    _repository = CompanyRepository(Supa.i);
    _commands = CompanyCommands(Supa.i);
    _isOnline = ConnectivityService.instance.isOnline;
    _connectivitySub =
        ConnectivityService.instance.onStatusChange.listen((online) {
      if (!mounted) return;
      setState(() => _isOnline = online);
    });
    _refreshAll();
  }

  @override
  void dispose() {
    _connectivitySub?.cancel();
    _companyNameCtrl.dispose();
    _joinCodeCtrl.dispose();
    super.dispose();
  }

  Future<void> _refreshAll() async {
    if (_isRefreshing) return;
    setState(() {
      _isRefreshing = true;
      _fatalError = null;
      _transientError = null;
    });

    try {
      final overviewResult = await _repository.fetchCompanyOverview();
      final membership = overviewResult.data.membership;
      final missing = <String>{...overviewResult.missingTables};
      String? errorText = _describeError(overviewResult.error);

      List<Map<String, dynamic>> warehouses = const <Map<String, dynamic>>[];
      List<InventoryEntry> inventory = const <InventoryEntry>[];
      List<Map<String, dynamic>> equipment = const <Map<String, dynamic>>[];
      List<Map<String, dynamic>> purchaseRequests =
          const <Map<String, dynamic>>[];
      List<CompanyJoinCode> joinCodes = const <CompanyJoinCode>[];
      List<MembershipInvite> invites = const <MembershipInvite>[];
      Map<String, dynamic>? profile;

      if (membership?.companyId != null) {
        final companyId = membership!.companyId!;

        final warehousesResult = await _repository.fetchWarehouses();
        warehouses = warehousesResult.data;
        missing.addAll(warehousesResult.missingTables);
        errorText ??= _describeError(warehousesResult.error);

        final inventoryResult = await _repository.fetchInventory();
        inventory = inventoryResult.data;
        missing.addAll(inventoryResult.missingTables);
        errorText ??= _describeError(inventoryResult.error);

        final equipmentResult = await _repository.fetchEquipment();
        equipment = equipmentResult.data;
        missing.addAll(equipmentResult.missingTables);
        errorText ??= _describeError(equipmentResult.error);

        final requestsResult = await _repository.fetchPurchaseRequests();
        purchaseRequests = requestsResult.data;
        missing.addAll(requestsResult.missingTables);
        errorText ??= _describeError(requestsResult.error);

        final joinCodeResult =
            await _repository.fetchJoinCodes(companyId: companyId);
        joinCodes = joinCodeResult.data;
        missing.addAll(joinCodeResult.missingTables);
        errorText ??= _describeError(joinCodeResult.error);

        final inviteResult = await _repository.fetchMembershipInvites(
          companyId: companyId,
        );
        invites = inviteResult.data;
        missing.addAll(inviteResult.missingTables);
        errorText ??= _describeError(inviteResult.error);

        final profileResult = await _repository.fetchUserProfile();
        profile = profileResult.data;
        missing.addAll(profileResult.missingTables);
        errorText ??= _describeError(profileResult.error);
      }

      if (!mounted) return;
      setState(() {
        _overview = overviewResult.data;
        _warehouses = warehouses;
        _inventory = inventory;
        _equipment = equipment;
        _purchaseRequests = purchaseRequests;
        _joinCodes = joinCodes;
        _invites = invites;
        _userProfile = profile;
        _missingTables = missing.toList();
        _transientError = errorText;
        _isLoading = false;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _fatalError = 'Impossible de charger les données : $error';
        _isLoading = false;
      });
    } finally {
      if (mounted) {
        setState(() => _isRefreshing = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return const Scaffold(
        body: Center(child: CircularProgressIndicator()),
      );
    }

    if (_fatalError != null) {
      return Scaffold(
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  _fatalError!,
                  style: Theme.of(context).textTheme.bodyLarge,
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 16),
                FilledButton.icon(
                  onPressed: _refreshAll,
                  icon: const Icon(Icons.refresh),
                  label: const Text('Réessayer'),
                ),
              ],
            ),
          ),
        ),
      );
    }

    final membership = _overview?.membership;
    if (membership == null || membership.companyId == null) {
      return _OnboardingView(
        creatingCompany: _creatingCompany,
        joiningCompany: _joiningCompany,
        companyNameCtrl: _companyNameCtrl,
        joinCodeCtrl: _joinCodeCtrl,
        onCreateCompany: _createCompany,
        onJoinCompany: _joinCompany,
        onRefresh: _refreshAll,
        isOnline: _isOnline,
        missingTables: _missingTables,
        transientError: _transientError,
      );
    }

    final body = _buildTabContent(membership);

    return Scaffold(
      backgroundColor: AppColors.surface,
      body: SafeArea(child: body),
      bottomNavigationBar: NavigationBar(
        backgroundColor: AppColors.surface,
        height: 68,
        selectedIndex: _currentTab.index,
        onDestinationSelected: (value) {
          setState(() => _currentTab = _GateTab.values[value]);
        },
        destinations: const [
          NavigationDestination(
            icon: Icon(Icons.home_outlined),
            selectedIcon: Icon(Icons.home),
            label: 'Accueil',
          ),
          NavigationDestination(
            icon: Icon(Icons.list_alt),
            selectedIcon: Icon(Icons.list),
            label: 'Liste',
          ),
          NavigationDestination(
            icon: Icon(Icons.inventory_2_outlined),
            selectedIcon: Icon(Icons.inventory_2),
            label: 'Inventaire',
          ),
          NavigationDestination(
            icon: Icon(Icons.build_outlined),
            selectedIcon: Icon(Icons.build),
            label: 'Équipement',
          ),
          NavigationDestination(
            icon: Icon(Icons.more_horiz),
            selectedIcon: Icon(Icons.more),
            label: 'Plus',
          ),
        ],
      ),
    );
  }

  Widget _buildTabContent(CompanyMembership membership) {
    final header = _HeaderBar(
      title: _tabTitle(_currentTab),
      companyName: membership.company?['name']?.toString() ?? 'Entreprise',
      showCalendar: _currentTab == _GateTab.list || _currentTab == _GateTab.more,
    );

    final banners = <Widget>[];
    if (!_isOnline) {
      banners.add(_StatusBanner.warning(
        icon: Icons.wifi_off,
        message: 'Mode hors ligne : les données peuvent être périmées.',
      ));
    }
    if (_missingTables.isNotEmpty) {
      banners.add(_StatusBanner.warning(
        icon: Icons.dataset_linked,
        message:
            'Tables manquantes : ${_missingTables.join(', ')}. Vérifie les migrations.',
      ));
    }
    if (_transientError != null) {
      banners.add(_StatusBanner.error(_transientError!));
    }

    final content = _buildCurrentTabBody(membership);

    return RefreshIndicator(
      onRefresh: _refreshAll,
      child: CustomScrollView(
        physics: const AlwaysScrollableScrollPhysics(),
        slivers: [
          SliverToBoxAdapter(child: header),
          if (banners.isNotEmpty)
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20),
                child: Column(
                  children: [
                    for (final banner in banners) ...[
                      banner,
                      const SizedBox(height: 12),
                    ],
                  ],
                ),
              ),
            ),
          SliverToBoxAdapter(child: content),
          const SliverPadding(padding: EdgeInsets.only(bottom: 90)),
        ],
      ),
    );
  }

  Widget _buildCurrentTabBody(CompanyMembership membership) {
    switch (_currentTab) {
      case _GateTab.home:
        return _HomeTab(
          overview: _overview,
          warehouses: _warehouses,
          inventory: _inventory,
          equipment: _equipment,
          userProfile: _userProfile,
          onQuickAction: _handleQuickAction,
        );
      case _GateTab.list:
        return _ListTab(
          requests: _purchaseRequests,
          onAddRequest: () => _showSnack('Fonction bientôt disponible.'),
          onReviewInventory: () => setState(() => _currentTab = _GateTab.inventory),
        );
      case _GateTab.inventory:
        return _InventoryTab(
          warehouses: _warehouses,
          inventory: _inventory,
          onCreateWarehouse: _promptCreateWarehouse,
        );
      case _GateTab.equipment:
        return _EquipmentTab(
          equipment: _equipment,
          onCreateEquipment: () => _showSnack('Création d’équipement à venir.'),
        );
      case _GateTab.more:
        return _MoreTab(
          membership: membership,
          members: _overview?.members ?? const <Map<String, dynamic>>[],
          joinCodes: _joinCodes,
          invites: _invites,
          userProfile: _userProfile,
          onRevokeCode: _handleRevokeJoinCode,
          onInviteMember: () => _showSnack('Invitations à venir.'),
        );
    }
  }

  String _tabTitle(_GateTab tab) {
    switch (tab) {
      case _GateTab.home:
        return 'Accueil';
      case _GateTab.list:
        return 'Liste';
      case _GateTab.inventory:
        return 'Inventaire';
      case _GateTab.equipment:
        return 'Équipement';
      case _GateTab.more:
        return 'Plus';
    }
  }

  Future<void> _createCompany() async {
    if (_creatingCompany) return;
    final name = _companyNameCtrl.text.trim();
    if (name.isEmpty) {
      _showSnack('Nom de l’entreprise requis.', error: true);
      return;
    }

    setState(() => _creatingCompany = true);
    final result = await _commands.createCompany(name: name);
    if (!mounted) return;
    setState(() => _creatingCompany = false);

    if (!result.ok) {
      _showSnack(
        _describeError(result.error) ?? 'Création impossible.',
        error: true,
      );
      return;
    }

    _companyNameCtrl.clear();
    _showSnack('Entreprise créée.');
    await _refreshAll();
  }

  Future<void> _joinCompany() async {
    if (_joiningCompany) return;
    final code = _joinCodeCtrl.text.trim();
    if (code.isEmpty) {
      _showSnack('Code requis.', error: true);
      return;
    }

    setState(() => _joiningCompany = true);
    final result = await _commands.joinCompanyWithCode(code: code);
    if (!mounted) return;
    setState(() => _joiningCompany = false);

    if (!result.ok) {
      _showSnack(
        _describeError(result.error) ?? 'Code invalide.',
        error: true,
      );
      return;
    }

    _joinCodeCtrl.clear();
    _showSnack('Bienvenue !');
    await _refreshAll();
  }

  Future<void> _promptCreateWarehouse() async {
    final membership = _overview?.membership;
    final companyId = membership?.companyId;
    if (companyId == null) return;

    final formKey = GlobalKey<FormState>();
    final nameCtrl = TextEditingController();
    final codeCtrl = TextEditingController();
    String? dialogError;
    var submitting = false;

    await showDialog<void>(
      context: context,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            Future<void> submit() async {
              if (!formKey.currentState!.validate()) return;
              setDialogState(() {
                submitting = true;
                dialogError = null;
              });

              final result = await _commands.createWarehouse(
                companyId: companyId,
                name: nameCtrl.text.trim(),
                code: codeCtrl.text.trim().isEmpty
                    ? null
                    : codeCtrl.text.trim(),
              );

              if (!mounted) return;

              if (!result.ok) {
                setDialogState(() {
                  submitting = false;
                  dialogError =
                      _describeError(result.error) ?? 'Erreur inconnue.';
                });
                return;
              }

              Navigator.of(context).pop();
              _showSnack('Entrepôt créé.');
              await _refreshAll();
            }

            return AlertDialog(
              title: const Text('Nouvel entrepôt'),
              content: Form(
                key: formKey,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    TextFormField(
                      controller: nameCtrl,
                      decoration: const InputDecoration(labelText: 'Nom'),
                      validator: (value) {
                        if (value == null || value.trim().isEmpty) {
                          return 'Nom requis';
                        }
                        return null;
                      },
                    ),
                    const SizedBox(height: 12),
                    TextFormField(
                      controller: codeCtrl,
                      decoration:
                          const InputDecoration(labelText: 'Code (optionnel)'),
                    ),
                    if (dialogError != null) ...[
                      const SizedBox(height: 12),
                      Text(
                        dialogError!,
                        style: TextStyle(color: Colors.red.shade700),
                      ),
                    ],
                  ],
                ),
              ),
              actions: [
                TextButton(
                  onPressed: submitting ? null : () => Navigator.pop(context),
                  child: const Text('Annuler'),
                ),
                FilledButton(
                  onPressed: submitting ? null : submit,
                  child: submitting
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Text('Créer'),
                ),
              ],
            );
          },
        );
      },
    );

    nameCtrl.dispose();
    codeCtrl.dispose();
  }

  Future<void> _handleRevokeJoinCode(CompanyJoinCode code) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text('Révoquer le code ?'),
          content: Text('Voulez-vous révoquer le code ${code.codeHint}?'),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: const Text('Annuler'),
            ),
            FilledButton(
              onPressed: () => Navigator.of(context).pop(true),
              child: const Text('Révoquer'),
            ),
          ],
        );
      },
    );

    if (confirm != true) return;
    final result = await _commands.revokeJoinCode(codeId: code.id);
    if (!result.ok) {
      _showSnack(
        _describeError(result.error) ?? 'Impossible de révoquer ce code.',
        error: true,
      );
      return;
    }
    _showSnack('Code révoqué.');
    await _refreshAll();
  }

  void _handleQuickAction(_QuickAction action) {
    switch (action) {
      case _QuickAction.newItem:
      case _QuickAction.newEquipment:
      case _QuickAction.members:
        _showSnack('Action bientôt disponible.');
        break;
      case _QuickAction.newWarehouse:
        _promptCreateWarehouse();
        break;
      case _QuickAction.viewInventory:
        setState(() => _currentTab = _GateTab.inventory);
        break;
    }
  }

  void _showSnack(String message, {bool error = false}) {
    if (!mounted) return;
    final theme = Theme.of(context);
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor:
            error ? theme.colorScheme.error : theme.colorScheme.primary,
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  String? _describeError(Object? error) {
    if (error == null) return null;
    return error.toString();
  }
}

// ---------------------------------------------------------------------------
// UI widgets
// ---------------------------------------------------------------------------

class _HeaderBar extends StatelessWidget {
  const _HeaderBar({
    required this.title,
    required this.companyName,
    this.showCalendar = false,
  });

  final String title;
  final String companyName;
  final bool showCalendar;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 20, 20, 12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          SizedBox(
            width: 48,
            height: 48,
            child: Image.asset(
              'assets/images/logtek_logo.png',
              fit: BoxFit.contain,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: Theme.of(context).textTheme.headlineSmall,
                ),
                Text(
                  companyName,
                  style: Theme.of(context)
                      .textTheme
                      .bodyLarge
                      ?.copyWith(color: Colors.black54),
                ),
              ],
            ),
          ),
          IconButton(
            icon: const Icon(Icons.search),
            onPressed: () => ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text('Recherche à venir.')),
            ),
          ),
          IconButton(
            icon:
                Icon(showCalendar ? Icons.calendar_month : Icons.notifications_none),
            onPressed: () => ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text('Fonctionnalité à venir.')),
            ),
          ),
        ],
      ),
    );
  }
}

class _StatusBanner extends StatelessWidget {
  const _StatusBanner._(this.color, this.icon, this.message);

  factory _StatusBanner.warning({required IconData icon, required String message}) {
    return _StatusBanner._(const Color(0xFFFFF1DC), icon, message);
  }

  factory _StatusBanner.error(String message) {
    return _StatusBanner._(const Color(0xFFFFE2E1), Icons.error_outline, message);
  }

  final Color color;
  final IconData icon;
  final String message;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Row(
        children: [
          Icon(icon, color: Colors.black87),
          const SizedBox(width: 12),
          Expanded(child: Text(message)),
        ],
      ),
    );
  }
}

class _OnboardingView extends StatelessWidget {
  const _OnboardingView({
    required this.creatingCompany,
    required this.joiningCompany,
    required this.companyNameCtrl,
    required this.joinCodeCtrl,
    required this.onCreateCompany,
    required this.onJoinCompany,
    required this.onRefresh,
    required this.isOnline,
    required this.missingTables,
    required this.transientError,
  });

  final bool creatingCompany;
  final bool joiningCompany;
  final TextEditingController companyNameCtrl;
  final TextEditingController joinCodeCtrl;
  final VoidCallback onCreateCompany;
  final VoidCallback onJoinCompany;
  final Future<void> Function() onRefresh;
  final bool isOnline;
  final List<String> missingTables;
  final String? transientError;

  @override
  Widget build(BuildContext context) {
    final banners = <Widget>[];
    if (!isOnline) {
      banners.add(_StatusBanner.warning(
        icon: Icons.wifi_off,
        message: 'Connexion perdue. Certaines actions seront indisponibles.',
      ));
    }
    if (missingTables.isNotEmpty) {
      banners.add(_StatusBanner.warning(
        icon: Icons.dataset_linked,
        message: 'Tables manquantes : ${missingTables.join(', ')}',
      ));
    }
    if (transientError != null) {
      banners.add(_StatusBanner.error(transientError!));
    }

    return Scaffold(
      backgroundColor: AppColors.surface,
      body: SafeArea(
        child: RefreshIndicator(
          onRefresh: onRefresh,
          child: ListView(
            padding: const EdgeInsets.all(24),
            children: [
              Center(
                child: Image.asset('assets/images/logtek_logo.png', height: 64),
              ),
              const SizedBox(height: 24),
              Text(
                'Bienvenue chez Logtek G&I',
                style: Theme.of(context).textTheme.headlineSmall,
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 8),
              const Text(
                'Crée une entreprise ou rejoins celle de ton équipe pour continuer.',
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 20),
              if (banners.isNotEmpty)
                Column(
                  children: [
                    for (final banner in banners) ...[
                      banner,
                      const SizedBox(height: 12),
                    ],
                  ],
                ),
              const SizedBox(height: 12),
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(20),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Text('Créer une entreprise',
                          style: Theme.of(context).textTheme.titleLarge),
                      const SizedBox(height: 12),
                      TextField(
                        controller: companyNameCtrl,
                        decoration: const InputDecoration(
                          labelText: 'Nom de l’entreprise',
                        ),
                      ),
                      const SizedBox(height: 16),
                      FilledButton.icon(
                        onPressed: creatingCompany ? null : onCreateCompany,
                        icon: creatingCompany
                            ? const SizedBox(
                                width: 16,
                                height: 16,
                                child: CircularProgressIndicator(strokeWidth: 2),
                              )
                            : const Icon(Icons.factory),
                        label: const Text('Créer'),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 16),
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(20),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Text('Rejoindre une entreprise',
                          style: Theme.of(context).textTheme.titleLarge),
                      const SizedBox(height: 12),
                      TextField(
                        controller: joinCodeCtrl,
                        textCapitalization: TextCapitalization.characters,
                        decoration: const InputDecoration(
                          labelText: 'Code d’accès',
                        ),
                      ),
                      const SizedBox(height: 16),
                      OutlinedButton.icon(
                        onPressed: joiningCompany ? null : onJoinCompany,
                        icon: joiningCompany
                            ? const SizedBox(
                                width: 16,
                                height: 16,
                                child: CircularProgressIndicator(strokeWidth: 2),
                              )
                            : const Icon(Icons.qr_code_2),
                        label: const Text('Rejoindre'),
                      ),
                    ],
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

// ---------------------------------------------------------------------------
// Home tab
// ---------------------------------------------------------------------------

enum _QuickAction {
  newItem,
  newWarehouse,
  viewInventory,
  newEquipment,
  members,
}

class _HomeTab extends StatelessWidget {
  const _HomeTab({
    required this.overview,
    required this.warehouses,
    required this.inventory,
    required this.equipment,
    required this.userProfile,
    required this.onQuickAction,
  });

  final CompanyOverview? overview;
  final List<Map<String, dynamic>> warehouses;
  final List<InventoryEntry> inventory;
  final List<Map<String, dynamic>> equipment;
  final Map<String, dynamic>? userProfile;
  final void Function(_QuickAction action) onQuickAction;

  @override
  Widget build(BuildContext context) {
    final user = Supabase.instance.client.auth.currentUser;
    final firstName = (userProfile?['first_name'] as String?)?.trim();
    final greetingName = firstName?.isNotEmpty == true
        ? firstName!
        : user?.email?.split('@').first ?? 'Utilisateur';

    final memberCount = overview?.members.length ?? 0;
    final warehouseCount = warehouses.length;
    final itemCount = inventory.length;
    final totalStock = inventory.fold<int>(0, (acc, entry) => acc + entry.totalQty);

    final quickActions = <(_QuickAction, String, IconData)>[
      (_QuickAction.newItem, 'Nouvel article', Icons.add_box_outlined),
      (_QuickAction.newWarehouse, 'Nouvel entrepôt', Icons.store_mall_directory),
      (_QuickAction.viewInventory, 'Voir inventaire', Icons.inventory_2),
      (_QuickAction.newEquipment, 'Nouvel équipement', Icons.build),
      (_QuickAction.members, 'Paramètres & membres', Icons.group_outlined),
    ];

    final topItems = inventory.take(3).toList();

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text('Bonjour $greetingName',
              style: Theme.of(context).textTheme.headlineSmall),
          const SizedBox(height: 4),
          Text(
            'Bienvenue chez ${overview?.membership?.company?['name'] ?? 'Logtek'}',
            style: Theme.of(context).textTheme.bodyLarge,
          ),
          const SizedBox(height: 24),
          Text('Aperçu rapide',
              style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 12),
          Wrap(
            runSpacing: 12,
            spacing: 12,
            children: [
              _MetricCard(
                icon: Icons.person_outline,
                label: 'Membres',
                value: '$memberCount',
              ),
              _MetricCard(
                icon: Icons.home_work_outlined,
                label: 'Entrepôts',
                value: '$warehouseCount',
              ),
              _MetricCard(
                icon: Icons.inventory_outlined,
                label: 'Articles',
                value: '$itemCount',
              ),
              _MetricCard(
                icon: Icons.trending_up,
                label: 'Stock total',
                value: '$totalStock',
              ),
            ],
          ),
          const SizedBox(height: 24),
          Text('Actions rapides',
              style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 12),
          Wrap(
            spacing: 12,
            runSpacing: 12,
            children: quickActions
                .map((action) => _QuickActionButton(
                      icon: action.$3,
                      label: action.$2,
                      onTap: () => onQuickAction(action.$1),
                    ))
                .toList(),
          ),
          const SizedBox(height: 24),
          Text('Top articles en stock',
              style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 12),
          if (topItems.isEmpty)
            _EmptyStateCard(
              title: 'Aucun article',
              subtitle: 'Ajoute un article pour démarrer ton inventaire.',
            )
          else
            Column(
              children: topItems
                  .map(
                    (entry) => _ListCard(
                      title: entry.item['name']?.toString() ?? 'Article',
                      subtitle:
                          '${entry.totalQty} en stock • SKU ${entry.item['sku'] ?? '-'}',
                      icon: Icons.inventory_2,
                    ),
                  )
                  .toList(),
            ),
          const SizedBox(height: 24),
          Text('Équipements récents',
              style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 12),
          if (equipment.isEmpty)
            _EmptyStateCard(
              title: 'Aucun équipement',
              subtitle: 'Ajoute ton premier équipement pour le suivre.',
            )
          else
            Column(
              children: equipment
                  .take(2)
                  .map((item) => _EquipmentCard(data: item))
                  .toList(),
            ),
        ],
      ),
    );
  }
}

class _MetricCard extends StatelessWidget {
  const _MetricCard({
    required this.icon,
    required this.label,
    required this.value,
  });

  final IconData icon;
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 150,
      child: Card(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(icon, color: AppColors.primary),
              const SizedBox(height: 12),
              Text(
                value,
                style: Theme.of(context)
                    .textTheme
                    .headlineSmall
                    ?.copyWith(fontWeight: FontWeight.w600),
              ),
              Text(label, style: Theme.of(context).textTheme.bodyMedium),
            ],
          ),
        ),
      ),
    );
  }
}

class _QuickActionButton extends StatelessWidget {
  const _QuickActionButton({
    required this.icon,
    required this.label,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        decoration: BoxDecoration(
          color: const Color(0xFFF6E8DD),
          borderRadius: BorderRadius.circular(24),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, color: AppColors.primary),
            const SizedBox(width: 8),
            Text(
              label,
              style: const TextStyle(fontWeight: FontWeight.w600),
            ),
          ],
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// More tab
// ---------------------------------------------------------------------------

class _MoreTab extends StatelessWidget {
  const _MoreTab({
    required this.membership,
    required this.members,
    required this.joinCodes,
    required this.invites,
    required this.userProfile,
    required this.onRevokeCode,
    required this.onInviteMember,
  });

  final CompanyMembership membership;
  final List<Map<String, dynamic>> members;
  final List<CompanyJoinCode> joinCodes;
  final List<MembershipInvite> invites;
  final Map<String, dynamic>? userProfile;
  final ValueChanged<CompanyJoinCode> onRevokeCode;
  final VoidCallback onInviteMember;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _SectionCard(
            title: 'Profil',
            subtitle:
                'Complète ton profil pour que tes collègues te reconnaissent.',
            child: _ProfileSection(
              membership: membership,
              userProfile: userProfile,
            ),
          ),
          _SectionCard(
            title: 'Membres',
            subtitle:
                'Surveille les personnes ayant accès à l’entreprise.',
            action: OutlinedButton.icon(
              onPressed: onInviteMember,
              icon: const Icon(Icons.person_add_alt_1),
              label: const Text('Inviter'),
            ),
            child: _MembersSection(members: members),
          ),
          _SectionCard(
            title: 'Entreprise',
            subtitle: 'Récapitulatif et codes de connexion à partager.',
            child: _CompanySection(
              membership: membership,
              joinCodes: joinCodes,
              invites: invites,
              onRevokeCode: onRevokeCode,
            ),
          ),
        ],
      ),
    );
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
    final user = Supabase.instance.client.auth.currentUser;
    final firstName = (userProfile?['first_name'] as String?)?.trim();
    final lastName = (userProfile?['last_name'] as String?)?.trim();
    final fullName = [firstName, lastName]
        .where((value) => value != null && value!.isNotEmpty)
        .map((value) => value!)
        .join(' ');
    final email = (userProfile?['email'] as String?)?.trim() ?? user?.email;
    final role = membership.role ?? 'membre';
    final roleLabel = role.isNotEmpty
        ? role[0].toUpperCase() + role.substring(1)
        : '—';

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _InfoRow(
          icon: Icons.person_outline,
          label: 'Nom complet',
          value: fullName.isNotEmpty ? fullName : 'Complète ton profil',
        ),
        const SizedBox(height: 12),
        _InfoRow(
          icon: Icons.alternate_email,
          label: 'Courriel',
          value: email ?? '—',
        ),
        const SizedBox(height: 12),
        _InfoRow(
          icon: Icons.verified_user_outlined,
          label: 'Rôle',
          value: roleLabel,
        ),
        const SizedBox(height: 16),
        Text(
          'Ces informations seront visibles par tes collègues.',
          style:
              Theme.of(context).textTheme.bodySmall?.copyWith(color: Colors.black54),
        ),
      ],
    );
  }
}

class _MembersSection extends StatelessWidget {
  const _MembersSection({required this.members});

  final List<Map<String, dynamic>> members;

  @override
  Widget build(BuildContext context) {
    final highlighted = members.take(4).toList(growable: false);
    final remaining = members.length - highlighted.length;

    if (members.isEmpty) {
      return const _EmptyStateCard(
        title: 'Aucun membre',
        subtitle: 'Invite tes collègues pour collaborer.',
      );
    }

    return Column(
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
            '+$remaining membre${remaining > 1 ? 's' : ''} supplémentaire${remaining > 1 ? 's' : ''}',
            style: Theme.of(context)
                .textTheme
                .bodyMedium
                ?.copyWith(color: Colors.black54),
          ),
        ],
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
    required this.joinCodes,
    required this.invites,
    required this.onRevokeCode,
  });

  final CompanyMembership membership;
  final List<CompanyJoinCode> joinCodes;
  final List<MembershipInvite> invites;
  final ValueChanged<CompanyJoinCode> onRevokeCode;

  @override
  Widget build(BuildContext context) {
    final companyName =
        membership.company?['name']?.toString() ?? 'Mon entreprise';
    final role = membership.role ?? 'membre';

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
        ),
        const SizedBox(height: 20),
        Text('Codes de connexion',
            style: Theme.of(context).textTheme.titleSmall),
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
                .map((code) => _JoinCodeCard(
                      code: code,
                      onRevoke: () => onRevokeCode(code),
                    ))
                .toList(),
          ),
        if (joinCodes.length > 3) ...[
          const SizedBox(height: 8),
          Text(
            '+${joinCodes.length - 3} code${joinCodes.length - 3 > 1 ? 's' : ''} supplémentaires',
            style: Theme.of(context)
                .textTheme
                .bodySmall
                ?.copyWith(color: Colors.black54),
          ),
        ],
        const SizedBox(height: 20),
        Text('Invitations récentes',
            style: Theme.of(context).textTheme.titleSmall),
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

class _JoinCodeCard extends StatelessWidget {
  const _JoinCodeCard({
    required this.code,
    required this.onRevoke,
  });

  final CompanyJoinCode code;
  final VoidCallback onRevoke;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDisabled = code.isRevoked || code.isExpired;
    final statusLabel = code.isRevoked
        ? 'Révoqué'
        : code.isExpired
            ? 'Expiré'
            : 'Actif';
    final statusColor = code.isRevoked
        ? Colors.red.shade100
        : code.isExpired
            ? Colors.orange.shade100
            : Colors.green.shade100;
    final usageText = code.maxUses != null
        ? '${code.uses}/${code.maxUses} utilisation${code.maxUses == 1 ? '' : 's'}'
        : '${code.uses} utilisation${code.uses > 1 ? 's' : ''}';
    final remaining = code.remainingUses;
    final expiresAt = code.expiresAt != null
        ? DateFormat.yMMMMd().format(code.expiresAt!.toLocal())
        : null;

    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        code.label?.isNotEmpty == true
                            ? code.label!
                            : 'Code ${code.codeHint ?? ''}',
                        style: theme.textTheme.bodyLarge
                            ?.copyWith(fontWeight: FontWeight.w600),
                      ),
                      if (code.codeHint != null)
                        Text('…${code.codeHint}',
                            style: theme.textTheme.bodySmall
                                ?.copyWith(color: Colors.black54)),
                    ],
                  ),
                ),
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                    color: statusColor,
                    borderRadius: BorderRadius.circular(999),
                  ),
                  child: Text(
                    statusLabel,
                    style: const TextStyle(fontWeight: FontWeight.w600),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Wrap(
              spacing: 12,
              runSpacing: 4,
              children: [
                _InfoChip(icon: Icons.people_alt_outlined, text: usageText),
                if (remaining != null)
                  _InfoChip(
                    icon: Icons.autorenew,
                    text: '${remaining} restant${remaining > 1 ? 's' : ''}',
                  ),
                if (expiresAt != null)
                  _InfoChip(
                    icon: Icons.calendar_month,
                    text: 'Expire le $expiresAt',
                  ),
                _InfoChip(
                  icon: Icons.workspace_premium_outlined,
                  text: code.role,
                ),
              ],
            ),
            if (!isDisabled) ...[
              const SizedBox(height: 12),
              Align(
                alignment: Alignment.centerRight,
                child: TextButton.icon(
                  onPressed: onRevoke,
                  icon: const Icon(Icons.block),
                  label: const Text('Révoquer'),
                ),
              ),
            ],
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
    final subtitle = DateFormat.yMMMd().format(invite.createdAt.toLocal());
    Color chipColor;
    String status;
    if (invite.isPending) {
      chipColor = Colors.orange.shade100;
      status = 'En attente';
    } else if (invite.isAccepted) {
      chipColor = Colors.green.shade100;
      status = 'Acceptée';
    } else if (invite.isCancelled) {
      chipColor = Colors.grey.shade200;
      status = 'Annulée';
    } else {
      chipColor = Colors.red.shade100;
      status = 'Erreur';
    }

    return ListTile(
      contentPadding: EdgeInsets.zero,
      leading: CircleAvatar(
        backgroundColor: AppColors.primary.withOpacity(0.12),
        child: const Icon(Icons.mail_outline, color: AppColors.primary),
      ),
      title: Text(invite.email),
      subtitle: Text('$subtitle • rôle ${invite.role}'),
      trailing: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
        decoration: BoxDecoration(
          color: chipColor,
          borderRadius: BorderRadius.circular(999),
        ),
        child: Text(status, style: const TextStyle(fontWeight: FontWeight.w600)),
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
                style:
                    theme.textTheme.bodySmall?.copyWith(color: Colors.black54),
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

class _InfoChip extends StatelessWidget {
  const _InfoChip({
    required this.icon,
    required this.text,
  });

  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: Colors.grey.shade100,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 16, color: Colors.black54),
          const SizedBox(width: 6),
          Text(text, style: const TextStyle(fontWeight: FontWeight.w500)),
        ],
      ),
    );
  }
}

class _ListCard extends StatelessWidget {
  const _ListCard({
    required this.title,
    required this.subtitle,
    required this.icon,
  });

  final String title;
  final String subtitle;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: ListTile(
        leading: CircleAvatar(
          backgroundColor: AppColors.primary.withOpacity(0.15),
          child: Icon(icon, color: AppColors.primary),
        ),
        title: Text(title, style: const TextStyle(fontWeight: FontWeight.w600)),
        subtitle: Text(subtitle),
        trailing: const Icon(Icons.open_in_new),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// List tab
// ---------------------------------------------------------------------------

class _ListTab extends StatelessWidget {
  const _ListTab({
    required this.requests,
    required this.onAddRequest,
    required this.onReviewInventory,
  });

  final List<Map<String, dynamic>> requests;
  final VoidCallback onAddRequest;
  final VoidCallback onReviewInventory;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Card(
            child: Padding(
              padding: const EdgeInsets.all(20),
              child: Column(
                crossFXML (truncated)
