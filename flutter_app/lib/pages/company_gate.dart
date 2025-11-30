import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:crypto/crypto.dart' as crypto;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'package:image_picker/image_picker.dart';
import 'package:path/path.dart' as p;
import 'package:supabase_flutter/supabase_flutter.dart';

import '../models/company_join_code.dart';
import '../models/company_role.dart';
import '../models/membership_invite.dart';
import '../services/company_commands.dart';
import '../services/company_repository.dart';
import '../services/connectivity_service.dart';
import '../services/copilot_service.dart';
import '../services/maintenance_service.dart';
import '../services/offline_actions_service.dart';
import '../services/offline_storage.dart';
import '../services/notification_service.dart';
import '../services/supabase_service.dart';
import '../theme/app_colors.dart';
import '../widgets/sync_status_chip.dart';
import '../widgets/copilot_sheet.dart';
import '../utils/async_utils.dart';
import 'sign_in_page.dart';
import 'notification_settings_page.dart';

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
typedef _MetaUpdateOutcome = ({
  bool ok,
  String message,
  bool isError,
  bool queuedOffline,
});

enum _InviteOption { email, joinCode }

const String _equipmentAssignedToKey = 'assigned_to';
const String _equipmentAssignedNameKey = 'assigned_to_name';
const String _equipmentAssignedAtKey = 'assigned_at';

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
  List<InventoryEntry> _lowStockItems = const <InventoryEntry>[];
  Map<String, dynamic>? _userProfile;
  List<String> _missingTables = const <String>[];
  Set<String> _updatingPurchaseRequests = const <String>{};
  final Map<String, String> _journalUserCache = <String, String>{};
  final Set<String> _pendingJoinCodeDeletes = <String>{};
  final Random _random = Random();
  final Map<String, String> _offlineIdMapping = <String, String>{};
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
  bool _offlineBannerVisible = false;
  Timer? _offlineBannerTimer;
  bool _isDeletingAccount = false;

  final TextEditingController _companyNameCtrl = TextEditingController();
  final TextEditingController _joinCodeCtrl = TextEditingController();
  bool _creatingCompany = false;
  bool _joiningCompany = false;

  @override
  void initState() {
    super.initState();
    _repository = CompanyRepository(Supa.i);
    _commands = CompanyCommands(Supa.i);
    _offlineIdMapping.addAll(
      OfflineStorage.instance.snapshotIdMappings(),
    );
    _registerOfflineHandlers();
    _isOnline = ConnectivityService.instance.isOnline;
    _connectivitySub =
        ConnectivityService.instance.onStatusChange.listen((online) async {
      if (!mounted) return;
      setState(() {
        _isOnline = online;
        if (online) {
          _offlineBannerVisible = false;
        }
      });
      if (online) {
        _offlineBannerTimer?.cancel();
        await OfflineActionsService.instance.processQueue();
        await _refreshPendingActionsCount();
        await NotificationService.instance.reconnect();
        await _refreshAll();
      } else {
        _showOfflineBannerTemporarily();
        _refreshPendingActionsCount();
      }
    });
    _refreshAll();
    _refreshPendingActionsCount();
    _queueSub = OfflineActionsService.instance.onQueueChanged.listen((count) {
      if (!mounted) return;
      setState(() => _pendingActionCount = count);
    });
  }

  @override
  void dispose() {
    _connectivitySub?.cancel();
    _queueSub?.cancel();
    _inlineMessageTimer?.cancel();
    _offlineBannerTimer?.cancel();
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

    if (!_isOnline) {
      final loaded = await _loadOfflineSnapshot(triggerBanner: true);
      if (loaded) {
        if (mounted) {
          setState(() => _isRefreshing = false);
        }
        _refreshPendingActionsCount();
        return;
      }
    }

    try {
      await (() async {
        final overviewResult = await _repository
            .fetchCompanyOverview()
            .timeout(const Duration(seconds: 8));
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

          final warehousesResult = await _repository
              .fetchWarehouses()
              .timeout(const Duration(seconds: 8));
          warehouses = warehousesResult.data;
          missing.addAll(warehousesResult.missingTables);
          errorText ??= _describeError(warehousesResult.error);

          final inventoryResult = await _repository
              .fetchInventory()
              .timeout(const Duration(seconds: 8));
          inventory = inventoryResult.data;
          missing.addAll(inventoryResult.missingTables);
          errorText ??= _describeError(inventoryResult.error);

          final equipmentResult = await _repository
              .fetchEquipment()
              .timeout(const Duration(seconds: 8));
          equipment = equipmentResult.data;
          missing.addAll(equipmentResult.missingTables);
          errorText ??= _describeError(equipmentResult.error);

          final requestsResult = await _repository
              .fetchPurchaseRequests()
              .timeout(const Duration(seconds: 8));
          purchaseRequests = requestsResult.data;
          missing.addAll(requestsResult.missingTables);
          errorText ??= _describeError(requestsResult.error);

          final joinCodeResult = await _repository
              .fetchJoinCodes(companyId: companyId)
              .timeout(const Duration(seconds: 8));
          joinCodes = joinCodeResult.data;
          if (_pendingJoinCodeDeletes.isNotEmpty) {
            joinCodes = joinCodes
                .where((code) => !_pendingJoinCodeDeletes.contains(code.id))
                .toList();
          }
          missing.addAll(joinCodeResult.missingTables);
          errorText ??= _describeError(joinCodeResult.error);

          final inviteResult = await _repository
              .fetchMembershipInvites(companyId: companyId)
              .timeout(const Duration(seconds: 8));
          invites = inviteResult.data;
          missing.addAll(inviteResult.missingTables);
          errorText ??= _describeError(inviteResult.error);

          final profileResult = await _repository
              .fetchUserProfile()
              .timeout(const Duration(seconds: 8));
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
          _recalculateLowStockItems(inventory);
          _isLoading = false;
        });
        runDetached(_persistPurchaseRequestsCache());
        runDetached(_persistEquipmentCache());
        runDetached(_persistPurchaseRequestsCache());
      })();
    } catch (error) {
      if (error is TimeoutException) {
        final loaded = await _loadOfflineSnapshot(triggerBanner: true);
        if (mounted) {
          setState(() {
            _isOnline = false;
            _offlineBannerVisible = true;
          });
        }
        if (!loaded && mounted) {
          setState(() {
            _fatalError = 'Données hors ligne indisponibles.';
            _isLoading = false;
          });
        }
        if (mounted) {
          setState(() => _isRefreshing = false);
        }
        return;
      }
      final loaded = await _loadOfflineSnapshot(triggerBanner: _isNetworkError(error));
      if (!loaded) {
        if (!mounted) return;
        setState(() {
          if (_isNetworkError(error)) {
            _isOnline = false;
            _offlineBannerVisible = true;
          }
          _fatalError = _isNetworkError(error)
              ? 'Données hors ligne indisponibles.'
              : 'Impossible de charger les données : $error';
          _isLoading = false;
        });
      }
    } finally {
      if (mounted) {
        setState(() => _isRefreshing = false);
      }
    }
    _refreshPendingActionsCount();
  }

  Future<bool> _loadOfflineSnapshot({bool triggerBanner = false}) async {
    final overview = await _repository.readCachedCompanyOverview();
    final membership = overview?.membership;
    if (overview == null || membership?.companyId == null) {
      return false;
    }
    final warehouses = await _repository.readCachedWarehouses() ?? _warehouses;
    final inventory =
        await _repository.readCachedInventoryEntries() ?? _inventory;
    final equipment = await _repository.readCachedEquipment() ?? _equipment;
    final purchaseRequests =
        await _repository.readCachedPurchaseRequests() ?? _purchaseRequests;
    var joinCodes = await _repository.readCachedJoinCodes() ?? _joinCodes;
    if (_pendingJoinCodeDeletes.isNotEmpty) {
      joinCodes = joinCodes
          .where((code) => !_pendingJoinCodeDeletes.contains(code.id))
          .toList(growable: false);
    }
    final invites = await _repository.readCachedInvites() ?? _invites;
    final profile = await _repository.readCachedUserProfile() ?? _userProfile;

    if (!mounted) {
      return true;
    }
    setState(() {
      _overview = overview;
      _warehouses = warehouses;
      _inventory = inventory;
      _equipment = equipment;
      _purchaseRequests = purchaseRequests;
      _joinCodes = joinCodes;
      _invites = invites;
      _userProfile = profile;
      _missingTables = const <String>[];
      _recalculateLowStockItems(inventory);
      _isLoading = false;
    });
    if (triggerBanner) {
      _showOfflineBannerTemporarily();
    }
    return true;
  }

  void _recalculateLowStockItems(List<InventoryEntry> inventory) {
    final lowStock = <InventoryEntry>[];
    for (final entry in inventory) {
      final meta = entry.item['meta'] as Map?;
      final minStock = (meta?['min_stock'] as num?)?.toInt();
      if (minStock != null && entry.totalQty < minStock) {
        lowStock.add(entry);
      }
    }
    setState(() => _lowStockItems = lowStock);
  }

  void _showOfflineBannerTemporarily() {
    if (!mounted) return;
    _offlineBannerTimer?.cancel();
    setState(() => _offlineBannerVisible = true);
    _offlineBannerTimer = Timer(const Duration(seconds: 5), () {
      if (!mounted) return;
      setState(() => _offlineBannerVisible = false);
    });
  }

  Future<void> _handleDeleteAccount() async {
    if (_isDeletingAccount) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Supprimer mon compte'),
        content: const Text(
          'Cette action supprimera définitivement votre compte Logtek G&I '
          'ainsi que vos données personnelles. Elle est irréversible. '
          'Veux-tu continuer ?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Annuler'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Supprimer définitivement'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;

    setState(() => _isDeletingAccount = true);
    final result = await _commands.deleteAccount();
    if (!result.ok) {
      if (mounted) {
        setState(() => _isDeletingAccount = false);
        _showSnack(
          _describeError(result.error) ??
              'Une erreur est survenue lors de la suppression du compte.',
          error: true,
        );
      }
      return;
    }

    final userId = Supa.i.auth.currentUser?.id;
    if (userId != null) {
      await OfflineStorage.instance.clearUserCache(userId);
    }
    await Supa.i.auth.signOut();
    if (!mounted) return;
    setState(() => _isDeletingAccount = false);
    Navigator.of(context).pushAndRemoveUntil(
      MaterialPageRoute(builder: (_) => const SignInPage()),
      (route) => false,
    );
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
      final user = Supa.i.auth.currentUser;
      String? profileValue(String key) {
        final raw = _userProfile?[key];
        if (raw is String) {
          final trimmed = raw.trim();
          if (trimmed.isNotEmpty) return trimmed;
        }
        return null;
      }

      String? onboardingName = profileValue('full_name');
      onboardingName ??= profileValue('display_name');

      String? onboardingEmail = profileValue('email');
      onboardingEmail ??= user?.email;

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
        userName: onboardingName,
        userEmail: onboardingEmail,
        onSignOut: _handleSignOut,
        onDeleteAccount: _handleDeleteAccount,
        isDeletingAccount: _isDeletingAccount,
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
        return null; // Pas de bouton + sur l'accueil
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
    if (_offlineBannerVisible) {
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
      final quickActionFeedback = await _copilotMaybeHandleQuickAction(intent);
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
        const message =
            'Précise quelle demande doit être marquée comme achetée.';
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
    final warehouseHint = _copilotPickString(
        payload, ['warehouse', 'warehouse_name', 'entrepot']);
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
    final normalized = _copilotNormalizeText(intent.rawText ?? intent.summary);
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
      const message = 'Précise le nom de la pièce à marquer comme achetée.';
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
        description:
            'Indique le nombre à ajouter (positif) ou retirer (négatif).',
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
    final warehouseHint = _copilotPickString(
        payload, ['warehouse', 'entrepot', 'warehouse_name']);
    final sectionHint =
        _copilotPickString(payload, ['section', 'section_name']);
    var warehouseId = _resolveWarehouseForEntry(entry, hint: warehouseHint);
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

    final itemLabel = entry.item['name']?.toString() ??
        entry.item['sku']?.toString() ??
        'Pièce';
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
        (intent.summary.isNotEmpty ? intent.summary : 'Tâche mécanique');
    final delay =
        _copilotPickInt(payload, ['delay_days', 'delai', 'due_in']) ?? 7;
    final repeat = _copilotPickInt(payload, ['repeat_days', 'repeat_every']);
    final priority = _normalizePriority(
        _copilotPickString(payload, ['priority']) ?? 'moyen');
    final task = <String, dynamic>{
      'id': 'copilot_${DateTime.now().microsecondsSinceEpoch}',
      'title': taskTitle,
      'delay_days': delay <= 0 ? 1 : delay,
      'priority': priority,
      'created_at': DateTime.now().toIso8601String(),
      'is_recheck': false,
      if (repeat != null && repeat > 0) 'repeat_every_days': repeat,
    };
    final equipmentLabel = equipment['name']?.toString() ?? 'Équipement';
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
      if (repeat != null && repeat > 0) 'Rappel : tous les $repeat jour(s)',
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
      successMessage: 'Tâche mécanique ajoutée par LogAI.',
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

  Future<_MetaUpdateOutcome> _persistEquipmentMetaUpdate({
    required Map<String, dynamic> equipment,
    required Map<String, dynamic> nextMeta,
    List<Map<String, dynamic>> events = const <Map<String, dynamic>>[],
    String successMessage = 'Équipement mis à jour.',
    String offlineMessage = 'Mise à jour en file (hors ligne).',
    String? errorFallbackMessage,
    bool showSuccessSnack = true,
    bool showOfflineSnack = true,
    bool refreshOnSuccess = true,
  }) async {
    final equipmentId = equipment['id']?.toString();
    if (equipmentId == null || equipmentId.isEmpty) {
      const message = 'Équipement inconnu.';
      _showSnack(message, error: true);
      return (
        ok: false,
        message: message,
        isError: true,
        queuedOffline: false,
      );
    }

    if (_isOnline) {
      final result = await _commands.updateEquipmentMeta(
        equipmentId: equipmentId,
        meta: nextMeta,
      );
      if (!result.ok || result.data == null) {
        final message = _describeError(result.error) ??
            errorFallbackMessage ??
            'Impossible de mettre à jour cet équipement.';
        _showSnack(message, error: true);
        return (
          ok: false,
          message: message,
          isError: true,
          queuedOffline: false,
        );
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
      if (refreshOnSuccess) {
        await _refreshAll();
      }
      if (showSuccessSnack && successMessage.isNotEmpty) {
        _showSnack(successMessage);
      }
      return (
        ok: true,
        message: successMessage,
        isError: false,
        queuedOffline: false,
      );
    }

    final companyId = _overview?.membership?.companyId;
    if (companyId == null) {
      const message = 'Entreprise inconnue.';
      _showSnack(message, error: true);
      return (
        ok: false,
        message: message,
        isError: true,
        queuedOffline: false,
      );
    }

    final local = Map<String, dynamic>.from(equipment)..['meta'] = nextMeta;
    _replaceEquipment(local);
    await OfflineActionsService.instance.enqueue(
      OfflineActionTypes.equipmentMetaUpdate,
      {
        'company_id': companyId,
        'equipment_id': equipmentId,
        'equipment_name': equipment['name']?.toString(),
        'meta': nextMeta,
        if (events.isNotEmpty) 'events': events,
      },
    );
    await _refreshPendingActionsCount();
    if (showOfflineSnack && offlineMessage.isNotEmpty) {
      _showOfflineQueuedSnack(offlineMessage);
    }
    return (
      ok: true,
      message: offlineMessage,
      isError: false,
      queuedOffline: true,
    );
  }

  Future<CopilotFeedback?> _applyEquipmentMetaUpdate({
    required Map<String, dynamic> equipment,
    required Map<String, dynamic> nextMeta,
    required List<Map<String, dynamic>> events,
    required String successMessage,
  }) async {
    final offlineMessage = successMessage.isEmpty
        ? 'Action enregistrée (hors ligne).'
        : '$successMessage (hors ligne).';
    final outcome = await _persistEquipmentMetaUpdate(
      equipment: equipment,
      nextMeta: nextMeta,
      events: events,
      successMessage: successMessage,
      offlineMessage: offlineMessage,
      errorFallbackMessage: 'Impossible de mettre à jour cet équipement.',
      showSuccessSnack: true,
      showOfflineSnack: true,
      refreshOnSuccess: true,
    );
    if (outcome.ok) {
      final message = outcome.queuedOffline ? offlineMessage : successMessage;
      return CopilotFeedback(message: message);
    }
    return CopilotFeedback(message: outcome.message, isError: true);
  }

  String _normalizePriority(String raw) {
    final normalized = _normalizeLabel(raw);
    if (normalized.contains('haut') ||
        normalized.contains('urgent') ||
        normalized.contains('élev') ||
        normalized.contains('elev')) {
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
    final sections = entry.sectionSplit[warehouseId] ?? const <String, int>{};
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
    if (sectionId == null || sectionId == InventoryEntry.unassignedSectionKey) {
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
    final sorted =
        _equipment.map((item) => Map<String, dynamic>.from(item)).toList()
          ..sort(
            (a, b) => (a['name']?.toString() ?? '')
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
                        final title = equip['name']?.toString() ?? 'Équipement';
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
          lowStockItems: _lowStockItems,
          onQuickAction: _handleQuickAction,
          onViewLowStock: _handleShowLowStockPage,
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
          onShowDetails: _handleEditPurchaseRequest,
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
          onAddTask: _addInventoryTask,
          onToggleTask: _toggleInventoryTask,
          onDeleteTask: _deleteInventoryTask,
          ensureItemForTask: _ensureItemForTask,
        );
      case _GateTab.equipment:
        return _EquipmentTab(
          equipment: _equipment,
          commands: _commands,
          onRefresh: _refreshAll,
          inventory: _inventory,
          warehouses: _warehouses,
          onReplaceEquipment: _replaceEquipment,
          onRemoveEquipment: _removeEquipment,
          companyId: membership.companyId,
          equipmentProvider: () => _equipment,
        );
      case _GateTab.more:
        return _MoreTab(
          membership: membership,
          members: _overview?.members ?? const <Map<String, dynamic>>[],
          equipment: _equipment,
          joinCodes: _joinCodes,
          invites: _invites,
          userProfile: _userProfile,
          onRevokeCode: _handleRevokeJoinCode,
          onInviteMember: _promptInviteMember,
          onShowCompanyJournal: _handleShowCompanyJournal,
          onDeleteJoinCode: _handleDeleteJoinCode,
          onAssignEquipment: _handleAssignEquipmentToMember,
          onChangeMemberRole: _handleChangeMemberRole,
          onRemoveMember: _handleRemoveMember,
          onDeleteAccount: _handleDeleteAccount,
          isDeletingAccount: _isDeletingAccount,
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

              if (!_isOnline) {
                final created = await _createWarehouseOffline(
                  companyId: companyId,
                  name: nameCtrl.text.trim(),
                  code: codeCtrl.text.trim().isEmpty
                      ? null
                      : codeCtrl.text.trim(),
                );
                if (created == null) {
                  setDialogState(() {
                    submitting = false;
                    dialogError = 'Action hors ligne impossible.';
                  });
                  return;
                }
                if (!context.mounted || !mounted) return;
                Navigator.of(context).pop();
                return;
              }

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
      backgroundColor: Colors.white,
      builder: (context) {
        return Container(
          color: Colors.white,
          child: SafeArea(
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
              if (!context.mounted) return;
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
        isOnline: _isOnline,
        onCreateOffline: ({required String name, String? code}) =>
            _createInventorySectionOffline(
          companyId: companyId,
          warehouseId: warehouseId,
          name: name,
          code: code,
        ),
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
    final companyId = await _resolveCompanyId();
    if (companyId == null) return;
    if (!mounted) return;
    final formKey = GlobalKey<FormState>();
    final nameCtrl = TextEditingController();
    final brandCtrl = TextEditingController();
    final modelCtrl = TextEditingController();
    final serialCtrl = TextEditingController();
    final yearCtrl = TextEditingController();
    const equipmentTypes = <String>[
      'Abatteuse',
      'Débardeur',
      'Camion transporteur',
      'Camion pick-up',
      'Bouteur',
      'Chargeuse',
      'Chargeuse sur pneus',
      'Excavatrice',
      'Tracteur',
      'Niveleuse',
      'Remorque',
      'Planteuse',
      'Débroussailleuse',
      'Autres',
    ];
    String selectedType = equipmentTypes.last;
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

              if (!_isOnline) {
                final created = await _createEquipmentOffline(
                  companyId: companyId,
                  name: nameCtrl.text.trim(),
                  brand: brandCtrl.text.trim().isEmpty
                      ? null
                      : brandCtrl.text.trim(),
                  model: modelCtrl.text.trim().isEmpty
                      ? null
                      : modelCtrl.text.trim(),
                  serial: serialCtrl.text.trim().isEmpty
                      ? null
                      : serialCtrl.text.trim(),
                  type: selectedType,
                  year: yearCtrl.text.trim().isEmpty
                      ? null
                      : yearCtrl.text.trim(),
                );
                if (created == null) {
                  setDialogState(() {
                    submitting = false;
                    dialogError = 'Action hors ligne impossible.';
                  });
                  return;
                }
                if (!context.mounted || !mounted) return;
                Navigator.of(context).pop();
                _showSnack('Équipement ajouté (hors ligne).');
                return;
              }

              final result = await _commands.createEquipment(
                companyId: companyId,
                name: nameCtrl.text.trim(),
                brand: brandCtrl.text.trim(),
                model: modelCtrl.text.trim(),
                serial: serialCtrl.text.trim(),
                type: selectedType,
                year: yearCtrl.text.trim(),
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
                        controller: yearCtrl,
                        keyboardType: TextInputType.number,
                        decoration:
                            const InputDecoration(labelText: 'Année (optionnel)'),
                        validator: (value) {
                          if (value == null || value.trim().isEmpty) {
                            return null;
                          }
                          final parsed = int.tryParse(value.trim());
                          if (parsed == null || parsed < 1900 || parsed > 2100) {
                            return 'Année invalide';
                          }
                          return null;
                        },
                      ),
                      const SizedBox(height: 12),
                      TextFormField(
                        controller: serialCtrl,
                        decoration: const InputDecoration(
                            labelText: 'Numéro de série (optionnel)'),
                      ),
                      const SizedBox(height: 12),
                      DropdownButtonFormField<String>(
                        value: selectedType,
                        items: equipmentTypes
                            .map(
                              (type) => DropdownMenuItem(
                                value: type,
                                child: Text(type),
                              ),
                            )
                            .toList(),
                        onChanged: (value) {
                          if (value == null || value.isEmpty) return;
                          setDialogState(() => selectedType = value);
                        },
                        decoration:
                            const InputDecoration(labelText: 'Type'),
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

  Future<void> _promptCreatePurchaseRequest({
    String? initialName,
    String? initialWarehouseId,
    String? initialSectionId,
  }) async {
    final companyId = _overview?.membership?.companyId;
    if (companyId == null) return;

    final created = await showDialog<Map<String, dynamic>?>(
      context: context,
      builder: (context) => _PurchaseRequestDialog(
        commands: _commands,
        companyId: companyId,
        warehouses: _warehouses,
        inventory: _inventory,
        describeError: _describeError,
        isOnline: _isOnline,
        onCreateItemOffline: ({
          required String name,
          String? sku,
          String? unit,
          String? category,
        }) =>
            _createInventoryItemOffline(
          companyId: companyId,
          name: name,
          sku: sku,
          unit: unit,
          category: category,
        ),
        initialName: initialName,
        initialWarehouseId: initialWarehouseId,
        initialSectionId: initialSectionId,
        onCreateOffline: _isOnline
            ? null
            : ({
                required String name,
                required int qty,
                String? warehouseId,
                String? sectionId,
                String? note,
                String? itemId,
          }) =>
            _createPurchaseRequestOffline(
              name: name,
              qty: qty,
              warehouseId: warehouseId,
              sectionId: sectionId,
              note: note,
              itemId: itemId ?? '',
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
      } else {
        // Ensure the new request shows up immediately when created offline.
        _replacePurchaseRequest(created);
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
          .map((equip) => equip['id']?.toString() == id ? updated : equip)
          .toList();
    });
    runDetached(_persistEquipmentCache());
  }

  void _removeEquipment(String? id) {
    if (id == null) return;
    setState(() {
      _equipment =
          _equipment.where((equip) => equip['id']?.toString() != id).toList();
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

  Future<void> _persistInventoryCache() async {
    final userId = Supa.i.auth.currentUser?.id;
    if (userId == null) return;
    final data = _inventory
        .map((entry) => {
              'item': entry.item,
              'totalQty': entry.totalQty,
              'warehouseSplit': entry.warehouseSplit,
              'sectionSplit': entry.sectionSplit,
            })
        .toList(growable: false);
    await OfflineStorage.instance.saveCache(
      '$userId::${OfflineCacheKeys.inventory}',
      data,
    );
  }

  Future<void> _persistWarehousesCache() async {
    final userId = Supa.i.auth.currentUser?.id;
    if (userId == null) return;
    await OfflineStorage.instance.saveCache(
      '$userId::${OfflineCacheKeys.warehouses}',
      _warehouses,
    );
  }

  Future<Map<String, dynamic>?> _createWarehouseOffline({
    required String companyId,
    required String name,
    String? code,
  }) async {
    final trimmedName = name.trim();
    if (trimmedName.isEmpty) return null;
    final normalizedCode = code?.trim();
    final tempId = _generateLocalId('wh');
    final record = <String, dynamic>{
      'id': tempId,
      'company_id': companyId,
      'name': trimmedName,
      if (normalizedCode != null && normalizedCode.isNotEmpty)
        'code': normalizedCode,
      'active': true,
      'created_at': DateTime.now().toIso8601String(),
      'sections': <Map<String, dynamic>>[],
    };
    setState(() {
      _warehouses = [..._warehouses, record];
    });
    await _persistWarehousesCache();
    await OfflineActionsService.instance.enqueue(
      OfflineActionTypes.warehouseCreate,
      {
        'temp_id': tempId,
        'company_id': companyId,
        'name': trimmedName,
        if (normalizedCode != null && normalizedCode.isNotEmpty)
          'code': normalizedCode,
      },
    );
    await _refreshPendingActionsCount();
    _showOfflineQueuedSnack('Entrepôt ajouté (hors ligne).');
    return record;
  }

  Future<Map<String, dynamic>?> _createInventorySectionOffline({
    required String companyId,
    required String warehouseId,
    required String name,
    String? code,
  }) async {
    final trimmedName = name.trim();
    if (trimmedName.isEmpty) return null;
    final normalizedCode = code?.trim();
    final hasWarehouse = _warehouses.any(
      (warehouse) => warehouse['id']?.toString() == warehouseId,
    );
    if (!hasWarehouse) return null;
    final tempId = _generateLocalId('section');
    final section = <String, dynamic>{
      'id': tempId,
      'company_id': companyId,
      'warehouse_id': warehouseId,
      'name': trimmedName,
      if (normalizedCode != null && normalizedCode.isNotEmpty)
        'code': normalizedCode,
      'active': true,
      'created_at': DateTime.now().toIso8601String(),
    };
    setState(() {
      _warehouses = _warehouses.map((warehouse) {
        if (warehouse['id']?.toString() != warehouseId) return warehouse;
        final sections = (warehouse['sections'] as List?)
                ?.whereType<Map>()
                .map((raw) => Map<String, dynamic>.from(raw))
                .toList() ??
            <Map<String, dynamic>>[];
        return {
          ...warehouse,
          'sections': [...sections, section],
        };
      }).toList();
    });
    await _persistWarehousesCache();
    await OfflineActionsService.instance.enqueue(
      OfflineActionTypes.inventorySectionCreate,
      {
        'temp_id': tempId,
        'company_id': companyId,
        'warehouse_id': warehouseId,
        'name': trimmedName,
        if (normalizedCode != null && normalizedCode.isNotEmpty)
          'code': normalizedCode,
      },
    );
    await _refreshPendingActionsCount();
    _showOfflineQueuedSnack('Section ajoutée (hors ligne).');
    return section;
  }

  Future<InventoryEntry?> _createInventoryItemOffline({
    required String companyId,
    required String name,
    String? sku,
    String? unit,
    String? category,
  }) async {
    final trimmedName = name.trim();
    if (trimmedName.isEmpty) return null;

    String? normalize(String? value) {
      if (value == null) return null;
      final trimmed = value.trim();
      return trimmed.isEmpty ? null : trimmed;
    }

    final normalizedSku = normalize(sku);
    final normalizedUnit = normalize(unit);
    final normalizedCategory = normalize(category);
    final tempId = _generateLocalId('item');
    final record = <String, dynamic>{
      'id': tempId,
      'company_id': companyId,
      'name': trimmedName,
      if (normalizedSku != null) 'sku': normalizedSku,
      if (normalizedUnit != null) 'unit': normalizedUnit,
      if (normalizedCategory != null) 'category': normalizedCategory,
      'active': true,
      'created_at': DateTime.now().toIso8601String(),
      'meta': <String, dynamic>{},
    };
    final entry = InventoryEntry(
      item: record,
      totalQty: 0,
      warehouseSplit: const <String, int>{},
      sectionSplit: const <String, Map<String, int>>{},
    );
    setState(() {
      _inventory = [..._inventory, entry];
    });
    runDetached(_persistInventoryCache());
    await OfflineActionsService.instance.enqueue(
      OfflineActionTypes.inventoryItemCreate,
      {
        'temp_id': tempId,
        'company_id': companyId,
        'name': trimmedName,
        if (normalizedSku != null) 'sku': normalizedSku,
        if (normalizedUnit != null) 'unit': normalizedUnit,
        if (normalizedCategory != null) 'category': normalizedCategory,
      },
    );
    await _refreshPendingActionsCount();
    _showOfflineQueuedSnack('Pièce créée (hors ligne).');
    return entry;
  }

  Future<void> _addInventoryTask(
    String itemId,
    String title, {
    Map<String, dynamic>? meta,
  }) async {
    final entry = _inventory
        .firstWhere((e) => e.item['id']?.toString() == itemId, orElse: () => const InventoryEntry(item: {}));
    if (entry.item.isEmpty) {
      _showSnack('Pièce introuvable.', error: true);
      return;
    }
    final itemMeta =
        Map<String, dynamic>.from(entry.item['meta'] as Map? ?? const {});
    final tasks = (itemMeta['tasks'] as List?)
            ?.whereType<Map>()
            .map((raw) => Map<String, dynamic>.from(raw))
            .toList() ??
        <Map<String, dynamic>>[];
    tasks.add({
      'id': 'task_${DateTime.now().microsecondsSinceEpoch}',
      'title': title,
      'created_at': DateTime.now().toIso8601String(),
      'done': false,
      if (meta != null) 'meta': meta,
    });
    itemMeta['tasks'] = tasks;
    await _persistItemMeta(
      itemId: itemId,
      meta: itemMeta,
      successMessage: 'Tâche ajoutée.',
    );
  }

  Future<void> _toggleInventoryTask(
    String itemId,
    String taskId,
    bool done,
  ) async {
    final entry = _inventory
        .firstWhere((e) => e.item['id']?.toString() == itemId, orElse: () => const InventoryEntry(item: {}));
    if (entry.item.isEmpty) return;
    final meta = Map<String, dynamic>.from(entry.item['meta'] as Map? ?? const {});
    final tasks = (meta['tasks'] as List?)
            ?.whereType<Map>()
            .map((raw) => Map<String, dynamic>.from(raw))
            .toList() ??
        <Map<String, dynamic>>[];
    final index = tasks.indexWhere((t) => t['id']?.toString() == taskId);
    if (index < 0) return;
    final task = tasks[index];
    if (!done) {
      tasks[index]['done'] = false;
      meta['tasks'] = tasks;
      await _persistItemMeta(itemId: itemId, meta: meta);
      return;
    }

    final taskMeta = task['meta'] as Map?;
    final isMove = taskMeta?['type']?.toString() == 'move';
    if (isMove) {
      final qty = (taskMeta?['qty'] as num?)?.toInt() ?? 1;
      final fromWh = taskMeta?['from_warehouse_id']?.toString();
      final toWh = taskMeta?['to_warehouse_id']?.toString();
      if (qty <= 0 || fromWh == null || toWh == null) {
        _showSnack('Tâche invalide : données manquantes.', error: true);
        return;
      }
      final fromSection = taskMeta?['from_section_id']?.toString();
      final toSection = taskMeta?['to_section_id']?.toString();
      final companyId = _overview?.membership?.companyId;
      final available = _availableQtyForTask(itemId, fromWh, fromSection);
      if (available < qty) {
        _showSnack('Stock insuffisant dans l’entrepôt source.', error: true);
        return;
      }
      if (companyId == null) {
        _showSnack('Entreprise inconnue.', error: true);
        return;
      }
      if (!_isOnline) {
        await OfflineActionsService.instance.enqueue(
          OfflineActionTypes.inventoryStockDelta,
          {
            'company_id': companyId,
            'warehouse_id': fromWh,
            'item_id': itemId,
            'delta': -qty,
            'section_id': _normalizeSectionId(fromSection),
            'note': task['title']?.toString(),
            'event': 'stock_delta',
            'metadata': {
              'task_id': taskId,
              'move_task': true,
              'direction': 'out',
            },
          },
        );
        await OfflineActionsService.instance.enqueue(
          OfflineActionTypes.inventoryStockDelta,
          {
            'company_id': companyId,
            'warehouse_id': toWh,
            'item_id': itemId,
            'delta': qty,
            'section_id': _normalizeSectionId(toSection),
            'note': task['title']?.toString(),
            'event': 'stock_delta',
            'metadata': {
              'task_id': taskId,
              'move_task': true,
              'direction': 'in',
            },
          },
        );
        await _refreshPendingActionsCount();
      } else {
        final remove = await _commands.applyStockDelta(
          companyId: companyId,
          itemId: itemId,
          warehouseId: fromWh,
          delta: -qty,
          sectionId: _normalizeSectionId(fromSection),
        );
        if (!remove.ok) {
          _showSnack(
            _describeError(remove.error) ?? 'Impossible de retirer le stock.',
            error: true,
          );
          return;
        }
        final add = await _commands.applyStockDelta(
          companyId: companyId,
          itemId: itemId,
          warehouseId: toWh,
          delta: qty,
          sectionId: _normalizeSectionId(toSection),
        );
        if (!add.ok) {
          await _commands.applyStockDelta(
            companyId: companyId,
            itemId: itemId,
            warehouseId: fromWh,
            delta: qty,
            sectionId: _normalizeSectionId(fromSection),
          );
          _showSnack(
            _describeError(add.error) ?? 'Impossible d’ajouter le stock.',
            error: true,
          );
          return;
        }
      }
    }

    // Remove the task once completed (move done or simple task).
    tasks.removeAt(index);
    meta['tasks'] = tasks;
    await _persistItemMeta(
      itemId: itemId,
      meta: meta,
      successMessage: 'Tâche complétée.',
    );
  }

  Future<void> _deleteInventoryTask(String itemId, String taskId) async {
    final entry = _inventory
        .firstWhere((e) => e.item['id']?.toString() == itemId, orElse: () => const InventoryEntry(item: {}));
    if (entry.item.isEmpty) return;
    final meta = Map<String, dynamic>.from(entry.item['meta'] as Map? ?? const {});
    final tasks = (meta['tasks'] as List?)
            ?.whereType<Map>()
            .map((raw) => Map<String, dynamic>.from(raw))
            .toList() ??
        <Map<String, dynamic>>[];
    tasks.removeWhere((t) => t['id']?.toString() == taskId);
    meta['tasks'] = tasks;
    await _persistItemMeta(itemId: itemId, meta: meta, successMessage: 'Tâche supprimée.');
  }

  Future<void> _persistItemMeta({
    required String itemId,
    required Map<String, dynamic> meta,
    String? successMessage,
  }) async {
    Future<void> queueOfflineUpdate() async {
      _applyLocalInventoryMeta(itemId, meta);
      await OfflineActionsService.instance.enqueue(
        OfflineActionTypes.inventoryItemMetaUpdate,
        {
          'item_id': itemId,
          'meta': meta,
        },
      );
      await _refreshPendingActionsCount();
      final offlineMessage = successMessage == null || successMessage.isEmpty
          ? 'Mise à jour en file (hors ligne).'
          : '$successMessage (hors ligne).';
      _showOfflineQueuedSnack(offlineMessage);
    }

    if (!_isOnline) {
      await queueOfflineUpdate();
      return;
    }

    final result = await _commands.updateItemMeta(
      itemId: itemId,
      meta: meta,
    );
    if (!result.ok || result.data == null) {
      if (_isNetworkError(result.error)) {
        await queueOfflineUpdate();
        return;
      }
      _showSnack(
        _describeError(result.error) ?? 'Impossible de mettre à jour la pièce.',
        error: true,
      );
      return;
    }
    final serverMeta = result.data?['meta'];
    final appliedMeta = serverMeta is Map
        ? Map<String, dynamic>.from(serverMeta)
        : meta;
    _applyLocalInventoryMeta(itemId, appliedMeta);
    if (successMessage != null) {
      _showSnack(successMessage);
    }
  }

  void _applyLocalInventoryMeta(String itemId, Map<String, dynamic> meta) {
    setState(() {
      _inventory = _inventory.map((entry) {
        if (entry.item['id']?.toString() != itemId) return entry;
        final newItem = Map<String, dynamic>.from(entry.item)..['meta'] = meta;
        return InventoryEntry(
          item: newItem,
          totalQty: entry.totalQty,
          warehouseSplit: entry.warehouseSplit,
          sectionSplit: entry.sectionSplit,
        );
      }).toList();
      _recalculateLowStockItems(_inventory);
    });
    runDetached(_persistInventoryCache());
  }

  int _availableQtyForTask(
    String itemId,
    String warehouseId,
    String? sectionId,
  ) {
    final entry = _inventory
        .firstWhere((e) => e.item['id']?.toString() == itemId, orElse: () => const InventoryEntry(item: {}));
    if (entry.item.isEmpty) return 0;
    if (sectionId != null && sectionId != InventoryEntry.unassignedSectionKey) {
      return entry.sectionSplit[warehouseId]?[sectionId] ?? 0;
    }
    return entry.warehouseSplit[warehouseId] ?? 0;
  }

  Future<String?> _ensureItemForTask(String name) async {
    final trimmed = name.trim();
    if (trimmed.isEmpty) return null;
    // Try find existing
    for (final entry in _inventory) {
      final entryName = entry.item['name']?.toString();
      if (entryName != null &&
          entryName.trim().toLowerCase() == trimmed.toLowerCase()) {
        return entry.item['id']?.toString();
      }
    }
    // Create new (online or offline)
    final companyId = _overview?.membership?.companyId;
    if (companyId == null) return null;
    if (_isOnline) {
      final result = await _commands.createItem(
        companyId: companyId,
        name: trimmed,
      );
      if (!result.ok) {
        _showSnack(
          _describeError(result.error) ?? 'Impossible de créer la pièce.',
          error: true,
        );
        return null;
      }
      final newId = result.data?['id']?.toString();
      if (newId != null) {
        await _refreshAll();
      }
      return newId;
    } else {
      final entry = await _createInventoryItemOffline(
        companyId: companyId,
        name: trimmed,
      );
      return entry?.item['id']?.toString();
    }
  }

  Future<Map<String, dynamic>?> _createEquipmentOffline({
    required String companyId,
    required String name,
    String? brand,
    String? model,
    String? serial,
    String? type,
    String? year,
  }) async {
    final trimmedName = name.trim();
    if (trimmedName.isEmpty) return null;
    final normalizedBrand = brand?.trim();
    final normalizedModel = model?.trim();
    final normalizedSerial = serial?.trim();
    final tempId = _generateLocalId('equip');
    final record = <String, dynamic>{
      'id': tempId,
      'company_id': companyId,
      'name': trimmedName,
      if (normalizedBrand != null && normalizedBrand.isNotEmpty)
        'brand': normalizedBrand,
      if (normalizedModel != null && normalizedModel.isNotEmpty)
        'model': normalizedModel,
      if (normalizedSerial != null && normalizedSerial.isNotEmpty)
        'serial': normalizedSerial,
      'active': true,
      'created_at': DateTime.now().toIso8601String(),
      'meta': {
        if (type != null && type.isNotEmpty) 'type': type,
        if (year != null && year.isNotEmpty) 'year': year,
      },
    };
    setState(() {
      _equipment = [..._equipment, record];
    });
    await _persistEquipmentCache();
    await OfflineActionsService.instance.enqueue(
      OfflineActionTypes.equipmentCreate,
      {
        'temp_id': tempId,
        'company_id': companyId,
        'name': trimmedName,
        if (normalizedBrand != null && normalizedBrand.isNotEmpty)
        'brand': normalizedBrand,
      if (normalizedModel != null && normalizedModel.isNotEmpty)
        'model': normalizedModel,
      if (normalizedSerial != null && normalizedSerial.isNotEmpty)
        'serial': normalizedSerial,
      if ((type != null && type.isNotEmpty) ||
          (year != null && year.isNotEmpty))
        'meta': {
          if (type != null && type.isNotEmpty) 'type': type,
          if (year != null && year.isNotEmpty) 'year': year,
        },
      },
    );
    await _refreshPendingActionsCount();
    _showOfflineQueuedSnack('Équipement ajouté (hors ligne).');
    return record;
  }

  Future<bool> _placePurchaseRequestOffline({
    required Map<String, dynamic> request,
    required String requestId,
    required String companyId,
    required String itemId,
    required String warehouseId,
    String? sectionId,
    required int qty,
  }) async {
    final note = request['name']?.toString();
    await OfflineActionsService.instance.enqueue(
      OfflineActionTypes.inventoryStockDelta,
      {
        'company_id': companyId,
        'warehouse_id': warehouseId,
        'item_id': itemId,
        'delta': qty,
        'section_id': sectionId,
        'note': note,
        'action': 'purchase_place',
        'metadata': {
          'request_id': requestId,
        },
        'event': 'purchase_stock_added',
      },
    );

    final patch = <String, dynamic>{
      'status': 'done',
      'item_id': itemId,
      'warehouse_id': warehouseId,
      'section_id': sectionId,
    };

    final updated = await _updatePurchaseRequestLocally(requestId, patch);
    _applyLocalInventoryDelta(
      itemId: itemId,
      itemName: request['name']?.toString() ?? 'Pièce',
      warehouseId: warehouseId,
      sectionId: sectionId,
      delta: qty,
      meta: request['meta'] is Map ? Map<String, dynamic>.from(request['meta']) : const {},
    );
    await OfflineActionsService.instance.enqueue(
      OfflineActionTypes.purchaseRequestUpdate,
      {
        'request_id': requestId,
        'patch': patch,
        'log': {
          'event': 'purchase_request_completed',
          'note': note,
          'payload': {
            'request_id': requestId,
            'item_id': itemId,
            'warehouse_id': warehouseId,
            'section_id': sectionId,
            'status': 'done',
            'qty': qty,
          },
        },
      },
    );
    await _refreshPendingActionsCount();
    _showOfflineQueuedSnack('Pièce placée (hors ligne).');
    return updated != null;
  }

  void _applyLocalInventoryDelta({
    required String itemId,
    required String itemName,
    required String warehouseId,
    String? sectionId,
    required int delta,
    Map<String, dynamic>? meta,
  }) {
    final sectionsKey = sectionId ?? InventoryEntry.unassignedSectionKey;
    final updated = <InventoryEntry>[];
    var matched = false;

    for (final entry in _inventory) {
      final id = entry.item['id']?.toString();
      if (id != itemId) {
        updated.add(entry);
        continue;
      }
      matched = true;
      final newTotal = (entry.totalQty + delta).clamp(0, 1 << 30);
      final newWarehouseSplit = Map<String, int>.from(entry.warehouseSplit);
      newWarehouseSplit[warehouseId] = (newWarehouseSplit[warehouseId] ?? 0) + delta;
      if (newWarehouseSplit[warehouseId]! < 0) newWarehouseSplit[warehouseId] = 0;

      final newSectionSplit = Map<String, Map<String, int>>.from(entry.sectionSplit);
      final perWarehouse =
          Map<String, int>.from(newSectionSplit[warehouseId] ?? const <String, int>{});
      perWarehouse[sectionsKey] = (perWarehouse[sectionsKey] ?? 0) + delta;
      if (perWarehouse[sectionsKey]! < 0) perWarehouse[sectionsKey] = 0;
      newSectionSplit[warehouseId] = perWarehouse;

      updated.add(
        InventoryEntry(
          item: {
            ...entry.item,
            if (meta != null && meta.isNotEmpty) 'meta': meta,
          },
          totalQty: newTotal,
          warehouseSplit: newWarehouseSplit,
          sectionSplit: newSectionSplit,
        ),
      );
    }

    if (!matched && delta > 0) {
      updated.add(
        InventoryEntry(
          item: {
            'id': itemId,
            'name': itemName,
            if (meta != null && meta.isNotEmpty) 'meta': meta,
          },
          totalQty: delta,
          warehouseSplit: {warehouseId: delta},
          sectionSplit: {
            warehouseId: {sectionsKey: delta},
          },
        ),
      );
    }

    setState(() {
      _inventory = updated;
      _recalculateLowStockItems(updated);
    });
    runDetached(_persistInventoryCache());
  }

  void _upsertWarehouseRecord(
    Map<String, dynamic> record, {
    String? replaceId,
  }) {
    final normalized = Map<String, dynamic>.from(record);
    final sectionsRaw = normalized['sections'];
    if (sectionsRaw is List) {
      normalized['sections'] = sectionsRaw
          .whereType<Map>()
          .map((section) => Map<String, dynamic>.from(section))
          .toList();
    } else {
      normalized['sections'] = <Map<String, dynamic>>[];
    }
    final actualId = normalized['id']?.toString();
    bool replaced = false;
    final updated = _warehouses.map((warehouse) {
      final id = warehouse['id']?.toString();
      if ((replaceId != null && id == replaceId) ||
          (replaceId == null && actualId != null && id == actualId)) {
        replaced = true;
        final preservedSections =
            (warehouse['sections'] as List?)?.whereType<Map>().map((section) {
                  final copy = Map<String, dynamic>.from(section);
                  if (actualId != null) {
                    copy['warehouse_id'] = actualId;
                  }
                  return copy;
                }).toList() ??
                const <Map<String, dynamic>>[];
        return {
          ...normalized,
          'sections': preservedSections.isNotEmpty
              ? preservedSections
              : normalized['sections'],
        };
      }
      return warehouse;
    }).toList();
    if (!replaced) {
      updated.add(normalized);
    }
    setState(() => _warehouses = updated);
    runDetached(_persistWarehousesCache());
  }

  void _upsertSectionRecord(
    Map<String, dynamic> record, {
    String? replaceId,
  }) {
    final normalized = Map<String, dynamic>.from(record);
    final actualId = normalized['id']?.toString();
    final targetWarehouseId = normalized['warehouse_id']?.toString();
    bool replaced = false;
    final updated = _warehouses.map((warehouse) {
      final sectionsRaw = warehouse['sections'];
      if (sectionsRaw is! List) return warehouse;
      var changed = false;
      final sections = sectionsRaw.whereType<Map>().map((section) {
        final sectionId = section['id']?.toString();
        if (replaceId != null && sectionId == replaceId) {
          replaced = true;
          changed = true;
          final next = Map<String, dynamic>.from(normalized);
          next['warehouse_id'] =
              next['warehouse_id']?.toString() ?? warehouse['id']?.toString();
          return next;
        }
        if (replaceId == null && actualId != null && sectionId == actualId) {
          replaced = true;
          changed = true;
          final next = Map<String, dynamic>.from(normalized);
          next['warehouse_id'] =
              next['warehouse_id']?.toString() ?? warehouse['id']?.toString();
          return next;
        }
        return Map<String, dynamic>.from(section);
      }).toList();
      if (changed) {
        return {...warehouse, 'sections': sections};
      }
      return warehouse;
    }).toList();

    List<Map<String, dynamic>> appendToWarehouse(
        Map<String, dynamic> warehouse) {
      final sectionsRaw = warehouse['sections'];
      final sections = sectionsRaw is List
          ? sectionsRaw
              .whereType<Map>()
              .map((section) => Map<String, dynamic>.from(section))
              .toList()
          : <Map<String, dynamic>>[];
      final next = Map<String, dynamic>.from(normalized);
      next['warehouse_id'] = warehouse['id']?.toString();
      sections.add(next);
      return sections;
    }

    if (!replaced && targetWarehouseId != null) {
      final appended = updated.map((warehouse) {
        if (warehouse['id']?.toString() == targetWarehouseId) {
          return {
            ...warehouse,
            'sections': appendToWarehouse(warehouse),
          };
        }
        return warehouse;
      }).toList();
      setState(() => _warehouses = appended);
    } else {
      setState(() => _warehouses = updated);
    }
    runDetached(_persistWarehousesCache());
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

  void _showOfflineQueuedSnack(
      [String message = 'Action enregistrée hors ligne.']) {
    _showSnack(message);
  }

  Future<void> _refreshPendingActionsCount() async {
    final actions = await OfflineStorage.instance.pendingActions();
    if (!mounted) return;
    setState(() => _pendingActionCount = actions.length);
  }

  Future<CommandResult<Map<String, dynamic>>>
      _markPurchaseRequestToPlaceOffline(
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
    String? itemId,
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
      if (itemId != null && itemId.isNotEmpty) 'item_id': itemId,
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
        if (itemId != null && itemId.isNotEmpty) 'item_id': itemId,
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
      if (!_isOnline || _isNetworkError(result.error)) {
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

  Future<void> _handleEditPurchaseRequest(Map<String, dynamic> request) async {
    final requestId = _purchaseRequestId(request);
    if (requestId == null) return;
    final initialNote = request['note']?.toString() ?? '';
    final itemId = request['item_id']?.toString() ??
        _matchInventoryItemByName(request['name']?.toString());
    final itemMeta = itemId == null
        ? const <String, dynamic>{}
        : Map<String, dynamic>.from(
            _inventory
                    .firstWhere(
                      (e) => e.item['id']?.toString() == itemId,
                      orElse: () => const InventoryEntry(item: {}),
                    )
                    .item['meta'] as Map? ??
                const {},
          );
    String? photoUrl = itemMeta['photo_url']?.toString();
    final noteCtrl = TextEditingController(text: initialNote);
    bool submitting = false;
    String? dialogError;
    bool uploadingPhoto = false;
    bool photoChanged = false;

    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setSheetState) {
            Widget preview() {
              if (photoUrl == null || photoUrl!.isEmpty) {
                return Container(
                  height: 140,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: Colors.grey.shade200,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: const Text('Aucune photo'),
                );
              }
              return ClipRRect(
                borderRadius: BorderRadius.circular(12),
                child: Image.network(
                  photoUrl!,
                  height: 200,
                  width: double.infinity,
                  fit: BoxFit.cover,
                  errorBuilder: (_, __, ___) => Container(
                    height: 140,
                    color: Colors.grey.shade200,
                    alignment: Alignment.center,
                    child: const Text('Photo non disponible'),
                  ),
                ),
              );
            }

            Future<void> pickPhoto(ImageSource source) async {
              if (!_isOnline) {
                _showSnack('Ajoute la photo en ligne pour l’envoyer.', error: true);
                return;
              }
              if (itemId == null) {
                _showSnack('Crée d’abord la pièce pour ajouter une photo.', error: true);
                return;
              }
              final picker = ImagePicker();
              final picked = await picker.pickImage(
                source: source,
                imageQuality: 80,
                maxWidth: 1600,
              );
              if (picked == null) return;
              setSheetState(() {
                uploadingPhoto = true;
                dialogError = null;
              });
              try {
                final uploadedUrl = await _uploadPhotoFromPath(picked.path);
                setSheetState(() {
                  photoUrl = uploadedUrl;
                  photoChanged = true;
                });
              } catch (e) {
                setSheetState(() {
                  dialogError = e.toString();
                });
              } finally {
                setSheetState(() => uploadingPhoto = false);
              }
            }

            Future<void> submit() async {
              setSheetState(() {
                submitting = true;
                dialogError = null;
              });
              final note = noteCtrl.text.trim();
              final patch = <String, dynamic>{
                'note': note,
              };

              if (!_isOnline) {
                final updated =
                    await _updatePurchaseRequestLocally(requestId, patch);
                await OfflineActionsService.instance.enqueue(
                  OfflineActionTypes.purchaseRequestUpdate,
                  {
                    'request_id': requestId,
                    'patch': patch,
                    'log': {
                      'event': 'purchase_request_note_updated',
                      'note': note,
                      'payload': {
                        'request_id': requestId,
                        'note': note,
                      },
                    },
                  },
                );
                await _refreshPendingActionsCount();
                if (!mounted || !context.mounted) return;
                Navigator.of(context).pop(updated);
                _showOfflineQueuedSnack('Commande mise à jour (hors ligne).');
                return;
              }

              final result = await _commands.updatePurchaseRequest(
                requestId: requestId,
                patch: patch,
              );
              if (!mounted || !context.mounted) return;
              if (!result.ok || result.data == null) {
                setSheetState(() {
                  submitting = false;
                  dialogError =
                      _describeError(result.error) ?? 'Impossible de modifier.';
                });
                return;
              }
              _replacePurchaseRequest(result.data!);

              if (photoChanged && photoUrl != null && itemId != null) {
                final meta = Map<String, dynamic>.from(
                    itemMeta.isEmpty ? <String, dynamic>{} : itemMeta);
                meta['photo_url'] = photoUrl!;
                await _persistItemMeta(
                  itemId: itemId,
                  meta: meta,
                  successMessage: null,
                );
              }
              if (!mounted || !context.mounted) return;
              Navigator.of(context).pop();
              _showSnack('Commande mise à jour.');
            }

            return Padding(
              padding: EdgeInsets.only(
                left: 16,
                right: 16,
                top: 16,
                bottom: MediaQuery.of(context).viewInsets.bottom + 24,
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      const Text(
                        'Détails de la commande',
                        style: TextStyle(fontWeight: FontWeight.w700),
                      ),
                      const Spacer(),
                      IconButton(
                        onPressed: submitting ? null : () => Navigator.pop(context),
                        icon: const Icon(Icons.close),
                      ),
                    ],
                  ),
                const SizedBox(height: 12),
                preview(),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: uploadingPhoto
                            ? null
                            : () => pickPhoto(ImageSource.camera),
                        icon: const Icon(Icons.photo_camera),
                        label: const Text('Prendre une photo'),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: uploadingPhoto
                            ? null
                            : () => pickPhoto(ImageSource.gallery),
                        icon: const Icon(Icons.photo_library_outlined),
                        label: const Text('Photothèque'),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: noteCtrl,
                  maxLines: 3,
                  decoration: const InputDecoration(
                      labelText: 'Note (optionnel)',
                      hintText: 'Ajoute un commentaire',
                    ),
                  ),
                  if (dialogError != null) ...[
                    const SizedBox(height: 8),
                    Text(dialogError!, style: const TextStyle(color: Colors.red)),
                  ],
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      TextButton(
                        onPressed:
                            submitting ? null : () => Navigator.of(context).pop(),
                        child: const Text('Annuler'),
                      ),
                      const Spacer(),
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
                  ),
                ],
              ),
            );
          },
        );
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

    var itemId = request['item_id']?.toString();
    itemId ??= _matchInventoryItemByName(request['name']?.toString());
    if (itemId == null) {
      final itemName = request['name']?.toString() ?? 'Pièce';
      if (_isOnline) {
        final createResult = await _commands.createItem(
          companyId: companyId,
          name: itemName,
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
      } else {
        final entry = await _createInventoryItemOffline(
          companyId: companyId,
          name: itemName,
        );
        itemId = entry?.item['id']?.toString();
        if (itemId == null) {
          _showSnack(
            'Impossible de créer l’article hors ligne pour cette pièce.',
            error: true,
          );
          return;
        }
      }
      request['item_id'] = itemId;
    }

    if (!_isOnline) {
      final placed = await _placePurchaseRequestOffline(
        request: request,
        requestId: requestId,
        companyId: companyId,
        itemId: itemId,
        warehouseId: warehouseId,
        sectionId: sectionId,
        qty: qty,
      );
      if (placed) {
        _applySectionToRequest(request, warehouseId, sectionId);
      }
      return;
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
      if (_isNetworkError(stockResult.error)) {
        final placedOffline = await _placePurchaseRequestOffline(
          request: request,
          requestId: requestId,
          companyId: companyId,
          itemId: itemId,
          warehouseId: warehouseId,
          sectionId: sectionId,
          qty: qty,
        );
        if (placedOffline) return;
      }
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
      if (_isNetworkError(updateResult.error)) {
        await _placePurchaseRequestOffline(
          request: request,
          requestId: requestId,
          companyId: companyId,
          itemId: itemId,
          warehouseId: warehouseId,
          sectionId: sectionId,
          qty: qty,
        );
        return;
      }
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
          equipmentProvider: () => _equipment,
          commands: _commands,
          describeError: _describeError,
          onRefresh: _refreshAll,
          isOnline: () => _isOnline,
          initialSectionId: sectionId,
          onShowJournal: ({
            String? scopeOverride,
            String? entityId,
            bool prefix = false,
          }) =>
              _handleOpenJournal(
            scopeOverride: scopeOverride ?? 'inventory',
            entityId: entityId,
            prefix: prefix,
          ),
          onManageWarehouse: _handleManageWarehouse,
          onCreateSectionOffline: ({
            required String warehouseId,
            required String name,
            String? code,
          }) =>
              _createInventorySectionOffline(
            companyId: companyId,
            warehouseId: warehouseId,
            name: name,
            code: code,
          ),
          onCreateItemOffline: ({
            required String name,
            String? sku,
            String? unit,
            String? category,
          }) =>
              _createInventoryItemOffline(
            companyId: companyId,
            name: name,
            sku: sku,
            unit: unit,
            category: category,
          ),
          onReplaceEquipment: _replaceEquipment,
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
    const sentinel = InventoryEntry.unassignedSectionKey;
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
                        // ignore: deprecated_member_use
                        value: section['id']?.toString() ?? '',
                        // ignore: deprecated_member_use
                        groupValue: selectedValue,
                        // ignore: deprecated_member_use
                        onChanged: (value) {
                          if (value == null) return;
                          setDialogState(() => selectedValue = value);
                        },
                        title: Text(
                            section['name']?.toString() ?? 'Section sans nom'),
                      ),
                    RadioListTile<String>(
                      // ignore: deprecated_member_use
                      value: sentinel,
                      // ignore: deprecated_member_use
                      groupValue: selectedValue,
                      // ignore: deprecated_member_use
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
                subtitle:
                    const Text('Code partagé pour rejoindre l’entreprise.'),
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

  Future<void> _handleChangeMemberRole(
    Map<String, dynamic> member,
  ) async {
    final companyId = _overview?.membership?.companyId;
    if (companyId == null) {
      _showSnack('Entreprise inconnue.', error: true);
      return;
    }
    final userUid = member['user_uid']?.toString();
    if (userUid == null || userUid.isEmpty) {
      _showSnack('Membre invalide.', error: true);
      return;
    }

    final actingRole = companyRoleFromString(_overview?.membership?.role);
    final assignableRoles = actingRole.assignableRoles;
    if (assignableRoles.isEmpty) {
      _showSnack(
        'Tu n’as pas la permission de modifier les rôles.',
        error: true,
      );
      return;
    }

    final memberName = _memberDisplayName(member);
    final currentRole = companyRoleFromString(member['role']?.toString());
    CompanyRole selectedRole = assignableRoles.contains(currentRole)
        ? currentRole
        : assignableRoles.first;

    final newRole = await showDialog<CompanyRole>(
      context: context,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            return AlertDialog(
              title: const Text('Changer le rôle'),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(
                    memberName,
                    style: Theme.of(context)
                        .textTheme
                        .titleMedium
                        ?.copyWith(fontWeight: FontWeight.w600),
                  ),
                  const SizedBox(height: 12),
                  DropdownButtonFormField<CompanyRole>(
                    initialValue: selectedRole,
                    decoration:
                        const InputDecoration(labelText: 'Nouveau rôle'),
                    items: assignableRoles
                        .map(
                          (role) => DropdownMenuItem<CompanyRole>(
                            value: role,
                            child: Text(role.label),
                          ),
                        )
                        .toList(growable: false),
                    onChanged: (value) {
                      if (value == null) return;
                      setDialogState(() => selectedRole = value);
                    },
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Les rôles contrôlent l’accès aux modules Logtek.',
                    style: Theme.of(context)
                        .textTheme
                        .bodySmall
                        ?.copyWith(color: Colors.black54),
                  ),
                ],
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.of(context).pop(null),
                  child: const Text('Annuler'),
                ),
                FilledButton(
                  onPressed: () => Navigator.of(context).pop(selectedRole),
                  child: const Text('Enregistrer'),
                ),
              ],
            );
          },
        );
      },
    );

    if (newRole == null || newRole == currentRole) {
      return;
    }

    if (!mounted) return;
    showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (_) => const Center(child: CircularProgressIndicator()),
    );
    final result = await _commands.updateMembershipRole(
      companyId: companyId,
      userUid: userUid,
      role: newRole.value,
    );
    if (!mounted) return;
    Navigator.of(context, rootNavigator: true).pop();

    if (!result.ok) {
      _showSnack(
        _describeError(result.error) ?? 'Modification impossible.',
        error: true,
      );
      return;
    }

    _showSnack('Rôle mis à jour.');
    await _refreshAll();
  }

  Future<void> _handleRemoveMember(Map<String, dynamic> member) async {
    final companyId = _overview?.membership?.companyId;
    if (companyId == null) {
      _showSnack('Entreprise inconnue.', error: true);
      return;
    }
    final userUid = member['user_uid']?.toString();
    if (userUid == null || userUid.isEmpty) {
      _showSnack('Membre invalide.', error: true);
      return;
    }
    final memberName = _memberDisplayName(member);

    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Retirer ce membre ?'),
        content: Text(
          '“$memberName” perdra immédiatement l’accès à l’entreprise.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Annuler'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Retirer'),
          ),
        ],
      ),
    );

    if (confirm != true || !mounted) return;

    showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (_) => const Center(child: CircularProgressIndicator()),
    );
    final result = await _commands.removeMembership(
      companyId: companyId,
      userUid: userUid,
    );
    if (!mounted) return;
    Navigator.of(context, rootNavigator: true).pop();

    if (!result.ok) {
      _showSnack(
        _describeError(result.error) ?? 'Suppression impossible.',
        error: true,
      );
      return;
    }

    _showSnack('Membre retiré.');
    await _refreshAll();
  }

  Future<void> _handleAssignEquipmentToMember(
    Map<String, dynamic> member,
  ) async {
    if (_equipment.isEmpty) {
      _showSnack('Aucun équipement disponible.', error: true);
      return;
    }
    final userUid = member['user_uid']?.toString();
    if (userUid == null || userUid.isEmpty) {
      _showSnack('Membre invalide.', error: true);
      return;
    }

    final memberName = _memberDisplayName(member);
    final equipmentList = _equipment.toList()
      ..sort(
        (a, b) => (a['name']?.toString() ?? '')
            .toLowerCase()
            .compareTo((b['name']?.toString() ?? '').toLowerCase()),
      );
    final currentSelection = equipmentList
        .where((item) => _equipmentAssignedUserId(item) == userUid)
        .map((item) => item['id']?.toString())
        .whereType<String>()
        .toSet();

    final selected = await showDialog<Set<String>>(
      context: context,
      builder: (context) {
        final workingSelection = <String>{...currentSelection};
        return StatefulBuilder(
          builder: (context, setDialogState) {
            return AlertDialog(
              title: const Text('Attribuer un équipement'),
              content: SizedBox(
                width: 420,
                child: SingleChildScrollView(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        'Sélectionne les équipements liés à $memberName.',
                        style: Theme.of(context)
                            .textTheme
                            .bodyMedium
                            ?.copyWith(color: Colors.black54),
                      ),
                      const SizedBox(height: 12),
                      for (final item in equipmentList)
                        Builder(
                          builder: (context) {
                            final equipmentId = item['id']?.toString();
                            if (equipmentId == null) {
                              return const SizedBox.shrink();
                            }
                            final assignedUid = _equipmentAssignedUserId(item);
                            final otherName = assignedUid == null
                                ? ''
                                : _memberNameByUid(assignedUid);
                            final assignedNameLabel =
                                assignedUid == null || assignedUid == userUid
                                    ? null
                                    : otherName.isNotEmpty
                                        ? otherName
                                        : _equipmentAssignedName(item);
                            final checked =
                                workingSelection.contains(equipmentId);
                            final subtitle = assignedUid == null
                                ? null
                                : assignedUid == userUid
                                    ? 'Attribué à $memberName'
                                    : 'Actuellement : ${assignedNameLabel ?? 'autre membre'}';
                            return CheckboxListTile(
                              value: checked,
                              controlAffinity: ListTileControlAffinity.leading,
                              onChanged: (value) {
                                if (value == null) return;
                                setDialogState(() {
                                  if (value) {
                                    workingSelection.add(equipmentId);
                                  } else {
                                    workingSelection.remove(equipmentId);
                                  }
                                });
                              },
                              title: Text(
                                  item['name']?.toString() ?? 'Équipement'),
                              subtitle:
                                  subtitle == null ? null : Text(subtitle),
                            );
                          },
                        ),
                    ],
                  ),
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.of(context).pop(null),
                  child: const Text('Annuler'),
                ),
                FilledButton(
                  onPressed: () =>
                      Navigator.of(context).pop(workingSelection.toSet()),
                  child: const Text('Enregistrer'),
                ),
              ],
            );
          },
        );
      },
    );

    if (selected == null) return;

    final updates = <({Map<String, dynamic> equipment, String? assignedTo})>[];
    for (final item in equipmentList) {
      final equipmentId = item['id']?.toString();
      if (equipmentId == null) continue;
      final assignedUid = _equipmentAssignedUserId(item);
      final shouldAssign = selected.contains(equipmentId);
      if (shouldAssign && assignedUid != userUid) {
        updates.add((equipment: item, assignedTo: userUid));
      } else if (!shouldAssign && assignedUid == userUid) {
        updates.add((equipment: item, assignedTo: null));
      }
    }

    if (updates.isEmpty) {
      _showSnack('Aucune modification apportée.');
      return;
    }

    if (!mounted) return;
    showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (_) => const Center(child: CircularProgressIndicator()),
    );
    var queuedOffline = false;
    String? failureMessage;
    for (final update in updates) {
      final nextMeta = Map<String, dynamic>.from(
          update.equipment['meta'] as Map? ?? const <String, dynamic>{});
      if (update.assignedTo == null) {
        nextMeta.remove(_equipmentAssignedToKey);
        nextMeta.remove(_equipmentAssignedNameKey);
        nextMeta.remove(_equipmentAssignedAtKey);
      } else {
        nextMeta[_equipmentAssignedToKey] = update.assignedTo;
        nextMeta[_equipmentAssignedNameKey] = memberName;
        nextMeta[_equipmentAssignedAtKey] = DateTime.now().toIso8601String();
      }
      final equipmentName =
          update.equipment['name']?.toString() ?? 'Équipement';
      final events = <Map<String, dynamic>>[
        {
          'event': update.assignedTo == null
              ? 'equipment_unassigned'
              : 'equipment_assigned',
          'category': 'general',
          'note': update.assignedTo == null
              ? '$equipmentName retiré de $memberName'
              : '$equipmentName attribué à $memberName',
          'payload': {
            'equipment_id': update.equipment['id']?.toString(),
            'assigned_to': update.assignedTo,
            if (update.assignedTo != null) 'assigned_name': memberName,
          },
        },
      ];
      final outcome = await _persistEquipmentMetaUpdate(
        equipment: update.equipment,
        nextMeta: nextMeta,
        events: events,
        successMessage: '',
        offlineMessage: 'Assignation enregistrée (hors ligne).',
        errorFallbackMessage: 'Impossible de mettre à jour l’équipement.',
        showSuccessSnack: false,
        showOfflineSnack: false,
        refreshOnSuccess: false,
      );
      if (!outcome.ok) {
        failureMessage = outcome.message;
        break;
      }
      queuedOffline = queuedOffline || outcome.queuedOffline;
    }

    if (!mounted) return;
    Navigator.of(context, rootNavigator: true).pop();

    if (failureMessage != null) {
      _showSnack(failureMessage, error: true);
      return;
    }

    if (queuedOffline) {
      _showOfflineQueuedSnack('Assignations enregistrées (hors ligne).');
    } else {
      _showSnack('Assignations mises à jour.');
    }

    if (_isOnline) {
      await _refreshAll();
    } else {
      setState(() {});
    }
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
                          if (value
                                  .trim()
                                  .replaceAll(RegExp(r'\s+'), '')
                                  .length <
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
                                  : () =>
                                      setDialogState(() => expiresAt = null),
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
    final codeId = code.id;
    if (codeId.isEmpty) {
      _showSnack('Code inconnu.', error: true);
      return;
    }

    void removeLocally() {
      if (!mounted) return;
      setState(() {
        _joinCodes =
            _joinCodes.where((candidate) => candidate.id != codeId).toList();
      });
    }

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

    if (!_isOnline) {
      _pendingJoinCodeDeletes.add(codeId);
      removeLocally();
      await OfflineActionsService.instance.enqueue(
        OfflineActionTypes.joinCodeDelete,
        {'code_id': codeId},
      );
      await _refreshPendingActionsCount();
      _showOfflineQueuedSnack('Code supprimé (hors ligne).');
      return;
    }

    _pendingJoinCodeDeletes.add(codeId);
    removeLocally();
    final result = await _commands.deleteJoinCode(codeId: codeId);
    if (!result.ok) {
      _pendingJoinCodeDeletes.remove(codeId);
      _showSnack(
        _describeError(result.error) ?? 'Impossible de supprimer ce code.',
        error: true,
      );
      await _refreshAll();
      return;
    }
    _showSnack('Code supprimé.');
    await _refreshAll();
    _pendingJoinCodeDeletes.remove(codeId);
  }

  void _handleQuickAction(_QuickAction action) {
    runDetached(_launchQuickActionFlow(action));
  }

  void _handleShowLowStockPage() {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (context) => _LowStockPage(
          items: _lowStockItems,
          onOrder: (item) {
            final name = item.item['name']?.toString();
            String? warehouseId;
            String? sectionId;

            // Try to find where the item is stored
            if (item.warehouseSplit.isNotEmpty) {
              // Pick the first warehouse where it exists
              warehouseId = item.warehouseSplit.keys.first;

              // Try to find a section in this warehouse
              final sections = item.sectionSplit[warehouseId];
              if (sections != null && sections.isNotEmpty) {
                // Pick the first section, ignoring unassigned if possible unless it's the only one
                final sectionKeys = sections.keys
                    .where((k) => k != InventoryEntry.unassignedSectionKey)
                    .toList();
                if (sectionKeys.isNotEmpty) {
                  sectionId = sectionKeys.first;
                } else if (sections
                    .containsKey(InventoryEntry.unassignedSectionKey)) {
                  // It's in unassigned
                  sectionId = null;
                }
              }
            }

            _promptCreatePurchaseRequest(
              initialName: name,
              initialWarehouseId: warehouseId,
              initialSectionId: sectionId,
            );
          },
        ),
      ),
    );
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
    final entry = await _copilotPromptInventoryItem();
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

  String? _scopeForTab(_GateTab tab) {
    switch (tab) {
      case _GateTab.home:
        return null;
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

  String _scopeLabel(String? scope) {
    if (scope == null) return 'Activité globale';
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
    if (category == null || category.isEmpty || category == 'general') {
      return equipmentId;
    }
    return '$equipmentId::$category';
  }

  String _memberNameByUid(String userUid) {
    final members = _overview?.members ?? const <Map<String, dynamic>>[];
    final match = members.firstWhere(
      (member) => member['user_uid']?.toString() == userUid,
      orElse: () => const <String, dynamic>{},
    );
    if (match.isEmpty) return '';
    return _memberDisplayName(match);
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

  String _generateLocalId(String scope) {
    final timestamp = DateTime.now().microsecondsSinceEpoch;
    final salt = _random.nextInt(1 << 20);
    return 'local_${scope}_${timestamp}_$salt';
  }

  /// Returns the current company id, falling back to cached overview if needed.
  Future<String?> _resolveCompanyId() async {
    final live = _overview?.membership?.companyId;
    if (live != null) return live;
    final cached = await _repository.readCachedCompanyOverview();
    return cached?.membership?.companyId;
  }

  Future<String> _uploadPhotoFromPath(String path) async {
    final file = File(path);
    if (!await file.exists()) {
      throw 'Fichier photo introuvable.';
    }
    final userId = Supa.i.auth.currentUser?.id ?? 'anon';
    final ext = p.extension(path).replaceAll('.', '');
    final fileName =
        'requests/$userId/${DateTime.now().microsecondsSinceEpoch}.${ext.isEmpty ? 'jpg' : ext}';
    final storage = Supa.i.storage.from('inventory-photos');
    await storage.upload(fileName, file);
    final publicUrl = storage.getPublicUrl(fileName);
    return publicUrl;
  }

  String? _resolveOfflineId(String? rawId) {
    if (rawId == null) return null;
    return _offlineIdMapping[rawId] ?? rawId;
  }

  Future<String?> _resolveOfflineIdAsync(String? rawId) async {
    final direct = _resolveOfflineId(rawId);
    if (direct != null && direct != rawId) return direct;
    if (rawId == null) return null;
    final fromStorage = await OfflineStorage.instance.resolveIdMapping(rawId);
    if (fromStorage != null) {
      _offlineIdMapping[rawId] = fromStorage;
      return fromStorage;
    }
    return direct;
  }

  void _rememberOfflineMapping(String? tempId, String? actualId) {
    if (tempId == null || actualId == null) return;
    _offlineIdMapping[tempId] = actualId;
    // Persist so we can resolve after app restarts.
    runDetached(
      OfflineStorage.instance.saveIdMapping(tempId, actualId),
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
      OfflineActionTypes.inventorySectionCreate,
      _processQueuedInventorySectionCreate,
    );
    OfflineActionsService.instance.registerHandler(
      OfflineActionTypes.inventorySectionUpdate,
      _processQueuedInventorySectionUpdate,
    );
    OfflineActionsService.instance.registerHandler(
      OfflineActionTypes.inventorySectionDelete,
      _processQueuedInventorySectionDelete,
    );
    OfflineActionsService.instance.registerHandler(
      OfflineActionTypes.inventoryItemCreate,
      _processQueuedInventoryItemCreate,
    );
    OfflineActionsService.instance.registerHandler(
      OfflineActionTypes.inventoryItemMetaUpdate,
      _processQueuedInventoryItemMetaUpdate,
    );
    OfflineActionsService.instance.registerHandler(
      OfflineActionTypes.equipmentMetaUpdate,
      _processQueuedEquipmentMetaUpdate,
    );
    OfflineActionsService.instance.registerHandler(
      OfflineActionTypes.equipmentDelete,
      _processQueuedEquipmentDelete,
    );
    OfflineActionsService.instance.registerHandler(
      OfflineActionTypes.joinCodeDelete,
      _processQueuedJoinCodeDelete,
    );
    OfflineActionsService.instance.registerHandler(
      OfflineActionTypes.warehouseCreate,
      _processQueuedWarehouseCreate,
    );
    OfflineActionsService.instance.registerHandler(
      OfflineActionTypes.equipmentCreate,
      _processQueuedEquipmentCreate,
    );
    _offlineHandlersRegistered = true;
  }

  void _unregisterOfflineHandlers() {
    if (!_offlineHandlersRegistered) return;
    OfflineActionsService.instance
        .registerHandler(OfflineActionTypes.purchaseRequestUpdate, null);
    OfflineActionsService.instance
        .registerHandler(OfflineActionTypes.purchaseRequestDelete, null);
    OfflineActionsService.instance
        .registerHandler(OfflineActionTypes.purchaseRequestMarkToPlace, null);
    OfflineActionsService.instance
        .registerHandler(OfflineActionTypes.purchaseRequestCreate, null);
    OfflineActionsService.instance
        .registerHandler(OfflineActionTypes.inventoryStockDelta, null);
    OfflineActionsService.instance
        .registerHandler(OfflineActionTypes.inventoryDeleteItem, null);
    OfflineActionsService.instance
        .registerHandler(OfflineActionTypes.inventorySectionCreate, null);
    OfflineActionsService.instance
        .registerHandler(OfflineActionTypes.inventorySectionUpdate, null);
    OfflineActionsService.instance
        .registerHandler(OfflineActionTypes.inventorySectionDelete, null);
    OfflineActionsService.instance
        .registerHandler(OfflineActionTypes.inventoryItemCreate, null);
    OfflineActionsService.instance
        .registerHandler(OfflineActionTypes.inventoryItemMetaUpdate, null);
    OfflineActionsService.instance
        .registerHandler(OfflineActionTypes.equipmentMetaUpdate, null);
    OfflineActionsService.instance
        .registerHandler(OfflineActionTypes.equipmentDelete, null);
    OfflineActionsService.instance
        .registerHandler(OfflineActionTypes.joinCodeDelete, null);
    OfflineActionsService.instance
        .registerHandler(OfflineActionTypes.warehouseCreate, null);
    OfflineActionsService.instance
        .registerHandler(OfflineActionTypes.equipmentCreate, null);
    _offlineHandlersRegistered = false;
  }

  Future<void> _processQueuedPurchaseRequestUpdate(
    Map<String, dynamic> payload,
  ) async {
    final requestId =
        await _resolveOfflineIdAsync(payload['request_id']?.toString());
    final patchRaw = payload['patch'];
    if (requestId == null || patchRaw is! Map) return;
    final patch = Map<String, dynamic>.from(patchRaw);
    Future<void> resolvePatchId(String key) async {
      final raw = patch[key];
      if (raw == null) return;
      final resolved = await _resolveOfflineIdAsync(raw.toString());
      if (resolved != null) {
        patch[key] = resolved;
      }
    }

    await resolvePatchId('item_id');
    await resolvePatchId('warehouse_id');
    await resolvePatchId('section_id');
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
    final warehouseId =
        await _resolveOfflineIdAsync(payload['warehouse_id']?.toString());
    final sectionId =
        await _resolveOfflineIdAsync(payload['section_id']?.toString());
    final note = payload['note']?.toString();
    final itemId =
        await _resolveOfflineIdAsync(payload['item_id']?.toString());
    final result = await _commands.createPurchaseRequest(
      companyId: companyId,
      name: name,
      qty: qty,
      warehouseId: warehouseId,
      sectionId: sectionId,
      note: note,
      itemId: itemId,
    );
    if (!result.ok || result.data == null) {
      throw result.error ?? 'Impossible de créer la demande.';
    }
    if (!mounted) return;
    final tempId = payload['temp_id']?.toString();
    if (tempId != null) {
      _removePurchaseRequest(tempId);
    }
    final newId = result.data!['id']?.toString();
    _rememberOfflineMapping(tempId, newId);
    _replacePurchaseRequest(result.data!);
    await _logJournal(
      scope: 'list',
      event: 'purchase_request_created',
      entityId: newId,
      note: name,
      payload: {
        'request_id': newId,
        'qty': qty,
        'warehouse_id': warehouseId,
        'section_id': sectionId,
      },
    );
  }

  Future<void> _processQueuedWarehouseCreate(
    Map<String, dynamic> payload,
  ) async {
    final membership = _overview?.membership;
    final companyId =
        payload['company_id']?.toString() ?? membership?.companyId;
    final name = payload['name']?.toString();
    if (companyId == null || name == null) {
      throw StateError('Payload invalide pour warehouse_create.');
    }
    final rawCode = payload['code']?.toString();
    final code =
        rawCode == null || rawCode.trim().isEmpty ? null : rawCode.trim();
    final tempId = payload['temp_id']?.toString();
    final result = await _commands.createWarehouse(
      companyId: companyId,
      name: name,
      code: code,
    );
    if (!result.ok || result.data == null) {
      throw result.error ?? 'Impossible de créer l’entrepôt.';
    }
    if (!mounted) return;
    final newId = result.data!['id']?.toString();
    _rememberOfflineMapping(tempId, newId);
    _upsertWarehouseRecord(result.data!, replaceId: tempId);
  }

  Future<void> _processQueuedInventorySectionCreate(
    Map<String, dynamic> payload,
  ) async {
    final membership = _overview?.membership;
    final companyId =
        payload['company_id']?.toString() ?? membership?.companyId;
    final warehouseRaw = payload['warehouse_id']?.toString();
    final name = payload['name']?.toString();
    if (companyId == null || warehouseRaw == null || name == null) {
      throw StateError('Payload invalide pour inventory_section_create.');
    }
    final warehouseId =
        await _resolveOfflineIdAsync(warehouseRaw) ?? warehouseRaw;
    final rawCode = payload['code']?.toString();
    final code =
        rawCode == null || rawCode.trim().isEmpty ? null : rawCode.trim();
    final tempId = payload['temp_id']?.toString();
    final result = await _commands.createInventorySection(
      companyId: companyId,
      warehouseId: warehouseId,
      name: name,
      code: code,
    );
    if (!result.ok || result.data == null) {
      throw result.error ?? 'Impossible de créer la section.';
    }
    if (!mounted) return;
    final section = result.data!;
    final newId = section['id']?.toString();
    _rememberOfflineMapping(tempId, newId);
    _upsertSectionRecord(section, replaceId: tempId);
    final resolvedWarehouseId =
        section['warehouse_id']?.toString() ?? warehouseId;
    await _logJournal(
      scope: 'inventory',
      event: 'section_created',
      entityId: newId == null
          ? _inventoryWarehouseEntityId(resolvedWarehouseId)
          : _inventorySectionEntityId(resolvedWarehouseId, newId),
      note: name,
      payload: {
        'warehouse_id': resolvedWarehouseId,
        'section_id': newId,
        if (code != null) 'code': code,
      },
    );
  }

  Future<void> _processQueuedInventoryItemCreate(
    Map<String, dynamic> payload,
  ) async {
    final membership = _overview?.membership;
    final companyId =
        payload['company_id']?.toString() ?? membership?.companyId;
    final name = payload['name']?.toString();
    if (companyId == null || name == null) {
      throw StateError('Payload invalide pour inventory_item_create.');
    }

    String? normalize(String? value) {
      if (value == null) return null;
      final trimmed = value.trim();
      return trimmed.isEmpty ? null : trimmed;
    }

    final tempId = payload['temp_id']?.toString();
    final result = await _commands.createItem(
      companyId: companyId,
      name: name,
      sku: normalize(payload['sku']?.toString()),
      unit: normalize(payload['unit']?.toString()),
      category: normalize(payload['category']?.toString()),
    );
    if (!result.ok || result.data == null) {
      throw result.error ?? 'Impossible de créer la pièce.';
    }
    if (!mounted) return;
    final item = Map<String, dynamic>.from(result.data!);
    final newId = item['id']?.toString();
    _rememberOfflineMapping(tempId, newId);
    setState(() {
      var replaced = false;
      final updated = _inventory.map((entry) {
        final entryId = entry.item['id']?.toString();
        if (tempId != null && entryId == tempId) {
          replaced = true;
          final mergedItem = {
            ...entry.item,
            ...item,
          };
          return InventoryEntry(
            item: mergedItem,
            totalQty: entry.totalQty,
            warehouseSplit: entry.warehouseSplit,
            sectionSplit: entry.sectionSplit,
          );
        }
        return entry;
      }).toList(growable: false);
      if (replaced) {
        _inventory = updated;
      } else {
        _inventory = [
          ...updated,
          InventoryEntry(
            item: item,
            totalQty: 0,
            warehouseSplit: const <String, int>{},
            sectionSplit: const <String, Map<String, int>>{},
          ),
        ];
      }
    });
    runDetached(_persistInventoryCache());
  }

  Future<void> _processQueuedInventoryItemMetaUpdate(
    Map<String, dynamic> payload,
  ) async {
    final itemId =
        await _resolveOfflineIdAsync(payload['item_id']?.toString());
    final metaPayload = payload['meta'];
    if (itemId == null || metaPayload is! Map) {
      throw StateError('Payload invalide pour inventory_item_meta_update.');
    }
    final meta = Map<String, dynamic>.from(metaPayload);
    final result = await _commands.updateItemMeta(
      itemId: itemId,
      meta: meta,
    );
    if (!result.ok) {
      throw result.error ?? 'Impossible de synchroniser la pièce.';
    }
    if (result.data == null || !mounted) return;
    final newMeta = result.data!['meta'];
    if (newMeta is Map) {
      _applyLocalInventoryMeta(
        itemId,
        Map<String, dynamic>.from(newMeta),
      );
    }
  }

  Future<void> _processQueuedInventorySectionUpdate(
    Map<String, dynamic> payload,
  ) async {
    final sectionId =
        await _resolveOfflineIdAsync(payload['section_id']?.toString());
    final patchRaw = payload['patch'];
    if (sectionId == null || patchRaw is! Map) {
      throw StateError('Payload invalide pour inventory_section_update.');
    }
    final patch = Map<String, dynamic>.from(patchRaw);
    final result = await _commands.updateInventorySection(
      sectionId: sectionId,
      patch: patch,
    );
    if (!result.ok || result.data == null) {
      throw result.error ?? 'Impossible de mettre à jour la section.';
    }
    if (!mounted) return;
    _upsertSectionRecord(result.data!);
  }

  Future<void> _processQueuedInventorySectionDelete(
    Map<String, dynamic> payload,
  ) async {
    final sectionId =
        await _resolveOfflineIdAsync(payload['section_id']?.toString());
    if (sectionId == null) {
      throw StateError('Payload invalide pour inventory_section_delete.');
    }
    final result = await _commands.deleteInventorySection(sectionId: sectionId);
    if (!result.ok) {
      throw result.error ?? 'Impossible de supprimer la section.';
    }
    if (!mounted) return;
    setState(() {
      _warehouses = _warehouses.map((warehouse) {
        final sections = warehouse['sections'];
        if (sections is! List) return warehouse;
        final filtered = sections
            .whereType<Map>()
            .where((section) => section['id']?.toString() != sectionId)
            .toList();
        if (filtered.length == sections.length) {
          return warehouse;
        }
        return {...warehouse, 'sections': filtered};
      }).toList();
    });
    runDetached(_persistWarehousesCache());
  }

  Future<void> _processQueuedEquipmentCreate(
    Map<String, dynamic> payload,
  ) async {
    final membership = _overview?.membership;
    final companyId =
        payload['company_id']?.toString() ?? membership?.companyId;
    final name = payload['name']?.toString();
    if (companyId == null || name == null) {
      throw StateError('Payload invalide pour equipment_create.');
    }
    String? normalize(String? value) {
      if (value == null) return null;
      final trimmed = value.trim();
      return trimmed.isEmpty ? null : trimmed;
    }

    final tempId = payload['temp_id']?.toString();
    final result = await _commands.createEquipment(
      companyId: companyId,
      name: name,
      brand: normalize(payload['brand']?.toString()),
      model: normalize(payload['model']?.toString()),
      serial: normalize(payload['serial']?.toString()),
    );
    if (!result.ok || result.data == null) {
      throw result.error ?? 'Impossible de créer l’équipement.';
    }
    if (!mounted) return;
    final equipment = Map<String, dynamic>.from(result.data!);
    final newId = equipment['id']?.toString();
    _rememberOfflineMapping(tempId, newId);
    setState(() {
      var replaced = false;
      _equipment = _equipment.map((item) {
        if (tempId != null && item['id']?.toString() == tempId) {
          replaced = true;
          final next = Map<String, dynamic>.from(equipment);
          final localMeta = item['meta'];
          if (localMeta is Map && localMeta.isNotEmpty) {
            next['meta'] = Map<String, dynamic>.from(localMeta);
          }
          return next;
        }
        return item;
      }).toList();
      if (!replaced) {
        _equipment = [..._equipment, equipment];
      }
    });
    await _persistEquipmentCache();
    await _logJournal(
      scope: 'equipment',
      event: 'equipment_created',
      entityId: equipment['id']?.toString(),
      note: name,
      payload: equipment,
    );
  }

  Future<void> _processQueuedEquipmentDelete(
    Map<String, dynamic> payload,
  ) async {
    final rawId = payload['equipment_id']?.toString();
    final equipmentId = await _resolveOfflineIdAsync(rawId);
    if (equipmentId == null) {
      throw StateError('Payload invalide pour equipment_delete.');
    }
    final result = await _commands.deleteEquipment(equipmentId: equipmentId);
    if (!result.ok) {
      throw result.error ?? 'Impossible de supprimer cet équipement.';
    }
    if (!mounted) return;
    _removeEquipment(equipmentId);
    await _logJournal(
      scope: 'equipment',
      event: 'equipment_deleted',
      entityId: equipmentId,
      note: payload['equipment_name']?.toString(),
      payload: {'equipment_id': equipmentId},
    );
  }

  Future<void> _processQueuedPurchaseRequestDelete(
    Map<String, dynamic> payload,
  ) async {
    final requestId =
        await _resolveOfflineIdAsync(payload['request_id']?.toString());
    if (requestId == null) return;
    final result = await _commands.deletePurchaseRequest(requestId: requestId);
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
    final requestId =
        await _resolveOfflineIdAsync(payload['request_id']?.toString());
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
    final warehouseId =
        await _resolveOfflineIdAsync(payload['warehouse_id']?.toString());
    final itemId =
        await _resolveOfflineIdAsync(payload['item_id']?.toString());
    final delta = payload['delta'] is int
        ? payload['delta'] as int
        : int.tryParse(payload['delta']?.toString() ?? '');
    if (companyId == null || warehouseId == null || itemId == null) {
      throw StateError('Payload invalide pour inventory_stock_delta.');
    }
    if (delta == null) {
      throw StateError('Delta manquant pour inventory_stock_delta.');
    }
    final sectionId =
        await _resolveOfflineIdAsync(payload['section_id']?.toString());
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
    final itemId =
        await _resolveOfflineIdAsync(payload['item_id']?.toString());
    if (companyId == null || itemId == null) {
      throw StateError('Payload invalide pour inventory_delete_item.');
    }
    final sectionId =
        await _resolveOfflineIdAsync(payload['section_id']?.toString());
    final note = payload['note']?.toString();
    final warehouseId =
        await _resolveOfflineIdAsync(payload['warehouse_id']?.toString());
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
    final rawId = payload['equipment_id']?.toString();
    var equipmentId = await _resolveOfflineIdAsync(rawId);
    final equipmentName = payload['equipment_name']?.toString();
    if (equipmentId == null && equipmentName != null) {
      final match = _equipment.firstWhere(
        (e) =>
            (e['name']?.toString().toLowerCase() ?? '') ==
            equipmentName.toLowerCase(),
        orElse: () => const <String, dynamic>{},
      );
      final resolved = match['id']?.toString();
      if (resolved != null && rawId != null) {
        _rememberOfflineMapping(rawId, resolved);
      }
      equipmentId = resolved;
    }
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
      final message = result.error?.toString();
      if (message != null && message.contains('introuvable')) {
        // Équipement supprimé ou introuvable : on ignore pour ne pas bloquer la file.
        return;
      }
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

  Future<void> _processQueuedJoinCodeDelete(
    Map<String, dynamic> payload,
  ) async {
    final codeId = payload['code_id']?.toString();
    if (codeId == null || codeId.isEmpty) {
      throw StateError('Payload invalide pour join_code_delete.');
    }
    final result = await _commands.deleteJoinCode(codeId: codeId);
    if (!result.ok) {
      throw result.error ?? 'Impossible de supprimer le code.';
    }
    if (!mounted) return;
    _pendingJoinCodeDeletes.remove(codeId);
    setState(() {
      _joinCodes =
          _joinCodes.where((candidate) => candidate.id != codeId).toList();
    });
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
        final warehouseId =
            hasSection ? remainder.split(sectionSeparator).first : remainder;
        final sectionId =
            hasSection ? remainder.split(sectionSeparator).last : null;
        final warehouseName = _warehouseNameById(warehouseId);
        if (sectionId != null) {
          if (sectionId == InventoryEntry.unassignedSectionKey) {
            return '${warehouseName ?? "Entrepôt"} — Sans section';
          }
          final sectionName = _sectionNameById(warehouseId, sectionId);
          if (sectionName != null) {
            return '${warehouseName ?? "Entrepôt"} — Section $sectionName';
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

  Future<void> _handleOpenJournal({
    String? scopeOverride,
    String? entityId,
    bool prefix = false,
  }) async {
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
        : ' — ${_journalEntityLabel(scope ?? 'general', entityId) ?? entityId}';
    final title = 'Journal — $scopeTitle$entitySuffix';

    Future<List<Map<String, dynamic>>> loadEntries() async {
      final result = await _repository.fetchJournalEntries(
        scope: scope,
        entityId: entityId,
        prefix: prefix,
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
                scope: scope ?? 'home',
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
                                  final entryEntityId =
                                      entry['entity_id']?.toString();
                                  final showEntity =
                                      (entityId == null || prefix) &&
                                          entryEntityId != null;
                                  final event = entry['event']?.toString();
                                  final entryScope =
                                      entry['scope']?.toString() ??
                                          scope ??
                                          'general';
                                  final payload = entry['payload'] as Map?;

                                  String? extraInfo;
                                  if (event == 'stock_delta' &&
                                      payload != null) {
                                    final itemName =
                                        payload['item_name']?.toString();
                                    final delta = payload['delta'];
                                    final newQty = payload['new_qty'];
                                    final parts = <String>[];
                                    if (itemName != null) parts.add(itemName);
                                    if (delta != null) {
                                      final sign = (delta is num && delta > 0)
                                          ? '+'
                                          : '';
                                      parts.add('$sign$delta');
                                    }
                                    if (newQty != null) {
                                      parts.add('(Stock: $newQty)');
                                    }
                                    if (parts.isNotEmpty) {
                                      extraInfo = parts.join(' • ');
                                    }
                                  }

                                  return ListTile(
                                    contentPadding: EdgeInsets.zero,
                                    leading: const Icon(Icons.event_note),
                                    title: Text(
                                      journalEventLabel(event),
                                    ),
                                    subtitle: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        if (showEntity)
                                          Text(
                                            _journalEntityLabel(entryScope,
                                                    entryEntityId) ??
                                                entryEntityId,
                                            style: const TextStyle(
                                                fontWeight: FontWeight.w500),
                                          ),
                                        if (extraInfo != null)
                                          Text(
                                            extraInfo,
                                            style: const TextStyle(
                                                fontWeight: FontWeight.w600),
                                          ),
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

  Future<void> _handleSignOut() async {
    final userId = Supa.i.auth.currentUser?.id;
    if (userId != null) {
      await OfflineStorage.instance.clearUserCache(userId);
    }
    await Supa.i.auth.signOut();
    if (!mounted) return;
    Navigator.of(context).pushAndRemoveUntil(
      MaterialPageRoute(builder: (_) => const SignInPage()),
      (route) => false,
    );
  }

  String? _describeError(Object? error) {
    if (error == null) return null;
    if (_isNetworkError(error)) return null;
    return error.toString();
  }

  bool _isNetworkError(Object? error) {
    if (error == null) return false;
    if (error is SocketException || error is HandshakeException) return true;
    final message = error.toString().toLowerCase();
    return message.contains('failed host lookup') ||
        message.contains('socketexception') ||
        message.contains('connection refused') ||
        message.contains('connection reset') ||
        message.contains('timed out') ||
        message.contains('network is unreachable');
  }
}

class _PurchaseRequestDialog extends StatefulWidget {
  const _PurchaseRequestDialog({
    required this.commands,
    required this.companyId,
    required this.warehouses,
    required this.inventory,
    required this.describeError,
    required this.isOnline,
    this.onCreateOffline,
    this.onCreateItemOffline,
    this.initialName,
    this.initialWarehouseId,
    this.initialSectionId,
  });

  final CompanyCommands commands;
  final String companyId;
  final List<Map<String, dynamic>> warehouses;
  final List<InventoryEntry> inventory;
  final String? Function(Object? error) describeError;
  final bool isOnline;
  final Future<Map<String, dynamic>?> Function({
    required String name,
    required int qty,
    String? warehouseId,
    String? sectionId,
    String? note,
    String? itemId,
  })? onCreateOffline;
  final Future<InventoryEntry?> Function({
    required String name,
    String? sku,
    String? unit,
    String? category,
  })? onCreateItemOffline;
  final String? initialName;
  final String? initialWarehouseId;
  final String? initialSectionId;

  @override
  State<_PurchaseRequestDialog> createState() => _PurchaseRequestDialogState();
}

class _PurchaseRequestDialogState extends State<_PurchaseRequestDialog> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _nameCtrl;
  late final TextEditingController _noteCtrl;
  late final FocusNode _nameFocusNode;
  String? _selectedWarehouseId;
  String? _selectedSectionId;
  int _qty = 1;
  bool _submitting = false;
  String? _dialogError;

  @override
  void initState() {
    super.initState();
    _nameCtrl = TextEditingController(text: widget.initialName);
    _noteCtrl = TextEditingController();
    _nameFocusNode = FocusNode();
    _selectedWarehouseId = widget.initialWarehouseId;
    _selectedSectionId = widget.initialSectionId;
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    _noteCtrl.dispose();
    _nameFocusNode.dispose();
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
    final trimmedName = _nameCtrl.text.trim();

    Future<String?> ensureItemId() async {
      // Try local match first.
      final normalized = trimmedName.toLowerCase();
      for (final entry in widget.inventory) {
        final entryName = entry.item['name']?.toString();
        final entryId = entry.item['id']?.toString();
        if (entryName != null &&
            entryId != null &&
            entryName.trim().toLowerCase() == normalized) {
          return entryId;
        }
      }
      if (online) {
        final itemResult = await widget.commands.createItem(
          companyId: widget.companyId,
          name: trimmedName,
        );
        if (!itemResult.ok || itemResult.data == null) {
          setState(() {
            _submitting = false;
            _dialogError = widget.describeError(itemResult.error) ??
                'Impossible de créer cette pièce.';
          });
          return null;
        }
        return itemResult.data!['id']?.toString();
      }
      if (widget.onCreateItemOffline != null) {
        final created = await widget.onCreateItemOffline!(
          name: trimmedName,
          sku: null,
          unit: null,
          category: null,
        );
        return created?.item['id']?.toString();
      }
      setState(() {
        _submitting = false;
        _dialogError = 'Connexion requise pour créer cette pièce.';
      });
      return null;
    }

    final itemId = await ensureItemId();
    if (itemId == null || itemId.isEmpty) {
      return;
    }

    if (!online && widget.onCreateOffline != null) {
      final offlineCreated = await widget.onCreateOffline!.call(
        name: trimmedName,
        qty: _qty,
        warehouseId: _selectedWarehouseId,
        sectionId: _selectedSectionId,
        note: _noteCtrl.text.trim(),
        itemId: itemId,
      );
      if (!mounted) return;
      Navigator.of(context).pop(offlineCreated);
      return;
    }

    final result = await widget.commands.createPurchaseRequest(
      companyId: widget.companyId,
      name: trimmedName,
      qty: _qty,
      warehouseId: _selectedWarehouseId,
      sectionId: _selectedSectionId,
      note: _noteCtrl.text.trim(),
      itemId: itemId,
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
              RawAutocomplete<_ItemSuggestion>(
                textEditingController: _nameCtrl,
                focusNode: _nameFocusNode,
                displayStringForOption: (option) => option.name,
                optionsBuilder: (textEditingValue) {
                  final query = textEditingValue.text.trim().toLowerCase();
                  if (query.isEmpty) {
                    return const Iterable<_ItemSuggestion>.empty();
                  }
                  final matches = <_ItemSuggestion>[];
                  final seen = <String>{};
                  for (final entry in widget.inventory) {
                    final name = entry.item['name']?.toString();
                    if (name == null || name.isEmpty) continue;
                    final normalizedName = name.toLowerCase();
                    final sku = entry.item['sku']?.toString();
                    final normalizedSku = sku?.toLowerCase();
                    final matchesName = normalizedName.contains(query);
                    final matchesSku =
                        normalizedSku != null && normalizedSku.contains(query);
                    if (!matchesName && !matchesSku) continue;
                    if (seen.add(normalizedName)) {
                      matches.add(_ItemSuggestion(name: name, sku: sku));
                    }
                    if (matches.length >= 8) break;
                  }
                  return matches;
                },
                fieldViewBuilder:
                    (context, controller, focusNode, onFieldSubmitted) {
                  return TextFormField(
                    controller: controller,
                    focusNode: focusNode,
                    decoration: const InputDecoration(
                      labelText: 'Nom de la pièce',
                      helperText:
                          'Tape le nom ou le SKU pour réutiliser une pièce existante.',
                    ),
                    validator: (value) => value == null || value.trim().isEmpty
                        ? 'Nom requis'
                        : null,
                    textInputAction: TextInputAction.next,
                  );
                },
                optionsViewBuilder: (context, onSelected, options) {
                  return Align(
                    alignment: Alignment.topLeft,
                    child: Material(
                      elevation: 4,
                      child: ConstrainedBox(
                        constraints: BoxConstraints(
                          maxHeight: 240,
                          maxWidth: MediaQuery.of(context).size.width - 80,
                        ),
                        child: ListView.separated(
                          padding: EdgeInsets.zero,
                          itemBuilder: (context, index) {
                            final option = options.elementAt(index);
                            return ListTile(
                              title: Text(option.name),
                              subtitle: option.sku == null ||
                                      option.sku!.trim().isEmpty
                                  ? null
                                  : Text('SKU ${option.sku}'),
                              onTap: () => onSelected(option),
                            );
                          },
                          separatorBuilder: (_, __) => const Divider(height: 1),
                          itemCount: options.length,
                        ),
                      ),
                    ),
                  );
                },
                onSelected: (option) {
                  _nameCtrl.text = option.name;
                  _nameCtrl.selection = TextSelection.fromPosition(
                    TextPosition(offset: option.name.length),
                  );
                },
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

class _ItemSuggestion {
  const _ItemSuggestion({required this.name, this.sku});
  final String name;
  final String? sku;
}

class _InventorySectionDialog extends StatefulWidget {
  const _InventorySectionDialog({
    required this.commands,
    required this.companyId,
    required this.warehouseId,
    required this.warehouseName,
    required this.describeError,
    required this.isOnline,
    this.onCreateOffline,
  });

  final CompanyCommands commands;
  final String companyId;
  final String warehouseId;
  final String warehouseName;
  final String? Function(Object? error) describeError;
  final bool isOnline;
  final Future<Map<String, dynamic>?> Function({
    required String name,
    String? code,
  })? onCreateOffline;

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

    if (!widget.isOnline && widget.onCreateOffline != null) {
      final created = await widget.onCreateOffline!(
        name: _nameCtrl.text.trim(),
        code: _codeCtrl.text.trim().isEmpty ? null : _codeCtrl.text.trim(),
      );
      if (!mounted) return;
      if (created == null) {
        setState(() {
          _submitting = false;
          _dialogError = 'Action hors ligne impossible.';
        });
        return;
      }
      Navigator.of(context).pop(created);
      return;
    }

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
            style: const TextStyle(
              color: foreground,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
      ),
    );
  }
}

enum _OnboardingTab { company, more }

class _OnboardingView extends StatefulWidget {
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
    this.userName,
    this.userEmail,
    this.onSignOut,
    this.onDeleteAccount,
    this.isDeletingAccount = false,
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
  final String? userName;
  final String? userEmail;
  final Future<void> Function()? onSignOut;
  final Future<void> Function()? onDeleteAccount;
  final bool isDeletingAccount;

  @override
  State<_OnboardingView> createState() => _OnboardingViewState();
}

class _OnboardingViewState extends State<_OnboardingView> {
  _OnboardingTab _currentTab = _OnboardingTab.company;

  @override
  Widget build(BuildContext context) {
    final banners = _buildBanners();
    final content = _currentTab == _OnboardingTab.company
        ? _buildCompanyContent(banners)
        : _buildMoreContent(banners);

    return Scaffold(
      backgroundColor: AppColors.surface,
      body: SafeArea(child: content),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _currentTab.index,
        onDestinationSelected: (index) {
          if (!mounted) return;
          setState(() => _currentTab = _OnboardingTab.values[index]);
        },
        destinations: const [
          NavigationDestination(
            icon: Icon(Icons.business_outlined),
            selectedIcon: Icon(Icons.business),
            label: 'Entreprise',
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

  Widget _buildCompanyContent(List<Widget> banners) {
    return RefreshIndicator(
      onRefresh: widget.onRefresh,
      child: ListView(
        padding: const EdgeInsets.all(24),
        children: [
          _buildHeader(),
          if (banners.isNotEmpty) _buildBannerColumn(banners),
          const SizedBox(height: 12),
          _buildCreateCompanyCard(),
          const SizedBox(height: 16),
          _buildJoinCompanyCard(),
        ],
      ),
    );
  }

  Widget _buildMoreContent(List<Widget> banners) {
    return RefreshIndicator(
      onRefresh: widget.onRefresh,
      child: ListView(
        padding: const EdgeInsets.all(24),
        children: [
          _buildHeader(),
          if (banners.isNotEmpty) _buildBannerColumn(banners),
          const SizedBox(height: 12),
          _OnboardingProfileCard(
            userName: widget.userName,
            userEmail: widget.userEmail,
            onSignOut: widget.onSignOut,
            onDeleteAccount: widget.onDeleteAccount,
            isDeletingAccount: widget.isDeletingAccount,
          ),
        ],
      ),
    );
  }

  Widget _buildHeader() {
    return Column(
      children: [
        Center(child: Image.asset('assets/images/logtek_logo.png', height: 64)),
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
      ],
    );
  }

  Widget _buildBannerColumn(List<Widget> banners) {
    return Column(
      children: [
        for (final banner in banners) ...[
          banner,
          const SizedBox(height: 12),
        ],
      ],
    );
  }

  List<Widget> _buildBanners() {
    final banners = <Widget>[];
    if (!widget.isOnline) {
      banners.add(_StatusBanner.warning(
        icon: Icons.wifi_off,
        message: 'Connexion perdue. Certaines actions seront indisponibles.',
      ));
    }
    if (widget.missingTables.isNotEmpty) {
      banners.add(_StatusBanner.warning(
        icon: Icons.dataset_linked,
        message: 'Tables manquantes : ${widget.missingTables.join(', ')}',
      ));
    }
    if (widget.transientError != null) {
      banners.add(_StatusBanner.error(widget.transientError!));
    }
    return banners;
  }

  Widget _buildCreateCompanyCard() {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text('Créer une entreprise',
                style: Theme.of(context).textTheme.titleLarge),
            const SizedBox(height: 12),
            TextField(
              controller: widget.companyNameCtrl,
              decoration: const InputDecoration(
                labelText: 'Nom de l’entreprise',
              ),
            ),
            const SizedBox(height: 16),
            FilledButton.icon(
              onPressed: widget.creatingCompany ? null : widget.onCreateCompany,
              icon: widget.creatingCompany
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
    );
  }

  Widget _buildJoinCompanyCard() {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text('Rejoindre une entreprise',
                style: Theme.of(context).textTheme.titleLarge),
            const SizedBox(height: 12),
            TextField(
              controller: widget.joinCodeCtrl,
              textCapitalization: TextCapitalization.characters,
              decoration: const InputDecoration(
                labelText: 'Code d’accès',
              ),
            ),
            const SizedBox(height: 16),
            OutlinedButton.icon(
              onPressed: widget.joiningCompany ? null : widget.onJoinCompany,
              icon: widget.joiningCompany
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.login),
              label: const Text('Rejoindre'),
            ),
          ],
        ),
      ),
    );
  }
}

class _OnboardingProfileCard extends StatelessWidget {
  const _OnboardingProfileCard({
    this.userName,
    this.userEmail,
    this.onSignOut,
    this.onDeleteAccount,
    this.isDeletingAccount = false,
  });

  final String? userName;
  final String? userEmail;
  final Future<void> Function()? onSignOut;
  final Future<void> Function()? onDeleteAccount;
  final bool isDeletingAccount;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final displayName = (userName != null && userName!.isNotEmpty)
        ? userName!
        : (userEmail ?? 'Utilisateur connecté');
    final emailLabel = (userEmail != null && userEmail!.isNotEmpty)
        ? userEmail!
        : 'Email non disponible';
    final trimmed = displayName.trim();
    final initials =
        trimmed.isNotEmpty ? trimmed.substring(0, 1).toUpperCase() : '?';

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text('Profil & session',
                style: theme.textTheme.titleLarge?.copyWith(
                  fontWeight: FontWeight.w600,
                )),
            const SizedBox(height: 12),
            Row(
              children: [
                CircleAvatar(
                  child: Text(initials),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        displayName,
                        style: theme.textTheme.titleMedium,
                      ),
                      Text(emailLabel, style: theme.textTheme.bodySmall),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Text(
              'Gère ton profil même avant de rejoindre une entreprise.',
              style: theme.textTheme.bodySmall?.copyWith(color: Colors.black54),
            ),
            const SizedBox(height: 12),
            if (onSignOut != null)
              FilledButton.tonalIcon(
                onPressed: () => onSignOut?.call(),
                icon: const Icon(Icons.logout),
                label: const Text('Se déconnecter'),
              ),
            if (onSignOut != null && onDeleteAccount != null)
              const SizedBox(height: 12),
            if (onDeleteAccount != null)
              FilledButton(
                style: FilledButton.styleFrom(
                  backgroundColor: Colors.red.shade50,
                  foregroundColor: Colors.red.shade800,
                ),
                onPressed:
                    isDeletingAccount ? null : () => onDeleteAccount?.call(),
                child: isDeletingAccount
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Text('Supprimer mon compte'),
              ),
          ],
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

  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: action,
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
    final filtered = widget.inventory
        .where((entry) {
          if (query.isEmpty) return true;
          final name = entry.item['name']?.toString().toLowerCase() ?? '';
          final sku = entry.item['sku']?.toString().toLowerCase() ?? '';
          return name.contains(query) || sku.contains(query);
        })
        .take(60)
        .toList();

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
                          final sku = entry.item['sku']?.toString() ?? '';
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

String _memberDisplayName(Map<String, dynamic> member) {
  String pickField(String key) => member[key]?.toString().trim() ?? '';
  final fullName = pickField('full_name');
  final firstName = pickField('first_name');
  final lastName = pickField('last_name');
  final displayName = pickField('display_name');
  final composed = [firstName, lastName].where((value) => value.isNotEmpty);
  final composedName = composed.join(' ').trim();
  if (fullName.isNotEmpty) return fullName;
  if (composedName.isNotEmpty) return composedName;
  if (displayName.isNotEmpty) return displayName;
  final email = pickField('email');
  return email.isNotEmpty ? email : 'Membre';
}

String _memberEmail(Map<String, dynamic> member) {
  return member['email']?.toString().trim() ?? '';
}

String? _equipmentAssignedUserId(Map<String, dynamic> equipment) {
  final meta = equipment['meta'];
  if (meta is! Map) return null;
  final value = meta[_equipmentAssignedToKey];
  if (value == null) return null;
  final id = value.toString().trim();
  return id.isEmpty ? null : id;
}

String? _equipmentAssignedName(Map<String, dynamic> equipment) {
  final meta = equipment['meta'];
  if (meta is! Map) return null;
  final value = meta[_equipmentAssignedNameKey]?.toString().trim();
  if (value == null || value.isEmpty) return null;
  return value;
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
            final parsed = double.tryParse((value ?? '').replaceAll(',', '.'));
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
