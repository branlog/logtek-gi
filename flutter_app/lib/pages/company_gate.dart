import 'dart:async';

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../models/company_join_code.dart';
import '../models/company_role.dart';
import '../models/membership_invite.dart';
import '../services/company_commands.dart';
import '../services/company_repository.dart';
import '../services/connectivity_service.dart';
import '../services/supabase_service.dart';
import '../theme/app_colors.dart';

part 'company_gate_home_tab.dart';
part 'company_gate_list_tab.dart';
part 'company_gate_inventory_tab.dart';
part 'company_gate_equipment_tab.dart';
part 'company_gate_more_tab.dart';

class CompanyGatePage extends StatefulWidget {
  const CompanyGatePage({super.key});

  @override
  State<CompanyGatePage> createState() => _CompanyGatePageState();
}

enum _GateTab { home, list, inventory, equipment, more }

typedef _SectionSelectionResult = ({bool cancelled, String? sectionId});

typedef _AsyncCallback = Future<void> Function();

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
  Set<String> _updatingPurchaseRequests = const <String>{};
  final Map<String, String> _journalUserCache = <String, String>{};

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
      floatingActionButton: _buildGlobalFab(),
      floatingActionButtonLocation: FloatingActionButtonLocation.endFloat,
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

  Widget? _buildGlobalFab() {
    final action = _fabActionForCurrentTab();
    if (action == null) return null;
    return FloatingActionButton(
      onPressed: () => action(),
      tooltip: _fabTooltipForCurrentTab(),
      child: const Icon(Icons.add),
    );
  }

  _AsyncCallback? _fabActionForCurrentTab() {
    switch (_currentTab) {
      case _GateTab.home:
        return _showHomeFabMenu;
      case _GateTab.list:
        return _promptCreatePurchaseRequest;
      case _GateTab.inventory:
        return _showInventoryFabMenu;
      case _GateTab.equipment:
        return _promptCreateEquipment;
      case _GateTab.more:
        return _showMoreFabMenu;
    }
  }

  String _fabTooltipForCurrentTab() {
    switch (_currentTab) {
      case _GateTab.home:
        return 'Actions rapides';
      case _GateTab.list:
        return 'Ajouter une demande';
      case _GateTab.inventory:
        return 'Ajouter côté inventaire';
      case _GateTab.equipment:
        return 'Ajouter un équipement';
      case _GateTab.more:
        return 'Inviter / gérer';
    }
  }

  Widget _buildTabContent(CompanyMembership membership) {
    final header = _HeaderBar(
      title: _tabTitle(_currentTab),
      companyName: membership.company?['name']?.toString() ?? 'Entreprise',
      showCalendar:
          _currentTab == _GateTab.list || _currentTab == _GateTab.more,
      onShowJournal: _overview?.membership?.companyId == null
          ? null
          : () => _handleOpenJournal(),
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
          onAddRequest: _promptCreatePurchaseRequest,
          onReviewInventory: () =>
              setState(() => _currentTab = _GateTab.inventory),
          onIncreaseQty: (request) =>
              _handleAdjustPurchaseRequestQty(request, 1),
          onDecreaseQty: (request) =>
              _handleAdjustPurchaseRequestQty(request, -1),
          onDeleteRequest: _handleDeletePurchaseRequest,
          onMarkPurchased: _handleMarkPurchaseRequestPurchased,
          updatingRequestIds: _updatingPurchaseRequests,
        );
      case _GateTab.inventory:
        return _InventoryTab(
          warehouses: _warehouses,
          inventory: _inventory,
          onViewInventory: (warehouseId, {String? sectionId}) =>
              _handleViewInventory(warehouseId, sectionId: sectionId),
          requests: _purchaseRequests,
          onPlaceRequest: _handlePlacePurchaseRequest,
          updatingRequestIds: _updatingPurchaseRequests,
          onManageWarehouse: _handleManageWarehouse,
        );
      case _GateTab.equipment:
        return _EquipmentTab(
          equipment: _equipment,
          commands: _commands,
          onRefresh: _refreshAll,
          companyId: membership.companyId,
        );
      case _GateTab.more:
        return _MoreTab(
          membership: membership,
          members: _overview?.members ?? const <Map<String, dynamic>>[],
          joinCodes: _joinCodes,
          invites: _invites,
          userProfile: _userProfile,
          onRevokeCode: _handleRevokeJoinCode,
          onInviteMember: _promptInviteMember,
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
                code:
                    codeCtrl.text.trim().isEmpty ? null : codeCtrl.text.trim(),
              );

              if (!result.ok) {
                setDialogState(() {
                  submitting = false;
                  dialogError =
                      _describeError(result.error) ?? 'Erreur inconnue.';
                });
                return;
              }

              if (!context.mounted || !mounted) return;
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

  Future<void> _handleManageWarehouse(Map<String, dynamic> warehouse) async {
    final warehouseId = warehouse['id']?.toString();
    if (warehouseId == null) return;
    final name = warehouse['name']?.toString() ?? 'Entrepôt';
    await showModalBottomSheet<void>(
      context: context,
      builder: (context) {
        return SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ListTile(
                leading: const Icon(Icons.edit),
                title: const Text('Renommer'),
                onTap: () async {
                  Navigator.of(context).pop();
                  await _promptRenameWarehouse(warehouse);
                },
              ),
              ListTile(
                leading: const Icon(Icons.delete_outline, color: Colors.red),
                title: const Text('Supprimer'),
                onTap: () async {
                  Navigator.of(context).pop();
                  await _handleDeleteWarehouse(warehouseId, name);
                },
              ),
              ListTile(
                leading: const Icon(Icons.close),
                title: const Text('Annuler'),
                onTap: () => Navigator.of(context).pop(),
              ),
            ],
          ),
        );
      },
    );
  }

  Future<void> _promptRenameWarehouse(Map<String, dynamic> warehouse) async {
    final warehouseId = warehouse['id']?.toString();
    if (warehouseId == null) return;
    final formKey = GlobalKey<FormState>();
    final nameCtrl = TextEditingController(
      text: warehouse['name']?.toString() ?? '',
    );
    final codeCtrl = TextEditingController(
      text: warehouse['code']?.toString() ?? '',
    );
    var submitting = false;
    String? dialogError;

    final confirmed = await showDialog<bool>(
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
              final result = await _commands.updateWarehouse(
                warehouseId: warehouseId,
                patch: {
                  'name': nameCtrl.text.trim(),
                  'code': codeCtrl.text.trim().isEmpty
                      ? null
                      : codeCtrl.text.trim(),
                },
              );
              if (!result.ok) {
                setDialogState(() {
                  submitting = false;
                  dialogError =
                      _describeError(result.error) ?? 'Erreur inconnue.';
                });
                return;
              }
              if (!mounted) return;
              Navigator.of(context).pop(true);
              _showSnack('Entrepôt renommé.');
              await _refreshAll();
            }

            return AlertDialog(
              title: const Text('Renommer l’entrepôt'),
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
                      : const Text('Enregistrer'),
                ),
              ],
            );
          },
        );
      },
    );

    if (confirmed != true) {
      nameCtrl.dispose();
      codeCtrl.dispose();
      return;
    }

    nameCtrl.dispose();
    codeCtrl.dispose();
  }

  Future<void> _handleDeleteWarehouse(
      String warehouseId, String warehouseName) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Supprimer cet entrepôt ?'),
        content: Text('“$warehouseName” sera supprimé définitivement.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Annuler'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Supprimer'),
          ),
        ],
      ),
    );
    if (confirm != true) return;

    final result = await _commands.deleteWarehouse(warehouseId: warehouseId);
    if (!result.ok) {
      _showSnack(
        _describeError(result.error) ?? 'Suppression impossible.',
        error: true,
      );
      return;
    }

    _showSnack('Entrepôt supprimé.');
    await _refreshAll();
  }


  Future<void> _promptCreateInventorySection(
      Map<String, dynamic> warehouse) async {
    final companyId = _overview?.membership?.companyId;
    final warehouseId = warehouse['id']?.toString();
    if (companyId == null || warehouseId == null) return;

    final warehouseName = warehouse['name']?.toString() ?? 'Entrepôt';
    final created = await showDialog<Map<String, dynamic>?>(
      context: context,
      builder: (context) => _InventorySectionDialog(
        commands: _commands,
        companyId: companyId,
        warehouseId: warehouseId,
        warehouseName: warehouseName,
        describeError: _describeError,
      ),
    );
    if (created != null && mounted) {
      final sectionId = created['id']?.toString();
      final sectionName = created['name']?.toString() ?? 'Section';
      _showSnack('Section créée dans $warehouseName.');
      await _logJournal(
        scope: 'inventory',
        event: 'section_created',
        entityId: sectionId == null
            ? _inventoryWarehouseEntityId(warehouseId)
            : _inventorySectionEntityId(warehouseId, sectionId),
        note: sectionName,
        payload: {
          'warehouse_id': warehouseId,
          'section_id': sectionId,
          'code': created['code'],
        },
      );
      await _refreshAll();
    }
  }

  Future<void> _promptCreateItem() async {
    final companyId = _overview?.membership?.companyId;
    if (companyId == null) return;

    final formKey = GlobalKey<FormState>();
    final nameCtrl = TextEditingController();
    final skuCtrl = TextEditingController();
    final unitCtrl = TextEditingController();
    final categoryCtrl = TextEditingController();
    var submitting = false;
    String? dialogError;

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

              final result = await _commands.createItem(
                companyId: companyId,
                name: nameCtrl.text.trim(),
                sku: skuCtrl.text.trim(),
                unit: unitCtrl.text.trim(),
                category: categoryCtrl.text.trim(),
              );

              if (!result.ok) {
                setDialogState(() {
                  submitting = false;
                  dialogError =
                      _describeError(result.error) ?? 'Impossible de créer.';
                });
                return;
              }

              if (!context.mounted || !mounted) return;
              Navigator.of(context).pop();
              _showSnack('Article créé.');
              await _refreshAll();
            }

            return AlertDialog(
              title: const Text('Nouvel article'),
              content: Form(
                key: formKey,
                child: SingleChildScrollView(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      TextFormField(
                        controller: nameCtrl,
                        decoration: const InputDecoration(
                            labelText: 'Nom de l’article'),
                        validator: (value) =>
                            value == null || value.trim().isEmpty
                                ? 'Nom requis'
                                : null,
                      ),
                      const SizedBox(height: 12),
                      TextFormField(
                        controller: skuCtrl,
                        decoration:
                            const InputDecoration(labelText: 'SKU (optionnel)'),
                      ),
                      const SizedBox(height: 12),
                      TextFormField(
                        controller: unitCtrl,
                        decoration: const InputDecoration(
                            labelText: 'Unité (optionnel)'),
                      ),
                      const SizedBox(height: 12),
                      TextFormField(
                        controller: categoryCtrl,
                        decoration: const InputDecoration(
                            labelText: 'Catégorie (optionnel)'),
                      ),
                      if (dialogError != null) ...[
                        const SizedBox(height: 12),
                        Text(dialogError!,
                            style: const TextStyle(color: Colors.red)),
                      ],
                    ],
                  ),
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
    skuCtrl.dispose();
    unitCtrl.dispose();
    categoryCtrl.dispose();
  }

  Future<void> _promptCreateEquipment() async {
    final companyId = _overview?.membership?.companyId;
    if (companyId == null) return;

    final formKey = GlobalKey<FormState>();
    final nameCtrl = TextEditingController();
    final brandCtrl = TextEditingController();
    final modelCtrl = TextEditingController();
    final serialCtrl = TextEditingController();
    var submitting = false;
    String? dialogError;

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

              final result = await _commands.createEquipment(
                companyId: companyId,
                name: nameCtrl.text.trim(),
                brand: brandCtrl.text.trim(),
                model: modelCtrl.text.trim(),
                serial: serialCtrl.text.trim(),
              );

              if (!result.ok) {
                setDialogState(() {
                  submitting = false;
                  dialogError =
                      _describeError(result.error) ?? 'Impossible de créer.';
                });
                return;
              }

              if (!context.mounted || !mounted) return;
              Navigator.of(context).pop();
              _showSnack('Équipement créé.');
              await _refreshAll();
            }

            return AlertDialog(
              title: const Text('Nouvel équipement'),
              content: Form(
                key: formKey,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    TextFormField(
                      controller: nameCtrl,
                      decoration: const InputDecoration(
                          labelText: 'Nom de l’équipement'),
                      validator: (value) =>
                          value == null || value.trim().isEmpty
                              ? 'Nom requis'
                              : null,
                    ),
                    const SizedBox(height: 12),
                    TextFormField(
                      controller: brandCtrl,
                      decoration: const InputDecoration(
                          labelText: 'Marque (optionnel)'),
                    ),
                    const SizedBox(height: 12),
                    TextFormField(
                      controller: modelCtrl,
                      decoration: const InputDecoration(
                          labelText: 'Modèle (optionnel)'),
                    ),
                    const SizedBox(height: 12),
                    TextFormField(
                      controller: serialCtrl,
                      decoration: const InputDecoration(
                          labelText: 'Numéro de série (optionnel)'),
                    ),
                    if (dialogError != null) ...[
                      const SizedBox(height: 12),
                      Text(dialogError!,
                          style: const TextStyle(color: Colors.red)),
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
    brandCtrl.dispose();
    modelCtrl.dispose();
    serialCtrl.dispose();
  }

  Future<void> _promptCreatePurchaseRequest() async {
    final companyId = _overview?.membership?.companyId;
    if (companyId == null) return;

    final created = await showDialog<Map<String, dynamic>?>(
      context: context,
      builder: (context) => _PurchaseRequestDialog(
        commands: _commands,
        companyId: companyId,
        warehouses: _warehouses,
        describeError: _describeError,
      ),
    );

    if (created != null && mounted) {
      final requestId = created['id']?.toString();
      final name = created['name']?.toString();
      _showSnack('Demande ajoutée.');
      await _logJournal(
        scope: 'list',
        event: 'purchase_request_created',
        entityId: requestId,
        note: name,
        payload: {
          'request_id': requestId,
          'qty': created['qty'],
          'warehouse_id': created['warehouse_id'],
          'section_id': created['section_id'],
        },
      );
      await _refreshAll();
    }
  }

  String? _purchaseRequestId(Map<String, dynamic> data) {
    return data['id']?.toString();
  }

  void _replacePurchaseRequest(Map<String, dynamic> updated) {
    final targetId = _purchaseRequestId(updated);
    if (targetId == null) return;
    setState(() {
      _purchaseRequests = _purchaseRequests
          .map((request) =>
              _purchaseRequestId(request) == targetId ? updated : request)
          .toList();
    });
  }

  void _removePurchaseRequest(String requestId) {
    setState(() {
      _purchaseRequests = _purchaseRequests
          .where((request) => _purchaseRequestId(request) != requestId)
          .toList();
    });
  }

  Future<void> _handleAdjustPurchaseRequestQty(
      Map<String, dynamic> request, int delta) async {
    final requestId = _purchaseRequestId(request);
    final requestName = request['name']?.toString();
    if (requestId == null) return;

    final currentQty = int.tryParse(request['qty']?.toString() ?? '') ?? 0;
    final newQty = currentQty + delta;
    if (newQty <= 0) {
      _showSnack('La quantité doit être au moins 1.', error: true);
      return;
    }

    setState(() {
      _updatingPurchaseRequests = {
        ..._updatingPurchaseRequests,
        requestId,
      };
    });

    final result = await _commands.updatePurchaseRequest(
      requestId: requestId,
      patch: {'qty': newQty},
    );

    if (!mounted) return;

    setState(() {
      final next = {..._updatingPurchaseRequests};
      next.remove(requestId);
      _updatingPurchaseRequests = next;
    });

    if (!result.ok) {
      _showSnack(
        _describeError(result.error) ?? 'Impossible de mettre à jour.',
        error: true,
      );
      return;
    }

    final updated = result.data;
    final note = request['name']?.toString();
    if (updated == null) {
      await _logJournal(
        scope: 'list',
        event: 'purchase_request_qty_updated',
        entityId: requestId,
        note: note,
        payload: {
          'qty': newQty,
          'delta': delta,
          'request_id': requestId,
        },
      );
      await _refreshAll();
      return;
    }

    _replacePurchaseRequest(updated);
    await _logJournal(
      scope: 'list',
      event: 'purchase_request_qty_updated',
      entityId: requestId,
      note: note,
      payload: {
        'qty': updated['qty'] ?? newQty,
        'delta': delta,
        'request_id': requestId,
      },
    );
  }

  Future<void> _handleMarkPurchaseRequestPurchased(
      Map<String, dynamic> request) async {
    final requestId = _purchaseRequestId(request);
    if (requestId == null) return;

    final updated = await showDialog<Map<String, dynamic>>(
      context: context,
      builder: (context) => _PurchaseQtyDialog(
        title: 'Confirmer l’achat',
        confirmLabel: 'Mettre “à placer”',
        initialQty: int.tryParse(request['qty']?.toString() ?? '') ?? 1,
        helperText: 'Indique le nombre vraiment acheté.',
        describeError: _describeError,
        failureFallback: 'Impossible de confirmer l’achat.',
        onSubmit: (qty) => _commands.updatePurchaseRequest(
          requestId: requestId,
          patch: {
            'qty': qty,
            'status': 'to_place',
            'purchased_at': DateTime.now().toIso8601String(),
          },
        ),
      ),
    );

    if (updated != null && mounted) {
      _replacePurchaseRequest(updated);
      await _logJournal(
        scope: 'list',
        event: 'purchase_request_marked_to_place',
        entityId: requestId,
        note: request['name']?.toString(),
        payload: {
          'request_id': requestId,
          'status': updated['status'],
          'qty': updated['qty'],
        },
      );
      _showSnack('Demande à placer.');
    }
  }

  Future<void> _handlePlacePurchaseRequest(Map<String, dynamic> request) async {
    final requestId = _purchaseRequestId(request);
    final companyId = _overview?.membership?.companyId;
    final requestName = request['name']?.toString();
    if (requestId == null) return;
    if (companyId == null) {
      _showSnack('Entreprise inconnue. Recharge la page.', error: true);
      return;
    }

    final qty = int.tryParse(request['qty']?.toString() ?? '');
    if (qty == null || qty <= 0) {
      _showSnack('Quantité reçue invalide.', error: true);
      return;
    }

    var warehouseId = _extractWarehouseId(request);
    if (warehouseId == null || warehouseId.isEmpty) {
      warehouseId = await _promptWarehouseSelection();
      if (warehouseId == null) return;
      request['warehouse_id'] = warehouseId;
      final warehouseInfo = _warehouses.firstWhere(
        (warehouse) => warehouse['id']?.toString() == warehouseId,
        orElse: () => <String, dynamic>{},
      );
      if (warehouseInfo.isNotEmpty) {
        request['warehouse'] = warehouseInfo;
      }
    }

    var sectionId = _extractSectionId(request);
    if (warehouseId != null) {
      final sections = _sectionsForWarehouse(warehouseId);
      final hasExistingSection = sectionId != null &&
          sections.any((section) => section['id']?.toString() == sectionId);
      if (!hasExistingSection) {
        sectionId = null;
      }
      if (sections.isNotEmpty && sectionId == null) {
        final selection = await _promptSectionSelection(
          warehouseId: warehouseId,
        );
        if (selection.cancelled) {
          return;
        }
        sectionId = selection.sectionId;
      }
      _applySectionToRequest(request, warehouseId, sectionId);
    }

    if (warehouseId == null) {
      _showSnack('Sélectionne un entrepôt pour placer cette pièce.',
          error: true);
      return;
    }

    var itemId = request['item_id']?.toString();
    itemId ??= _matchInventoryItemByName(request['name']?.toString());
    if (itemId == null) {
      final createResult = await _commands.createItem(
        companyId: companyId,
        name: request['name']?.toString() ?? 'Pièce',
      );
      if (!createResult.ok) {
        _showSnack(
          _describeError(createResult.error) ??
              'Impossible de créer l’article pour cette pièce.',
          error: true,
        );
        return;
      }
      itemId = createResult.data?['id']?.toString();
      if (itemId == null) {
        _showSnack('Article créé mais identifiant manquant.', error: true);
        return;
      }
      request['item_id'] = itemId;
    }

    setState(() {
      _updatingPurchaseRequests = {
        ..._updatingPurchaseRequests,
        requestId,
      };
    });

    Future<void> clearUpdating() async {
      setState(() {
        final next = {..._updatingPurchaseRequests};
        next.remove(requestId);
        _updatingPurchaseRequests = next;
      });
    }

    final stockResult = await _commands.incrementStock(
      companyId: companyId,
      itemId: itemId,
      warehouseId: warehouseId,
      qty: qty,
      sectionId: sectionId,
    );

    if (!mounted) return;

    if (!stockResult.ok) {
      await clearUpdating();
      _showSnack(
        _describeError(stockResult.error) ??
            'Impossible d’ajouter cette pièce en stock.',
        error: true,
      );
      return;
    }

    final updateResult = await _commands.updatePurchaseRequest(
      requestId: requestId,
      patch: {
        'status': 'done',
        'item_id': itemId,
        'warehouse_id': warehouseId,
        'section_id': sectionId,
      },
    );

    if (!mounted) return;

    if (!updateResult.ok) {
      await _commands.applyStockDelta(
        companyId: companyId,
        itemId: itemId,
        warehouseId: warehouseId,
        delta: -qty,
        sectionId: sectionId,
      );
      await clearUpdating();
      _showSnack(
        _describeError(updateResult.error) ??
            'Stock ajouté mais impossible de mettre à jour la demande.',
        error: true,
      );
      return;
    }

    await clearUpdating();
    final updated = updateResult.data;
    if (updated != null) {
      _replacePurchaseRequest(updated);
    }
    await _logJournal(
      scope: 'list',
      event: 'purchase_request_completed',
      entityId: requestId,
      note: requestName,
      payload: {
        'request_id': requestId,
        'item_id': itemId,
        'qty': qty,
        'warehouse_id': warehouseId,
        'section_id': sectionId,
      },
    );
    await _logJournal(
      scope: 'inventory',
      event: 'purchase_stock_added',
      entityId: sectionId == null
          ? _inventoryWarehouseEntityId(warehouseId)
          : _inventorySectionEntityId(warehouseId, sectionId),
      note: requestName,
      payload: {
        'item_id': itemId,
        'qty': qty,
        'request_id': requestId,
        'warehouse_id': warehouseId,
        'section_id': sectionId,
      },
    );
    _showSnack('Pièce placée en stock.');
    await _refreshAll();
  }

  Future<void> _handleViewInventory(
    String warehouseId, {
    String? sectionId,
  }) async {
    final membership = _overview?.membership;
    final companyId = membership?.companyId;
    if (companyId == null) {
      _showSnack('Entreprise inconnue. Recharge la page.', error: true);
      return;
    }

    Map<String, dynamic>? warehouseProvider() {
      return _warehouses.firstWhere(
        (candidate) => candidate['id']?.toString() == warehouseId,
        orElse: () => const <String, dynamic>{},
      );
    }

    final currentWarehouse = warehouseProvider();
    if (currentWarehouse == null || currentWarehouse.isEmpty) {
      _showSnack('Entrepôt introuvable.', error: true);
      return;
    }

    await Navigator.of(context).push<bool>(
      MaterialPageRoute(
        builder: (context) => _WarehouseInventoryPage(
          companyId: companyId,
          warehouseId: warehouseId,
          warehouseProvider: warehouseProvider,
          warehousesProvider: () => _warehouses,
          inventoryProvider: () => _inventory,
          commands: _commands,
          describeError: _describeError,
          onRefresh: _refreshAll,
          initialSectionId: sectionId,
          onShowJournal: ({String? scopeOverride, String? entityId}) =>
              _handleOpenJournal(
            scopeOverride: scopeOverride ?? 'inventory',
            entityId: entityId,
          ),
          onManageWarehouse: _handleManageWarehouse,
        ),
      ),
    );

    // Les modifications rafraîchissent déjà l’état via onRefresh.
  }

  String? _extractWarehouseId(Map<String, dynamic> request) {
    final direct = request['warehouse_id'];
    if (direct != null) return direct.toString();
    final warehouse = request['warehouse'];
    if (warehouse is Map && warehouse['id'] != null) {
      return warehouse['id'].toString();
    }
    return null;
  }

  String? _extractSectionId(Map<String, dynamic> request) {
    final direct = request['section_id'];
    if (direct != null && direct.toString().isNotEmpty) {
      return direct.toString();
    }
    final section = request['section'];
    if (section is Map && section['id'] != null) {
      return section['id'].toString();
    }
    return null;
  }

  String? _matchInventoryItemByName(String? rawName) {
    final name = rawName?.trim();
    if (name == null || name.isEmpty) return null;
    final normalized = name.toLowerCase();
    for (final entry in _inventory) {
      final entryName = entry.item['name']?.toString();
      if (entryName != null && entryName.trim().toLowerCase() == normalized) {
        final id = entry.item['id']?.toString();
        if (id != null && id.isNotEmpty) return id;
      }
    }
    return null;
  }

  Future<String?> _promptWarehouseSelection() async {
    if (_warehouses.isEmpty) {
      _showSnack('Ajoute un entrepôt avant de placer la pièce.', error: true);
      return null;
    }
    if (_warehouses.length == 1) {
      final solo = _warehouses.first['id']?.toString();
      if (solo == null || solo.isEmpty) {
        _showSnack('Entrepôt invalide.', error: true);
        return null;
      }
      return solo;
    }
    return showDialog<String>(
      context: context,
      builder: (context) {
        return SimpleDialog(
          title: const Text('Choisir un entrepôt'),
          children: [
            for (final warehouse in _warehouses)
              if (warehouse['id'] != null)
                SimpleDialogOption(
                  onPressed: () =>
                      Navigator.of(context).pop(warehouse['id'].toString()),
                  child: Text(warehouse['name']?.toString() ?? 'Entrepôt'),
                ),
            SimpleDialogOption(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('Annuler'),
            ),
          ],
        );
      },
    );
  }

  List<Map<String, dynamic>> _sectionsForWarehouse(String warehouseId) {
    final warehouse = _warehouses.firstWhere(
      (candidate) => candidate['id']?.toString() == warehouseId,
      orElse: () => const <String, dynamic>{},
    );
    final sections = warehouse['sections'];
    if (sections is List) {
      return sections
          .whereType<Map>()
          .map((raw) => Map<String, dynamic>.from(raw))
          .toList(growable: false);
    }
    return const <Map<String, dynamic>>[];
  }

  Map<String, dynamic>? _findSectionInfo(
      String warehouseId, String? sectionId) {
    if (sectionId == null || sectionId.isEmpty) return null;
    final sections = _sectionsForWarehouse(warehouseId);
    final match = sections.firstWhere(
      (section) => section['id']?.toString() == sectionId,
      orElse: () => const <String, dynamic>{},
    );
    return match.isEmpty ? null : match;
  }

  void _applySectionToRequest(
    Map<String, dynamic> request,
    String warehouseId,
    String? sectionId,
  ) {
    if (sectionId == null || sectionId.isEmpty) {
      request.remove('section_id');
      request.remove('section');
      return;
    }
    request['section_id'] = sectionId;
    final sectionInfo = _findSectionInfo(warehouseId, sectionId);
    if (sectionInfo != null) {
      request['section'] = sectionInfo;
    }
  }

  Future<_SectionSelectionResult> _promptSectionSelection({
    required String warehouseId,
    String? initialSectionId,
  }) async {
    final sections = _sectionsForWarehouse(warehouseId);
    if (sections.isEmpty) {
      return (cancelled: false, sectionId: null);
    }
    final sentinel = InventoryEntry.unassignedSectionKey;
    var selectedValue = initialSectionId;
    final hasInitial = selectedValue != null &&
        sections.any((section) => section['id']?.toString() == selectedValue);
    if (!hasInitial) {
      selectedValue = sentinel;
    }

    final result = await showDialog<String?>(
      context: context,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            return AlertDialog(
              title: const Text('Choisir une section'),
              content: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    for (final section in sections)
                      RadioListTile<String>(
                        value: section['id']?.toString() ?? '',
                        groupValue: selectedValue,
                        onChanged: (value) {
                          if (value == null) return;
                          setDialogState(() => selectedValue = value);
                        },
                        title: Text(
                            section['name']?.toString() ?? 'Section sans nom'),
                      ),
                    RadioListTile<String>(
                      value: sentinel,
                      groupValue: selectedValue,
                      onChanged: (value) {
                        if (value == null) return;
                        setDialogState(() => selectedValue = value);
                      },
                      title: const Text('Sans section'),
                    ),
                  ],
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.of(context).pop(null),
                  child: const Text('Annuler'),
                ),
                FilledButton(
                  onPressed: () => Navigator.of(context).pop(selectedValue),
                  child: const Text('Choisir'),
                ),
              ],
            );
          },
        );
      },
    );

    if (result == null) {
      return (cancelled: true, sectionId: null);
    }
    if (result == sentinel) {
      return (cancelled: false, sectionId: null);
    }
    return (cancelled: false, sectionId: result);
  }

  Future<void> _handleDeletePurchaseRequest(
      Map<String, dynamic> request) async {
    final requestId = _purchaseRequestId(request);
    if (requestId == null) return;

    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Supprimer cette demande ?'),
        content: Text(
          '“${request['name'] ?? 'Pièce'}” sera retirée de la liste.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Annuler'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Supprimer'),
          ),
        ],
      ),
    );

    if (confirm != true) return;

    final result = await _commands.deletePurchaseRequest(requestId: requestId);

    if (!result.ok) {
      _showSnack(
        _describeError(result.error) ?? 'Suppression impossible.',
        error: true,
      );
      return;
    }

    if (!mounted) return;
    _removePurchaseRequest(requestId);
    await _logJournal(
      scope: 'list',
      event: 'purchase_request_deleted',
      entityId: requestId,
      note: request['name']?.toString(),
      payload: {
        'request_id': requestId,
      },
    );
    _showSnack('Demande supprimée.');
  }

  Future<void> _promptInviteMember() async {
    final companyId = _overview?.membership?.companyId;
    if (companyId == null) return;

    final formKey = GlobalKey<FormState>();
    final emailCtrl = TextEditingController();
    final noteCtrl = TextEditingController();
    const List<String> roles = CompanyRoles.values;
    var selectedRole = CompanyRoles.employee;
    var submitting = false;
    String? dialogError;

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

              final result = await _commands.inviteMemberByEmail(
                companyId: companyId,
                email: emailCtrl.text.trim(),
                role: selectedRole,
                notes: noteCtrl.text.trim(),
              );

              if (!result.ok) {
                setDialogState(() {
                  submitting = false;
                  dialogError =
                      _describeError(result.error) ?? 'Invitation impossible.';
                });
                return;
              }

              if (!context.mounted || !mounted) return;
              Navigator.of(context).pop();
              _showSnack('Invitation envoyée.');
              await _refreshAll();
            }

            return AlertDialog(
              title: const Text('Inviter un membre'),
              content: Form(
                key: formKey,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    TextFormField(
                      controller: emailCtrl,
                      decoration:
                          const InputDecoration(labelText: 'E-mail Supabase'),
                      keyboardType: TextInputType.emailAddress,
                      validator: (value) =>
                          value == null || value.trim().isEmpty
                              ? 'Adresse requise'
                              : null,
                    ),
                    const SizedBox(height: 12),
                    DropdownButtonFormField<String>(
                      initialValue: selectedRole,
                      decoration:
                          const InputDecoration(labelText: 'Rôle attribué'),
                      items: roles
                          .map(
                            (role) => DropdownMenuItem<String>(
                              value: role,
                              child: Text(role),
                            ),
                          )
                          .toList(),
                      onChanged: (value) {
                        if (value == null) return;
                        setDialogState(() => selectedRole = value);
                      },
                    ),
                    const SizedBox(height: 12),
                    TextFormField(
                      controller: noteCtrl,
                      decoration: const InputDecoration(
                        labelText: 'Note interne (optionnel)',
                      ),
                      minLines: 2,
                      maxLines: 3,
                    ),
                    if (dialogError != null) ...[
                      const SizedBox(height: 12),
                      Text(dialogError!,
                          style: const TextStyle(color: Colors.red)),
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
                      : const Text('Inviter'),
                ),
              ],
            );
          },
        );
      },
    );

    emailCtrl.dispose();
    noteCtrl.dispose();
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
        _promptCreateItem();
        break;
      case _QuickAction.newWarehouse:
        _promptCreateWarehouse();
        break;
      case _QuickAction.viewInventory:
        setState(() => _currentTab = _GateTab.inventory);
        break;
      case _QuickAction.newEquipment:
        _promptCreateEquipment();
        break;
      case _QuickAction.members:
        setState(() => _currentTab = _GateTab.more);
        break;
    }
  }

  String _scopeForTab(_GateTab tab) {
    switch (tab) {
      case _GateTab.home:
        return 'home';
      case _GateTab.list:
        return 'list';
      case _GateTab.inventory:
        return 'inventory';
      case _GateTab.equipment:
        return 'equipment';
      case _GateTab.more:
        return 'more';
    }
  }

  String _scopeLabel(String scope) {
    switch (scope) {
      case 'home':
        return 'Accueil';
      case 'list':
        return 'Liste';
      case 'inventory':
        return 'Inventaire';
      case 'equipment':
        return 'Équipement';
      case 'more':
        return 'Plus';
      default:
        return scope;
    }
  }

  String? _warehouseNameById(String? warehouseId) {
    if (warehouseId == null) return null;
    final match = _warehouses.firstWhere(
      (warehouse) => warehouse['id']?.toString() == warehouseId,
      orElse: () => const <String, dynamic>{},
    );
    if (match.isEmpty) return null;
    return match['name']?.toString();
  }

  String? _sectionNameById(String warehouseId, String sectionId) {
    final match = _warehouses.firstWhere(
      (warehouse) => warehouse['id']?.toString() == warehouseId,
      orElse: () => const <String, dynamic>{},
    );
    if (match.isEmpty) return null;
    final sections = match['sections'];
    if (sections is! List) return null;
    final section = sections.firstWhere(
      (candidate) => candidate['id']?.toString() == sectionId,
      orElse: () => const <String, dynamic>{},
    );
    if (section.isEmpty) return null;
    return section['name']?.toString();
  }

  String? _equipmentNameById(String equipmentId) {
    final match = _equipment.firstWhere(
      (item) => item['id']?.toString() == equipmentId,
      orElse: () => const <String, dynamic>{},
    );
    if (match.isEmpty) return null;
    return match['name']?.toString();
  }

  String? _equipmentCategoryLabel(String category) {
    switch (category) {
      case 'mechanic':
        return 'Mécanique';
      case 'diesel':
        return 'Diesel';
      case 'inventory':
        return 'Inventaire';
      case 'docs':
        return 'Documentation';
      default:
        return null;
    }
  }

  String? _purchaseRequestName(String requestId) {
    final match = _purchaseRequests.firstWhere(
      (request) => request['id']?.toString() == requestId,
      orElse: () => const <String, dynamic>{},
    );
    if (match.isEmpty) return null;
    final name = match['name']?.toString();
    if (name == null || name.isEmpty) {
      return requestId;
    }
    return name;
  }

  Future<void> _logJournal({
    required String scope,
    required String event,
    String? entityId,
    String? note,
    Map<String, dynamic>? payload,
  }) async {
    final companyId = _overview?.membership?.companyId;
    if (companyId == null) return;
    await _commands.logJournalEntry(
      companyId: companyId,
      scope: scope,
      entityId: entityId,
      event: event,
      note: note,
      payload: payload,
    );
  }

  Future<void> _hydrateJournalEntries(
    List<Map<String, dynamic>> entries,
  ) async {
    await loadJournalAuthors(_commands.client, _journalUserCache, entries);
  }

  String? _journalEntityLabel(String scope, String entityId) {
    if (scope == 'inventory') {
      const prefix = 'inventory/warehouse/';
      if (entityId.startsWith(prefix)) {
        final remainder = entityId.substring(prefix.length);
        const sectionSeparator = '/section/';
        final hasSection = remainder.contains(sectionSeparator);
        final warehouseId = hasSection
            ? remainder.split(sectionSeparator).first
            : remainder;
        final sectionId = hasSection
            ? remainder.split(sectionSeparator).last
            : null;
        final warehouseName = _warehouseNameById(warehouseId);
        if (sectionId != null) {
          if (sectionId == InventoryEntry.unassignedSectionKey) {
            return 'Section sans affectation';
          }
          final sectionName = _sectionNameById(warehouseId, sectionId);
          if (sectionName != null) {
            return 'Section $sectionName';
          }
        }
        if (warehouseName != null) {
          return 'Entrepôt $warehouseName';
        }
      }
    } else if (scope == 'equipment') {
      final parts = entityId.split('::');
      final equipmentId = parts.first;
      final category = parts.length > 1 ? parts[1] : 'general';
      final equipmentName = _equipmentNameById(equipmentId);
      final categoryLabel = _equipmentCategoryLabel(category);
      if (equipmentName != null) {
        return categoryLabel == null
            ? 'Équipement $equipmentName'
            : 'Équipement $equipmentName — $categoryLabel';
      }
    } else if (scope == 'list') {
      final name = _purchaseRequestName(entityId);
      if (name != null) {
        return 'Demande "$name"';
      }
    }
    return entityId;
  }

  Future<void> _handleOpenJournal(
      {String? scopeOverride, String? entityId}) async {
    final membership = _overview?.membership;
    final companyId = membership?.companyId;
    if (companyId == null) {
      _showSnack('Aucune entreprise sélectionnée.', error: true);
      return;
    }
    final scope = scopeOverride ?? _scopeForTab(_currentTab);
    final scopeTitle = _scopeLabel(scope);
    final entitySuffix = entityId == null
        ? ''
        : ' — ${_journalEntityLabel(scope, entityId) ?? entityId}';
    final title = 'Journal — $scopeTitle$entitySuffix';

    Future<List<Map<String, dynamic>>> loadEntries() async {
      final result = await _repository.fetchJournalEntries(
        scope: scope,
        entityId: entityId,
      );
      if (result.hasMissingTables) {
        throw StateError('journal_entries');
      }
      if (result.error != null) {
        throw result.error!;
      }
      return result.data
          .map((entry) => Map<String, dynamic>.from(entry))
          .toList();
    }

    String? sheetError;
    List<Map<String, dynamic>> entries = const <Map<String, dynamic>>[];
    try {
      entries = await loadEntries();
      await _hydrateJournalEntries(entries);
    } catch (error) {
      sheetError = friendlyJournalLoadError(error);
    }
    if (!mounted) return;

    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (context) {
        final noteCtrl = TextEditingController();
        bool submitting = false;
        return StatefulBuilder(
          builder: (context, setSheetState) {
            Future<void> refresh() async {
              try {
                final latest = await loadEntries();
                await _hydrateJournalEntries(latest);
                setSheetState(() {
                  entries = latest;
                  sheetError = null;
                });
              } catch (error) {
                setSheetState(
                  () => sheetError = friendlyJournalLoadError(error),
                );
              }
            }

            Future<void> submitNote() async {
              final note = noteCtrl.text.trim();
              if (note.isEmpty) return;
              setSheetState(() => submitting = true);
              await _commands.logJournalEntry(
                companyId: companyId,
                scope: scope,
                entityId: entityId,
                event: 'note',
                note: note,
              );
              noteCtrl.clear();
              await refresh();
              setSheetState(() => submitting = false);
            }

            return Padding(
              padding: EdgeInsets.only(
                left: 20,
                right: 20,
                top: 24,
                bottom: MediaQuery.of(context).viewInsets.bottom + 24,
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(
                    title,
                    style: Theme.of(context)
                        .textTheme
                        .titleLarge
                        ?.copyWith(fontWeight: FontWeight.w700),
                  ),
                  const SizedBox(height: 16),
                SizedBox(
                  height: MediaQuery.of(context).size.height * 0.45,
                  child: sheetError != null
                      ? Center(
                          child: Padding(
                            padding: const EdgeInsets.all(16),
                            child: Text(
                              sheetError!,
                              textAlign: TextAlign.center,
                            ),
                          ),
                        )
                      : entries.isEmpty
                          ? const Center(child: Text('Aucun événement.'))
                          : ListView.builder(
                              itemCount: entries.length,
                              itemBuilder: (_, index) {
                                final entry = entries[index];
                                final createdAt =
                                    entry['created_at']?.toString();
                                return ListTile(
                                  contentPadding: EdgeInsets.zero,
                                  leading: const Icon(Icons.event_note),
                                  title: Text(
                                    journalEventLabel(
                                      entry['event']?.toString(),
                                    ),
                                  ),
                                  subtitle: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      if (entry['note'] != null)
                                        Text(entry['note'].toString()),
                                      if (createdAt != null)
                                        Text(
                                          _formatDate(createdAt) ?? createdAt,
                                          style: Theme.of(context)
                                              .textTheme
                                              .bodySmall,
                                        ),
                                      if (entry['_author'] != null)
                                        Text(
                                          'Par ${entry['_author']}',
                                          style: Theme.of(context)
                                              .textTheme
                                              .bodySmall,
                                        ),
                                    ],
                                  ),
                                );
                              },
                            ),
                ),
                  const SizedBox(height: 16),
                  TextField(
                    controller: noteCtrl,
                    minLines: 1,
                    maxLines: 3,
                    decoration: const InputDecoration(
                      labelText: 'Ajouter une note au journal',
                    ),
                  ),
                  const SizedBox(height: 12),
                  FilledButton(
                    onPressed: submitting ? null : submitNote,
                    child: submitting
                        ? const SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Text('Enregistrer'),
                  ),
                ],
              ),
            );
          },
        );
      },
    );
  }

  Future<void> _showHomeFabMenu() async {
    final options = <_FabMenuOption>[
      _FabMenuOption(
        label: 'Nouvel article',
        icon: Icons.add_box_outlined,
        action: _promptCreateItem,
      ),
      _FabMenuOption(
        label: 'Nouvel entrepôt',
        icon: Icons.store_mall_directory_outlined,
        action: _promptCreateWarehouse,
      ),
      _FabMenuOption(
        label: 'Nouvel équipement',
        icon: Icons.build_outlined,
        action: _promptCreateEquipment,
      ),
      _FabMenuOption(
        label: 'Inviter un membre',
        icon: Icons.person_add_alt,
        action: _promptInviteMember,
      ),
    ];
    await _showFabMenu(options);
  }

  Future<void> _showInventoryFabMenu() async {
    final options = <_FabMenuOption>[
      _FabMenuOption(
        label: 'Nouvel entrepôt',
        icon: Icons.store_mall_directory_outlined,
        action: _promptCreateWarehouse,
      ),
    ];
    if (_warehouses.isNotEmpty) {
      options.addAll([
        _FabMenuOption(
          label: 'Nouvelle section',
          icon: Icons.view_day,
          action: _promptCreateSectionFromFab,
        ),
        _FabMenuOption(
          label: 'Ajouter des pièces',
          icon: Icons.inventory_2,
          action: _startAddPiecesFlow,
        ),
      ]);
    }
    await _showFabMenu(options);
  }

  Future<void> _showMoreFabMenu() async {
    final options = <_FabMenuOption>[
      _FabMenuOption(
        label: 'Inviter un membre',
        icon: Icons.person_add_alt,
        action: _promptInviteMember,
      ),
    ];
    await _showFabMenu(options);
  }

  Future<void> _showFabMenu(List<_FabMenuOption> options) async {
    if (options.isEmpty) {
      _showSnack('Aucune action disponible pour le moment.');
      return;
    }
    await showModalBottomSheet<void>(
      context: context,
      builder: (context) {
        return SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: options
                .map(
                  (option) => ListTile(
                    leading: Icon(option.icon),
                    title: Text(option.label),
                    onTap: () async {
                      Navigator.of(context).pop();
                      await option.action();
                    },
                  ),
                )
                .toList(),
          ),
        );
      },
    );
  }

  Future<void> _promptCreateSectionFromFab() async {
    final warehouse = await _selectWarehouseForAction(
      title: 'Choisir un entrepôt pour la section',
    );
    if (warehouse == null) return;
    await _promptCreateInventorySection(warehouse);
  }

  Future<void> _startAddPiecesFlow() async {
    final warehouse = await _selectWarehouseForAction(
      title: 'Ajouter des pièces dans…',
    );
    if (warehouse == null) return;
    final warehouseId = warehouse['id']?.toString();
    if (warehouseId == null) return;
    await _handleViewInventory(warehouseId);
  }

  Future<Map<String, dynamic>?> _selectWarehouseForAction({
    String title = 'Choisir un entrepôt',
  }) async {
    if (_warehouses.isEmpty) {
      _showSnack('Crée un entrepôt avant d’utiliser cette action.',
          error: true);
      return null;
    }
    final selectedId = await showDialog<String>(
      context: context,
      builder: (context) {
        return SimpleDialog(
          title: Text(title),
          children: [
            for (final warehouse in _warehouses)
              if (warehouse['id'] != null)
                SimpleDialogOption(
                  onPressed: () =>
                      Navigator.of(context).pop(warehouse['id'].toString()),
                  child: Text(warehouse['name']?.toString() ?? 'Entrepôt'),
                ),
            SimpleDialogOption(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('Annuler'),
            ),
          ],
        );
      },
    );
    if (selectedId == null) return null;
    final match = _warehouses.firstWhere(
      (warehouse) => warehouse['id']?.toString() == selectedId,
      orElse: () => const <String, dynamic>{},
    );
    if (match.isEmpty) return null;
    return match;
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

class _PurchaseRequestDialog extends StatefulWidget {
  const _PurchaseRequestDialog({
    required this.commands,
    required this.companyId,
    required this.warehouses,
    required this.describeError,
  });

  final CompanyCommands commands;
  final String companyId;
  final List<Map<String, dynamic>> warehouses;
  final String? Function(Object? error) describeError;

  @override
  State<_PurchaseRequestDialog> createState() => _PurchaseRequestDialogState();
}

class _PurchaseRequestDialogState extends State<_PurchaseRequestDialog> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _nameCtrl;
  late final TextEditingController _noteCtrl;
  String? _selectedWarehouseId;
  String? _selectedSectionId;
  int _qty = 1;
  bool _submitting = false;
  String? _dialogError;

  @override
  void initState() {
    super.initState();
    _nameCtrl = TextEditingController();
    _noteCtrl = TextEditingController();
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    _noteCtrl.dispose();
    super.dispose();
  }

  void _incrementQty() {
    if (_submitting) return;
    setState(() => _qty++);
  }

  void _decrementQty() {
    if (_submitting || _qty <= 1) return;
    setState(() => _qty--);
  }

  Future<void> _handleSubmit() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() {
      _submitting = true;
      _dialogError = null;
    });

    final result = await widget.commands.createPurchaseRequest(
      companyId: widget.companyId,
      name: _nameCtrl.text.trim(),
      qty: _qty,
      warehouseId: _selectedWarehouseId,
      sectionId: _selectedSectionId,
      note: _noteCtrl.text.trim(),
    );

    if (!mounted) return;

    if (!result.ok) {
      setState(() {
        _submitting = false;
        _dialogError =
            widget.describeError(result.error) ?? 'Impossible de créer.';
      });
      return;
    }

    Navigator.of(context).pop(
      result.data ?? const <String, dynamic>{},
    );
  }

  @override
  Widget build(BuildContext context) {
    final sections = _sectionsForWarehouse(_selectedWarehouseId);
    return AlertDialog(
      title: const Text('Nouvelle pièce à suivre'),
      content: Form(
        key: _formKey,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextFormField(
                controller: _nameCtrl,
                decoration: const InputDecoration(labelText: 'Nom de la pièce'),
                validator: (value) =>
                    value == null || value.trim().isEmpty ? 'Nom requis' : null,
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  const Text('Quantité'),
                  const Spacer(),
                  IconButton(
                    icon: const Icon(Icons.remove),
                    onPressed: _qty > 1 && !_submitting ? _decrementQty : null,
                  ),
                  SizedBox(
                    width: 40,
                    child: Center(
                      child: Text(
                        '$_qty',
                        style: const TextStyle(
                          fontWeight: FontWeight.w600,
                          fontSize: 16,
                        ),
                      ),
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.add),
                    onPressed: _submitting ? null : _incrementQty,
                  ),
                ],
              ),
              const SizedBox(height: 12),
              DropdownButtonFormField<String?>(
                // ignore: deprecated_member_use
                value: _selectedWarehouseId,
                items: [
                  const DropdownMenuItem<String?>(
                    value: null,
                    child: Text('Sans entrepôt'),
                  ),
                  ...widget.warehouses.map(
                    (warehouse) => DropdownMenuItem<String?>(
                      value: warehouse['id']?.toString(),
                      child: Text(warehouse['name']?.toString() ?? '—'),
                    ),
                  ),
                ],
                onChanged: (value) {
                  setState(() {
                    _selectedWarehouseId = value;
                    _selectedSectionId = null;
                  });
                },
                decoration: const InputDecoration(
                  labelText: 'Entrepôt (optionnel)',
                ),
              ),
              if (sections.isNotEmpty) ...[
                const SizedBox(height: 12),
                DropdownButtonFormField<String?>(
                  // ignore: deprecated_member_use
                  value: _selectedSectionId,
                  items: [
                    const DropdownMenuItem<String?>(
                      value: null,
                      child: Text('Sans section'),
                    ),
                    ...sections.map(
                      (section) => DropdownMenuItem<String?>(
                        value: section['id']?.toString(),
                        child: Text(section['name']?.toString() ?? '—'),
                      ),
                    ),
                  ],
                  onChanged: (value) {
                    setState(() => _selectedSectionId = value);
                  },
                  decoration: const InputDecoration(
                    labelText: 'Section (optionnel)',
                  ),
                ),
              ],
              const SizedBox(height: 12),
              TextFormField(
                controller: _noteCtrl,
                decoration: const InputDecoration(
                  labelText: 'Note interne (optionnel)',
                ),
                minLines: 2,
                maxLines: 3,
              ),
              if (_dialogError != null) ...[
                const SizedBox(height: 12),
                Text(
                  _dialogError!,
                  style: const TextStyle(color: Colors.red),
                ),
              ],
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: _submitting ? null : () => Navigator.pop(context),
          child: const Text('Annuler'),
        ),
        FilledButton(
          onPressed: _submitting ? null : _handleSubmit,
          child: _submitting
              ? const SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Text('Créer'),
        ),
      ],
    );
  }

  List<Map<String, dynamic>> _sectionsForWarehouse(String? warehouseId) {
    if (warehouseId == null) {
      return const <Map<String, dynamic>>[];
    }
    final match = widget.warehouses.firstWhere(
      (warehouse) => warehouse['id']?.toString() == warehouseId,
      orElse: () => const <String, dynamic>{},
    );
    final sections = match['sections'];
    if (sections is List) {
      return sections
          .whereType<Map>()
          .map((raw) => Map<String, dynamic>.from(raw))
          .toList(growable: false);
    }
    return const <Map<String, dynamic>>[];
  }
}

