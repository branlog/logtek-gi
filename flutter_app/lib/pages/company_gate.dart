import 'dart:async';
import 'dart:convert';
import 'dart:math';

import 'package:crypto/crypto.dart' as crypto;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../models/company_join_code.dart';
import '../models/company_role.dart';
import '../models/membership_invite.dart';
import '../services/company_commands.dart';
import '../services/company_repository.dart';
import '../services/connectivity_service.dart';
import '../services/copilot_service.dart';
import '../services/offline_actions_service.dart';
import '../services/offline_storage.dart';
import '../services/supabase_service.dart';
import '../theme/app_colors.dart';
import '../widgets/sync_status_chip.dart';
import '../widgets/copilot_sheet.dart';
import '../utils/async_utils.dart';

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
typedef _AsyncValueChanged<T> = Future<void> Function(T value);
enum _InviteOption { email, joinCode }

class _CompanyGatePageState extends State<CompanyGatePage> {
  late final CompanyRepository _repository;
  late final CompanyCommands _commands;

  StreamSubscription<bool>? _connectivitySub;
  StreamSubscription<int>? _queueSub;
  bool _isOnline = true;
  bool _isLoading = true;
  bool _isRefreshing = false;
  String? _fatalError;
  String? _transientError;
  int _pendingActionCount = 0;

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
  final Random _random = Random();
  bool _offlineHandlersRegistered = false;
  final List<_CopilotIncident> _copilotIncidents = <_CopilotIncident>[];
  static const Map<String, String> _accentMap = {
    'à': 'a',
    'á': 'a',
    'â': 'a',
    'ä': 'a',
    'ã': 'a',
    'å': 'a',
    'ç': 'c',
    'é': 'e',
    'è': 'e',
    'ê': 'e',
    'ë': 'e',
    'í': 'i',
    'ì': 'i',
    'î': 'i',
    'ï': 'i',
    'ñ': 'n',
    'ó': 'o',
    'ò': 'o',
    'ô': 'o',
    'ö': 'o',
    'õ': 'o',
    'ù': 'u',
    'ú': 'u',
    'û': 'u',
    'ü': 'u',
    'œ': 'oe',
  };
  _InlineMessage? _inlineMessage;
  Timer? _inlineMessageTimer;

  final TextEditingController _companyNameCtrl = TextEditingController();
  final TextEditingController _joinCodeCtrl = TextEditingController();
  bool _creatingCompany = false;
  bool _joiningCompany = false;

  @override
  void initState() {
    super.initState();
    _repository = CompanyRepository(Supa.i);
    _commands = CompanyCommands(Supa.i);
    _registerOfflineHandlers();
    _isOnline = ConnectivityService.instance.isOnline;
    _connectivitySub =
        ConnectivityService.instance.onStatusChange.listen((online) {
      if (!mounted) return;
      setState(() => _isOnline = online);
      if (online) {
        OfflineActionsService.instance.processQueue();
        _refreshAll();
      } else {
        _refreshPendingActionsCount();
      }
    });
    _refreshAll();
    _refreshPendingActionsCount();
    _queueSub =
        OfflineActionsService.instance.onQueueChanged.listen((count) {
      if (!mounted) return;
      setState(() => _pendingActionCount = count);
    });
  }

  @override
  void dispose() {
    _connectivitySub?.cancel();
    _queueSub?.cancel();
    _inlineMessageTimer?.cancel();
    _companyNameCtrl.dispose();
    _joinCodeCtrl.dispose();
    _unregisterOfflineHandlers();
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
      runDetached(_persistPurchaseRequestsCache());
      runDetached(_persistEquipmentCache());
      runDetached(_persistPurchaseRequestsCache());
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
    _refreshPendingActionsCount();
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
      floatingActionButton: _buildFloatingButtons(),
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

  Widget? _buildFloatingButtons() {
    final List<Widget> buttons = [];
    final canUseCopilot = _overview?.membership?.companyId != null;
    buttons.add(
      FloatingActionButton.small(
        heroTag: 'copilot_fab',
        tooltip: 'LogAI',
        onPressed: canUseCopilot ? _showCopilotSheet : null,
        child: const Icon(Icons.bolt_outlined),
      ),
    );
    final primaryFab = _buildPrimaryFab();
    if (primaryFab != null) {
      buttons.add(const SizedBox(height: 12));
      buttons.add(primaryFab);
    }
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.end,
      children: buttons,
    );
  }

  Widget? _buildPrimaryFab() {
    final action = _fabActionForCurrentTab();
    if (action == null) return null;
    return FloatingActionButton(
      heroTag: 'primary_fab',
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
      onShowCopilot: _overview?.membership?.companyId == null
          ? null
          : () => _showCopilotSheet(),
      statusIndicator: SyncStatusChip(
        online: _isOnline,
        pendingActions: _pendingActionCount,
        onSync: _isOnline
            ? () => OfflineActionsService.instance.processQueue()
            : null,
      ),
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
    final inlineMessage = _inlineMessage;

    return Stack(
      children: [
        RefreshIndicator(
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
        ),
        if (inlineMessage != null)
          Positioned(
            left: 0,
            right: 0,
            bottom: 0,
            child: SafeArea(
              minimum: const EdgeInsets.only(bottom: 12),
              child: _InlineMessageBanner(
                message: inlineMessage,
                onClose: _dismissInlineMessage,
              ),
            ),
          ),
      ],
    );
  }

  Future<void> _showCopilotSheet() async {
    final service = CopilotService.instance;
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => CopilotSheet(
        service: service,
        onSubmit: _handleCopilotCommand,
        online: _isOnline,
        onlineStream: ConnectivityService.instance.onStatusChange,
      ),
    );
    await service.stopListening();
  }

  Future<CopilotFeedback?> _handleCopilotCommand(String text) async {
    final intent = await CopilotService.instance.interpretText(text);
    return _executeCopilotIntent(intent);
  }

  Future<CopilotFeedback?> _executeCopilotIntent(CopilotIntent intent) async {
    try {
      final quickActionFeedback =
          await _copilotMaybeHandleQuickAction(intent);
      if (quickActionFeedback != null) return quickActionFeedback;

      if (intent.type == CopilotIntentType.unknown) {
        final maybeMarked = await _copilotMaybeMarkExistingRequest(intent);
        if (maybeMarked != null) return maybeMarked;
      }
      switch (intent.type) {
        case CopilotIntentType.createPurchaseRequest:
          return await _copilotCreatePurchaseRequest(intent);
        case CopilotIntentType.inventoryAdjust:
          return await _copilotAdjustInventory(intent);
        case CopilotIntentType.equipmentTask:
          return await _copilotHandleEquipmentTask(intent);
        case CopilotIntentType.dieselLog:
          return await _copilotHandleDieselLog(intent);
        case CopilotIntentType.unknown:
          final fallbackPrompt = intent.rawText ?? intent.summary;
          final response =
              await CopilotService.instance.converse(fallbackPrompt);
          if (response != null) {
            return CopilotFeedback(message: response);
          }
          final message = intent.summary.isEmpty
              ? 'LogAI n’a pas compris cette commande.'
              : intent.summary;
          _showSnack(message, error: true);
          _recordCopilotIncident(
            fallbackPrompt,
            message,
          );
          return CopilotFeedback(message: message, isError: true);
      }
    } catch (error) {
      final message = 'Copilot — ${error.toString()}';
      _showSnack(message, error: true);
      _recordCopilotIncident(
        intent.rawText ?? intent.summary,
        message,
      );
      return CopilotFeedback(message: message, isError: true);
    }
  }

  Future<CopilotFeedback?> _copilotCreatePurchaseRequest(
    CopilotIntent intent,
  ) async {
    final companyId = _overview?.membership?.companyId;
    if (companyId == null) {
      const message = 'Aucune entreprise sélectionnée.';
      _showSnack(message, error: true);
      return const CopilotFeedback(message: message, isError: true);
    }
    final payload = intent.payload;
    final action = _copilotPickString(payload, ['action'])?.toLowerCase();
    var name = _copilotPickString(payload, [
      'item_name',
      'name',
      'article',
      'item',
    ]);
    name ??= _inferItemName(intent.rawText);
    var qty = _copilotPickInt(payload, ['qty', 'quantity', 'quantite']);
    qty ??= _extractFirstInt(intent.rawText);
    final wantsMarkExisting =
        _copilotShouldMarkPurchaseRequest(action, intent.rawText);

    if (wantsMarkExisting) {
      if (name == null || name.trim().isEmpty) {
        const message = 'Précise quelle demande doit être marquée comme achetée.';
        return const CopilotFeedback(message: message, isError: true);
      }
      final target = _copilotFindPurchaseRequestByName(name);
      if (target == null) {
        final message = 'Aucune demande existante ne correspond à "$name".';
        return CopilotFeedback(message: message, isError: true);
      }
      return _copilotMarkPurchaseRequest(target, qty: qty);
    }

    final note = _copilotPickString(payload, ['note', 'comment']) ??
        intent.rawText ??
        name;
    final warehouseHint =
        _copilotPickString(payload, ['warehouse', 'warehouse_name', 'entrepot']);
    final sectionHint =
        _copilotPickString(payload, ['section', 'section_name']);
    if (name == null || name.trim().isEmpty || qty == null || qty <= 0) {
      const message = 'Copilot a besoin d’un nom et d’une quantité.';
      _showSnack(message, error: true);
      return const CopilotFeedback(message: message, isError: true);
    }

    final warehouseId =
        warehouseHint == null ? null : _matchWarehouseId(warehouseHint);
    final sectionId = sectionHint == null || warehouseId == null
        ? null
        : _matchSectionId(warehouseId, sectionHint);

    final confirmed = await _confirmCopilotAction(
      title: 'Créer la demande ?',
      lines: [
        'Article : $name',
        'Quantité : $qty',
        if (warehouseId != null)
          'Entrepôt : ${_warehouseNameById(warehouseId) ?? warehouseId}',
        if (sectionId != null && warehouseId != null)
          'Section : ${_sectionLabel(warehouseId, sectionId)}',
        if (note != null && note.isNotEmpty) 'Note : $note',
        if (!_isOnline) 'Mode hors ligne — mise en file.',
      ],
    );
    if (confirmed != true) {
      const message = 'Création annulée.';
      return const CopilotFeedback(message: message);
    }

    if (_isOnline) {
      final result = await _commands.createPurchaseRequest(
        companyId: companyId,
        name: name,
        qty: qty,
        warehouseId: warehouseId,
        sectionId: sectionId,
        note: note,
      );
      if (!result.ok || result.data == null) {
        final message = _describeError(result.error) ??
            'Impossible de créer la demande via Copilot.';
        _showSnack(message, error: true);
        return CopilotFeedback(message: message, isError: true);
      }
      _replacePurchaseRequest(result.data!);
      await _logJournal(
        scope: 'list',
        event: 'purchase_request_created',
        entityId: result.data!['id']?.toString(),
        note: name,
        payload: {
          'request_id': result.data!['id'],
          'qty': qty,
          'warehouse_id': warehouseId,
          'section_id': sectionId,
          'copilot': true,
        },
      );
      await _refreshAll();
      final message = 'Demande “$name” ajoutée.';
      _showSnack(message);
      return CopilotFeedback(message: message);
    } else {
      await _createPurchaseRequestOffline(
        name: name,
        qty: qty,
        warehouseId: warehouseId,
        sectionId: sectionId,
        note: note,
      );
      const message = 'Demande enregistrée hors ligne.';
      _showOfflineQueuedSnack(message);
      return const CopilotFeedback(message: message);
    }
  }