class _InventorySectionDialog extends StatefulWidget {
  const _InventorySectionDialog({
    required this.commands,
    required this.companyId,
    required this.warehouseId,
    required this.warehouseName,
    required this.describeError,
  });

  final CompanyCommands commands;
  final String companyId;
  final String warehouseId;
  final String warehouseName;
  final String? Function(Object? error) describeError;

  @override
  State<_InventorySectionDialog> createState() =>
      _InventorySectionDialogState();
}

class _InventorySectionDialogState extends State<_InventorySectionDialog> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _nameCtrl;
  late final TextEditingController _codeCtrl;
  bool _submitting = false;
  String? _dialogError;

  @override
  void initState() {
    super.initState();
    _nameCtrl = TextEditingController();
    _codeCtrl = TextEditingController();
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    _codeCtrl.dispose();
    super.dispose();
  }

  Future<void> _handleSubmit() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() {
      _submitting = true;
      _dialogError = null;
    });

    final result = await widget.commands.createInventorySection(
      companyId: widget.companyId,
      warehouseId: widget.warehouseId,
      name: _nameCtrl.text.trim(),
      code: _codeCtrl.text.trim().isEmpty ? null : _codeCtrl.text.trim(),
    );

    if (!mounted) return;

    if (!result.ok) {
      setState(() {
        _submitting = false;
        _dialogError = widget.describeError(result.error) ?? 'Erreur inconnue.';
      });
      return;
    }

    Navigator.of(context).pop(
      result.data ?? const <String, dynamic>{},
    );
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text('Section - ${widget.warehouseName}'),
      content: Form(
        key: _formKey,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextFormField(
                controller: _nameCtrl,
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
                controller: _codeCtrl,
                decoration: const InputDecoration(
                  labelText: 'Code (optionnel)',
                ),
              ),
              if (_dialogError != null) ...[
                const SizedBox(height: 12),
                Text(
                  _dialogError!,
                  style: TextStyle(color: Colors.red.shade700),
                ),
              ],
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: _submitting ? null : () => Navigator.pop(context),
          child: const Text('Annuler'),
        ),
        FilledButton(
          onPressed: _submitting ? null : _handleSubmit,
          child: _submitting
              ? const SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Text('Créer'),
        ),
      ],
    );
  }
}