  Future<CopilotFeedback?> _copilotMarkPurchaseRequest(
    Map<String, dynamic> request, {
    int? qty,
  }) async {
    final requestId = _purchaseRequestId(request);
    if (requestId == null) {
      const message = 'Demande introuvable.';
      _showSnack(message, error: true);
      return const CopilotFeedback(message: message, isError: true);
    }
    final effectiveQty = qty != null && qty > 0
        ? qty
        : int.tryParse(request['qty']?.toString() ?? '') ?? 1;

    if (_isOnline) {
      final result = await _commands.updatePurchaseRequest(
        requestId: requestId,
        patch: {
          'qty': effectiveQty,
          'status': 'to_place',
          'purchased_at': DateTime.now().toIso8601String(),
        },
      );
      if (!result.ok || result.data == null) {
        final message = _describeError(result.error) ??
            'Impossible de marquer la demande comme achetée.';
        _showSnack(message, error: true);
        return CopilotFeedback(message: message, isError: true);
      }
      _replacePurchaseRequest(result.data!);
      await _logJournal(
        scope: 'list',
        event: 'purchase_request_marked_to_place',
        entityId: requestId,
        note: request['name']?.toString(),
        payload: {
          'request_id': requestId,
          'status': result.data!['status'],
          'qty': result.data!['qty'],
          'copilot': true,
        },
      );
      final message =
          'Demande “${request['name']?.toString() ?? 'pièce'}” marquée comme achetée.';
      _showSnack(message);
      return CopilotFeedback(message: message);
    } else {
      final offlineResult =
          await _markPurchaseRequestToPlaceOffline(request, effectiveQty);
      if (!offlineResult.ok || offlineResult.data == null) {
        final message = _describeError(offlineResult.error) ??
            'Action hors ligne impossible.';
        _showSnack(message, error: true);
        return CopilotFeedback(message: message, isError: true);
      }
      _replacePurchaseRequest(offlineResult.data!);
      const message = 'Demande mise “à placer” (hors ligne).';
      return const CopilotFeedback(message: message);
    }
  }

  Future<CopilotFeedback?> _copilotMaybeHandleQuickAction(
      CopilotIntent intent) async {
    final normalized =
        _copilotNormalizeText(intent.rawText ?? intent.summary);
    if (normalized.isEmpty) return null;
    final mentionsQuickActions = _copilotContainsAny(
      normalized,
      [
        'action moov',
        'action rapide',
        'actions rapides',
        'menu action',
        'ouvre action',
        'ouvre le bouton',
        'ouvre bouton',
        'lance action',
      ],
    );
    if (!mentionsQuickActions) return null;

    final target = _copilotIdentifyQuickAction(normalized);
    if (target == null) {
      const message = 'Quelle action rapide dois-je lancer ?';
      _showSnack(message);
      return const CopilotFeedback(message: message, isError: true);
    }
    runDetached(_launchQuickActionFlow(target));
    final label = _quickActionLabel(target);
    return CopilotFeedback(message: 'Action "$label" ouverte.');
  }

  _QuickAction? _copilotIdentifyQuickAction(String normalized) {
    bool containsAll(List<String> parts) =>
        parts.every((part) => normalized.contains(part));
    if (containsAll(['prendre', 'piece']) ||
        normalized.contains('sortir piece') ||
        normalized.contains('retirer piece') ||
        normalized.contains('action moov prendre')) {
      return _QuickAction.pickItem;
    }
    if (containsAll(['mettre', 'commande']) ||
        normalized.contains('ajouter commande') ||
        normalized.contains('action moov commande')) {
      return _QuickAction.placeOrder;
    }
    if (containsAll(['faire', 'plein']) ||
        normalized.contains('diesel') ||
        normalized.contains('carburant') ||
        normalized.contains('plein de diesel')) {
      return _QuickAction.logFuel;
    }
    if (normalized.contains('tache mecanique') ||
        normalized.contains('tache maintenance') ||
        normalized.contains('entretien') ||
        normalized.contains('action moov tache')) {
      return _QuickAction.addMechanicTask;
    }
    return null;
  }

  Future<CopilotFeedback?> _copilotMaybeMarkExistingRequest(
      CopilotIntent intent) async {
    final payload = intent.payload;
    final action = _copilotPickString(payload, ['action']);
    final rawText = intent.rawText ?? intent.summary;
    if (!_copilotShouldMarkPurchaseRequest(action, rawText)) {
      return null;
    }
    final candidateName = _copilotPickString(
          payload,
          ['item_name', 'name', 'article', 'item'],
        ) ??
        _inferItemName(rawText);
    if (candidateName == null || candidateName.trim().isEmpty) {
      const message =
          'Précise le nom de la pièce à marquer comme achetée.';
      _showSnack(message, error: true);
      return const CopilotFeedback(message: message, isError: true);
    }
    final target = _copilotFindPurchaseRequestByName(candidateName);
    if (target == null) {
      final message = 'Aucune demande ne correspond à "$candidateName".';
      _showSnack(message, error: true);
      return CopilotFeedback(message: message, isError: true);
    }
    final qty = _copilotPickInt(payload, ['qty', 'quantity', 'quantite']) ??
        _extractFirstInt(rawText);
    return _copilotMarkPurchaseRequest(target, qty: qty);
  }

  Future<CopilotFeedback?> _copilotAdjustInventory(
    CopilotIntent intent,
  ) async {
    final companyId = _overview?.membership?.companyId;
    if (companyId == null) {
      const message = 'Aucune entreprise sélectionnée.';
      _showSnack(message, error: true);
      return const CopilotFeedback(message: message, isError: true);
    }
    if (_inventory.isEmpty) {
      const message = 'Inventaire indisponible.';
      _showSnack(message, error: true);
      return const CopilotFeedback(message: message, isError: true);
    }
    final payload = intent.payload;
    var delta = _copilotPickInt(payload, ['delta', 'qty', 'quantity']);
    delta ??= _extractFirstInt(intent.rawText);
    if (delta == null || delta == 0) {
      delta = await _copilotPromptQuantity(
        title: 'Quelle quantité ajuster ?',
        description: 'Indique le nombre à ajouter (positif) ou retirer (négatif).',
      );
    }
    if (delta == null || delta == 0) {
      const message = 'Aucune quantité fournie.';
      _showSnack(message, error: true);
      return const CopilotFeedback(message: message, isError: true);
    }
    final itemId = _copilotPickString(payload, ['item_id', 'piece_id']);
    final sku = _copilotPickString(payload, ['sku', 'code']);
    final itemName =
        _copilotPickString(payload, ['item_name', 'piece', 'article', 'name']);
    var entry = _findInventoryEntry(
      itemId: itemId,
      sku: sku,
      name: itemName,
    );
    entry ??= await _copilotPromptInventoryItem(
      hint: itemName ?? sku ?? intent.rawText,
    );
    if (entry == null) {
      const message = 'Aucune pièce sélectionnée.';
      _showSnack(message, error: true);
      return const CopilotFeedback(message: message, isError: true);
    }
    final warehouseHint =
        _copilotPickString(payload, ['warehouse', 'entrepot', 'warehouse_name']);
    final sectionHint =
        _copilotPickString(payload, ['section', 'section_name']);
    var warehouseId =
        _resolveWarehouseForEntry(entry, hint: warehouseHint);
    warehouseId ??= await _copilotPromptWarehouse(entry);
    if (warehouseId == null) {
      const message = 'Entrepôt requis pour cette pièce.';
      _showSnack(message, error: true);
      return const CopilotFeedback(message: message, isError: true);
    }
    var sectionId = _resolveSectionForEntry(
      entry,
      warehouseId,
      hint: sectionHint,
    );
    sectionId ??= await _copilotPromptSection(entry, warehouseId);
    final normalizedSectionId = _normalizeSectionId(sectionId);
    final itemDbId = entry.item['id']?.toString();
    if (itemDbId == null) {
      const message = 'Identifiant de pièce manquant.';
      _showSnack(message, error: true);
      return const CopilotFeedback(message: message, isError: true);
    }

    final itemLabel =
        entry.item['name']?.toString() ?? entry.item['sku']?.toString() ?? 'Pièce';
    final lines = [
      'Pièce : $itemLabel',
      'Quantité : ${delta > 0 ? '+$delta' : delta}',
      'Entrepôt : ${_warehouseNameById(warehouseId) ?? warehouseId}',
      if (sectionId != null)
        'Section : ${_sectionLabel(warehouseId, sectionId)}',
      if (!_isOnline) 'Mode hors ligne — en attente de synchronisation.',
    ];
    final confirmed = await _confirmCopilotAction(
      title: 'Confirmer l’ajustement ?',
      lines: lines,
    );
    if (confirmed != true) {
      const message = 'Ajustement annulé.';
      return const CopilotFeedback(message: message);
    }

    if (_isOnline) {
      final result = await _commands.applyStockDelta(
        companyId: companyId,
        itemId: itemDbId,
        warehouseId: warehouseId,
        delta: delta,
        sectionId: normalizedSectionId,
      );
      if (!result.ok) {
        final message = _describeError(result.error) ??
            'Impossible de modifier cet inventaire.';
        _showSnack(message, error: true);
        return CopilotFeedback(message: message, isError: true);
      }
      await _logJournal(
        scope: 'inventory',
        event: 'stock_delta',
        entityId: normalizedSectionId == null
            ? _inventoryWarehouseEntityId(warehouseId)
            : _inventorySectionEntityId(warehouseId, normalizedSectionId),
        note: intent.summary,
        payload: {
          'item_id': itemDbId,
          'delta': delta,
          'section_id': normalizedSectionId,
          'warehouse_id': warehouseId,
          'copilot': true,
        },
      );
      await _refreshAll();
      final message = delta > 0
          ? 'Ajout de $delta unité(s) enregistré.'
          : 'Retrait de ${delta.abs()} unité(s) enregistré.';
      _showSnack(message);
      return CopilotFeedback(message: message);
    } else {
      await OfflineActionsService.instance.enqueue(
        OfflineActionTypes.inventoryStockDelta,
        {
          'company_id': companyId,
          'warehouse_id': warehouseId,
          'item_id': itemDbId,
          'delta': delta,
          'section_id': normalizedSectionId,
          'note': intent.summary.isNotEmpty
              ? intent.summary
              : (entry.item['name']?.toString() ?? itemLabel),
          'action': 'copilot',
          'metadata': {
            'copilot': true,
          },
          'event': 'stock_delta',
        },
      );
      await _refreshPendingActionsCount();
      const message = 'Ajustement inventaire enregistré hors ligne.';
      _showOfflineQueuedSnack(message);
      return const CopilotFeedback(message: message);
    }
  }

  Future<CopilotFeedback?> _copilotHandleEquipmentTask(
    CopilotIntent intent,
  ) async {
    if (_equipment.isEmpty) {
      const message = 'Aucun équipement chargé.';
      _showSnack(message, error: true);
      return const CopilotFeedback(message: message, isError: true);
    }
    final payload = intent.payload;
    final equipmentId =
        _copilotPickString(payload, ['equipment_id', 'equip_id']);
    final equipmentName =
        _copilotPickString(payload, ['equipment_name', 'equipement']);
    Map<String, dynamic>? equipment =
        _findEquipment(equipmentId: equipmentId, name: equipmentName);
    equipment ??= await _copilotPromptEquipmentSelection();
    if (equipment == null) {
      const message = 'Aucun équipement sélectionné.';
      _showSnack(message, error: true);
      return const CopilotFeedback(message: message, isError: true);
    }
    final meta =
        Map<String, dynamic>.from(equipment['meta'] as Map? ?? const {});
    final existingTasks = (meta['mechanic_tasks'] as List?)
            ?.whereType<Map>()
            .map((task) => Map<String, dynamic>.from(task))
            .toList() ??
        <Map<String, dynamic>>[];
    final taskTitle = _copilotPickString(
          payload,
          ['task', 'task_name', 'action', 'note'],
        ) ??
        (intent.summary.isNotEmpty
            ? intent.summary
            : 'Tâche mécanique');
    final delay =
        _copilotPickInt(payload, ['delay_days', 'delai', 'due_in']) ?? 7;
    final repeat =
        _copilotPickInt(payload, ['repeat_days', 'repeat_every']);
    final priority =
        _normalizePriority(_copilotPickString(payload, ['priority']) ?? 'moyen');
    final task = <String, dynamic>{
      'id': 'copilot_${DateTime.now().microsecondsSinceEpoch}',
      'title': taskTitle,
      'delay_days': delay <= 0 ? 1 : delay,
      'priority': priority,
      'created_at': DateTime.now().toIso8601String(),
      if (repeat != null && repeat > 0) 'repeat_every_days': repeat,
    };
    final equipmentLabel =
        equipment['name']?.toString() ?? 'Équipement';
    existingTasks.add(task);
    meta['mechanic_tasks'] = existingTasks;
    final events = [
      {
        'event': 'mechanic_task_added',
        'category': 'mechanic',
        'note': taskTitle,
        'payload': {
          'task_id': task['id'],
          'priority': priority,
          'delay_days': task['delay_days'],
          'copilot': true,
        },
      },
    ];

    final confirmLines = [
      'Équipement : $equipmentLabel',
      'Tâche : $taskTitle',
      'Priorité : ${priority.toUpperCase()}',
      'Délai : ${task['delay_days']} jour(s)',
      if (repeat != null && repeat > 0)
        'Rappel : tous les $repeat jour(s)',
    ];
    final confirmed = await _confirmCopilotAction(
      title: 'Ajouter cette tâche ?',
      lines: confirmLines,
    );
    if (confirmed != true) {
      const message = 'Tâche annulée.';
      return const CopilotFeedback(message: message);
    }

    return await _applyEquipmentMetaUpdate(
      equipment: equipment,
      nextMeta: meta,
      events: events,
      successMessage: 'Tâche mécanique ajoutée par Copilot.',
    );
  }

  Future<CopilotFeedback?> _copilotHandleDieselLog(
    CopilotIntent intent,
  ) async {
    if (_equipment.isEmpty) {
      const message = 'Aucun équipement chargé.';
      _showSnack(message, error: true);
      return const CopilotFeedback(message: message, isError: true);
    }
    final payload = intent.payload;
    Map<String, dynamic>? equipment = _findEquipment(
      equipmentId: _copilotPickString(payload, ['equipment_id']),
      name: _copilotPickString(payload, ['equipment_name', 'equipement']),
    );
    equipment ??= await _copilotPromptEquipmentSelection();
    if (equipment == null) {
      const message = 'Aucun équipement sélectionné.';
      _showSnack(message, error: true);
      return const CopilotFeedback(message: message, isError: true);
    }
    final meta =
        Map<String, dynamic>.from(equipment['meta'] as Map? ?? const {});
    final logs = (meta['diesel_logs'] as List?)
            ?.whereType<Map>()
            .map((log) => Map<String, dynamic>.from(log))
            .toList() ??
        <Map<String, dynamic>>[];

    double? liters = _copilotPickDouble(
      payload,
      ['liters', 'fuel_liters', 'diesel_liters', 'qty'],
    );
    liters ??= _extractFirstDouble(intent.rawText);
    if (liters == null || liters <= 0) {
      liters = await _copilotPromptDouble(
        title: 'Quantité de carburant ?',
        description: 'Entre les litres ajoutés. Utilise un nombre positif.',
      );
    }
    if (liters == null || liters <= 0) {
      const message = 'Quantité de carburant requise.';
      _showSnack(message, error: true);
      return const CopilotFeedback(message: message, isError: true);
    }

    final note = _copilotPickString(payload, ['note', 'comment']) ??
        (intent.summary.isNotEmpty ? intent.summary : null);
    final equipmentLabel = equipment['name']?.toString() ?? 'Équipement';
    final confirmed = await _confirmCopilotAction(
      title: 'Ajouter une entrée diesel ?',
      lines: [
        'Équipement : $equipmentLabel',
        'Quantité : ${liters.toStringAsFixed(1)} L',
        if (note != null && note.isNotEmpty) 'Note : $note',
        if (!_isOnline) 'Mode hors ligne — journal en attente.',
      ],
    );
    if (confirmed != true) {
      const message = 'Entrée diesel annulée.';
      return const CopilotFeedback(message: message);
    }

    final entry = {
      'id': 'copilot_${DateTime.now().microsecondsSinceEpoch}',
      'liters': liters,
      'note': note,
      'created_at': DateTime.now().toIso8601String(),
    };
    logs.add(entry);
    meta['diesel_logs'] = logs;

    return await _applyEquipmentMetaUpdate(
      equipment: equipment,
      nextMeta: meta,
      events: [
        {
          'event': 'diesel_entry_added',
          'category': 'diesel',
          'note': '${liters.toStringAsFixed(1)} L',
          'payload': {
            'liters': liters,
            'copilot': true,
          },
        },
      ],
      successMessage: 'Entrée diesel ajoutée.',
    );
  }

  String? _copilotPickString(
    Map<String, dynamic> payload,
    List<String> keys,
  ) {
    for (final key in keys) {
      final raw = payload[key];
      if (raw is String && raw.trim().isNotEmpty) {
        return raw.trim();
      }
    }
    return null;
  }

  int? _copilotPickInt(
    Map<String, dynamic> payload,
    List<String> keys,
  ) {
    for (final key in keys) {
      final parsed = _copilotParseInt(payload[key]);
      if (parsed != null) return parsed;
    }
    return null;
  }

  double? _copilotPickDouble(
    Map<String, dynamic> payload,
    List<String> keys,
  ) {
    for (final key in keys) {
      final parsed = _copilotParseDouble(payload[key]);
      if (parsed != null) return parsed;
    }
    return null;
  }

  int? _copilotParseInt(dynamic value) {
    if (value == null) return null;
    if (value is int) return value;
    if (value is double) return value.round();
    if (value is num) return value.toInt();
    if (value is String) {
      final normalized = value.trim();
      if (normalized.isEmpty) return null;
      final cleaned = normalized.replaceAll(RegExp(r'[^0-9\-]'), '');
      if (cleaned.isEmpty) return null;
      return int.tryParse(cleaned);
    }
    return null;
  }

  double? _copilotParseDouble(dynamic value) {
    if (value == null) return null;
    if (value is double) return value;
    if (value is int) return value.toDouble();
    if (value is num) return value.toDouble();
    if (value is String) {
      final normalized = value.replaceAll(',', '.').trim();
      if (normalized.isEmpty) return null;
      return double.tryParse(normalized);
    }
    return null;
  }

  bool _copilotShouldMarkPurchaseRequest(String? action, String? rawText) {
    final normalizedAction = action?.toLowerCase();
    const actionKeywords = {
      'mark_purchased',
      'completed',
      'complete',
      'mettre_a_placer',
      'marque_achete',
      'marquer_achete',
    };
    if (normalizedAction != null && actionKeywords.contains(normalizedAction)) {
      return true;
    }
    final normalizedText = _copilotNormalizeText(rawText ?? '');
    if (normalizedText.isEmpty) return false;
    const fragments = [
      'j ai achete',
      'je les ai achete',
      'deja achete',
      'marque comme achete',
      'mettre a placer',
      'met les a placer',
      'mettre les a placer',
      'c est recu',
      'bien recu',
      'commande recu',
      'deja recu',
      'c est arrive',
      'arrive ce matin',
    ];
    for (final fragment in fragments) {
      if (normalizedText.contains(fragment)) return true;
    }
    return false;
  }

  Map<String, dynamic>? _copilotFindPurchaseRequestByName(String? query) {
    final normalized = _copilotNormalizeText(query ?? '');
    if (normalized.isEmpty) return null;
    Map<String, dynamic>? bestMatch;
    var bestScore = 0;
    final tokens = normalized.split(' ')..removeWhere((token) => token.isEmpty);
    for (final request in _purchaseRequests) {
      final name = request['name']?.toString();
      if (name == null) continue;
      final candidate = _copilotNormalizeText(name);
      if (candidate.isEmpty) continue;
      if (candidate == normalized) {
        return request;
      }
      final score = tokens
          .where((token) => token.length >= 3 && candidate.contains(token))
          .length;
      if (score > bestScore) {
        bestScore = score;
        bestMatch = request;
      }
    }
    return bestScore == 0 ? null : bestMatch;
  }

  String _copilotNormalizeText(String input) {
    if (input.isEmpty) return '';
    final buffer = StringBuffer();
    for (final rune in input.toLowerCase().runes) {
      final char = String.fromCharCode(rune);
      buffer.write(_accentMap[char] ?? char);
    }
    return buffer
        .toString()
        .replaceAll(RegExp(r'[^a-z0-9]+'), ' ')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
  }

  bool _copilotContainsAny(String haystack, List<String> values) {
    for (final value in values) {
      if (value.isEmpty) continue;
      if (haystack.contains(value)) return true;
    }
    return false;
  }

  String _normalizeLabel(String value) => value.trim().toLowerCase();