class _InventoryBreakdownLine {
  const _InventoryBreakdownLine({
    required this.itemId,
    required this.name,
    this.sku,
    required this.qty,
    this.unit,
  });

  final String itemId;
  final String name;
  final String? sku;
  final int qty;
  final String? unit;
}

class _PurchaseQtyDialog extends StatefulWidget {
  const _PurchaseQtyDialog({
    required this.title,
    required this.confirmLabel,
    required this.initialQty,
    required this.onSubmit,
    required this.describeError,
    required this.failureFallback,
    this.helperText,
  });

  final String title;
  final String confirmLabel;
  final int initialQty;
  final Future<CommandResult<Map<String, dynamic>>> Function(int qty) onSubmit;
  final String? Function(Object? error) describeError;
  final String failureFallback;
  final String? helperText;

  @override
  State<_PurchaseQtyDialog> createState() => _PurchaseQtyDialogState();
}

class _PurchaseQtyDialogState extends State<_PurchaseQtyDialog> {
  late int _qty;
  bool _submitting = false;
  String? _dialogError;

  @override
  void initState() {
    super.initState();
    _qty = widget.initialQty > 0 ? widget.initialQty : 1;
  }

  void _incrementQty() {
    if (_submitting) return;
    setState(() => _qty++);
  }