  bool _matchesLabel(String query, String? candidate) {
    if (candidate == null || candidate.trim().isEmpty) return false;
    final normalizedCandidate = _normalizeLabel(candidate);
    return normalizedCandidate == query ||
        normalizedCandidate.contains(query) ||
        query.contains(normalizedCandidate);
  }

  String? _matchWarehouseId(String query) {
    final normalized = _normalizeLabel(query);
    for (final warehouse in _warehouses) {
      final id = warehouse['id']?.toString();
      if (id == null) continue;
      if (id == query) return id;
      final name = warehouse['name']?.toString();
      final code = warehouse['code']?.toString();
      if (_matchesLabel(normalized, name) || _matchesLabel(normalized, code)) {
        return id;
      }
    }
    return null;
  }

  String? _matchSectionId(String warehouseId, String query) {
    final normalized = _normalizeLabel(query);
    final warehouse = _warehouses.firstWhere(
      (element) => element['id']?.toString() == warehouseId,
      orElse: () => const <String, dynamic>{},
    );
    final sections = warehouse['sections'];
    if (sections is List) {
      for (final raw in sections) {
        if (raw is! Map) continue;
        final sectionId = raw['id']?.toString();
        final name = raw['name']?.toString();
        final code = raw['code']?.toString();
        if (sectionId == query ||
            _matchesLabel(normalized, name) ||
            _matchesLabel(normalized, code)) {
          return sectionId;
        }
      }
    }
    if (normalized.contains('sans') || normalized.contains('aucun')) {
      return InventoryEntry.unassignedSectionKey;
    }
    return null;
  }

  InventoryEntry? _findInventoryEntry({
    String? itemId,
    String? sku,
    String? name,
  }) {
    if (itemId != null) {
      final normalized = itemId.trim();
      for (final entry in _inventory) {
        if (entry.item['id']?.toString() == normalized) return entry;
      }
    }
    if (sku != null) {
      final normalized = _normalizeLabel(sku);
      for (final entry in _inventory) {
        final entrySku = entry.item['sku']?.toString();
        if (entrySku != null && _matchesLabel(normalized, entrySku)) {
          return entry;
        }
      }
    }
    if (name != null) {
      final normalized = _normalizeLabel(name);
      for (final entry in _inventory) {
        final entryName = entry.item['name']?.toString();
        if (entryName != null && _matchesLabel(normalized, entryName)) {
          return entry;
        }
      }
    }
    return null;
  }

  String? _resolveWarehouseForEntry(
    InventoryEntry entry, {
    String? hint,
  }) {
    if (hint != null) {
      final match = _matchWarehouseId(hint);
      if (match != null && entry.warehouseSplit.containsKey(match)) {
        return match;
      }
    }
    if (entry.warehouseSplit.isEmpty) return null;
    final sorted = entry.warehouseSplit.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    return sorted.first.key;
  }

  String? _resolveSectionForEntry(
    InventoryEntry entry,
    String warehouseId, {
    String? hint,
  }) {
    final sections = entry.sectionSplit[warehouseId];
    if (hint != null) {
      final match = _matchSectionId(warehouseId, hint);
      if (match != null) {
        if (match == InventoryEntry.unassignedSectionKey ||
            sections == null ||
            sections.containsKey(match)) {
          return match;
        }
      }
    }
    if (sections == null || sections.isEmpty) {
      return InventoryEntry.unassignedSectionKey;
    }
    final sorted = sections.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    return sorted.first.key;
  }

  String? _normalizeSectionId(String? sectionId) {
    if (sectionId == null || sectionId == InventoryEntry.unassignedSectionKey) {
      return null;
    }
    return sectionId;
  }

  Map<String, dynamic>? _findEquipment({
    String? equipmentId,
    String? name,
  }) {
    if (equipmentId != null) {
      final id = equipmentId.trim();
      final match = _equipment.firstWhere(
        (item) => item['id']?.toString() == id,
        orElse: () => const <String, dynamic>{},
      );
      if (match.isNotEmpty) return match;
    }
    if (name != null) {
      final normalized = _normalizeLabel(name);
      for (final equip in _equipment) {
        final equipName = equip['name']?.toString();
        if (equipName != null && _matchesLabel(normalized, equipName)) {
          return equip;
        }
      }
    }
    return null;
  }

  Future<CopilotFeedback?> _applyEquipmentMetaUpdate({
    required Map<String, dynamic> equipment,
    required Map<String, dynamic> nextMeta,
    required List<Map<String, dynamic>> events,
    required String successMessage,
  }) async {
    final equipmentId = equipment['id']?.toString();
    if (equipmentId == null) {
      const message = 'Équipement inconnu.';
      _showSnack(message, error: true);
      return const CopilotFeedback(message: message, isError: true);
    }
    if (_isOnline) {
      final result = await _commands.updateEquipmentMeta(
        equipmentId: equipmentId,
        meta: nextMeta,
      );
      if (!result.ok || result.data == null) {
        final message = _describeError(result.error) ??
            'Impossible de mettre à jour cet équipement.';
        _showSnack(message, error: true);
        return CopilotFeedback(message: message, isError: true);
      }
      _replaceEquipment(result.data!);
      for (final event in events) {
        await _logJournal(
          scope: 'equipment',
          event: event['event']?.toString() ?? 'note',
          entityId: _equipmentEntityId(
            equipmentId,
            event['category']?.toString(),
          ),
          note: event['note']?.toString(),
          payload: event['payload'] is Map
              ? Map<String, dynamic>.from(event['payload'] as Map)
              : null,
        );
      }
      await _refreshAll();
      _showSnack(successMessage);
      return CopilotFeedback(message: successMessage);
    } else {
      final companyId = _overview?.membership?.companyId;
      if (companyId == null) {
        const message = 'Entreprise inconnue.';
        _showSnack(message, error: true);
        return const CopilotFeedback(message: message, isError: true);
      }
      final local = Map<String, dynamic>.from(equipment)
        ..['meta'] = nextMeta;
      _replaceEquipment(local);
      await OfflineActionsService.instance.enqueue(
        OfflineActionTypes.equipmentMetaUpdate,
        {
          'company_id': companyId,
          'equipment_id': equipmentId,
          'meta': nextMeta,
          if (events.isNotEmpty) 'events': events,
        },
      );
      await _refreshPendingActionsCount();
      _showOfflineQueuedSnack(successMessage);
      return CopilotFeedback(message: successMessage);
    }
  }

  String _normalizePriority(String raw) {
    final normalized = _normalizeLabel(raw);
    if (normalized.contains('haut') ||
        normalized.contains('urgent') ||
        normalized.contains('élev')) {
      return 'eleve';
    }
    if (normalized.contains('faible') || normalized.contains('low')) {
      return 'faible';
    }
    return 'moyen';
  }