  void _decrementQty() {
    if (_submitting || _qty <= 1) return;
    setState(() => _qty--);
  }

  Future<void> _handleSubmit() async {
    setState(() {
      _submitting = true;
      _dialogError = null;
    });

    final result = await widget.onSubmit(_qty);
    if (!mounted) return;

    if (!result.ok) {
      setState(() {
        _submitting = false;
        _dialogError =
            widget.describeError(result.error) ?? widget.failureFallback;
      });
      return;
    }

    Navigator.of(context).pop(result.data);
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(widget.title),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              const Text('Quantité'),
              const Spacer(),
              IconButton(
                icon: const Icon(Icons.remove),
                onPressed: !_submitting && _qty > 1 ? _decrementQty : null,
              ),
              SizedBox(
                width: 40,
                child: _submitting
                    ? const Center(
                        child: SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        ),
                      )
                    : Center(
                        child: Text(
                          '$_qty',
                          style: const TextStyle(
                            fontWeight: FontWeight.w600,
                            fontSize: 16,
                          ),
                        ),
                      ),
              ),
              IconButton(
                icon: const Icon(Icons.add),
                onPressed: _submitting ? null : _incrementQty,
              ),
            ],
          ),
          if (widget.helperText != null)
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Text(
                widget.helperText!,
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ),
          if (_dialogError != null) ...[
            const SizedBox(height: 12),
            Text(
              _dialogError!,
              style: const TextStyle(color: Colors.red),
            ),
          ],
        ],
      ),
      actions: [
        TextButton(
          onPressed: _submitting ? null : () => Navigator.pop(context),
          child: const Text('Annuler'),
        ),
        FilledButton(
          onPressed: _submitting ? null : _handleSubmit,
          child: _submitting
              ? const SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : Text(widget.confirmLabel),
        ),
      ],
    );
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
    this.onShowJournal,
  });

  final String title;
  final String companyName;
  final bool showCalendar;
  final VoidCallback? onShowJournal;

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
            icon: const Icon(Icons.history),
            onPressed: onShowJournal,
          ),
          IconButton(
            icon: Icon(
                showCalendar ? Icons.calendar_month : Icons.notifications_none),
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

  factory _StatusBanner.warning(
      {required IconData icon, required String message}) {
    return _StatusBanner._(const Color(0xFFFFF1DC), icon, message);
  }

  factory _StatusBanner.error(String message) {
    return _StatusBanner._(
        const Color(0xFFFFE2E1), Icons.error_outline, message);
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
                                child:
                                    CircularProgressIndicator(strokeWidth: 2),
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
                                child:
                                    CircularProgressIndicator(strokeWidth: 2),
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

String? _formatDate(dynamic raw) {
  DateTime? date;
  if (raw is DateTime) {
    date = raw;
  } else if (raw is String) {
    date = DateTime.tryParse(raw);
  }
  if (date == null) return null;
  return DateFormat.yMMMMd('fr_CA').format(date.toLocal());
}

class _FabMenuOption {
  const _FabMenuOption({
    required this.label,
    required this.icon,
    required this.action,
  });

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

class _ListCard extends StatelessWidget {
  const _ListCard({
    required this.title,
    required this.subtitle,
    required this.icon,
  });

  final String title;
  final String subtitle;
  final IconData icon;
  final Future<void> Function() action;
}