  Future<bool?> _confirmCopilotAction({
    required String title,
    required List<String> lines,
  }) async {
    if (!mounted) return false;
    return showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(title),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            for (final line in lines)
              Padding(
                padding: const EdgeInsets.only(bottom: 6),
                child: Text(line),
              ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Annuler'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Confirmer'),
          ),
        ],
      ),
    );
  }

  Future<String?> _copilotPromptWarehouse(InventoryEntry entry) async {
    if (!mounted) return null;
    final candidates = entry.warehouseSplit.entries
        .where((item) => item.value > 0)
        .toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    if (candidates.isEmpty) return null;
    return showDialog<String>(
      context: context,
      builder: (context) => SimpleDialog(
        title: const Text('Choisir un entrepôt'),
        children: [
          for (final candidate in candidates)
            SimpleDialogOption(
              onPressed: () => Navigator.of(context).pop(candidate.key),
              child: Text(
                '${_warehouseNameById(candidate.key) ?? 'Entrepôt'} '
                '• ${candidate.value} en stock',
              ),
            ),
          SimpleDialogOption(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Annuler'),
          ),
        ],
      ),
    );
  }

  Future<String?> _copilotPromptSection(
    InventoryEntry entry,
    String warehouseId,
  ) async {
    if (!mounted) return null;
    final sections =
        entry.sectionSplit[warehouseId] ?? const <String, int>{};
    final options = sections.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    return showDialog<String>(
      context: context,
      builder: (context) => SimpleDialog(
        title: const Text('Section ?'),
        children: [
          if (options.isEmpty)
            SimpleDialogOption(
              onPressed: () => Navigator.of(context)
                  .pop(InventoryEntry.unassignedSectionKey),
              child: const Text('Sans section'),
            )
          else ...[
            for (final option in options)
              SimpleDialogOption(
                onPressed: () => Navigator.of(context).pop(option.key),
                child: Text(
                  '${_sectionLabel(warehouseId, option.key)} • ${option.value}',
                ),
              ),
            SimpleDialogOption(
              onPressed: () => Navigator.of(context)
                  .pop(InventoryEntry.unassignedSectionKey),
              child: const Text('Sans section'),
            ),
          ],
          SimpleDialogOption(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Annuler'),
          ),
        ],
      ),
    );
  }

  Future<InventoryEntry?> _copilotPromptInventoryItem({
    String? hint,
  }) async {
    if (!mounted || _inventory.isEmpty) return null;
    final entry = await showModalBottomSheet<InventoryEntry>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => _InventorySearchSheet(
        inventory: _inventory,
        initialQuery: hint,
      ),
    );
    return entry;
  }

  String _sectionLabel(String warehouseId, String? sectionId) {
    if (sectionId == null ||
        sectionId == InventoryEntry.unassignedSectionKey) {
      return 'Sans section';
    }
    return _sectionNameById(warehouseId, sectionId) ?? 'Section';
  }

  int? _extractFirstInt(String? text) {
    if (text == null || text.trim().isEmpty) return null;
    final match = RegExp(r'(-?\d+)').firstMatch(text);
    if (match == null) return null;
    return int.tryParse(match.group(0)!);
  }

  double? _extractFirstDouble(String? text) {
    if (text == null || text.trim().isEmpty) return null;
    final match = RegExp(r'(-?\d+(?:[.,]\d+)?)').firstMatch(text);
    if (match == null) return null;
    final normalized = match.group(0)!.replaceAll(',', '.');
    return double.tryParse(normalized);
  }

  String? _inferItemName(String? rawText) {
    if (rawText == null || rawText.trim().isEmpty) return null;
    var candidate = rawText.toLowerCase();
    candidate = candidate.replaceAll(RegExp(r'\d+'), ' ');
    for (final filler in [
      'mettre',
      'mets',
      'met',
      'mettez',
      'ajoute',
      'ajouter',
      'ajoutez',
      'commande',
      'en commande',
      'a commande',
      'à commander',
      'commander',
      'mettre en',
      'mettre en commande',
      'fait',
      'mettre',
      'dans la liste',
      'dans',
      'la',
      'le',
      'les',
      'des',
      'un',
      'une'
    ]) {
      candidate = candidate.replaceAll(filler, ' ');
    }
    candidate = candidate.replaceAll(RegExp(r'[^a-zA-Z0-9 ]'), ' ');
    candidate = candidate.replaceAll(RegExp(r'\s+'), ' ').trim();
    if (candidate.isEmpty) return null;
    return candidate;
  }

  Future<Map<String, dynamic>?> _copilotPromptEquipmentSelection() async {
    if (!mounted || _equipment.isEmpty) return null;
    final sorted = _equipment
        .map((item) => Map<String, dynamic>.from(item))
        .toList()
      ..sort(
        (a, b) =>
            (a['name']?.toString() ?? '')
                .toLowerCase()
                .compareTo((b['name']?.toString() ?? '').toLowerCase()),
      );
    return showModalBottomSheet<Map<String, dynamic>>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) {
        final maxHeight = min<double>(420, 72.0 * sorted.length + 80);
        return Material(
          color: Colors.white,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
          child: SafeArea(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const ListTile(
                    contentPadding: EdgeInsets.zero,
                    title: Text('Sélectionner un équipement'),
                    subtitle: Text('Choisis la fiche concernée.'),
                  ),
                  SizedBox(
                    height: maxHeight,
                    child: ListView.separated(
                      itemCount: sorted.length,
                      separatorBuilder: (_, __) => const Divider(height: 1),
                      itemBuilder: (context, index) {
                        final equip = sorted[index];
                        final title =
                            equip['name']?.toString() ?? 'Équipement';
                        final brand = equip['brand']?.toString();
                        final model = equip['model']?.toString();
                        final serial = equip['serial']?.toString();
                        final details = [
                          if (brand != null && brand.isNotEmpty) brand,
                          if (model != null && model.isNotEmpty) model,
                          if (serial != null && serial.isNotEmpty) serial,
                        ].join(' • ');
                        return ListTile(
                          title: Text(title),
                          subtitle: details.isEmpty ? null : Text(details),
                          onTap: () => Navigator.of(context).pop(equip),
                          trailing: const Icon(Icons.chevron_right),
                        );
                      },
                    ),
                  ),
                  const SizedBox(height: 8),
                  TextButton(
                    onPressed: () => Navigator.of(context).pop(),
                    child: const Text('Annuler'),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  Future<int?> _copilotPromptQuantity({
    required String title,
    String? description,
  }) async {
    if (!mounted) return null;
    return showDialog<int>(
      context: context,
      builder: (_) => _IntegerInputDialog(
        title: title,
        helperText: description,
      ),
    );
  }

  Future<double?> _copilotPromptDouble({
    required String title,
    String? description,
  }) async {
    if (!mounted) return null;
    return showDialog<double>(
      context: context,
      builder: (_) => _DecimalInputDialog(
        title: title,
        helperText: description,
      ),
    );
  }

  void _recordCopilotIncident(String input, String reason) {
    final incident = _CopilotIncident(
      timestamp: DateTime.now(),
      input: input,
      reason: reason,
    );
    _copilotIncidents.add(incident);
    if (_copilotIncidents.length > 50) {
      _copilotIncidents.removeAt(0);
    }
    debugPrint(
        '[LogAI] incident: ${incident.timestamp.toIso8601String()} — ${incident.input} :: ${incident.reason}');
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
        final pendingRequests = _purchaseRequests
            .where(
              (request) =>
                  (request['status']?.toString() ?? 'pending') == 'pending',
            )
            .toList(growable: false);
        return _ListTab(
          requests: pendingRequests,
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
          onShowCompanyJournal: _handleShowCompanyJournal,
          onDeleteJoinCode: _handleDeleteJoinCode,
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
              final payload = result.data ?? <String, dynamic>{};
              await _logJournal(
                scope: 'equipment',
                event: 'equipment_created',
                entityId: payload['id']?.toString(),
                note: nameCtrl.text.trim(),
                payload: payload,
              );
              await _refreshAll();
            }

            return AlertDialog(
              title: const Text('Nouvel équipement'),
              content: Form(
                key: formKey,
                child: SingleChildScrollView(
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
        isOnline: _isOnline,
        onCreateOffline: _isOnline
            ? null
            : ({
                required String name,
                required int qty,
                String? warehouseId,
                String? sectionId,
                String? note,
              }) =>
                _createPurchaseRequestOffline(
                  name: name,
                  qty: qty,
                  warehouseId: warehouseId,
                  sectionId: sectionId,
                  note: note,
                ),
      ),
    );

    if (created != null && mounted) {
      final requestId = created['id']?.toString();
      if (_isOnline) {
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
  }

  String? _purchaseRequestId(Map<String, dynamic> data) {
    return data['id']?.toString();
  }

  void _replacePurchaseRequest(Map<String, dynamic> updated) {
    final targetId = _purchaseRequestId(updated);
    if (targetId == null) return;
    setState(() {
      var found = false;
      _purchaseRequests = _purchaseRequests.map((request) {
        if (_purchaseRequestId(request) == targetId) {
          found = true;
          return updated;
        }
        return request;
      }).toList();
      if (!found) {
        _purchaseRequests = [..._purchaseRequests, updated];
      }
    });
    runDetached(_persistPurchaseRequestsCache());
  }

  void _removePurchaseRequest(String requestId) {
    setState(() {
      _purchaseRequests = _purchaseRequests
          .where((request) => _purchaseRequestId(request) != requestId)
          .toList();
    });
    runDetached(_persistPurchaseRequestsCache());
  }

  Future<void> _persistPurchaseRequestsCache() async {
    final userId = Supa.i.auth.currentUser?.id;
    if (userId == null) return;
    await OfflineStorage.instance.saveCache(
      '$userId::${OfflineCacheKeys.purchaseRequests}',
      _purchaseRequests,
    );
  }

  void _replaceEquipment(Map<String, dynamic> updated) {
    final id = updated['id']?.toString();
    if (id == null) return;
    setState(() {
      _equipment = _equipment
          .map((equip) =>
              equip['id']?.toString() == id ? updated : equip)
          .toList();
    });
    runDetached(_persistEquipmentCache());
  }

  Future<void> _persistEquipmentCache() async {
    final userId = Supa.i.auth.currentUser?.id;
    if (userId == null) return;
    await OfflineStorage.instance.saveCache(
      '$userId::${OfflineCacheKeys.equipment}',
      _equipment,
    );
  }

  Future<Map<String, dynamic>?> _updatePurchaseRequestLocally(
    String requestId,
    Map<String, dynamic> patch,
  ) async {
    Map<String, dynamic>? updated;
    setState(() {
      _purchaseRequests = _purchaseRequests.map((request) {
        if (_purchaseRequestId(request) == requestId) {
          updated = Map<String, dynamic>.from(request)..addAll(patch);
          return updated!;
        }
        return request;
      }).toList();
    });
    await _persistPurchaseRequestsCache();
    return updated;
  }

  void _showOfflineQueuedSnack([String message = 'Action enregistrée hors ligne.']) {
    _showSnack(message);
  }

  Future<void> _refreshPendingActionsCount() async {
    final actions = await OfflineStorage.instance.pendingActions();
    if (!mounted) return;
    setState(() => _pendingActionCount = actions.length);
  }

  Future<CommandResult<Map<String, dynamic>>> _markPurchaseRequestToPlaceOffline(
    Map<String, dynamic> request,
    int qty,
  ) async {
    final updated = await _markPurchaseRequestToPlaceLocally(request, qty);
    if (updated == null) {
      return const CommandResult(error: 'Action hors ligne impossible.');
    }
    return CommandResult<Map<String, dynamic>>(data: updated);
  }

  Future<Map<String, dynamic>?> _markPurchaseRequestToPlaceLocally(
    Map<String, dynamic> request,
    int qty,
  ) async {
    final requestId = _purchaseRequestId(request);
    if (requestId == null) return null;
    final purchasedAt = DateTime.now().toIso8601String();
    final updated = await _updatePurchaseRequestLocally(
      requestId,
      {
        'qty': qty,
        'status': 'to_place',
        'purchased_at': purchasedAt,
      },
    );
    if (updated == null) return null;
    await OfflineActionsService.instance.enqueue(
      OfflineActionTypes.purchaseRequestMarkToPlace,
      {
        'request_id': requestId,
        'qty': qty,
        'purchased_at': purchasedAt,
        'note': request['name']?.toString(),
      },
    );
    await _refreshPendingActionsCount();
    _showOfflineQueuedSnack('Demande mise “à placer” (hors ligne).');
    return updated;
  }

  Future<Map<String, dynamic>?> _createPurchaseRequestOffline({
    required String name,
    required int qty,
    String? warehouseId,
    String? sectionId,
    String? note,
  }) async {
    final tempId = 'local_${DateTime.now().microsecondsSinceEpoch}';
    Map<String, dynamic>? warehouse;
    if (warehouseId != null && warehouseId.isNotEmpty) {
      final match = _warehouses.firstWhere(
        (candidate) => candidate['id']?.toString() == warehouseId,
        orElse: () => const <String, dynamic>{},
      );
      if (match.isNotEmpty) {
        warehouse = match;
      }
    }
    final record = <String, dynamic>{
      'id': tempId,
      'name': name,
      'qty': qty,
      'status': 'pending',
      'note': note,
      'warehouse_id': warehouseId,
      'section_id': sectionId,
      'created_at': DateTime.now().toIso8601String(),
      if (warehouse != null) 'warehouse': warehouse,
    };
    setState(() {
      _purchaseRequests = [..._purchaseRequests, record];
    });
    await _persistPurchaseRequestsCache();
    await OfflineActionsService.instance.enqueue(
      OfflineActionTypes.purchaseRequestCreate,
      {
        'temp_id': tempId,
        'name': name,
        'qty': qty,
        'warehouse_id': warehouseId,
        'section_id': sectionId,
        'note': note,
      },
    );
    await _refreshPendingActionsCount();
    _showOfflineQueuedSnack('Demande ajoutée (hors ligne).');
    return record;
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

    Future<void> queueOfflineUpdate() async {
      await _updatePurchaseRequestLocally(requestId, {'qty': newQty});
      await OfflineActionsService.instance.enqueue(
        OfflineActionTypes.purchaseRequestUpdate,
        {
          'request_id': requestId,
          'patch': {'qty': newQty},
          'log': {
            'event': 'purchase_request_qty_updated',
            'note': requestName,
            'payload': {
              'qty': newQty,
              'delta': delta,
              'request_id': requestId,
            },
          },
        },
      );
      await _refreshPendingActionsCount();
      _showOfflineQueuedSnack('Quantité mise à jour (hors ligne).');
    }

    if (!_isOnline) {
      await queueOfflineUpdate();
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
      if (!_isOnline) {
        await queueOfflineUpdate();
        return;
      }
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
        onSubmit: (qty) {
          if (!_isOnline) {
            return _markPurchaseRequestToPlaceOffline(request, qty);
          }
          return _commands.updatePurchaseRequest(
            requestId: requestId,
            patch: {
              'qty': qty,
              'status': 'to_place',
              'purchased_at': DateTime.now().toIso8601String(),
            },
          );
        },
      ),
    );

    if (updated != null && mounted) {
      _replacePurchaseRequest(updated);
      if (_isOnline) {
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
          isOnline: () => _isOnline,
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

    if (!_isOnline) {
      _removePurchaseRequest(requestId);
      await OfflineActionsService.instance.enqueue(
        OfflineActionTypes.purchaseRequestDelete,
        {
          'request_id': requestId,
          'note': request['name']?.toString(),
        },
      );
      await _refreshPendingActionsCount();
      _showOfflineQueuedSnack('Demande supprimée (hors ligne).');
      return;
    }

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
    final membership = _overview?.membership;
    if (membership?.companyId == null) {
      _showSnack('Entreprise inconnue.', error: true);
      return;
    }

    final action = await showModalBottomSheet<_InviteOption>(
      context: context,
      builder: (context) {
        return SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ListTile(
                leading: const Icon(Icons.mail_outline),
                title: const Text('Inviter par e-mail'),
                subtitle: const Text('Envoie une invitation Supabase.'),
                onTap: () => Navigator.of(context).pop(_InviteOption.email),
              ),
              ListTile(
                leading: const Icon(Icons.qr_code_2),
                title: const Text('Créer un code de connexion'),
                subtitle: const Text('Code partagé pour rejoindre l’entreprise.'),
                onTap: () => Navigator.of(context).pop(_InviteOption.joinCode),
              ),
            ],
          ),
        );
      },
    );

    switch (action) {
      case _InviteOption.email:
        await _promptInviteMemberByEmail();
        break;
      case _InviteOption.joinCode:
        await _promptCreateJoinCode();
        break;
      case null:
        break;
    }
  }

  Future<void> _promptInviteMemberByEmail() async {
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

  Future<void> _promptCreateJoinCode() async {
    final companyId = _overview?.membership?.companyId;
    if (companyId == null) return;

    final formKey = GlobalKey<FormState>();
    final codeCtrl = TextEditingController(text: _generateJoinCode());
    final labelCtrl = TextEditingController();
    final usesCtrl = TextEditingController();
    const roles = CompanyRoles.values;
    var selectedRole = CompanyRoles.employee;
    DateTime? expiresAt;
    var submitting = false;
    String? dialogError;

    String formatExpireDate(DateTime? date) {
      if (date == null) return 'Aucune expiration';
      return DateFormat.yMMMMd('fr_CA').format(date);
    }

    DateTime endOfDay(DateTime date) {
      return DateTime(date.year, date.month, date.day, 23, 59, 59);
    }

    Future<void> showCodeDialog(String code) async {
      if (!mounted) return;
      await showDialog<void>(
        context: context,
        builder: (context) {
          return AlertDialog(
            title: const Text('Code de connexion créé'),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                SelectableText(
                  code,
                  textAlign: TextAlign.center,
                  style: Theme.of(context)
                      .textTheme
                      .headlineSmall
                      ?.copyWith(fontWeight: FontWeight.w700),
                ),
                const SizedBox(height: 12),
                const Text(
                  'Partage ce code avec ton collègue pour qu’il rejoigne l’entreprise.',
                ),
              ],
            ),
            actions: [
              TextButton.icon(
                onPressed: () {
                  Clipboard.setData(ClipboardData(text: code));
                },
                icon: const Icon(Icons.copy),
                label: const Text('Copier'),
              ),
              FilledButton(
                onPressed: () => Navigator.of(context).pop(),
                child: const Text('Fermer'),
              ),
            ],
          );
        },
      );
    }

    await showDialog<void>(
      context: context,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            Future<void> pickExpiration() async {
              final now = DateTime.now();
              final initial = expiresAt ?? now.add(const Duration(days: 14));
              final selected = await showDatePicker(
                context: context,
                initialDate: initial,
                firstDate: now,
                lastDate: now.add(const Duration(days: 365 * 2)),
              );
              if (selected != null) {
                setDialogState(() => expiresAt = endOfDay(selected));
              }
            }

            Future<void> submit() async {
              if (!formKey.currentState!.validate()) return;
              setDialogState(() {
                submitting = true;
                dialogError = null;
              });

              final rawCode =
                  codeCtrl.text.replaceAll(RegExp(r'\s+'), '').toUpperCase();
              final codeHash =
                  crypto.sha256.convert(utf8.encode(rawCode)).toString();
              final codeHint = rawCode.length <= 4
                  ? rawCode
                  : rawCode.substring(rawCode.length - 4);
              final maxUses = int.tryParse(usesCtrl.text.trim());

              final result = await _commands.createJoinCode(
                companyId: companyId,
                role: selectedRole,
                codeHash: codeHash,
                codeHint: codeHint,
                label: labelCtrl.text.trim(),
                maxUses: maxUses != null && maxUses > 0 ? maxUses : null,
                expiresAt: expiresAt,
              );

              if (!result.ok) {
                setDialogState(() {
                  submitting = false;
                  dialogError =
                      _describeError(result.error) ?? 'Création impossible.';
                });
                return;
              }

              if (!context.mounted || !mounted) return;
              Navigator.of(context).pop();
              await showCodeDialog(rawCode);
              _showSnack('Code créé.');
              await _refreshAll();
            }

            return AlertDialog(
              title: const Text('Nouveau code de connexion'),
              content: Form(
                key: formKey,
                child: SingleChildScrollView(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      TextFormField(
                        controller: codeCtrl,
                        decoration: InputDecoration(
                          labelText: 'Code à partager',
                          suffixIcon: IconButton(
                            tooltip: 'Regénérer',
                            icon: const Icon(Icons.refresh),
                            onPressed: () => setDialogState(
                              () => codeCtrl.text = _generateJoinCode(),
                            ),
                          ),
                        ),
                        textCapitalization: TextCapitalization.characters,
                        validator: (value) {
                          if (value == null || value.trim().isEmpty) {
                            return 'Code requis';
                          }
                          if (value.trim().replaceAll(RegExp(r'\s+'), '').length <
                              4) {
                            return 'Au moins 4 caractères';
                          }
                          return null;
                        },
                      ),
                      const SizedBox(height: 12),
                      TextFormField(
                        controller: labelCtrl,
                        decoration: const InputDecoration(
                          labelText: 'Libellé (optionnel)',
                        ),
                      ),
                      const SizedBox(height: 12),
                      DropdownButtonFormField<String>(
                        value: selectedRole,
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
                        controller: usesCtrl,
                        decoration: const InputDecoration(
                          labelText: 'Nombre maximum d’utilisations',
                          hintText: 'Laisser vide pour illimité',
                        ),
                        keyboardType: TextInputType.number,
                      ),
                      const SizedBox(height: 12),
                      ListTile(
                        contentPadding: EdgeInsets.zero,
                        leading: const Icon(Icons.today),
                        title: Text(formatExpireDate(expiresAt)),
                        subtitle: const Text(
                          'Choisis une date d’expiration (optionnel).',
                        ),
                        trailing: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            IconButton(
                              tooltip: 'Effacer',
                              onPressed: expiresAt == null
                                  ? null
                                  : () => setDialogState(() => expiresAt = null),
                              icon: const Icon(Icons.clear),
                            ),
                            IconButton(
                              tooltip: 'Définir',
                              onPressed: pickExpiration,
                              icon: const Icon(Icons.edit_calendar),
                            ),
                          ],
                        ),
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
                      : const Text('Créer le code'),
                ),
              ],
            );
          },
        );
      },
    );

    codeCtrl.dispose();
    labelCtrl.dispose();
    usesCtrl.dispose();
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

  Future<void> _handleDeleteJoinCode(CompanyJoinCode code) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text('Supprimer le code ?'),
          content: const Text(
            'Le code sera supprimé définitivement. Cette action est irréversible.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: const Text('Annuler'),
            ),
            FilledButton(
              onPressed: () => Navigator.of(context).pop(true),
              style: FilledButton.styleFrom(
                backgroundColor: Colors.red,
              ),
              child: const Text('Supprimer'),
            ),
          ],
        );
      },
    );

    if (confirm != true) return;
    final result = await _commands.deleteJoinCode(codeId: code.id);
    if (!result.ok) {
      _showSnack(
        _describeError(result.error) ?? 'Impossible de supprimer ce code.',
        error: true,
      );
      return;
    }
    _showSnack('Code supprimé.');
    if (mounted) {
      setState(() {
        _joinCodes =
            _joinCodes.where((candidate) => candidate.id != code.id).toList();
      });
    }
    await _refreshAll();
  }

  void _handleQuickAction(_QuickAction action) {
    runDetached(_launchQuickActionFlow(action));
  }

  Future<void> _launchQuickActionFlow(_QuickAction action) async {
    switch (action) {
      case _QuickAction.pickItem:
        await _handleQuickPickPiece();
        break;
      case _QuickAction.placeOrder:
        await _promptCreatePurchaseRequest();
        break;
      case _QuickAction.logFuel:
        await _handleQuickLogFuel();
        break;
      case _QuickAction.addMechanicTask:
        await _handleQuickMechanicTask();
        break;
    }
  }

  String _quickActionLabel(_QuickAction action) {
    switch (action) {
      case _QuickAction.pickItem:
        return 'Prendre une pièce';
      case _QuickAction.placeOrder:
        return 'Mettre en commande';
      case _QuickAction.logFuel:
        return 'Faire le plein';
      case _QuickAction.addMechanicTask:
        return 'Tâche mécanique';
    }
  }

  Future<void> _handleQuickPickPiece() async {
    final entry = await _copilotPromptInventoryItem(hint: 'pièce');
    if (entry == null) return;
    final warehouseId = await _copilotPromptWarehouse(entry);
    if (warehouseId == null) return;
    final sectionId = await _copilotPromptSection(entry, warehouseId);
    final qty = await _copilotPromptQuantity(
      title: 'Quantité à retirer',
      description: 'Entier positif (sera retiré du stock).',
    );
    if (qty == null || qty <= 0) return;
    await _copilotAdjustInventory(
      CopilotIntent(
        type: CopilotIntentType.inventoryAdjust,
        summary: 'Retirer $qty ${entry.item['name']?.toString() ?? 'pièce'}',
        payload: {
          'item_id': entry.item['id']?.toString(),
          'item_name': entry.item['name']?.toString(),
          'delta': -qty,
          'warehouse': warehouseId,
          'section': sectionId,
          'note': 'Action rapide',
        },
      ),
    );
  }

  Future<void> _handleQuickLogFuel() async {
    final equipment = await _copilotPromptEquipmentSelection();
    if (equipment == null) return;
    final liters = await _copilotPromptDouble(
      title: 'Litres ajoutés',
      description: 'Entre une valeur positive en litres.',
    );
    if (liters == null || liters <= 0) return;
    final note = await _promptOptionalNote();
    await _copilotHandleDieselLog(
      CopilotIntent(
        type: CopilotIntentType.dieselLog,
        summary: note?.isNotEmpty == true
            ? note!
            : 'Diesel ${liters.toStringAsFixed(1)} L',
        payload: {
          'equipment_id': equipment['id']?.toString(),
          'equipment_name': equipment['name']?.toString(),
          'liters': liters,
          if (note != null && note.trim().isNotEmpty) 'note': note.trim(),
        },
      ),
    );
  }

  Future<void> _handleQuickMechanicTask() async {
    final equipment = await _copilotPromptEquipmentSelection();
    if (equipment == null) return;
    final details = await _promptMechanicTaskDetails();
    if (details == null) return;
    await _copilotHandleEquipmentTask(
      CopilotIntent(
        type: CopilotIntentType.equipmentTask,
        summary: details['title'] as String,
        payload: {
          'equipment_id': equipment['id']?.toString(),
          'equipment_name': equipment['name']?.toString(),
          'task': details['title'],
          'delay_days': details['delay_days'],
          'priority': details['priority'],
          if (details['repeat_days'] != null)
            'repeat_days': details['repeat_days'],
        },
      ),
    );
  }

  Future<Map<String, dynamic>?> _promptMechanicTaskDetails() async {
    return showDialog<Map<String, dynamic>>(
      context: context,
      builder: (context) => const _MechanicTaskDialog(),
    );
  }

  Future<String?> _promptOptionalNote({
    String title = 'Ajouter une note',
    String label = 'Note (optionnel)',
  }) async {
    final ctrl = TextEditingController();
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: Colors.white,
        title: Text(title),
        content: TextField(
          controller: ctrl,
          decoration: InputDecoration(labelText: label),
          maxLines: 3,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Ignorer'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Enregistrer'),
          ),
        ],
      ),
    );
    final value = ctrl.text.trim();
    ctrl.dispose();
    if (confirmed == true) {
      return value;
    }
    return null;
  }

  Future<void> _handleShowCompanyJournal() async {
    await _handleOpenJournal(scopeOverride: 'company');
  }

  String _generateJoinCode({int length = 8}) {
    const chars = 'ABCDEFGHJKLMNPQRSTUVWXYZ23456789';
    return List<String>.generate(
      length,
      (_) => chars[_random.nextInt(chars.length)],
    ).join();
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

  String _equipmentEntityId(String equipmentId, String? category) {
    if (category == null ||
        category.isEmpty ||
        category == 'general') {
      return equipmentId;
    }
    return '$equipmentId::$category';
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

  void _registerOfflineHandlers() {
    if (_offlineHandlersRegistered) return;
    OfflineActionsService.instance.registerHandler(
      OfflineActionTypes.purchaseRequestUpdate,
      _processQueuedPurchaseRequestUpdate,
    );
    OfflineActionsService.instance.registerHandler(
      OfflineActionTypes.purchaseRequestDelete,
      _processQueuedPurchaseRequestDelete,
    );
    OfflineActionsService.instance.registerHandler(
      OfflineActionTypes.purchaseRequestMarkToPlace,
      _processQueuedPurchaseRequestMarkToPlace,
    );
    OfflineActionsService.instance.registerHandler(
      OfflineActionTypes.purchaseRequestCreate,
      _processQueuedPurchaseRequestCreate,
    );
    OfflineActionsService.instance.registerHandler(
      OfflineActionTypes.inventoryStockDelta,
      _processQueuedInventoryStockDelta,
    );
    OfflineActionsService.instance.registerHandler(
      OfflineActionTypes.inventoryDeleteItem,
      _processQueuedInventoryDeleteItem,
    );
    OfflineActionsService.instance.registerHandler(
      OfflineActionTypes.equipmentMetaUpdate,
      _processQueuedEquipmentMetaUpdate,
    );
    _offlineHandlersRegistered = true;
  }

  void _unregisterOfflineHandlers() {
    if (!_offlineHandlersRegistered) return;
    OfflineActionsService.instance
        .registerHandler(OfflineActionTypes.purchaseRequestUpdate, null);
    OfflineActionsService.instance
        .registerHandler(OfflineActionTypes.purchaseRequestDelete, null);
    OfflineActionsService.instance.registerHandler(
        OfflineActionTypes.purchaseRequestMarkToPlace, null);
    OfflineActionsService.instance
        .registerHandler(OfflineActionTypes.purchaseRequestCreate, null);
    OfflineActionsService.instance
        .registerHandler(OfflineActionTypes.inventoryStockDelta, null);
    OfflineActionsService.instance
        .registerHandler(OfflineActionTypes.inventoryDeleteItem, null);
    OfflineActionsService.instance
        .registerHandler(OfflineActionTypes.equipmentMetaUpdate, null);
    _offlineHandlersRegistered = false;
  }

  Future<void> _processQueuedPurchaseRequestUpdate(
    Map<String, dynamic> payload,
  ) async {
    final requestId = payload['request_id']?.toString();
    final patchRaw = payload['patch'];
    if (requestId == null || patchRaw is! Map) return;
    final patch = Map<String, dynamic>.from(patchRaw);
    final result = await _commands.updatePurchaseRequest(
      requestId: requestId,
      patch: patch,
    );
    if (!result.ok || result.data == null) {
      throw result.error ?? 'Impossible de mettre à jour.';
    }
    if (!mounted) return;
    _replacePurchaseRequest(result.data!);
    final log = payload['log'];
    if (log is Map) {
      await _logJournal(
        scope: 'list',
        event: log['event']?.toString() ?? 'purchase_request_qty_updated',
        entityId: requestId,
        note: log['note']?.toString(),
        payload: log['payload'] is Map
            ? Map<String, dynamic>.from(log['payload'] as Map)
            : null,
      );
    }
  }

  Future<void> _processQueuedPurchaseRequestCreate(
    Map<String, dynamic> payload,
  ) async {
    final membership = _overview?.membership;
    final companyId = membership?.companyId;
    if (companyId == null) {
      throw StateError('Entreprise inconnue pour la création hors ligne.');
    }
    final name = payload['name']?.toString();
    final qty = payload['qty'] is int
        ? payload['qty'] as int
        : int.tryParse(payload['qty']?.toString() ?? '');
    if (name == null || qty == null) {
      throw StateError('Payload invalide pour la demande hors ligne.');
    }
    final warehouseId = payload['warehouse_id']?.toString();
    final sectionId = payload['section_id']?.toString();
    final note = payload['note']?.toString();
    final result = await _commands.createPurchaseRequest(
      companyId: companyId,
      name: name,
      qty: qty,
      warehouseId: warehouseId,
      sectionId: sectionId,
      note: note,
    );
    if (!result.ok || result.data == null) {
      throw result.error ?? 'Impossible de créer la demande.';
    }
    if (!mounted) return;
    final tempId = payload['temp_id']?.toString();
    if (tempId != null) {
      _removePurchaseRequest(tempId);
    }
    _replacePurchaseRequest(result.data!);
    await _logJournal(
      scope: 'list',
      event: 'purchase_request_created',
      entityId: result.data!['id']?.toString(),
      note: name,
      payload: {
        'request_id': result.data!['id'],
        'qty': qty,
        'warehouse_id': warehouseId,
        'section_id': sectionId,
      },
    );
  }

  Future<void> _processQueuedPurchaseRequestDelete(
    Map<String, dynamic> payload,
  ) async {
    final requestId = payload['request_id']?.toString();
    if (requestId == null) return;
    final result =
        await _commands.deletePurchaseRequest(requestId: requestId);
    if (!result.ok) {
      throw result.error ?? 'Suppression impossible.';
    }
    if (!mounted) return;
    _removePurchaseRequest(requestId);
    await _logJournal(
      scope: 'list',
      event: 'purchase_request_deleted',
      entityId: requestId,
      note: payload['note']?.toString(),
      payload: {'request_id': requestId},
    );
  }

  Future<void> _processQueuedPurchaseRequestMarkToPlace(
    Map<String, dynamic> payload,
  ) async {
    final requestId = payload['request_id']?.toString();
    final qty = payload['qty'];
    if (requestId == null || qty is! int) return;
    final patch = <String, dynamic>{
      'qty': qty,
      'status': 'to_place',
    };
    final purchasedAt = payload['purchased_at']?.toString();
    if (purchasedAt != null) {
      patch['purchased_at'] = purchasedAt;
    }
    final result = await _commands.updatePurchaseRequest(
      requestId: requestId,
      patch: patch,
    );
    if (!result.ok || result.data == null) {
      throw result.error ?? 'Impossible de mettre à jour.';
    }
    if (!mounted) return;
    _replacePurchaseRequest(result.data!);
    await _logJournal(
      scope: 'list',
      event: 'purchase_request_marked_to_place',
      entityId: requestId,
      note: payload['note']?.toString(),
      payload: {
        'request_id': requestId,
        'status': 'to_place',
        'qty': qty,
      },
    );
  }

  Future<void> _processQueuedInventoryStockDelta(
    Map<String, dynamic> payload,
  ) async {
    final companyId =
        payload['company_id']?.toString() ?? _overview?.membership?.companyId;
    final warehouseId = payload['warehouse_id']?.toString();
    final itemId = payload['item_id']?.toString();
    final delta = payload['delta'] is int
        ? payload['delta'] as int
        : int.tryParse(payload['delta']?.toString() ?? '');
    if (companyId == null || warehouseId == null || itemId == null) {
      throw StateError('Payload invalide pour inventory_stock_delta.');
    }
    if (delta == null) {
      throw StateError('Delta manquant pour inventory_stock_delta.');
    }
    final sectionId = payload['section_id']?.toString();
    final note = payload['note']?.toString();
    final action = payload['action']?.toString() ?? 'manual';
    final metadata = payload['metadata'] is Map
        ? Map<String, dynamic>.from(payload['metadata'] as Map)
        : null;
    final event = payload['event']?.toString() ?? 'stock_delta';

    final result = await _commands.applyStockDelta(
      companyId: companyId,
      itemId: itemId,
      warehouseId: warehouseId,
      delta: delta,
      sectionId: sectionId,
    );
    if (!result.ok) {
      throw result.error ?? 'Impossible de synchroniser l’inventaire.';
    }
    final newQty = result.data ?? 0;
    await _logJournal(
      scope: 'inventory',
      event: event,
      entityId: sectionId == null
          ? _inventoryWarehouseEntityId(warehouseId)
          : _inventorySectionEntityId(warehouseId, sectionId),
      note: note,
      payload: {
        'item_id': itemId,
        'warehouse_id': warehouseId,
        'section_id': sectionId,
        'delta': delta,
        'new_qty': newQty,
        'action': action,
        if (metadata != null) ...metadata,
      },
    );
  }

  Future<void> _processQueuedInventoryDeleteItem(
    Map<String, dynamic> payload,
  ) async {
    final companyId =
        payload['company_id']?.toString() ?? _overview?.membership?.companyId;
    final itemId = payload['item_id']?.toString();
    if (companyId == null || itemId == null) {
      throw StateError('Payload invalide pour inventory_delete_item.');
    }
    final sectionId = payload['section_id']?.toString();
    final note = payload['note']?.toString();
    final warehouseId = payload['warehouse_id']?.toString();
    if (warehouseId == null) {
      throw StateError('Entrepôt manquant pour item_deleted.');
    }
    final result = await _commands.deleteItem(
      companyId: companyId,
      itemId: itemId,
    );
    if (!result.ok) {
      throw result.error ?? 'Impossible de supprimer la pièce.';
    }
    await _logJournal(
      scope: 'inventory',
      event: 'item_deleted',
      entityId: sectionId == null
          ? _inventoryWarehouseEntityId(warehouseId)
          : _inventorySectionEntityId(warehouseId, sectionId),
      note: note,
      payload: {
        'item_id': itemId,
        'section_id': sectionId,
      },
    );
  }

  Future<void> _processQueuedEquipmentMetaUpdate(
    Map<String, dynamic> payload,
  ) async {
    final equipmentId = payload['equipment_id']?.toString();
    final metaRaw = payload['meta'];
    if (equipmentId == null || metaRaw is! Map) {
      throw StateError('Payload invalide pour equipment_meta_update.');
    }
    final meta = Map<String, dynamic>.from(metaRaw);
    final result = await _commands.updateEquipmentMeta(
      equipmentId: equipmentId,
      meta: meta,
    );
    if (!result.ok || result.data == null) {
      throw result.error ?? 'Impossible de mettre à jour l’équipement.';
    }
    if (!mounted) return;
    _replaceEquipment(result.data!);
    final events = payload['events'];
    if (events is List) {
      for (final raw in events.whereType<Map>()) {
        await _logJournal(
          scope: 'equipment',
          event: raw['event']?.toString() ?? 'note',
          entityId: _equipmentEntityId(
            equipmentId,
            raw['category']?.toString(),
          ),
          note: raw['note']?.toString(),
          payload: raw['payload'] is Map
              ? Map<String, dynamic>.from(raw['payload'] as Map)
              : null,
        );
      }
    }
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
    _inlineMessageTimer?.cancel();
    setState(() {
      _inlineMessage = _InlineMessage(text: message, isError: error);
    });
    _inlineMessageTimer = Timer(const Duration(seconds: 4), () {
      if (!mounted) return;
      setState(() => _inlineMessage = null);
    });
  }

  void _dismissInlineMessage() {
    if (!mounted) return;
    _inlineMessageTimer?.cancel();
    setState(() => _inlineMessage = null);
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
    required this.isOnline,
    this.onCreateOffline,
  });

  final CompanyCommands commands;
  final String companyId;
  final List<Map<String, dynamic>> warehouses;
  final String? Function(Object? error) describeError;
  final bool isOnline;
  final Future<Map<String, dynamic>?> Function({
    required String name,
    required int qty,
    String? warehouseId,
    String? sectionId,
    String? note,
  })? onCreateOffline;

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

    final bool online = ConnectivityService.instance.isOnline;
    if (!online && widget.onCreateOffline != null) {
      final offlineCreated = await widget.onCreateOffline!.call(
        name: _nameCtrl.text.trim(),
        qty: _qty,
        warehouseId: _selectedWarehouseId,
        sectionId: _selectedSectionId,
        note: _noteCtrl.text.trim(),
      );
      if (!mounted) return;
      Navigator.of(context).pop(offlineCreated);
      return;
    }

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

  _InventoryBreakdownLine copyWith({
    String? name,
    String? sku,
    int? qty,
    String? unit,
  }) {
    return _InventoryBreakdownLine(
      itemId: itemId,
      name: name ?? this.name,
      sku: sku ?? this.sku,
      qty: qty ?? this.qty,
      unit: unit ?? this.unit,
    );
  }
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
     this.onShowCopilot,
    this.statusIndicator,
  });

  final String title;
  final String companyName;
  final bool showCalendar;
  final VoidCallback? onShowJournal;
  final VoidCallback? onShowCopilot;
  final Widget? statusIndicator;

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
                Row(
                  children: [
                    Expanded(
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Flexible(
                            child: Text(
                              title,
                              style: Theme.of(context).textTheme.headlineSmall,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          if (statusIndicator != null) ...[
                            const SizedBox(width: 6),
                            statusIndicator!,
                          ],
                        ],
                      ),
                    ),
                  ],
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

class _InlineMessage {
  const _InlineMessage({required this.text, this.isError = false});

  final String text;
  final bool isError;
}

class _InlineMessageBanner extends StatelessWidget {
  const _InlineMessageBanner({
    super.key,
    required this.message,
    this.onClose,
  });

  final _InlineMessage message;
  final VoidCallback? onClose;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final Color background =
        message.isError ? theme.colorScheme.error : theme.colorScheme.primary;
    const Color foreground = Colors.white;

    return AnimatedSwitcher(
      duration: const Duration(milliseconds: 250),
      child: GestureDetector(
        onTap: onClose,
        behavior: HitTestBehavior.opaque,
        child: Container(
          key: ValueKey('${message.text}_${message.isError}'),
          width: double.infinity,
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
          decoration: BoxDecoration(
            color: background,
          ),
          child: Text(
            message.text,
            style: TextStyle(
              color: foreground,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
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
  final IconData icon;
  final _AsyncCallback action;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () {
        action();
      },
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(24),
          border: Border.all(color: AppColors.outline.withValues(alpha: 0.2)),
          boxShadow: const [
            BoxShadow(
              color: Color(0x15000000),
              blurRadius: 6,
              offset: Offset(0, 3),
            ),
          ],
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

class _CopilotIncident {
  const _CopilotIncident({
    required this.timestamp,
    required this.input,
    required this.reason,
  });

  final DateTime timestamp;
  final String input;
  final String reason;
}

class _InventorySearchSheet extends StatefulWidget {
  const _InventorySearchSheet({
    required this.inventory,
    this.initialQuery,
  });

  final List<InventoryEntry> inventory;
  final String? initialQuery;

  @override
  State<_InventorySearchSheet> createState() => _InventorySearchSheetState();
}

class _InventorySearchSheetState extends State<_InventorySearchSheet> {
  late final TextEditingController _controller =
      TextEditingController(text: widget.initialQuery ?? '');

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final query = _controller.text.trim().toLowerCase();
    final filtered = widget.inventory.where((entry) {
      if (query.isEmpty) return true;
      final name = entry.item['name']?.toString().toLowerCase() ?? '';
      final sku = entry.item['sku']?.toString().toLowerCase() ?? '';
      return name.contains(query) || sku.contains(query);
    }).take(60).toList();

    return Material(
      color: Colors.white,
      borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
      child: SafeArea(
        child: SingleChildScrollView(
          padding: EdgeInsets.only(
            left: 16,
            right: 16,
            bottom: MediaQuery.of(context).viewInsets.bottom + 16,
            top: 16,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: _controller,
                decoration: const InputDecoration(
                  labelText: 'Recherche article',
                  prefixIcon: Icon(Icons.search),
                ),
                autofocus: true,
                onChanged: (_) => setState(() {}),
              ),
              const SizedBox(height: 12),
              ConstrainedBox(
                constraints: const BoxConstraints(maxHeight: 420),
                child: filtered.isEmpty
                    ? const Center(
                        child: Padding(
                          padding: EdgeInsets.all(24),
                          child: Text('Aucun article trouvé.'),
                        ),
                      )
                    : ListView.separated(
                        shrinkWrap: true,
                        itemCount: filtered.length,
                        separatorBuilder: (_, __) => const Divider(height: 1),
                        itemBuilder: (context, index) {
                          final entry = filtered[index];
                          final name =
                              entry.item['name']?.toString() ?? 'Article';
                          final sku =
                              entry.item['sku']?.toString() ?? '';
                          final total = entry.totalQty;
                          return ListTile(
                            title: Text(name),
                            subtitle: sku.isEmpty ? null : Text(sku),
                            trailing: Text(
                              '$total',
                              style: const TextStyle(
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                            onTap: () => Navigator.of(context).pop(entry),
                          );
                        },
                      ),
              ),
              const SizedBox(height: 12),
              TextButton(
                onPressed: () => Navigator.of(context).pop(),
                child: const Text('Annuler'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _IntegerInputDialog extends StatefulWidget {
  const _IntegerInputDialog({
    required this.title,
    this.helperText,
  });

  final String title;
  final String? helperText;

  @override
  State<_IntegerInputDialog> createState() => _IntegerInputDialogState();
}

class _IntegerInputDialogState extends State<_IntegerInputDialog> {
  final GlobalKey<FormState> _formKey = GlobalKey<FormState>();
  final TextEditingController _controller = TextEditingController();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      backgroundColor: Colors.white,
      title: Text(widget.title),
      content: Form(
        key: _formKey,
        child: TextFormField(
          controller: _controller,
          keyboardType: const TextInputType.numberWithOptions(signed: true),
          decoration: InputDecoration(
            labelText: 'Quantité',
            helperText: widget.helperText,
          ),
          validator: (value) {
            final parsed = int.tryParse(value?.trim() ?? '');
            if (parsed == null || parsed == 0) {
              return 'Entre un entier non nul.';
            }
            return null;
          },
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Annuler'),
        ),
        FilledButton(
          onPressed: () {
            if (!_formKey.currentState!.validate()) return;
            Navigator.of(context).pop(int.parse(_controller.text.trim()));
          },
          child: const Text('Confirmer'),
        ),
      ],
    );
  }
}

class _DecimalInputDialog extends StatefulWidget {
  const _DecimalInputDialog({
    required this.title,
    this.helperText,
  });

  final String title;
  final String? helperText;

  @override
  State<_DecimalInputDialog> createState() => _DecimalInputDialogState();
}

class _DecimalInputDialogState extends State<_DecimalInputDialog> {
  final GlobalKey<FormState> _formKey = GlobalKey<FormState>();
  final TextEditingController _controller = TextEditingController();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      backgroundColor: Colors.white,
      title: Text(widget.title),
      content: Form(
        key: _formKey,
        child: TextFormField(
          controller: _controller,
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          decoration: InputDecoration(
            labelText: 'Valeur',
            helperText: widget.helperText,
          ),
          validator: (value) {
            final parsed =
                double.tryParse((value ?? '').replaceAll(',', '.'));
            if (parsed == null || parsed <= 0) {
              return 'Entre une valeur positive.';
            }
            return null;
          },
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Annuler'),
        ),
        FilledButton(
          onPressed: () {
            if (!_formKey.currentState!.validate()) return;
            Navigator.of(context).pop(
              double.parse(
                _controller.text.trim().replaceAll(',', '.'),
              ),
            );
          },
          child: const Text('Confirmer'),
        ),
      ],
    );
  }
}
