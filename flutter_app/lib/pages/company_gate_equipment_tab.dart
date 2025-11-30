part of 'company_gate.dart';

// ---------------------------------------------------------------------------
// Equipment tab
// ---------------------------------------------------------------------------

enum _EquipmentFilter { active, inactive }

const List<String> kEquipmentTypes = <String>[
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

class _EquipmentTab extends StatefulWidget {
  const _EquipmentTab({
    required this.equipment,
    required this.commands,
    required this.onRefresh,
    required this.inventory,
    required this.warehouses,
    required this.onReplaceEquipment,
    required this.onRemoveEquipment,
    required this.equipmentProvider,
    this.companyId,
  });

  final List<Map<String, dynamic>> equipment;
  final List<InventoryEntry> inventory;
  final List<Map<String, dynamic>> warehouses;
  final CompanyCommands commands;
  final Future<void> Function() onRefresh;
  final void Function(Map<String, dynamic> equipment) onReplaceEquipment;
  final void Function(String equipmentId) onRemoveEquipment;
  final List<Map<String, dynamic>> Function() equipmentProvider;
  final String? companyId;

  @override
  State<_EquipmentTab> createState() => _EquipmentTabState();
}

class _EquipmentTabState extends State<_EquipmentTab> {
  _EquipmentFilter _filter = _EquipmentFilter.active;
  final Set<String> _updatingIds = <String>{};

  String _normalize(String input) {
    const accentMap = {
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
    };
    final buffer = StringBuffer();
    for (final rune in input.runes) {
      final char = String.fromCharCode(rune).toLowerCase();
      buffer.write(accentMap[char] ?? char);
    }
    return buffer.toString();
  }

  String _categoryFor(Map<String, dynamic> item) {
    final meta = item['meta'];
    if (meta is Map) {
      final type = meta['type']?.toString();
      if (type != null && type.trim().isNotEmpty) return type;
    }
    final name = item['name']?.toString() ?? '';
    final normalized = _normalize(name);
    if (normalized.contains('abatteuse')) return 'Abatteuse';
    if (normalized.contains('debardeur') || normalized.contains('débardeu')) {
      return 'Débardeur';
    }
    if (normalized.contains('transport') || normalized.contains('camion t')) {
      return 'Camion transporteur';
    }
    if (normalized.contains('pick') || normalized.contains('pickup')) {
      return 'Camion pick-up';
    }
    return 'Autres';
  }

  List<Map<String, dynamic>> get _filteredEquipment {
    return widget.equipment
        .where((item) =>
            (_filter == _EquipmentFilter.active && item['active'] != false) ||
            (_filter == _EquipmentFilter.inactive && item['active'] == false))
        .toList();
  }

  @override
  Widget build(BuildContext context) {
    final filtered = _filteredEquipment;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text('Équipement',
              style: Theme.of(context)
                  .textTheme
                  .titleLarge
                  ?.copyWith(fontWeight: FontWeight.w700)),
          const SizedBox(height: 6),
          Text(
            'Appuie sur le bouton + pour ajouter un équipement.',
            style: Theme.of(context).textTheme.bodySmall,
          ),
          const SizedBox(height: 16),
          Wrap(
            spacing: 12,
            runSpacing: 8,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              const Text('Afficher'),
              DropdownButton<_EquipmentFilter>(
                value: _filter,
                onChanged: (value) {
                  if (value == null) return;
                  setState(() => _filter = value);
                },
                items: const [
                  DropdownMenuItem(
                    value: _EquipmentFilter.active,
                    child: Text('Actifs'),
                  ),
                  DropdownMenuItem(
                    value: _EquipmentFilter.inactive,
                    child: Text('Inactifs'),
                  ),
                ],
              ),
              if (_filter == _EquipmentFilter.inactive)
                const Text(
                  'Réactive un appareil via son bouton.',
                  style: TextStyle(fontSize: 12, color: Colors.black54),
                ),
            ],
          ),
          const SizedBox(height: 12),
          if (filtered.isEmpty)
            const _EmptyCard(
              title: 'Aucun équipement',
              subtitle: 'Aucun résultat pour ce filtre.',
            )
          else
            Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: _buildGroupedEquipment(filtered),
            ),
        ],
      ),
    );
  }

  List<Widget> _buildGroupedEquipment(List<Map<String, dynamic>> items) {
    final grouped = <String, List<Map<String, dynamic>>>{};
    for (final raw in items) {
      final item = raw is Map
          ? Map<String, dynamic>.from(raw)
          : <String, dynamic>{};
      final cat = _categoryFor(item);
      grouped.putIfAbsent(cat, () => <Map<String, dynamic>>[]).add(item);
    }

    final orderedCategories = kEquipmentTypes
        .where((cat) => grouped[cat]?.isNotEmpty == true)
        .toList();
    for (final entry in grouped.entries) {
      if (!orderedCategories.contains(entry.key)) {
        orderedCategories.add(entry.key);
      }
    }

    final widgets = <Widget>[];
    for (final cat in orderedCategories) {
      final list = grouped[cat] ?? const <Map<String, dynamic>>[];
      widgets.add(Padding(
        padding: const EdgeInsets.only(top: 8, bottom: 4, left: 4),
        child: Text(
          cat,
          style: Theme.of(context)
              .textTheme
              .titleMedium
              ?.copyWith(fontWeight: FontWeight.w700),
        ),
      ));
      widgets.addAll(list.map((item) => _EquipmentListCard(
            data: item,
            onTap: () => _showEquipmentDetail(context, item),
            footer: _filter == _EquipmentFilter.inactive
                ? Align(
                    alignment: Alignment.centerLeft,
                    child: TextButton.icon(
                      onPressed:
                          _updatingIds.contains(item['id']?.toString() ?? '')
                              ? null
                              : () => _setEquipmentActive(item, true),
                      icon: _updatingIds.contains(item['id']?.toString() ?? '')
                          ? const SizedBox(
                              width: 16,
                              height: 16,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Icon(Icons.refresh_outlined),
                      label: const Text('Réactiver'),
                    ),
                  )
                : null,
          )));
      widgets.add(const Divider(height: 16, thickness: 0.8));
    }
    if (widgets.isNotEmpty) {
      widgets.removeLast(); // remove last divider
    }
    return widgets;
  }

  Future<void> _showEquipmentDetail(
    BuildContext context,
    Map<String, dynamic> data,
  ) async {
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => _EquipmentDetailPage(
          data: data,
          commands: widget.commands,
          onUpdated: widget.onRefresh,
          companyId: widget.companyId,
          inventory: widget.inventory,
          warehouses: widget.warehouses,
          allEquipment: widget.equipment,
          onEquipmentChanged: widget.onReplaceEquipment,
          onOtherEquipmentChanged: widget.onReplaceEquipment,
          onDeleteEquipment: widget.onRemoveEquipment,
        ),
      ),
    );
  }

  Future<void> _setEquipmentActive(
    Map<String, dynamic> equipment,
    bool active,
  ) async {
    final id = equipment['id']?.toString();
    if (id == null) return;
    setState(() => _updatingIds.add(id));
    final result = await widget.commands.updateEquipment(
      equipmentId: id,
      active: active,
    );
    setState(() => _updatingIds.remove(id));
    if (!result.ok) {
      _showSnack(
        _describeError(result.error) ?? 'Impossible de mettre à jour.',
        error: true,
      );
      return;
    }
    _showSnack(active ? 'Équipement réactivé.' : 'Équipement désactivé.');
    await widget.onRefresh();
  }

  void _showSnack(String message, {bool error = false}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: error
            ? Theme.of(context).colorScheme.error
            : Theme.of(context).colorScheme.primary,
      ),
    );
  }

  String? _describeError(Object? error) {
    if (error == null) return null;
    if (error is String) return error;
    return error.toString();
  }
}

class _EquipmentListCard extends StatelessWidget {
  const _EquipmentListCard({
    required this.data,
    required this.onTap,
    this.footer,
  });

  final Map<String, dynamic> data;
  final VoidCallback onTap;
  final Widget? footer;

  @override
  Widget build(BuildContext context) {
    final name = data['name']?.toString() ?? 'Équipement';
    final brand = data['brand']?.toString();
    final model = data['model']?.toString();
    final serial = data['serial']?.toString();
    final meta = data['meta'];
    String? type;
    String? year;
    if (meta is Map) {
      type = meta['type']?.toString();
      year = meta['year']?.toString();
    }
    final subtitle = [
      if (brand != null) brand,
      if (model != null) model,
      if (serial != null) 'SN $serial',
      if (year != null && year.isNotEmpty) 'Année $year',
    ].join(' • ');

    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  const CircleAvatar(
                    backgroundColor: Color(0xFFECEFF1),
                    child: Icon(Icons.build, color: AppColors.primary),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(name,
                            style: Theme.of(context)
                                .textTheme
                                .titleMedium
                                ?.copyWith(fontWeight: FontWeight.w700)),
                        Text(
                          subtitle.isEmpty ? '—' : subtitle,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ],
                    ),
                  ),
                  const Icon(Icons.chevron_right),
                ],
              ),
              const SizedBox(height: 12),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  if (brand != null) _Pill(label: 'Marque $brand'),
                  if (model != null) _Pill(label: 'Modèle $model'),
                  if (serial != null) _Pill(label: 'Serie #$serial'),
                  if (type != null && type.isNotEmpty) _Pill(label: type),
                  if (year != null && year.isNotEmpty) _Pill(label: 'Année $year'),
                ],
              ),
              if (footer != null) ...[
                const SizedBox(height: 12),
                footer!,
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _EquipmentDetailPage extends StatefulWidget {
  const _EquipmentDetailPage({
    required this.data,
    required this.commands,
    required this.inventory,
    required this.warehouses,
    this.allEquipment = const <Map<String, dynamic>>[],
    this.onEquipmentChanged,
    this.onOtherEquipmentChanged,
    this.onDeleteEquipment,
    this.onUpdated,
    this.companyId,
  });

  final Map<String, dynamic> data;
  final CompanyCommands commands;
  final List<InventoryEntry> inventory;
  final List<Map<String, dynamic>> warehouses;
  final List<Map<String, dynamic>> allEquipment;
  final void Function(Map<String, dynamic> equipment)? onEquipmentChanged;
  final void Function(Map<String, dynamic> equipment)? onOtherEquipmentChanged;
  final void Function(String equipmentId)? onDeleteEquipment;
  final Future<void> Function()? onUpdated;
  final String? companyId;

  @override
  State<_EquipmentDetailPage> createState() => _EquipmentDetailPageState();
}

class _EquipmentDetailPageState extends State<_EquipmentDetailPage>
    with SingleTickerProviderStateMixin {
  late Map<String, dynamic> _equipment;
  late final TabController _tabController;
  late final TextEditingController _inventorySearchCtrl;
  bool _savingTask = false;
  bool _savingOil = false;
  bool _loadingOilEvents = false;
  List<MaintenanceEvent> _oilEvents = const <MaintenanceEvent>[];
  final Map<String, String> _userNameCache = <String, String>{};

  @override
  void initState() {
    super.initState();
    _equipment = Map<String, dynamic>.from(widget.data);
    _tabController = TabController(length: 5, vsync: this)
      ..addListener(_handleTabChanged);
    _inventorySearchCtrl = TextEditingController()
      ..addListener(() => setState(() {}));
    _loadOilEvents();
  }

  @override
  void dispose() {
    _inventorySearchCtrl.dispose();
    _tabController.removeListener(_handleTabChanged);
    _tabController.dispose();
    super.dispose();
  }

  Map<String, dynamic> get _meta => Map<String, dynamic>.from(
        _equipment['meta'] as Map? ?? const <String, dynamic>{},
      );

  List<_MechanicTask> get _mechanicTasks {
    final list = _meta['mechanic_tasks'];
    if (list is List) {
      return list
          .whereType<Map>()
          .map((raw) => _MechanicTask.fromMap(raw))
          .toList(growable: false);
    }
    return const <_MechanicTask>[];
  }

  List<_DieselEntry> get _dieselEntries {
    final list = _meta['diesel_logs'];
    if (list is List) {
      return list
          .whereType<Map>()
          .map((raw) => _DieselEntry.fromMap(raw))
          .toList(growable: false);
    }
    return const <_DieselEntry>[];
  }

  List<_EquipmentInventoryItem> get _inventoryItems {
    final list = _meta['inventory_items'];
    if (list is List) {
      return list
          .whereType<Map>()
          .map((raw) => _EquipmentInventoryItem.fromMap(raw))
          .toList(growable: false);
    }
    return const <_EquipmentInventoryItem>[];
  }

  List<_EquipmentInventoryItem> _inventoryItemsFromMeta(
    Map<String, dynamic> meta,
  ) {
    final list = meta['inventory_items'];
    if (list is List) {
      return list
          .whereType<Map>()
          .map((raw) => _EquipmentInventoryItem.fromMap(raw))
          .toList();
    }
    return <_EquipmentInventoryItem>[];
  }

  bool get _isOnline => ConnectivityService.instance.isOnline;
  List<Map<String, dynamic>> get _warehouses =>
      widget.warehouses.map((w) => Map<String, dynamic>.from(w)).toList();
  Map<String, dynamic> _equipmentById(String id) {
    if (_equipment['id']?.toString() == id) return _equipment;
    return widget.allEquipment.firstWhere(
      (e) => e['id']?.toString() == id,
      orElse: () => const <String, dynamic>{},
    );
  }

  double? get _dieselDailyAverage {
    final entries = _dieselEntries;
    if (entries.isEmpty) return null;
    final totalsByDay = <String, double>{};
    for (final entry in entries) {
      final key = _dayKey(entry.createdAt);
      totalsByDay[key] = (totalsByDay[key] ?? 0) + entry.liters;
    }
    if (totalsByDay.isEmpty) return null;
    final total = totalsByDay.values.fold<double>(
      0,
      (sum, value) => sum + value,
    );
    if (totalsByDay.isEmpty || total <= 0) return null;
    final avg = total / totalsByDay.length;
    if (avg.isNaN || avg.isInfinite) return null;
    return avg;
  }

  List<_ItemSuggestion> _filterCompanyInventory(String query) {
    final matches = <_ItemSuggestion>[];
    final seen = <String>{};
    for (final entry in widget.inventory) {
      final name = entry.item['name']?.toString();
      if (name == null || name.isEmpty) continue;
      final normalized = name.toLowerCase();
      final sku = entry.item['sku']?.toString();
      final normalizedSku = sku?.toLowerCase();
      if (!normalized.contains(query) &&
          (normalizedSku == null || !normalizedSku.contains(query))) {
        continue;
      }
      if (seen.add(normalized)) {
        matches.add(_ItemSuggestion(name: name, sku: sku));
      }
      if (matches.length >= 8) break;
    }
    return matches;
  }

  String? _matchInventoryItemId(String name, {String? sku}) {
    final normalized = name.trim().toLowerCase();
    final normalizedSku = sku?.trim().toLowerCase();
    for (final entry in widget.inventory) {
      final entryName = entry.item['name']?.toString();
      final entrySku = entry.item['sku']?.toString();
      final nameMatch =
          entryName != null && entryName.trim().toLowerCase() == normalized;
      final skuMatch = normalizedSku != null &&
          normalizedSku.isNotEmpty &&
          entrySku != null &&
          entrySku.trim().toLowerCase() == normalizedSku;
      if (nameMatch || skuMatch) {
        final id = entry.item['id']?.toString();
        if (id != null && id.isNotEmpty) return id;
      }
    }
    return null;
  }

  Map<String, dynamic>? _warehouseById(String id) {
    return _warehouses.firstWhere(
      (warehouse) => warehouse['id']?.toString() == id,
      orElse: () => const <String, dynamic>{},
    );
  }

  List<_SectionOption> _sectionOptionsForWarehouse(String warehouseId) {
    final warehouse = _warehouseById(warehouseId);
    final sections = (warehouse?['sections'] as List?)
            ?.whereType<Map>()
            .map((raw) => Map<String, dynamic>.from(raw))
            .toList() ??
        const <Map<String, dynamic>>[];
    final options = sections
        .map(
          (section) => _SectionOption(
            id: section['id']?.toString() ?? '',
            label: section['name']?.toString() ?? 'Section',
          ),
        )
        .where((option) => option.id.isNotEmpty)
        .toList(growable: true);
    if (!options.any(
      (option) => option.id == InventoryEntry.unassignedSectionKey,
    )) {
      options.add(
        const _SectionOption(
          id: InventoryEntry.unassignedSectionKey,
          label: 'Sans section',
        ),
      );
    }
    return options;
  }

  String get _equipmentName => _equipment['name']?.toString() ?? 'Équipement';
  String get _equipmentId => _equipment['id']?.toString() ?? '';
  String? get _companyId =>
      _equipment['company_id']?.toString() ?? widget.companyId;
  String _journalEntityId(String category) {
    if (_equipmentId.isEmpty) return '';
    if (category.isEmpty || category == 'general') return _equipmentId;
    return '$_equipmentId::$category';
  }

  void _openJournalForCurrentTab() {
    final index = _tabController.index;
    final category = _journalCategoryForIndex(index);
    final label = _tabLabelForIndex(index);
    _openJournalSheet(
      category: category,
      title: '$_equipmentName — $label',
    );
  }

  String _journalCategoryForIndex(int index) {
    switch (index) {
      case 0:
        return 'mechanic';
      case 1:
        return 'diesel';
      case 2:
        return 'inventory';
      case 3:
        return 'docs';
      default:
        return 'general';
    }
  }

  void _handleTabChanged() {
    if (!_tabController.indexIsChanging) {
      setState(() {});
    }
  }

  Future<void> _loadOilEvents() async {
    final id = _equipment['id']?.toString();
    if (id == null || id.isEmpty) return;
    setState(() => _loadingOilEvents = true);
    try {
      final events = await maintenanceService.fetchOilChanges(id);
      if (mounted) setState(() => _oilEvents = events);
    } finally {
      if (mounted) setState(() => _loadingOilEvents = false);
    }
  }

  String _tabLabelForIndex(int index) {
    switch (index) {
      case 0:
        return 'Mécanique';
      case 1:
        return 'Entretien';
      case 2:
        return 'Diesel';
      case 3:
        return 'Inventaire';
      case 4:
        return 'Documentation';
      default:
        return 'Journal';
    }
  }

  Map<String, double?> _oilStatus() {
    final meta = _meta;
    final last = (meta['last_oil_change_hours'] as num?)?.toDouble() ??
        (_equipment['last_oil_change_hours'] as num?)?.toDouble();
    final interval =
        (meta['oil_change_interval_hours'] as num?)?.toDouble() ??
            (_equipment['oil_change_interval_hours'] as num?)?.toDouble() ??
            250.0;
    final currentHours = (_equipment['hours'] as num?)?.toDouble() ??
        (_equipment['meter'] as num?)?.toDouble() ??
        last ??
        0;
    final nextDue = last != null ? last + interval : null;
    final progress = (last != null && interval > 0)
        ? ((currentHours - last) / interval).clamp(0.0, 2.0)
        : null;
    return {
      'last': last,
      'interval': interval,
      'current': currentHours,
      'next': nextDue,
      'progress': progress,
    };
  }

  double _currentHours() {
    return (_equipment['hours'] as num?)?.toDouble() ??
        (_equipment['meter'] as num?)?.toDouble() ??
        0;
  }

  List<_CustomMaintenance> get _customMaintenance {
    final meta = _meta;
    final raw = meta['custom_maintenance'];
    if (raw is List) {
      return raw
          .whereType<Map>()
          .map((e) => _CustomMaintenance.fromMap(e))
          .toList();
    }
    return const <_CustomMaintenance>[];
  }

  @override
  Widget build(BuildContext context) {
    final name = _equipmentName;
    return Scaffold(
      appBar: AppBar(
        title: Text(name),
        actions: [
          IconButton(
            icon: const Icon(Icons.edit_outlined),
            tooltip: 'Modifier',
            onPressed: _promptEditEquipment,
          ),
          IconButton(
            icon: const Icon(Icons.history),
            tooltip: 'Journal de la section',
            onPressed: _openJournalForCurrentTab,
          ),
        ],
        bottom: TabBar(
          controller: _tabController,
          isScrollable: true,
          tabs: const [
            Tab(icon: Icon(Icons.build_circle), text: 'Mécanique'),
            Tab(icon: Icon(Icons.handyman), text: 'Entretien'),
            Tab(icon: Icon(Icons.local_gas_station), text: 'Diesel'),
            Tab(icon: Icon(Icons.inventory_2), text: 'Inventaire'),
            Tab(icon: Icon(Icons.description), text: 'Docs'),
          ],
        ),
      ),
      body: TabBarView(
        controller: _tabController,
        children: [
          _tabWrap(_buildMechanicSection(context)),
          _tabWrap(_buildMaintenanceSection(context)),
          _tabWrap(_buildDieselSection(context)),
          _tabWrap(_buildInventorySection(context)),
          _tabWrap(_buildDocsSection(context)),
        ],
      ),
      floatingActionButton: _buildSectionFab(),
      floatingActionButtonLocation: FloatingActionButtonLocation.endFloat,
    );
  }

  Widget _buildMechanicSection(BuildContext context) {
    final meta = _meta;
    final lastService = meta['last_service']?.toString() ?? 'Non renseigné';
    final notes = meta['mechanic_notes']?.toString() ?? '';
    final tasks = _mechanicTasks;
    final standardTasks =
        tasks.where((task) => !task.isRecheck).toList(growable: false);
    final recheckTasks =
        tasks.where((task) => task.isRecheck).toList(growable: false);

    Widget buildTaskList(List<_MechanicTask> list) {
      if (_savingTask) {
        return const LinearProgressIndicator(minHeight: 2);
      }
      if (list.isEmpty) {
        return const Text('Aucune tâche enregistrée.');
      }
      return Column(
        children: list.map(
          (task) {
            final subtitleParts = <String>[
              'À faire sous ${task.delayDays} jour(s)',
              'Échéance ${_formatDate(task.dueDate.toIso8601String()) ?? '—'}',
            ];
            if (task.repeatEveryDays != null) {
              subtitleParts.insert(
                1,
                'Rappel tous les ${task.repeatEveryDays} jour(s)',
              );
            }
            return Card(
              child: ListTile(
                leading: CircleAvatar(
                  backgroundColor: _priorityColor(task.priority),
                  child: Text(task.priority.substring(0, 1).toUpperCase()),
                ),
                title: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(task.title),
                    if (task.isRecheck)
                      Text(
                        'Re-vérification programmée',
                        style: Theme.of(context)
                            .textTheme
                            .bodySmall
                            ?.copyWith(color: Colors.black54),
                      ),
                  ],
                ),
                subtitle: Text(subtitleParts.join(' • ')),
                trailing: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    IconButton(
                      tooltip: 'Marquer comme fait',
                      icon: const Icon(Icons.check_circle_outline),
                      onPressed: _savingTask
                          ? null
                          : () => _completeMechanicTask(task),
                    ),
                    IconButton(
                      tooltip: 'Supprimer',
                      icon: const Icon(Icons.delete_outline),
                      onPressed:
                          _savingTask ? null : () => _confirmRemoveTask(task),
                    ),
                  ],
                ),
              ),
            );
          },
        ).toList(growable: false),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Dernier entretien : $lastService'),
        const SizedBox(height: 8),
        Text(notes.isEmpty ? 'Aucune note mécanique.' : notes),
        const SizedBox(height: 16),
        Text(
          'Tâches à faire',
          style: Theme.of(context)
              .textTheme
              .titleSmall
              ?.copyWith(fontWeight: FontWeight.w600),
        ),
        buildTaskList(standardTasks),
        if (recheckTasks.isNotEmpty) ...[
          const SizedBox(height: 24),
          Text(
            'À re-vérifier',
            style: Theme.of(context)
                .textTheme
                .titleSmall
                ?.copyWith(fontWeight: FontWeight.w600),
          ),
          buildTaskList(recheckTasks),
        ],
      ],
    );
  }

  Widget _buildMaintenanceSection(BuildContext context) {
    final items = _customMaintenance;
    final current = _currentHours();

    Widget cardFor(_CustomMaintenance item) {
      final progress = item.progress(current);
      Color barColor;
      if (progress >= 1) {
        barColor = Colors.red.shade700;
      } else if (progress >= 0.85) {
        barColor = Colors.orange.shade700;
      } else {
        barColor = Colors.green.shade600;
      }
      final percent = (progress * 100).clamp(0, 200).toStringAsFixed(0);
      final nextDue =
          item.lastHours != null ? item.lastHours! + item.intervalHours : null;

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
                    child: Text(
                      item.name,
                      style: Theme.of(context)
                          .textTheme
                          .titleMedium
                          ?.copyWith(fontWeight: FontWeight.w700),
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.edit_outlined),
                    tooltip: 'Modifier',
                    onPressed: _savingTask ? null : () => _editCustomMaintenance(item),
                  ),
                ],
              ),
              const SizedBox(height: 4),
              Row(
                children: [
                  Expanded(
                    child: _StatTile(
                      label: 'Dernière',
                      value: item.lastHours != null
                          ? '${item.lastHours!.toStringAsFixed(1)} h'
                          : '—',
                    ),
                  ),
                  Expanded(
                    child: _StatTile(
                      label: 'Intervalle',
                      value: '${item.intervalHours.toStringAsFixed(0)} h',
                    ),
                  ),
                  Expanded(
                    child: _StatTile(
                      label: 'Prochaine',
                      value:
                          nextDue != null ? '${nextDue.toStringAsFixed(1)} h' : '—',
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              LinearProgressIndicator(
                value: progress > 1 ? 1 : progress,
                minHeight: 10,
                backgroundColor: Colors.grey.shade200,
                valueColor: AlwaysStoppedAnimation<Color>(barColor),
              ),
              const SizedBox(height: 6),
              Text('Avancement $percent%'),
              const SizedBox(height: 10),
              Row(
                children: [
                  ElevatedButton.icon(
                    onPressed:
                        _savingTask ? null : () => _markCustomDone(item),
                    icon: const Icon(Icons.check_circle_outline),
                    label: const Text('Marquer effectué'),
                  ),
                  const SizedBox(width: 12),
                  TextButton.icon(
                    onPressed: _savingTask
                        ? null
                        : () => _deleteCustomMaintenance(item),
                    icon: const Icon(Icons.delete_outline),
                    label: const Text('Supprimer'),
                  ),
                ],
              ),
            ],
          ),
        ),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (items.isEmpty)
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Entretien',
                    style: Theme.of(context)
                        .textTheme
                        .titleMedium
                        ?.copyWith(fontWeight: FontWeight.w700),
                  ),
                  const SizedBox(height: 8),
                  const Text('Aucun suivi pour le moment.'),
                  const SizedBox(height: 12),
                  FilledButton.icon(
                    onPressed: _addCustomMaintenance,
                    icon: const Icon(Icons.add),
                    label: const Text('Ajouter un suivi'),
                  ),
                ],
              ),
            ),
          )
        else ...[
          ...items.map(cardFor),
          const SizedBox(height: 12),
          Align(
            alignment: Alignment.centerLeft,
            child: FilledButton.icon(
              onPressed: _addCustomMaintenance,
              icon: const Icon(Icons.add),
              label: const Text('Ajouter un suivi'),
            ),
          ),
        ],
      ],
    );
  }

  Widget _buildOilChangeSection() {
    final oil = _oilStatus();
    final last = oil['last'];
    final interval = oil['interval'] ?? 250.0;
    final nextDue = oil['next'];
    final progress = oil['progress'] ?? 0.0;
    Color barColor;
    if (progress >= 1.0) {
      barColor = Colors.red.shade700;
    } else if (progress >= 0.7) {
      barColor = Colors.orange.shade700;
    } else {
      barColor = Colors.green.shade600;
    }

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Vidange moteur',
              style: Theme.of(context)
                  .textTheme
                  .titleMedium
                  ?.copyWith(fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(
                  child: _StatTile(
                    label: 'Dernière',
                    value: last != null ? '${last.toStringAsFixed(1)} h' : '—',
                  ),
                ),
                Expanded(
                  child: _StatTile(
                    label: 'Intervalle',
                    value: '${interval.toStringAsFixed(0)} h',
                  ),
                ),
                Expanded(
                  child: _StatTile(
                    label: 'Prochaine',
                    value: nextDue != null
                        ? '${nextDue.toStringAsFixed(1)} h'
                        : '—',
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            LinearProgressIndicator(
              value: progress > 1 ? 1 : progress,
              minHeight: 10,
              backgroundColor: Colors.grey.shade200,
              valueColor: AlwaysStoppedAnimation<Color>(barColor),
            ),
            const SizedBox(height: 8),
            Text(
              'Avancement ${(progress * 100).clamp(0, 200).toStringAsFixed(0)}%',
              style: Theme.of(context).textTheme.bodySmall,
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                ElevatedButton.icon(
                  onPressed: _savingOil ? null : _promptOilChange,
                  icon: const Icon(Icons.water_drop_outlined),
                  label: const Text('Marquer vidange effectuée'),
                ),
                const SizedBox(width: 12),
                if (_savingOil || _loadingOilEvents)
                  const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
              ],
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Container(
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  padding:
                      const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                  child: Text(
                    'Intervalle ${interval.toStringAsFixed(0)} h',
                    style: Theme.of(context)
                        .textTheme
                        .titleMedium
                        ?.copyWith(fontWeight: FontWeight.w700),
                  ),
                ),
                const Spacer(),
                Container(
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(24),
                  ),
                  child: PopupMenuButton<double>(
                    tooltip: 'Changer l’intervalle',
                    color: Colors.white,
                    itemBuilder: (context) => [
                      PopupMenuItem<double>(
                        value: 250,
                        child: const Text('Intervalle 250 h'),
                      ),
                      PopupMenuItem<double>(
                        value: 500,
                        child: const Text('Intervalle 500 h'),
                      ),
                      const PopupMenuDivider(),
                      PopupMenuItem<double>(
                        value: -1,
                        child: const Text('Intervalle personnalisé…'),
                      ),
                    ],
                    onSelected: (value) async {
                      if (value == -1) {
                        final custom =
                            await _promptCustomOilInterval(interval);
                        if (custom != null && custom > 0) {
                          _updateOilInterval(custom);
                        }
                      } else if (value > 0) {
                        _updateOilInterval(value);
                      }
                    },
                    child: const Padding(
                      padding:
                          EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                      child: Icon(Icons.more_vert),
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _promptOilChange() async {
    final formKey = GlobalKey<FormState>();
    final hoursCtrl = TextEditingController(
      text: ((_equipment['hours'] as num?) ??
              (_equipment['meter'] as num?) ??
              (_equipment['last_oil_change_hours'] as num?) ??
              0)
          .toString(),
    );
    final notesCtrl = TextEditingController();

    await showModalBottomSheet<void>(
      context: context,
      backgroundColor: Colors.white,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (context) {
        return Padding(
          padding: EdgeInsets.only(
            bottom: MediaQuery.of(context).viewInsets.bottom + 16,
            left: 16,
            right: 16,
            top: 12,
          ),
          child: Form(
            key: formKey,
            child: Wrap(
              runSpacing: 12,
              children: [
                Text(
                  'Nouvelle vidange',
                  style: Theme.of(context)
                      .textTheme
                      .titleMedium
                      ?.copyWith(fontWeight: FontWeight.w700),
                ),
                TextFormField(
                  controller: hoursCtrl,
                  keyboardType:
                      const TextInputType.numberWithOptions(decimal: true),
                  decoration:
                      const InputDecoration(labelText: 'Heures actuelles'),
                  validator: (value) {
                    final parsed = double.tryParse(value ?? '');
                    if (parsed == null || parsed < 0) {
                      return 'Heures invalides';
                    }
                    return null;
                  },
                ),
                TextFormField(
                  controller: notesCtrl,
                  decoration:
                      const InputDecoration(labelText: 'Notes (optionnel)'),
                  maxLines: 2,
                ),
                Align(
                  alignment: Alignment.centerRight,
                  child: FilledButton(
                    onPressed: () async {
                      if (!formKey.currentState!.validate()) return;
                      final hours = double.parse(hoursCtrl.text.trim());
                      final notes = notesCtrl.text.trim();
                      Navigator.of(context).pop();
                      await _recordOilChange(hours, notes.isEmpty ? null : notes);
                    },
                    child: const Text('Enregistrer'),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );

  }

  Future<void> _recordOilChange(double hours, String? notes) async {
    final id = _equipment['id']?.toString();
    if (id == null) return;
    setState(() => _savingOil = true);
    final meta = Map<String, dynamic>.from(
        _equipment['meta'] as Map? ?? const <String, dynamic>{});
    meta['last_oil_change_hours'] = hours;
    try {
      await maintenanceService.recordOilChange(
        equipmentId: id,
        hours: hours,
        notes: notes,
      );
      if (mounted) {
        setState(() {
          _equipment = {
            ..._equipment,
            'last_oil_change_hours': hours,
            'meta': meta,
          };
        });
      }
      await _loadOilEvents();
      _showSnack('Vidange enregistrée.');
      await widget.onUpdated?.call();
    } catch (error) {
      _showSnack(
        _describeError(error) ?? 'Impossible d’enregistrer la vidange.',
        error: true,
      );
    } finally {
      if (mounted) setState(() => _savingOil = false);
    }
  }

  Future<void> _updateOilInterval(double interval) async {
    final nextMeta = Map<String, dynamic>.from(_meta);
    nextMeta['oil_change_interval_hours'] = interval;
    await _submitEquipmentMeta(
      nextMeta,
      successMessage: 'Intervalle de vidange mis à jour.',
      errorMessage: 'Impossible de mettre à jour la vidange.',
    );
  }

  Future<double?> _promptCustomOilInterval(double current) async {
    final formKey = GlobalKey<FormState>();
    final ctrl = TextEditingController(text: current.toStringAsFixed(0));
    double? result;
    await showModalBottomSheet<void>(
      context: context,
      backgroundColor: Colors.white,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (context) {
        return Padding(
          padding: EdgeInsets.only(
            bottom: MediaQuery.of(context).viewInsets.bottom + 16,
            left: 16,
            right: 16,
            top: 12,
          ),
          child: Form(
            key: formKey,
            child: Wrap(
              runSpacing: 12,
              children: [
                Text(
                  'Intervalle personnalisé',
                  style: Theme.of(context)
                      .textTheme
                      .titleMedium
                      ?.copyWith(fontWeight: FontWeight.w700),
                ),
                TextFormField(
                  controller: ctrl,
                  keyboardType:
                      const TextInputType.numberWithOptions(decimal: true),
                  decoration: const InputDecoration(
                    labelText: 'Intervalle (heures)',
                  ),
                  validator: (value) {
                    final parsed = double.tryParse(value ?? '');
                    if (parsed == null || parsed <= 0) {
                      return 'Intervalle invalide';
                    }
                    return null;
                  },
                ),
                Align(
                  alignment: Alignment.centerRight,
                  child: FilledButton(
                    onPressed: () {
                      if (!formKey.currentState!.validate()) return;
                      result = double.parse(ctrl.text.trim());
                      Navigator.of(context).pop();
                    },
                    child: const Text('Enregistrer'),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
    return result;
  }

  Widget _buildOilDueReminder() {
    final oil = _oilStatus();
    final progress = oil['progress'];
    if (progress == null || progress < 0.85) return const SizedBox.shrink();

    return Card(
      color: Colors.orange.shade50,
      child: ListTile(
        leading: const Icon(Icons.warning_amber_rounded, color: Colors.orange),
        title: const Text('Vidange moteur à planifier'),
        subtitle: Text(
          progress >= 1
              ? 'Vidange dépassée, fais-la dès que possible.'
              : 'Prévois la vidange avant d’atteindre la limite.',
        ),
        trailing: FilledButton(
          onPressed: _savingOil ? null : _promptOilChange,
          child: const Text('Marquer'),
        ),
      ),
    );
  }

  Future<void> _addCustomMaintenance() async {
    await _editCustomMaintenance(null);
  }

  Future<void> _editCustomMaintenance(_CustomMaintenance? item) async {
    final formKey = GlobalKey<FormState>();
    final nameCtrl = TextEditingController(text: item?.name ?? '');
    final intervalCtrl = TextEditingController(
        text: item?.intervalHours.toString() ?? '250');
    final lastCtrl = TextEditingController(
        text: item?.lastHours?.toString() ??
            (_currentHours() > 0 ? _currentHours().toString() : ''));
    const suggestions = <String>[
      'Changement huile moteur',
      'Changement huile hydraulique',
      'Filtre à air',
      'Filtre carburant',
      'Graissage',
      'Nettoyage radiateur',
    ];

    await showModalBottomSheet<void>(
      context: context,
      backgroundColor: Colors.white,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (context) {
        return Padding(
          padding: EdgeInsets.only(
            bottom: MediaQuery.of(context).viewInsets.bottom + 16,
            left: 16,
            right: 16,
            top: 12,
          ),
          child: Form(
            key: formKey,
            child: Wrap(
              runSpacing: 12,
              children: [
                Text(
                  item == null ? 'Nouveau suivi' : 'Modifier le suivi',
                  style: Theme.of(context)
                      .textTheme
                      .titleMedium
                      ?.copyWith(fontWeight: FontWeight.w700),
                ),
                Autocomplete<String>(
                  optionsBuilder: (text) {
                    final query = text.text.toLowerCase().trim();
                    if (query.isEmpty) return const Iterable<String>.empty();
                    return suggestions.where(
                      (s) => s.toLowerCase().contains(query),
                    );
                  },
                  fieldViewBuilder:
                      (context, controller, focusNode, onFieldSubmitted) {
                    controller.text = nameCtrl.text;
                    controller.selection = TextSelection.fromPosition(
                        TextPosition(offset: controller.text.length));
                    controller.addListener(() {
                      nameCtrl.text = controller.text;
                    });
                    return TextFormField(
                      controller: controller,
                      focusNode: focusNode,
                      decoration:
                          const InputDecoration(labelText: 'Nom du suivi'),
                      validator: (value) => value == null || value.trim().isEmpty
                          ? 'Nom requis'
                          : null,
                    );
                  },
                  onSelected: (value) => nameCtrl.text = value,
                ),
                TextFormField(
                  controller: intervalCtrl,
                  keyboardType:
                      const TextInputType.numberWithOptions(decimal: true),
                  decoration:
                      const InputDecoration(labelText: 'Intervalle (heures)'),
                  validator: (value) {
                    final parsed = double.tryParse(value ?? '');
                    if (parsed == null || parsed <= 0) {
                      return 'Intervalle invalide';
                    }
                    return null;
                  },
                ),
                TextFormField(
                  controller: lastCtrl,
                  keyboardType:
                      const TextInputType.numberWithOptions(decimal: true),
                  decoration: const InputDecoration(
                      labelText: 'Dernières heures (optionnel)'),
                  validator: (value) {
                    if (value == null || value.trim().isEmpty) return null;
                    final parsed = double.tryParse(value);
                    if (parsed == null || parsed < 0) {
                      return 'Valeur invalide';
                    }
                    return null;
                  },
                ),
                Align(
                  alignment: Alignment.centerRight,
                  child: FilledButton(
                    onPressed: () async {
                      if (!formKey.currentState!.validate()) return;
                      final interval =
                          double.parse(intervalCtrl.text.trim());
                      final last = double.tryParse(lastCtrl.text.trim());
                      final updated = List<_CustomMaintenance>.from(
                          _customMaintenance);
                      if (item == null) {
                        updated.add(
                          _CustomMaintenance(
                            id: DateTime.now()
                                .microsecondsSinceEpoch
                                .toString(),
                            name: nameCtrl.text.trim(),
                            intervalHours: interval,
                            lastHours: last,
                          ),
                        );
                      } else {
                        final idx =
                            updated.indexWhere((entry) => entry.id == item.id);
                        if (idx >= 0) {
                          updated[idx] = item.copyWith(
                            name: nameCtrl.text.trim(),
                            intervalHours: interval,
                            lastHours: last,
                          );
                        }
                      }
                      Navigator.of(context).pop();
                      await _saveCustomMaintenance(updated);
                    },
                    child: const Text('Enregistrer'),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Future<void> _markCustomDone(_CustomMaintenance item) async {
    final formKey = GlobalKey<FormState>();
    final hoursCtrl = TextEditingController(text: _currentHours().toString());
    await showModalBottomSheet<void>(
      context: context,
      backgroundColor: Colors.white,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (context) {
        return Padding(
          padding: EdgeInsets.only(
            bottom: MediaQuery.of(context).viewInsets.bottom + 16,
            left: 16,
            right: 16,
            top: 12,
          ),
          child: Form(
            key: formKey,
            child: Wrap(
              runSpacing: 12,
              children: [
                Text(
                  'Marquer "${item.name}"',
                  style: Theme.of(context)
                      .textTheme
                      .titleMedium
                      ?.copyWith(fontWeight: FontWeight.w700),
                ),
                TextFormField(
                  controller: hoursCtrl,
                  keyboardType:
                      const TextInputType.numberWithOptions(decimal: true),
                  decoration:
                      const InputDecoration(labelText: 'Heures actuelles'),
                  validator: (value) {
                    final parsed = double.tryParse(value ?? '');
                    if (parsed == null || parsed < 0) {
                      return 'Heures invalides';
                    }
                    return null;
                  },
                ),
                Align(
                  alignment: Alignment.centerRight,
                  child: FilledButton(
                    onPressed: () async {
                      if (!formKey.currentState!.validate()) return;
                      final hours = double.parse(hoursCtrl.text.trim());
                      Navigator.of(context).pop();
                      final updated = List<_CustomMaintenance>.from(
                          _customMaintenance);
                      final idx =
                          updated.indexWhere((entry) => entry.id == item.id);
                      if (idx >= 0) {
                        updated[idx] = item.copyWith(lastHours: hours);
                        await _saveCustomMaintenance(updated);
                      }
                    },
                    child: const Text('Enregistrer'),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Future<void> _deleteCustomMaintenance(_CustomMaintenance item) async {
    final updated = _customMaintenance
        .where((entry) => entry.id != item.id)
        .toList(growable: false);
    await _saveCustomMaintenance(updated);
  }

  Future<void> _saveCustomMaintenance(
      List<_CustomMaintenance> items) async {
    final nextMeta = Map<String, dynamic>.from(_meta);
    nextMeta['custom_maintenance'] =
        items.map((e) => e.toMap()).toList(growable: false);
    await _submitEquipmentMeta(
      nextMeta,
      successMessage: 'Suivis mis à jour.',
      errorMessage: 'Impossible de mettre à jour les suivis.',
    );
  }


  Widget _buildDieselSection(BuildContext context) {
    final meta = _meta;
    final avgDaily = _dieselDailyAverage;
    final tankValue = (meta['diesel_tank'] as num?)?.toDouble();
    String formatValue(double? value, {String suffix = ''}) {
      if (value == null) return '—';
      final decimals = value % 1 == 0 ? 0 : 1;
      final base = value.toStringAsFixed(decimals);
      return suffix.isEmpty ? base : '$base $suffix';
    }

    final avgText = formatValue(avgDaily, suffix: 'L/j');
    final tankText = formatValue(tankValue, suffix: 'L');
    final entries = _dieselEntries;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Consommation moyenne : $avgText'),
                  Text('Capacité réservoir : $tankText'),
                ],
              ),
            ),
            IconButton(
              tooltip: 'Modifier la capacité du réservoir',
              icon: const Icon(Icons.edit_outlined),
              onPressed: _savingTask ? null : _editDieselTank,
            ),
          ],
        ),
        const SizedBox(height: 16),
        Text(
          'Journal diesel',
          style: Theme.of(context)
              .textTheme
              .titleSmall
              ?.copyWith(fontWeight: FontWeight.w600),
        ),
        if (_savingTask)
          const LinearProgressIndicator(minHeight: 2)
        else if (entries.isEmpty)
          const Text('Aucune entrée enregistré pour le moment.')
        else
          Column(
            children: entries
                .map(
                  (entry) => ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: const Icon(Icons.local_gas_station),
                    title: Text('${entry.liters.toStringAsFixed(1)} L'),
                    subtitle: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                            'Ajouté le ${_formatDate(entry.createdAt.toIso8601String()) ?? ''}'),
                        if (entry.note != null && entry.note!.isNotEmpty)
                          Text(entry.note!),
                      ],
                    ),
                    trailing: IconButton(
                      icon: const Icon(Icons.delete_outline),
                      onPressed: _savingTask
                          ? null
                          : () => _confirmRemoveDieselEntry(entry),
                    ),
                  ),
                )
                .toList(growable: false),
          ),
      ],
    );
  }

  Widget _buildInventorySection(BuildContext context) {
    final items = _inventoryItems;
    final query = _inventorySearchCtrl.text.trim().toLowerCase();
    final filteredItems = query.isEmpty
        ? items
        : items
            .where(
              (item) =>
                  item.name.toLowerCase().contains(query) ||
                  (item.sku?.toLowerCase().contains(query) ?? false) ||
                  (item.note?.toLowerCase().contains(query) ?? false),
            )
            .toList();
    final totalQty =
        filteredItems.fold<double>(0, (value, item) => value + (item.qty ?? 0));
    if (items.isEmpty) {
      return const Card(
        child: Padding(
          padding: EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Aucune pièce liée.',
                style: TextStyle(fontWeight: FontWeight.w600),
              ),
              SizedBox(height: 8),
              Text(
                'Utilise le bouton + pour associer les pièces et consommables nécessaires à cet équipement.',
              ),
            ],
          ),
        ),
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '${filteredItems.length} article(s)',
                    style: Theme.of(context)
                        .textTheme
                        .titleMedium
                        ?.copyWith(fontWeight: FontWeight.w700),
                  ),
                  Text(
                    '${totalQty.toStringAsFixed(totalQty % 1 == 0 ? 0 : 1)} pièce(s)',
                  ),
                ],
              ),
            ),
            if (_savingTask) const SizedBox(width: 8),
            if (_savingTask)
              const SizedBox(
                width: 24,
                height: 24,
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
          ],
        ),
        const SizedBox(height: 16),
        TextField(
          controller: _inventorySearchCtrl,
          decoration: InputDecoration(
            hintText: 'Rechercher une pièce liée',
            prefixIcon: const Icon(Icons.search),
            suffixIcon: _inventorySearchCtrl.text.isEmpty
                ? null
                : IconButton(
                    icon: const Icon(Icons.clear),
                    onPressed: () => _inventorySearchCtrl.clear(),
                  ),
            border: const OutlineInputBorder(),
          ),
        ),
        const SizedBox(height: 16),
        Card(
          child: Column(
            children: [
              if (filteredItems.isEmpty)
                const Padding(
                  padding: EdgeInsets.all(16),
                  child: Text('Aucun résultat pour cette recherche.'),
                )
              else
                for (var i = 0; i < filteredItems.length; i++) ...[
                  _EquipmentInventoryItemRow(
                    item: filteredItems[i],
                    busy: _savingTask,
                    onIncrement: () => _adjustInventoryItemQty(filteredItems[i],
                        increase: true),
                    onDecrement: () => _adjustInventoryItemQty(filteredItems[i],
                        increase: false),
                    onEdit: () => _editInventoryItem(item: filteredItems[i]),
                    onDelete: () =>
                        _confirmRemoveInventoryItem(filteredItems[i]),
                    onMove: () => _promptMoveInventoryItem(filteredItems[i]),
                  ),
                  if (i != filteredItems.length - 1) const Divider(height: 1),
                ],
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildDocsSection(BuildContext context) {
    final docs = (_equipment['documents'] as List?)
            ?.whereType<Map>()
            .map((doc) => Map<String, dynamic>.from(doc))
            .toList() ??
        const <Map<String, dynamic>>[];
    if (docs.isEmpty) {
      return const Text('Aucun document joint pour l’instant.');
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: docs
          .map(
            (doc) => ListTile(
              contentPadding: EdgeInsets.zero,
              leading: const Icon(Icons.picture_as_pdf),
              title: Text(doc['title']?.toString() ?? 'Document'),
              subtitle: Text(doc['updated_at']?.toString() ?? ''),
              onTap: () {
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(content: Text('Ouvrir ${doc['title']} à venir.')),
                );
              },
            ),
          )
          .toList(growable: false),
    );
  }

  Future<void> _openJournalSheet({
    required String category,
    required String title,
  }) async {
    final companyId = _companyId;
    final entityId = _journalEntityId(category);
    if (companyId == null || _equipmentId.isEmpty || entityId.isEmpty) {
      _showSnack('Journal indisponible pour cet équipement.', error: true);
      return;
    }

    Future<List<Map<String, dynamic>>> loadEntries() {
      return widget.commands.fetchJournalEntries(
        companyId: companyId,
        scope: 'equipment',
        entityId: entityId,
      );
    }

    String? sheetError;
    List<Map<String, dynamic>> entries = const <Map<String, dynamic>>[];
    try {
      entries = await loadEntries();
      await loadJournalAuthors(
        widget.commands.client,
        _userNameCache,
        entries,
      );
    } catch (error) {
      sheetError = friendlyJournalLoadError(error);
    }
    if (!mounted) return;

    final noteCtrl = TextEditingController();
    try {
      await showModalBottomSheet<void>(
        context: context,
        isScrollControlled: true,
        builder: (context) {
          bool submitting = false;
          return StatefulBuilder(
            builder: (context, setSheetState) {
              Future<void> refresh() async {
                try {
                  final latest = await loadEntries();
                  await loadJournalAuthors(
                    widget.commands.client,
                    _userNameCache,
                    latest,
                  );
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
                await _recordJournalEvent(
                  'note',
                  category: category,
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
                  crossAxisAlignment: CrossAxisAlignment.start,
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
                                    final created =
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
                                          if (created != null)
                                            Text(
                                              _formatDate(created) ?? created,
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
    } finally {
      noteCtrl.dispose();
    }
  }

  Future<void> _promptEditEquipment() async {
    if (_equipmentId.isEmpty) {
      _showSnack('Équipement inconnu.', error: true);
      return;
    }

    final formKey = GlobalKey<FormState>();
    final nameCtrl =
        TextEditingController(text: _equipment['name']?.toString() ?? '');
    final brandCtrl =
        TextEditingController(text: _equipment['brand']?.toString() ?? '');
    final modelCtrl =
        TextEditingController(text: _equipment['model']?.toString() ?? '');
    final serialCtrl =
        TextEditingController(text: _equipment['serial']?.toString() ?? '');
    final yearCtrl = TextEditingController(
      text: () {
        final meta = _equipment['meta'];
        if (meta is Map) {
          final raw = meta['year']?.toString();
          if (raw != null && raw.isNotEmpty) return raw;
        }
        return '';
      }(),
    );
    final equipmentTypes = kEquipmentTypes;
    String selectedType = () {
      final meta = _equipment['meta'];
      if (meta is Map) {
        final type = meta['type']?.toString();
        if (type != null && type.trim().isNotEmpty) return type;
      }
      return equipmentTypes.last;
    }();
    var active = _equipment['active'] != false;
    var submitting = false;
    String? dialogError;

    await showDialog<void>(
      context: context,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            InputDecoration decoration(
                String label, TextEditingController ctrl) {
              return InputDecoration(
                labelText: label,
                suffixIcon: ctrl.text.isEmpty
                    ? null
                    : IconButton(
                        tooltip: 'Effacer',
                        icon: const Icon(Icons.clear),
                        onPressed: () {
                          ctrl.clear();
                          setDialogState(() {});
                        },
                      ),
              );
            }

            Future<void> submit() async {
              if (!formKey.currentState!.validate()) return;
              setDialogState(() {
                submitting = true;
                dialogError = null;
              });

              final result = await widget.commands.updateEquipment(
                equipmentId: _equipmentId,
                name: nameCtrl.text.trim(),
                brand: brandCtrl.text,
                model: modelCtrl.text,
                serial: serialCtrl.text,
                active: active,
                meta: () {
                  final existingMeta = _equipment['meta'] is Map
                      ? Map<String, dynamic>.from(_equipment['meta'] as Map)
                      : <String, dynamic>{};
                  existingMeta['type'] = selectedType;
                  final year = yearCtrl.text.trim();
                  if (year.isNotEmpty) {
                    existingMeta['year'] = year;
                  } else {
                    existingMeta.remove('year');
                  }
                  return existingMeta;
                }(),
              );

              if (!result.ok || result.data == null) {
                setDialogState(() {
                  submitting = false;
                  dialogError =
                      _describeError(result.error) ?? 'Mise à jour impossible.';
                });
                return;
              }

              if (!mounted || !context.mounted) return;
              setState(() => _equipment = result.data!);
              Navigator.of(context).pop();
              _showSnack('Équipement mis à jour.');
              await widget.onUpdated?.call();
            }

            return AlertDialog(
              title: const Text('Modifier l’équipement'),
              content: Form(
                key: formKey,
                child: SingleChildScrollView(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      TextFormField(
                        controller: nameCtrl,
                        decoration: decoration('Nom', nameCtrl),
                        textCapitalization: TextCapitalization.sentences,
                        validator: (value) =>
                            value == null || value.trim().isEmpty
                                ? 'Nom requis'
                                : null,
                        onChanged: (_) => setDialogState(() {}),
                      ),
                      const SizedBox(height: 12),
                      TextFormField(
                        controller: brandCtrl,
                        decoration: decoration('Marque', brandCtrl),
                        onChanged: (_) => setDialogState(() {}),
                      ),
                      const SizedBox(height: 12),
                      TextFormField(
                        controller: modelCtrl,
                        decoration: decoration('Modèle', modelCtrl),
                        onChanged: (_) => setDialogState(() {}),
                      ),
                      const SizedBox(height: 12),
                      TextFormField(
                        controller: yearCtrl,
                        keyboardType: TextInputType.number,
                        decoration: decoration('Année (optionnel)', yearCtrl),
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
                        onChanged: (_) => setDialogState(() {}),
                      ),
                      const SizedBox(height: 12),
                      TextFormField(
                        controller: serialCtrl,
                        decoration: decoration('Numéro de série', serialCtrl),
                        onChanged: (_) => setDialogState(() {}),
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
                        decoration: const InputDecoration(labelText: 'Type'),
                      ),
                      const SizedBox(height: 12),
                      SwitchListTile.adaptive(
                        value: active,
                        onChanged: (value) =>
                            setDialogState(() => active = value),
                        title: const Text('Équipement actif'),
                      ),
                      if (dialogError != null) ...[
                        const SizedBox(height: 12),
                        Text(
                          dialogError!,
                          style: const TextStyle(color: Colors.red),
                        ),
                      ],
                      const Divider(height: 32),
                      Align(
                        alignment: Alignment.centerLeft,
                        child: TextButton.icon(
                          onPressed: submitting
                              ? null
                              : () async {
                                  Navigator.of(context).pop();
                                  await _confirmDeleteEquipment();
                                },
                          icon: const Icon(Icons.delete_outline),
                          label: const Text('Supprimer cet équipement'),
                          style: TextButton.styleFrom(
                            foregroundColor: Colors.red,
                          ),
                        ),
                      ),
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
                      : const Text('Enregistrer'),
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

  Future<void> _confirmDeleteEquipment() async {
    if (_equipmentId.isEmpty) {
      _showSnack('Équipement inconnu.', error: true);
      return;
    }

    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Supprimer cet équipement ?'),
        content: const Text(
          'Cette action est définitive. Les journaux et historiques resteront consultables.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Annuler'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Supprimer'),
          ),
        ],
      ),
    );
    if (confirm != true) return;

    if (!_isOnline) {
      widget.onDeleteEquipment?.call(_equipmentId);
      await OfflineActionsService.instance.enqueue(
        OfflineActionTypes.equipmentDelete,
        {
          'equipment_id': _equipmentId,
          'equipment_name': _equipmentName,
        },
      );
      _showSnack('Suppression enregistrée (hors ligne).');
      if (mounted) {
        Navigator.of(context).pop();
      }
      return;
    }

    final result = await widget.commands.deleteEquipment(
      equipmentId: _equipmentId,
    );

    if (!result.ok) {
      _showSnack(
        _describeError(result.error) ?? 'Impossible de supprimer.',
        error: true,
      );
      return;
    }

    await _recordJournalEvent(
      'equipment_deleted',
      category: 'general',
      note: _equipmentName,
      payload: {'equipment_id': _equipmentId},
    );
    widget.onDeleteEquipment?.call(_equipmentId);
    if (widget.onUpdated != null) {
      await widget.onUpdated!();
    }
    _showSnack('Équipement supprimé.');
    if (mounted) {
      Navigator.of(context).pop();
    }
  }

  Future<void> _addMechanicTask() async {
    final titleCtrl = TextEditingController();
    final delayCtrl = TextEditingController(text: '7');
    String priority = 'moyen';
    final formKey = GlobalKey<FormState>();

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Nouvelle tâche mécanique'),
        content: Form(
          key: formKey,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextFormField(
                controller: titleCtrl,
                decoration:
                    const InputDecoration(labelText: 'Description de la tâche'),
                validator: (value) =>
                    value == null || value.trim().isEmpty ? 'Nom requis' : null,
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: delayCtrl,
                keyboardType: TextInputType.number,
                decoration:
                    const InputDecoration(labelText: 'Délai (en jours)'),
                validator: (value) {
                  final parsed = int.tryParse(value ?? '');
                  if (parsed == null || parsed <= 0) {
                    return 'Entier positif requis';
                  }
                  return null;
                },
              ),
              const SizedBox(height: 12),
              DropdownButtonFormField<String>(
                initialValue: priority,
                decoration: const InputDecoration(labelText: 'Priorité'),
                items: const [
                  DropdownMenuItem(value: 'faible', child: Text('Faible')),
                  DropdownMenuItem(value: 'moyen', child: Text('Moyen')),
                  DropdownMenuItem(value: 'eleve', child: Text('Élevé')),
                ],
                onChanged: (value) {
                  if (value == null) return;
                  priority = value;
                },
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Annuler'),
          ),
          FilledButton(
            onPressed: () {
              if (!formKey.currentState!.validate()) return;
              Navigator.of(context).pop(true);
            },
            child: const Text('Ajouter'),
          ),
        ],
      ),
    );

    if (confirmed != true) return;
    final delay = int.parse(delayCtrl.text.trim());
    final task = _MechanicTask(
      id: DateTime.now().microsecondsSinceEpoch.toString(),
      title: titleCtrl.text.trim(),
      delayDays: delay,
      priority: priority,
      createdAt: DateTime.now(),
      isRecheck: false,
    );
    final tasks = [..._mechanicTasks, task];
    await _saveMechanicTasks(
      tasks,
      successMessage: 'Tâche ajoutée.',
      events: [
        _QueuedEquipmentEvent(
          event: 'mechanic_task_added',
          category: 'mechanic',
          note: task.title,
          payload: {
            'delay_days': delay,
            'priority': priority,
          },
        ),
      ],
    );
  }

  Future<void> _completeMechanicTask(_MechanicTask task) async {
    final noteCtrl = TextEditingController();
    final recheckCtrl = TextEditingController(
      text: (task.repeatEveryDays ?? task.delayDays).toString(),
    );
    bool scheduleRecheck = task.repeatEveryDays != null;
    bool recurringRecheck = task.repeatEveryDays != null;
    final formKey = GlobalKey<FormState>();

    final result = await showDialog<Map<String, dynamic>>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: const Text('Marquer la tâche comme faite'),
          content: Form(
            key: formKey,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    task.title,
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                  const SizedBox(height: 12),
                  TextFormField(
                    controller: noteCtrl,
                    decoration:
                        const InputDecoration(labelText: 'Note (optionnel)'),
                    minLines: 2,
                    maxLines: 4,
                  ),
                  const SizedBox(height: 12),
                  SwitchListTile.adaptive(
                    contentPadding: EdgeInsets.zero,
                    value: scheduleRecheck,
                    title: const Text('Planifier une re-vérification'),
                    subtitle:
                        const Text('Crée une nouvelle tâche avec un délai.'),
                    onChanged: (value) {
                      setDialogState(() {
                        scheduleRecheck = value;
                        if (!scheduleRecheck) {
                          recurringRecheck = false;
                        } else if (recheckCtrl.text.trim().isEmpty) {
                          recheckCtrl.text = task.delayDays.toString();
                        }
                      });
                    },
                  ),
                  if (scheduleRecheck) ...[
                    TextFormField(
                      controller: recheckCtrl,
                      keyboardType: TextInputType.number,
                      decoration:
                          const InputDecoration(labelText: 'Délai (en jours)'),
                      validator: (value) {
                        if (!scheduleRecheck) return null;
                        final parsed = int.tryParse(value ?? '');
                        if (parsed == null || parsed <= 0) {
                          return 'Entier positif requis';
                        }
                        return null;
                      },
                    ),
                    CheckboxListTile(
                      contentPadding: EdgeInsets.zero,
                      controlAffinity: ListTileControlAffinity.leading,
                      value: recurringRecheck,
                      title: const Text('Reprendre tous les X jours'),
                      subtitle: const Text(
                          'Réutilise automatiquement ce délai pour la suite.'),
                      onChanged: (value) => setDialogState(
                        () => recurringRecheck = value ?? false,
                      ),
                    ),
                  ],
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
              onPressed: () {
                if (!formKey.currentState!.validate()) return;
                final note = noteCtrl.text.trim();
                final delay = scheduleRecheck
                    ? int.tryParse(recheckCtrl.text.trim())
                    : null;
                Navigator.of(context).pop({
                  'note': note.isEmpty ? null : note,
                  'recheckDelay': delay,
                  'recurring': scheduleRecheck && recurringRecheck,
                });
              },
              child: const Text('Confirmer'),
            ),
          ],
        ),
      ),
    );

    if (result == null || !mounted) return;

    final note = result['note'] as String?;
    final recheckDelay = result['recheckDelay'] as int?;
    final recurring = result['recurring'] as bool? ?? false;

    final updatedTasks =
        _mechanicTasks.where((t) => t.id != task.id).toList(growable: true);
    if (recheckDelay != null && recheckDelay > 0) {
      updatedTasks.add(
        _MechanicTask(
          id: DateTime.now().microsecondsSinceEpoch.toString(),
          title: task.title,
          delayDays: recheckDelay,
          repeatEveryDays: recurring ? recheckDelay : null,
          priority: task.priority,
          createdAt: DateTime.now(),
          isRecheck: true,
        ),
      );
    }

    final payload = <String, dynamic>{
      'task_id': task.id,
      'priority': task.priority,
      'original_delay_days': task.delayDays,
    };
    if (note != null) {
      payload['note'] = note;
    }
    if (recheckDelay != null) {
      payload['recheck_delay_days'] = recheckDelay;
      payload['recurring_recheck'] = recurring;
    }

    final successMessage = recheckDelay != null
        ? 'Tâche complétée — re-vérification dans $recheckDelay jour${recheckDelay > 1 ? 's' : ''}'
            '${recurring ? ' (répétée)' : ''}.'
        : 'Tâche complétée.';

    await _saveMechanicTasks(
      updatedTasks,
      successMessage: successMessage,
      events: [
        _QueuedEquipmentEvent(
          event: 'mechanic_task_completed',
          category: 'mechanic',
          note: note == null ? task.title : '${task.title} — $note',
          payload: payload,
        ),
      ],
    );
  }

  Future<void> _confirmRemoveTask(_MechanicTask task) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Supprimer cette tâche ?'),
        content: Text('"${task.title}" sera retirée de la liste.'),
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
    if (confirm == true) {
      final tasks = _mechanicTasks.where((t) => t.id != task.id).toList();
      await _saveMechanicTasks(
        tasks,
        successMessage: 'Tâche supprimée.',
        events: [
          _QueuedEquipmentEvent(
            event: 'mechanic_task_removed',
            category: 'mechanic',
            note: task.title,
          ),
        ],
      );
    }
  }

  Future<bool> _saveMechanicTasks(
    List<_MechanicTask> tasks, {
    String? successMessage,
    List<_QueuedEquipmentEvent>? events,
  }) async {
    final nextMeta = Map<String, dynamic>.from(_meta);
    nextMeta['mechanic_tasks'] = tasks.map((task) => task.toMap()).toList();
    return _submitEquipmentMeta(
      nextMeta,
      successMessage: successMessage,
      events: events,
      errorMessage: 'Impossible de mettre à jour les tâches.',
    );
  }

  Future<void> _editDieselTank() async {
    final meta = _meta;
    final tankCtrl = TextEditingController(
      text: meta['diesel_tank']?.toString() ?? '',
    );
    final formKey = GlobalKey<FormState>();

    double? parseNumber(String raw) {
      final trimmed = raw.trim();
      if (trimmed.isEmpty) return null;
      return double.tryParse(trimmed.replaceAll(',', '.'));
    }

    String? validate(String? value) {
      if (value == null || value.trim().isEmpty) return null;
      final parsed = parseNumber(value);
      if (parsed == null || parsed <= 0) {
        return 'Valeur invalide';
      }
      return null;
    }

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Capacité du réservoir'),
        content: Form(
          key: formKey,
          child: TextFormField(
            controller: tankCtrl,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            decoration: const InputDecoration(
              labelText: 'Capacité réservoir (L)',
              helperText: 'Laisser vide pour effacer la valeur.',
            ),
            validator: validate,
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Annuler'),
          ),
          FilledButton(
            onPressed: () {
              if (!formKey.currentState!.validate()) return;
              Navigator.of(context).pop(true);
            },
            child: const Text('Enregistrer'),
          ),
        ],
      ),
    );

    if (confirmed != true) return;
    final nextMeta = Map<String, dynamic>.from(_meta);
    final tankValue = parseNumber(tankCtrl.text);
    nextMeta.remove('diesel_avg');
    if (tankValue == null) {
      nextMeta.remove('diesel_tank');
    } else {
      nextMeta['diesel_tank'] = tankValue;
    }

    await _submitEquipmentMeta(
      nextMeta,
      successMessage: 'Capacité du réservoir mise à jour.',
      errorMessage: 'Impossible de mettre à jour les informations diesel.',
    );
  }

  Future<void> _editInventoryItem({_EquipmentInventoryItem? item}) async {
    final titleCtrl = TextEditingController(text: item?.name ?? '');
    final skuCtrl = TextEditingController(text: item?.sku ?? '');
    final noteCtrl = TextEditingController(text: item?.note ?? '');
    final formKey = GlobalKey<FormState>();
    int qtyValue = (item?.qty?.round() ?? 1).clamp(1, 9999);
    final nameFocusNode = FocusNode();

    Future<void> adjustQty(StateSetter setDialogState, bool increase) async {
      setDialogState(() {
        if (increase) {
          qtyValue += 1;
        } else if (qtyValue > 1) {
          qtyValue -= 1;
        }
      });
    }

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title:
              Text(item == null ? 'Ajouter des pièces' : 'Modifier la pièce'),
          content: Form(
            key: formKey,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  RawAutocomplete<_ItemSuggestion>(
                    textEditingController: titleCtrl,
                    focusNode: nameFocusNode,
                    displayStringForOption: (option) => option.name,
                    optionsBuilder: (textEditingValue) {
                      final query = textEditingValue.text.trim().toLowerCase();
                      if (query.isEmpty) {
                        return const Iterable<_ItemSuggestion>.empty();
                      }
                      return _filterCompanyInventory(query);
                    },
                    fieldViewBuilder: (
                      context,
                      controller,
                      focusNode,
                      onFieldSubmitted,
                    ) {
                      return TextFormField(
                        controller: controller,
                        focusNode: focusNode,
                        decoration: const InputDecoration(
                          labelText: 'Nom de la pièce',
                          helperText:
                              'Sélectionne une pièce existante ou ajoute un nouveau nom.',
                        ),
                        textCapitalization: TextCapitalization.sentences,
                        validator: (value) =>
                            value == null || value.trim().isEmpty
                                ? 'Nom requis'
                                : null,
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
                              separatorBuilder: (_, __) =>
                                  const Divider(height: 1),
                              itemCount: options.length,
                            ),
                          ),
                        ),
                      );
                    },
                    onSelected: (option) {
                      titleCtrl.text = option.name;
                      titleCtrl.selection = TextSelection.fromPosition(
                        TextPosition(offset: option.name.length),
                      );
                    },
                  ),
                  const SizedBox(height: 12),
                  TextFormField(
                    controller: skuCtrl,
                    decoration:
                        const InputDecoration(labelText: 'SKU (optionnel)'),
                  ),
                  const SizedBox(height: 12),
                  TextFormField(
                    controller: noteCtrl,
                    decoration:
                        const InputDecoration(labelText: 'Note (optionnel)'),
                    minLines: 1,
                    maxLines: 3,
                  ),
                  const SizedBox(height: 16),
                  Align(
                    alignment: Alignment.centerLeft,
                    child: Text(
                      'Quantité',
                      style: Theme.of(context)
                          .textTheme
                          .titleMedium
                          ?.copyWith(fontWeight: FontWeight.w600),
                    ),
                  ),
                  const SizedBox(height: 8),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      IconButton.filledTonal(
                        icon: const Icon(Icons.remove),
                        onPressed: qtyValue > 1
                            ? () => adjustQty(setDialogState, false)
                            : null,
                      ),
                      Text(
                        '$qtyValue',
                        style: Theme.of(context)
                            .textTheme
                            .headlineSmall
                            ?.copyWith(fontWeight: FontWeight.w700),
                      ),
                      IconButton.filledTonal(
                        icon: const Icon(Icons.add),
                        onPressed: () => adjustQty(setDialogState, true),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: const Text('Annuler'),
            ),
            FilledButton(
              onPressed: () {
                if (!formKey.currentState!.validate()) return;
                Navigator.of(context).pop(true);
              },
              child: Text(item == null ? 'Ajouter' : 'Enregistrer'),
            ),
          ],
        ),
      ),
    );

    nameFocusNode.dispose();

    if (confirmed != true) {
      return;
    }

    String? linkedItemId =
        _matchInventoryItemId(titleCtrl.text, sku: skuCtrl.text);
    if (linkedItemId == null && _isOnline && _companyId != null) {
      final created = await widget.commands.createItem(
        companyId: _companyId!,
        name: titleCtrl.text.trim(),
        sku: skuCtrl.text.trim().isEmpty ? null : skuCtrl.text.trim(),
      );
      if (created.ok) {
        linkedItemId = created.data?['id']?.toString();
      }
    }

    final nextItems = [..._inventoryItems];
    final updatedItem = _EquipmentInventoryItem(
      id: item?.id ?? DateTime.now().microsecondsSinceEpoch.toString(),
      name: titleCtrl.text.trim(),
      qty: qtyValue.toDouble(),
      sku: skuCtrl.text.trim().isEmpty ? null : skuCtrl.text.trim(),
      note: noteCtrl.text.trim().isEmpty ? null : noteCtrl.text.trim(),
      itemId: linkedItemId ?? item?.itemId,
    );

    if (item == null) {
      nextItems.add(updatedItem);
    } else {
      final index = nextItems.indexWhere((element) => element.id == item.id);
      if (index >= 0) {
        nextItems[index] = updatedItem;
      } else {
        nextItems.add(updatedItem);
      }
    }

    await _saveInventoryItems(
      nextItems,
      successMessage:
          item == null ? 'Pièce liée ajoutée.' : 'Pièce liée mise à jour.',
      events: [
        _QueuedEquipmentEvent(
          event: item == null
              ? 'equipment_inventory_item_added'
              : 'equipment_inventory_item_updated',
          category: 'inventory',
          note: updatedItem.name,
          payload: {
            if (updatedItem.qty != null) 'qty': updatedItem.qty,
            if (updatedItem.sku != null) 'sku': updatedItem.sku,
            if (updatedItem.itemId != null) 'item_id': updatedItem.itemId,
          },
        ),
      ],
    );
  }

  Future<void> _confirmRemoveInventoryItem(_EquipmentInventoryItem item) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Retirer cette pièce ?'),
        content: Text('Retirer "${item.name}" de la liste liée ?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Annuler'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Retirer'),
          ),
        ],
      ),
    );
    if (confirm != true) return;

    final nextItems =
        _inventoryItems.where((candidate) => candidate.id != item.id).toList();
    await _saveInventoryItems(
      nextItems,
      successMessage: 'Pièce liée retirée.',
      events: [
        _QueuedEquipmentEvent(
          event: 'equipment_inventory_item_removed',
          category: 'inventory',
          note: item.name,
        ),
      ],
    );
  }

  Future<void> _adjustInventoryItemQty(
    _EquipmentInventoryItem item, {
    required bool increase,
  }) async {
    final current = item.qty ?? 0;
    if (!increase && current <= 0) return;
    final nextQty =
        increase ? current + 1 : (current - 1).clamp(0, double.infinity);
    final updated = item.copyWith(qty: nextQty.toDouble());
    final nextItems = _inventoryItems
        .map((candidate) => candidate.id == item.id ? updated : candidate)
        .toList();
    await _saveInventoryItems(
      nextItems,
      successMessage: 'Quantité ajustée.',
      events: [
        _QueuedEquipmentEvent(
          event: 'equipment_inventory_item_updated',
          category: 'inventory',
          note: updated.name,
          payload: {
            'qty_before': current,
            'qty_after': nextQty,
            'delta': increase ? 1 : -1,
          },
        ),
      ],
    );
  }

  Future<String?> _ensureItemLinked(_EquipmentInventoryItem item) async {
    if (item.itemId != null && item.itemId!.isNotEmpty) {
      return item.itemId;
    }
    final matchedId =
        _matchInventoryItemId(item.name, sku: item.sku ?? item.note);
    if (matchedId != null) {
      await _updateInventoryItemEntry(item.copyWith(itemId: matchedId));
      return matchedId;
    }
    if (!_isOnline || _companyId == null) {
      _showSnack(
        'Associe la pièce à l’inventaire (connexion requise).',
        error: true,
      );
      return null;
    }
    final created = await widget.commands.createItem(
      companyId: _companyId!,
      name: item.name,
      sku: item.sku,
    );
    if (!created.ok || created.data?['id'] == null) {
      _showSnack(
        _describeError(created.error) ??
            'Impossible de créer la pièce pour le déplacement.',
        error: true,
      );
      return null;
    }
    final newId = created.data!['id']?.toString();
    if (newId == null || newId.isEmpty) return null;
    await _updateInventoryItemEntry(item.copyWith(itemId: newId));
    return newId;
  }

  Future<void> _updateInventoryItemEntry(
    _EquipmentInventoryItem updated, {
    List<_QueuedEquipmentEvent>? events,
    String? successMessage,
  }) {
    final nextItems = _inventoryItems
        .map((candidate) => candidate.id == updated.id ? updated : candidate)
        .toList();
    return _saveInventoryItems(
      nextItems,
      successMessage: successMessage,
      events: events,
    );
  }

  Future<void> _promptMoveInventoryItem(_EquipmentInventoryItem item) async {
    final companyId = _companyId;
    if (companyId == null) {
      _showSnack('Entreprise inconnue.', error: true);
      return;
    }
    if (_warehouses.isEmpty) {
      _showSnack('Aucun entrepôt disponible.', error: true);
      return;
    }

    final otherEquipment = widget.allEquipment
        .where((e) => (e['id']?.toString() ?? '') != _equipmentId)
        .toList();

    final moveChoice = await showModalBottomSheet<String>(
      context: context,
      backgroundColor: Colors.white,
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.move_to_inbox_outlined),
              title: const Text('Vers une section / entrepôt'),
              onTap: () => Navigator.of(context).pop('warehouse'),
            ),
            ListTile(
              leading: const Icon(Icons.swap_horiz),
              title: const Text('Vers un équipement'),
              onTap: () => Navigator.of(context).pop('equipment'),
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

    if (moveChoice == null) return;

    if (moveChoice == 'equipment' && otherEquipment.isEmpty) {
      _showSnack('Aucun autre équipement disponible.', error: true);
      return;
    }

    final request = await showModalBottomSheet<_EquipmentMoveRequest>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.white,
      builder: (context) {
        final defaultWarehouse = _warehouses.firstWhere(
          (w) => w['id'] != null,
          orElse: () => const <String, dynamic>{},
        );
        String? warehouseId = defaultWarehouse['id']?.toString();
        String? sectionId;
        String? otherEquipmentId = otherEquipment
            .firstWhere(
              (e) => e['id'] != null,
              orElse: () => const <String, dynamic>{},
            )['id']
            ?.toString();
        final qtyCtrl = TextEditingController(text: '1');

        return StatefulBuilder(
          builder: (context, setSheetState) {
            final sections = warehouseId == null
                ? const <_SectionOption>[]
                : _sectionOptionsForWarehouse(warehouseId!);
            const outbound = true; // depuis cet équipement
            final title =
                moveChoice == 'warehouse' ? 'Vers un entrepôt' : 'Vers un équipement';
            return Padding(
              padding: EdgeInsets.only(
                bottom: MediaQuery.of(context).viewInsets.bottom,
              ),
              child: SafeArea(
                child: SingleChildScrollView(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          const Text(
                            'Déplacer la pièce',
                            style: TextStyle(
                              fontWeight: FontWeight.w700,
                              fontSize: 18,
                            ),
                          ),
                          IconButton(
                            icon: const Icon(Icons.close),
                            onPressed: () => Navigator.of(context).pop(),
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      Chip(
                        label: Text(title),
                        avatar: const Icon(Icons.swap_vert),
                        backgroundColor: AppColors.surfaceAlt,
                      ),
                      const SizedBox(height: 16),
                      if (moveChoice == 'warehouse') ...[
                        DropdownButtonFormField<String>(
                          initialValue: warehouseId,
                          items: _warehouses
                              .where((w) => w['id'] != null)
                              .map(
                                (w) => DropdownMenuItem(
                                  value: w['id']!.toString(),
                                  child: Text(
                                    w['name']?.toString() ?? 'Entrepôt',
                                  ),
                                ),
                              )
                              .toList(),
                          onChanged: (value) {
                            setSheetState(() {
                              warehouseId = value;
                              sectionId = null;
                            });
                          },
                          decoration: const InputDecoration(
                            labelText: 'Entrepôt',
                          ),
                        ),
                        const SizedBox(height: 12),
                        DropdownButtonFormField<String>(
                          initialValue: sectionId,
                          items: sections
                              .map(
                                (section) => DropdownMenuItem(
                                  value: section.id,
                                  child: Text(section.label),
                                ),
                              )
                              .toList(),
                          onChanged: (value) =>
                              setSheetState(() => sectionId = value),
                          decoration: const InputDecoration(
                            labelText: 'Section (optionnel)',
                          ),
                        ),
                      ] else ...[
                        DropdownButtonFormField<String>(
                          initialValue: otherEquipmentId,
                          items: otherEquipment
                              .where((e) => e['id'] != null)
                              .map(
                                (e) => DropdownMenuItem(
                                  value: e['id']!.toString(),
                                  child: Text(
                                    e['name']?.toString() ?? 'Équipement',
                                  ),
                                ),
                              )
                              .toList(),
                          onChanged: (value) =>
                              setSheetState(() => otherEquipmentId = value),
                          decoration: const InputDecoration(
                            labelText: 'Équipement cible',
                          ),
                        ),
                        const SizedBox(height: 12),
                        if (otherEquipment.isEmpty)
                          const Text(
                            'Aucun autre équipement disponible.',
                            style: TextStyle(color: Colors.black54),
                          ),
                      ],
                      const SizedBox(height: 12),
                      TextFormField(
                        controller: qtyCtrl,
                        keyboardType: TextInputType.number,
                        decoration: InputDecoration(
                          labelText: outbound
                              ? 'Quantité (max ${item.qty?.toInt() ?? 0})'
                              : 'Quantité',
                        ),
                      ),
                      const SizedBox(height: 20),
                      SizedBox(
                        width: double.infinity,
                        child: FilledButton(
                          onPressed: () {
                            final parsed = int.tryParse(qtyCtrl.text.trim());
                            if (parsed == null || parsed <= 0) {
                              _showSnack('Quantité invalide.', error: true);
                              return;
                            }
                            if (outbound &&
                                ((item.qty ?? 0).toInt() <= 0 ||
                                    parsed > (item.qty ?? 0))) {
                              _showSnack(
                                'Quantité disponible insuffisante.',
                                error: true,
                              );
                              return;
                            }
                            if (moveChoice == 'equipment' &&
                                ((otherEquipmentId?.isEmpty ?? true))) {
                              _showSnack(
                                'Choisis un autre équipement.',
                                error: true,
                              );
                              return;
                            }
                            Navigator.of(context).pop(
                              _EquipmentMoveRequest(
                                direction: moveChoice == 'warehouse'
                                    ? _EquipmentMoveDirection.toWarehouse
                                    : _EquipmentMoveDirection.toOtherEquipment,
                                warehouseId: warehouseId ?? '',
                                sectionId: sectionId,
                                qty: parsed,
                                otherEquipmentId: otherEquipmentId,
                              ),
                            );
                          },
                          child: const Text('Valider le déplacement'),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            );
          },
        );
      },
    );

    if (request == null) return;
    if (request.warehouseId.isEmpty) {
      _showSnack('Entrepôt requis pour le déplacement.', error: true);
      return;
    }

    final itemId = await _ensureItemLinked(item);
    if (itemId == null) return;

    if (request.direction == _EquipmentMoveDirection.toEquipment) {
      await _executeMoveFromWarehouse(
        item: item,
        itemId: itemId,
        request: request,
      );
    } else if (request.direction == _EquipmentMoveDirection.toWarehouse) {
      await _executeMoveToWarehouse(
        item: item,
        itemId: itemId,
        request: request,
      );
    } else if (request.direction == _EquipmentMoveDirection.toOtherEquipment &&
        request.otherEquipmentId != null) {
      await _executeMoveToOtherEquipment(
        item: item,
        itemId: itemId,
        request: request,
        targetEquipmentId: request.otherEquipmentId!,
      );
    } else if (request.direction ==
            _EquipmentMoveDirection.fromOtherEquipment &&
        request.otherEquipmentId != null) {
      await _executeMoveFromOtherEquipment(
        item: item,
        itemId: itemId,
        request: request,
        sourceEquipmentId: request.otherEquipmentId!,
      );
    }
  }

  Future<void> _executeMoveFromWarehouse({
    required _EquipmentInventoryItem item,
    required String itemId,
    required _EquipmentMoveRequest request,
  }) async {
    final companyId = _companyId;
    if (companyId == null) {
      _showSnack('Entreprise inconnue.', error: true);
      return;
    }
    final sectionId = _normalizeSectionId(request.sectionId);
    final delta = -request.qty;

    if (_isOnline) {
      final result = await widget.commands.applyStockDelta(
        companyId: companyId,
        itemId: itemId,
        warehouseId: request.warehouseId,
        delta: delta,
        sectionId: sectionId,
      );
      if (!result.ok) {
        _showSnack(
          _describeError(result.error) ??
              'Impossible de retirer depuis cet entrepôt.',
          error: true,
        );
        return;
      }
    } else {
      await OfflineActionsService.instance.enqueue(
        OfflineActionTypes.inventoryStockDelta,
        {
          'company_id': companyId,
          'warehouse_id': request.warehouseId,
          'item_id': itemId,
          'delta': delta,
          'section_id': sectionId,
          'note': item.name,
          'event': 'stock_delta',
          'metadata': {
            'from_equipment': false,
            'to_equipment': _equipmentId,
          },
        },
      );
    }

    final updatedQty = (item.qty ?? 0) + request.qty;
    await _updateInventoryItemEntry(
      item.copyWith(qty: updatedQty),
      successMessage: _isOnline
          ? 'Pièce récupérée depuis l’entrepôt.'
          : 'Pièce récupérée (hors ligne).',
      events: [
        _QueuedEquipmentEvent(
          event: 'equipment_inventory_item_moved_in',
          category: 'inventory',
          note: item.name,
          payload: {
            'qty': request.qty,
            'warehouse_id': request.warehouseId,
            'section_id': sectionId,
          },
        ),
      ],
    );
  }

  Future<void> _executeMoveToWarehouse({
    required _EquipmentInventoryItem item,
    required String itemId,
    required _EquipmentMoveRequest request,
  }) async {
    final companyId = _companyId;
    if (companyId == null) {
      _showSnack('Entreprise inconnue.', error: true);
      return;
    }
    final available = item.qty ?? 0;
    if (available <= 0 || request.qty > available) {
      _showSnack('Quantité insuffisante sur cet équipement.', error: true);
      return;
    }
    final sectionId = _normalizeSectionId(request.sectionId);
    final delta = request.qty;

    if (_isOnline) {
      final result = await widget.commands.applyStockDelta(
        companyId: companyId,
        itemId: itemId,
        warehouseId: request.warehouseId,
        delta: delta,
        sectionId: sectionId,
      );
      if (!result.ok) {
        _showSnack(
          _describeError(result.error) ??
              'Impossible d’ajouter dans cet entrepôt.',
          error: true,
        );
        return;
      }
    } else {
      await OfflineActionsService.instance.enqueue(
        OfflineActionTypes.inventoryStockDelta,
        {
          'company_id': companyId,
          'warehouse_id': request.warehouseId,
          'item_id': itemId,
          'delta': delta,
          'section_id': sectionId,
          'note': item.name,
          'event': 'stock_delta',
          'metadata': {
            'from_equipment': _equipmentId,
            'to_equipment': false,
          },
        },
      );
    }

    final updatedQty = (item.qty ?? 0) - request.qty;
    await _updateInventoryItemEntry(
      item.copyWith(qty: updatedQty < 0 ? 0 : updatedQty),
      successMessage:
          _isOnline ? 'Pièce renvoyée au stock.' : 'Pièce renvoyée (hors ligne).',
      events: [
        _QueuedEquipmentEvent(
          event: 'equipment_inventory_item_moved_out',
          category: 'inventory',
          note: item.name,
          payload: {
            'qty': request.qty,
            'warehouse_id': request.warehouseId,
            'section_id': sectionId,
          },
        ),
      ],
    );
  }

  Future<void> _executeMoveToOtherEquipment({
    required _EquipmentInventoryItem item,
    required String itemId,
    required _EquipmentMoveRequest request,
    required String targetEquipmentId,
  }) async {
    final available = item.qty ?? 0;
    if (available <= 0 || request.qty > available) {
      _showSnack('Quantité insuffisante sur cet équipement.', error: true);
      return;
    }
    final target =
        widget.allEquipment.firstWhere((e) => e['id']?.toString() == targetEquipmentId, orElse: () => const {});
    if (target.isEmpty) {
      _showSnack('Équipement cible introuvable.', error: true);
      return;
    }

    final targetMeta =
        Map<String, dynamic>.from(target['meta'] as Map? ?? const {});
    final targetItems = _inventoryItemsFromMeta(targetMeta);
    final existingIndex = targetItems.indexWhere(
      (entry) =>
          (entry.itemId != null && entry.itemId == itemId) ||
          entry.name.trim().toLowerCase() == item.name.trim().toLowerCase(),
    );
    if (existingIndex >= 0) {
      final current = targetItems[existingIndex];
      targetItems[existingIndex] = current.copyWith(
        qty: (current.qty ?? 0) + request.qty,
        itemId: current.itemId ?? itemId,
      );
    } else {
      targetItems.add(
        _EquipmentInventoryItem(
          id: DateTime.now().microsecondsSinceEpoch.toString(),
          name: item.name,
          qty: request.qty.toDouble(),
          sku: item.sku,
          note: item.note,
          itemId: itemId,
        ),
      );
    }
    targetMeta['inventory_items'] = targetItems.map((e) => e.toMap()).toList();

    final updatedQty = (item.qty ?? 0) - request.qty;
    await _updateInventoryItemEntry(
      item.copyWith(qty: updatedQty < 0 ? 0 : updatedQty),
      successMessage: _isOnline
          ? 'Pièce envoyée à un autre équipement.'
          : 'Pièce envoyée (hors ligne).',
      events: [
        _QueuedEquipmentEvent(
          event: 'equipment_inventory_item_moved_out',
          category: 'inventory',
          note: item.name,
          payload: {
            'qty': request.qty,
            'to_equipment_id': targetEquipmentId,
          },
        ),
      ],
    );

    await _applyExternalEquipmentMeta(
      equipmentId: targetEquipmentId,
      nextMeta: targetMeta,
      events: [
        _QueuedEquipmentEvent(
          event: 'equipment_inventory_item_moved_in',
          category: 'inventory',
          note: item.name,
          payload: {
            'qty': request.qty,
            'from_equipment_id': _equipmentId,
            'item_id': itemId,
          },
        ),
      ],
    );
  }

  Future<void> _executeMoveFromOtherEquipment({
    required _EquipmentInventoryItem item,
    required String itemId,
    required _EquipmentMoveRequest request,
    required String sourceEquipmentId,
  }) async {
    final source =
        widget.allEquipment.firstWhere((e) => e['id']?.toString() == sourceEquipmentId, orElse: () => const {});
    if (source.isEmpty) {
      _showSnack('Équipement source introuvable.', error: true);
      return;
    }
    final sourceMeta =
        Map<String, dynamic>.from(source['meta'] as Map? ?? const {});
    final sourceItems = _inventoryItemsFromMeta(sourceMeta);
    final sourceIndex = sourceItems.indexWhere(
      (entry) =>
          (entry.itemId != null && entry.itemId == itemId) ||
          entry.name.trim().toLowerCase() == item.name.trim().toLowerCase(),
    );
    if (sourceIndex < 0) {
      _showSnack('Pièce absente sur l’équipement source.', error: true);
      return;
    }
    final sourceItem = sourceItems[sourceIndex];
    final available = sourceItem.qty ?? 0;
    if (available <= 0 || request.qty > available) {
      _showSnack('Quantité insuffisante sur l’équipement source.', error: true);
      return;
    }
    final nextSourceQty = available - request.qty;
    if (nextSourceQty <= 0) {
      sourceItems.removeAt(sourceIndex);
    } else {
      sourceItems[sourceIndex] = sourceItem.copyWith(qty: nextSourceQty);
    }
    sourceMeta['inventory_items'] =
        sourceItems.map((entry) => entry.toMap()).toList();

    final updatedQty = (item.qty ?? 0) + request.qty;
    await _updateInventoryItemEntry(
      item.copyWith(qty: updatedQty),
      successMessage:
          _isOnline ? 'Pièce reçue depuis un équipement.' : 'Pièce reçue (hors ligne).',
      events: [
        _QueuedEquipmentEvent(
          event: 'equipment_inventory_item_moved_in',
          category: 'inventory',
          note: item.name,
          payload: {
            'qty': request.qty,
            'from_equipment_id': sourceEquipmentId,
          },
        ),
      ],
    );

    await _applyExternalEquipmentMeta(
      equipmentId: sourceEquipmentId,
      nextMeta: sourceMeta,
      events: [
        _QueuedEquipmentEvent(
          event: 'equipment_inventory_item_moved_out',
          category: 'inventory',
          note: item.name,
          payload: {
            'qty': request.qty,
            'to_equipment_id': _equipmentId,
            'item_id': itemId,
          },
        ),
      ],
    );
  }

  String? _normalizeSectionId(String? sectionId) {
    if (sectionId == null || sectionId.isEmpty) return null;
    if (sectionId == InventoryEntry.unassignedSectionKey) return null;
    return sectionId;
  }

  Future<void> _addDieselEntry() async {
    final litersCtrl = TextEditingController(text: '10');
    final noteCtrl = TextEditingController();
    final formKey = GlobalKey<FormState>();

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Nouvelle entrée diesel'),
        content: Form(
          key: formKey,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextFormField(
                controller: litersCtrl,
                keyboardType:
                    const TextInputType.numberWithOptions(decimal: true),
                decoration: const InputDecoration(labelText: 'Litres ajoutés'),
                validator: (value) {
                  final parsed = double.tryParse(value ?? '');
                  if (parsed == null || parsed <= 0) {
                    return 'Quantité invalide';
                  }
                  return null;
                },
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: noteCtrl,
                decoration:
                    const InputDecoration(labelText: 'Note (optionnel)'),
                minLines: 1,
                maxLines: 3,
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Annuler'),
          ),
          FilledButton(
            onPressed: () {
              if (!formKey.currentState!.validate()) return;
              Navigator.of(context).pop(true);
            },
            child: const Text('Ajouter'),
          ),
        ],
      ),
    );

    if (confirmed != true) return;
    final entry = _DieselEntry(
      id: DateTime.now().microsecondsSinceEpoch.toString(),
      liters: double.parse(litersCtrl.text.trim()),
      note: noteCtrl.text.trim().isEmpty ? null : noteCtrl.text.trim(),
      createdAt: DateTime.now(),
    );
    final entries = [..._dieselEntries, entry];
    await _saveDieselEntries(
      entries,
      successMessage: 'Entrée diesel ajoutée.',
      events: [
        _QueuedEquipmentEvent(
          event: 'diesel_entry_added',
          category: 'diesel',
          note: '${entry.liters.toStringAsFixed(1)} L',
          payload: {'liters': entry.liters},
        ),
      ],
    );
  }

  Future<void> _confirmRemoveDieselEntry(_DieselEntry entry) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Supprimer cette entrée ?'),
        content: Text('Supprimer ${entry.liters} L du journal diesel ?'),
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
    if (confirm == true) {
      final entries = _dieselEntries
          .where(
            (candidate) => candidate.id != entry.id,
          )
          .toList();
      await _saveDieselEntries(
        entries,
        successMessage: 'Entrée supprimée.',
        events: [
          _QueuedEquipmentEvent(
            event: 'diesel_entry_removed',
            category: 'diesel',
            note: '${entry.liters.toStringAsFixed(1)} L',
          ),
        ],
      );
    }
  }

  Future<bool> _saveDieselEntries(
    List<_DieselEntry> entries, {
    String? successMessage,
    List<_QueuedEquipmentEvent>? events,
  }) async {
    final nextMeta = Map<String, dynamic>.from(_meta);
    nextMeta['diesel_logs'] = entries.map((entry) => entry.toMap()).toList();
    return _submitEquipmentMeta(
      nextMeta,
      successMessage: successMessage,
      events: events,
      errorMessage: 'Impossible de mettre à jour le journal.',
    );
  }

  Future<bool> _saveInventoryItems(
    List<_EquipmentInventoryItem> items, {
    String? successMessage,
    List<_QueuedEquipmentEvent>? events,
  }) async {
    final nextMeta = Map<String, dynamic>.from(_meta);
    nextMeta['inventory_items'] = items.map((item) => item.toMap()).toList();
    return _submitEquipmentMeta(
      nextMeta,
      successMessage: successMessage,
      events: events,
      errorMessage: 'Impossible de mettre à jour l’inventaire lié.',
    );
  }

  Future<bool> _submitEquipmentMeta(
    Map<String, dynamic> nextMeta, {
    String? successMessage,
    List<_QueuedEquipmentEvent>? events,
    String? errorMessage,
  }) async {
    if (_equipmentId.isEmpty) {
      _showSnack('Équipement inconnu.', error: true);
      return false;
    }
    if (_isOnline) {
      setState(() => _savingTask = true);
      final result = await widget.commands.updateEquipmentMeta(
        equipmentId: _equipmentId,
        meta: nextMeta,
      );
      setState(() => _savingTask = false);

      if (!result.ok || result.data == null) {
        _showSnack(
          _describeError(result.error) ??
              (errorMessage ?? 'Impossible de mettre à jour.'),
          error: true,
        );
        return false;
      }

      setState(() {
        _equipment = result.data!;
      });
      widget.onEquipmentChanged?.call(_equipment);
      await widget.onUpdated?.call();
      if (events != null) {
        for (final event in events) {
          await _recordJournalEvent(
            event.event,
            category: event.category,
            note: event.note,
            payload: event.payload,
          );
        }
      }
      if (successMessage != null) {
        _showSnack(successMessage);
      }
      return true;
    } else {
      final companyId = _companyId;
      if (companyId == null) {
        _showSnack('Entreprise inconnue.', error: true);
        return false;
      }
      setState(() {
        _equipment = Map<String, dynamic>.from(_equipment)..['meta'] = nextMeta;
      });
      await _queueEquipmentMetaUpdate(
        companyId: companyId,
        nextMeta: nextMeta,
        events: events,
        equipmentIdOverride: _equipmentId,
      );
      widget.onEquipmentChanged?.call(_equipment);
      if (successMessage != null) {
        _showSnack('$successMessage (hors ligne).');
      } else {
        _showSnack('Modification enregistrée hors ligne.');
      }
      return true;
    }
  }

  Future<void> _applyExternalEquipmentMeta({
    required String equipmentId,
    required Map<String, dynamic> nextMeta,
    List<_QueuedEquipmentEvent>? events,
  }) async {
    final companyId = _companyId;
    if (companyId == null) {
      _showSnack('Entreprise inconnue.', error: true);
      return;
    }
    if (_isOnline) {
      final result = await widget.commands.updateEquipmentMeta(
        equipmentId: equipmentId,
        meta: nextMeta,
      );
      if (!result.ok || result.data == null) {
        _showSnack(
          _describeError(result.error) ??
              'Impossible de mettre à jour l’autre équipement.',
          error: true,
        );
        return;
      }
      widget.onOtherEquipmentChanged?.call(result.data!);
      if (events != null) {
        for (final event in events) {
          await widget.commands.logJournalEntry(
            companyId: companyId,
            scope: 'equipment',
            entityId: _equipmentEntityIdFor(equipmentId, event.category),
            event: event.event,
            note: event.note,
            payload: event.payload,
          );
        }
      }
      await widget.onUpdated?.call();
    } else {
      await _queueEquipmentMetaUpdate(
        companyId: companyId,
        nextMeta: nextMeta,
        events: events,
        equipmentIdOverride: equipmentId,
      );
      final merged = {
        ..._equipmentById(equipmentId),
        'meta': nextMeta,
        'id': equipmentId,
      };
      widget.onOtherEquipmentChanged?.call(merged);
    }
  }

  String _equipmentEntityIdFor(String equipmentId, String category) {
    if (category.isEmpty || category == 'general') return equipmentId;
    return '$equipmentId::$category';
  }

  Future<void> _queueEquipmentMetaUpdate({
    required String companyId,
    required Map<String, dynamic> nextMeta,
    List<_QueuedEquipmentEvent>? events,
    String? equipmentIdOverride,
  }) async {
    await OfflineActionsService.instance.enqueue(
      OfflineActionTypes.equipmentMetaUpdate,
      {
        'company_id': companyId,
        'equipment_id': equipmentIdOverride ?? _equipmentId,
        'meta': nextMeta,
        if (events != null && events.isNotEmpty)
          'events': events.map((event) => event.toMap()).toList(),
      },
    );
  }

  Widget? _buildSectionFab() {
    final action = _fabActionForIndex(_tabController.index);
    if (action == null) return null;
    final disabled = _savingTask;
    return FloatingActionButton.extended(
      onPressed: disabled ? null : () => action.onPressed(),
      icon: Icon(action.icon),
      label: Text(action.label),
    );
  }

  _EquipmentFabAction? _fabActionForIndex(int index) {
    switch (index) {
      case 0:
        return _EquipmentFabAction(
          icon: Icons.add,
          label: 'Nouvelle tâche',
          onPressed: _addMechanicTask,
        );
      case 1:
        return _EquipmentFabAction(
          icon: Icons.add_task,
          label: 'Ajouter un suivi',
          onPressed: _addCustomMaintenance,
        );
      case 2:
        return _EquipmentFabAction(
          icon: Icons.local_gas_station,
          label: 'Nouvelle entrée diesel',
          onPressed: _addDieselEntry,
        );
      default:
        return _EquipmentFabAction(
          icon: Icons.inventory_2,
          label: 'Ajouter des pièces',
          onPressed: () => _editInventoryItem(),
        );
    }
  }

  void _showSnack(String message, {bool error = false}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: error
            ? Theme.of(context).colorScheme.error
            : Theme.of(context).colorScheme.primary,
      ),
    );
  }

  Color _priorityColor(String priority) {
    switch (priority) {
      case 'faible':
        return Colors.green.shade200;
      case 'eleve':
        return Colors.red.shade200;
      case 'moyen':
      default:
        return Colors.orange.shade200;
    }
  }

  Widget _tabWrap(Widget child) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(20),
      child: child,
    );
  }

  String _dayKey(DateTime date) {
    final local = date.toLocal();
    final dayOnly = DateTime(local.year, local.month, local.day);
    return dayOnly.toIso8601String();
  }

  String? _describeError(Object? error) {
    if (error == null) return null;
    return error.toString();
  }

  Future<void> _recordJournalEvent(
    String event, {
    String category = 'general',
    String? note,
    Map<String, dynamic>? payload,
  }) async {
    final companyId = _companyId;
    final entityId = _journalEntityId(category);
    if (companyId == null || _equipmentId.isEmpty || entityId.isEmpty) return;
    await widget.commands.logJournalEntry(
      companyId: companyId,
      scope: 'equipment',
      entityId: entityId,
      event: event,
      note: note,
      payload: payload,
    );
    await widget.onUpdated?.call();
  }
}

class _MechanicTask {
  const _MechanicTask({
    required this.id,
    required this.title,
    required this.delayDays,
    required this.priority,
    required this.createdAt,
    this.repeatEveryDays,
    this.isRecheck = false,
  });

  final String id;
  final String title;
  final int delayDays;
  final String priority;
  final DateTime createdAt;
  final int? repeatEveryDays;
  final bool isRecheck;

  DateTime get dueDate => createdAt.add(Duration(days: delayDays));

  factory _MechanicTask.fromMap(Map map) {
    final created = map['created_at'];
    return _MechanicTask(
      id: map['id']?.toString() ?? '',
      title: map['title']?.toString() ?? 'Tâche',
      delayDays: (map['delay_days'] as num?)?.round() ?? 0,
      priority: map['priority']?.toString() ?? 'moyen',
      createdAt: created is String
          ? DateTime.tryParse(created) ?? DateTime.now()
          : created is DateTime
              ? created
              : DateTime.now(),
      repeatEveryDays: (map['repeat_every_days'] as num?)?.round(),
      isRecheck: map['is_recheck'] == true,
    );
  }

  Map<String, dynamic> toMap() {
    final data = <String, dynamic>{
      'id': id,
      'title': title,
      'delay_days': delayDays,
      'priority': priority,
      'created_at': createdAt.toIso8601String(),
      'is_recheck': isRecheck,
    };
    if (repeatEveryDays != null) {
      data['repeat_every_days'] = repeatEveryDays;
    }
    return data;
  }
}

class _DieselEntry {
  const _DieselEntry({
    required this.id,
    required this.liters,
    this.note,
    required this.createdAt,
  });

  final String id;
  final double liters;
  final String? note;
  final DateTime createdAt;

  factory _DieselEntry.fromMap(Map map) {
    final created = map['created_at'];
    return _DieselEntry(
      id: map['id']?.toString() ?? '',
      liters: (map['liters'] as num?)?.toDouble() ?? 0,
      note: map['note']?.toString(),
      createdAt: created is String
          ? DateTime.tryParse(created) ?? DateTime.now()
          : created is DateTime
              ? created
              : DateTime.now(),
    );
  }

  Map<String, dynamic> toMap() {
    return <String, dynamic>{
      'id': id,
      'liters': liters,
      'note': note,
      'created_at': createdAt.toIso8601String(),
    };
  }
}

class _QueuedEquipmentEvent {
  const _QueuedEquipmentEvent({
    required this.event,
    this.category = 'general',
    this.note,
    this.payload,
  });

  final String event;
  final String category;
  final String? note;
  final Map<String, dynamic>? payload;

  Map<String, dynamic> toMap() {
    return <String, dynamic>{
      'event': event,
      'category': category,
      if (note != null) 'note': note,
      if (payload != null) 'payload': payload,
    };
  }
}

typedef _EquipmentFabCallback = Future<void> Function();

class _EquipmentFabAction {
  const _EquipmentFabAction({
    required this.icon,
    required this.label,
    required this.onPressed,
  });

  final IconData icon;
  final String label;
  final _EquipmentFabCallback onPressed;
}

class _StatTile extends StatelessWidget {
  const _StatTile({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: Theme.of(context)
              .textTheme
              .labelSmall
              ?.copyWith(color: Colors.black54),
        ),
        const SizedBox(height: 4),
        Text(
          value,
          style: Theme.of(context)
              .textTheme
              .titleMedium
              ?.copyWith(fontWeight: FontWeight.w700),
        ),
      ],
    );
  }
}

class _CustomMaintenance {
  const _CustomMaintenance({
    required this.id,
    required this.name,
    required this.intervalHours,
    this.lastHours,
  });

  final String id;
  final String name;
  final double intervalHours;
  final double? lastHours;

  double progress(double currentHours) {
    if (lastHours == null || intervalHours <= 0) return 0;
    return ((currentHours - lastHours!) / intervalHours).clamp(0.0, 2.0);
  }

  _CustomMaintenance copyWith({
    String? name,
    double? intervalHours,
    double? lastHours,
  }) {
    return _CustomMaintenance(
      id: id,
      name: name ?? this.name,
      intervalHours: intervalHours ?? this.intervalHours,
      lastHours: lastHours ?? this.lastHours,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'name': name,
      'interval_hours': intervalHours,
      if (lastHours != null) 'last_hours': lastHours,
    };
  }

  factory _CustomMaintenance.fromMap(Map map) {
    return _CustomMaintenance(
      id: map['id']?.toString() ?? DateTime.now().microsecondsSinceEpoch.toString(),
      name: map['name']?.toString() ?? 'Suivi',
      intervalHours: (map['interval_hours'] as num?)?.toDouble() ?? 0,
      lastHours: (map['last_hours'] as num?)?.toDouble(),
    );
  }
}

enum _EquipmentMoveDirection {
  toEquipment,
  toWarehouse,
  toOtherEquipment,
  fromOtherEquipment,
}

class _EquipmentMoveRequest {
  const _EquipmentMoveRequest({
    required this.direction,
    required this.warehouseId,
    this.sectionId,
    required this.qty,
    this.otherEquipmentId,
  });

  final _EquipmentMoveDirection direction;
  final String warehouseId;
  final String? sectionId;
  final int qty;
  final String? otherEquipmentId;
}

class _EquipmentInventoryItemRow extends StatelessWidget {
  const _EquipmentInventoryItemRow({
    required this.item,
    required this.busy,
    this.onIncrement,
    this.onDecrement,
    this.onEdit,
    this.onDelete,
    this.onMove,
  });

  final _EquipmentInventoryItem item;
  final bool busy;
  final VoidCallback? onIncrement;
  final VoidCallback? onDecrement;
  final VoidCallback? onEdit;
  final VoidCallback? onDelete;
  final VoidCallback? onMove;

  @override
  Widget build(BuildContext context) {
    final qtyLabel = item.qty?.toInt().toString() ?? '—';
    final subtitleParts = <String>[];
    if (item.sku != null && item.sku!.isNotEmpty) {
      subtitleParts.add('SKU ${item.sku}');
    }
    if (item.note != null && item.note!.isNotEmpty) {
      subtitleParts.add(item.note!);
    }
    return ListTile(
      contentPadding: EdgeInsets.zero,
      leading: CircleAvatar(
        backgroundColor: AppColors.surfaceAlt,
        child: Text(
          qtyLabel,
          style: const TextStyle(fontWeight: FontWeight.w700),
        ),
      ),
      title: Text(
        item.name,
        style: const TextStyle(fontWeight: FontWeight.w600),
      ),
      subtitle: subtitleParts.isEmpty ? null : Text(subtitleParts.join(' • ')),
      trailing: Wrap(
        spacing: 4,
        children: [
          IconButton(
            tooltip: 'Augmenter',
            icon: const Icon(Icons.add),
            onPressed: busy ? null : onIncrement,
          ),
          IconButton(
            tooltip: 'Diminuer',
            icon: const Icon(Icons.remove_circle_outline),
            onPressed: busy ? null : onDecrement,
          ),
          IconButton(
            tooltip: 'Modifier',
            icon: const Icon(Icons.edit_outlined),
            onPressed: busy ? null : onEdit,
          ),
          IconButton(
            tooltip: 'Déplacer',
            icon: const Icon(Icons.swap_horiz),
            onPressed: busy ? null : onMove,
          ),
          IconButton(
            tooltip: 'Supprimer',
            icon: const Icon(Icons.delete_outline),
            onPressed: busy ? null : onDelete,
          ),
        ],
      ),
    );
  }
}

class _EquipmentInventoryItem {
  const _EquipmentInventoryItem({
    required this.id,
    required this.name,
    this.qty,
    this.sku,
    this.note,
    this.itemId,
  });

  final String id;
  final String name;
  final double? qty;
  final String? sku;
  final String? note;
  final String? itemId;

  _EquipmentInventoryItem copyWith({
    String? name,
    double? qty,
    String? sku,
    String? note,
    String? itemId,
  }) {
    return _EquipmentInventoryItem(
      id: id,
      name: name ?? this.name,
      qty: qty ?? this.qty,
      sku: sku ?? this.sku,
      note: note ?? this.note,
      itemId: itemId ?? this.itemId,
    );
  }

  factory _EquipmentInventoryItem.fromMap(Map map) {
    final legacyUnit = map['unit']?.toString();
    return _EquipmentInventoryItem(
      id: map['id']?.toString() ?? '',
      name: map['name']?.toString() ?? 'Pièce',
      qty: (map['qty'] as num?)?.toDouble(),
      sku: map['sku']?.toString() ?? legacyUnit,
      note: map['note']?.toString(),
      itemId: map['item_id']?.toString(),
    );
  }

  Map<String, dynamic> toMap() {
    return <String, dynamic>{
      'id': id,
      'name': name,
      if (qty != null) 'qty': qty,
      if (sku != null && sku!.isNotEmpty) 'sku': sku,
      if (note != null && note!.isNotEmpty) 'note': note,
      if (itemId != null && itemId!.isNotEmpty) 'item_id': itemId,
    };
  }
}

Future<void> loadJournalAuthors(
  SupabaseClient client,
  Map<String, String> cache,
  List<Map<String, dynamic>> entries,
) async {
  final missingIds = <String>{};
  for (final entry in entries) {
    final createdBy = entry['created_by']?.toString();
    if (createdBy == null || createdBy.isEmpty) continue;
    if (!cache.containsKey(createdBy)) {
      missingIds.add(createdBy);
    }
  }
  if (missingIds.isNotEmpty) {
    try {
      final quoted = missingIds.map((id) => '"$id"').join(',');
      final response = await client
          .from('user_profiles')
          .select('user_uid, first_name, last_name')
          .filter('user_uid', 'in', '($quoted)');
      final data = (response as List?) ?? const <dynamic>[];
      for (final raw in data) {
        if (raw is! Map) continue;
        final uid = raw['user_uid']?.toString();
        if (uid == null) continue;
        cache[uid] = _formatJournalUserName(
          raw['first_name']?.toString(),
          raw['last_name']?.toString(),
        );
      }
    } catch (_) {
      // ignore lookup errors
    }
  }
  for (final entry in entries) {
    final createdBy = entry['created_by']?.toString();
    if (createdBy == null || createdBy.isEmpty) continue;
    entry['_author'] = cache[createdBy] ?? 'Utilisateur';
  }
}

String journalEventLabel(String? raw) {
  if (raw == null || raw.isEmpty) return 'Événement';
  final key = raw.toLowerCase();
  const labels = {
    'mechanic_task_added': 'Tâche mécanique ajoutée',
    'mechanic_task_removed': 'Tâche mécanique supprimée',
    'mechanic_task_completed': 'Tâche mécanique complétée',
    'diesel_entry_added': 'Entrée diesel ajoutée',
    'diesel_entry_removed': 'Entrée diesel supprimée',
    'equipment_inventory_item_added': 'Pièce liée ajoutée',
    'equipment_inventory_item_updated': 'Pièce liée mise à jour',
    'equipment_inventory_item_removed': 'Pièce liée retirée',
    'section_created': 'Section créée',
    'section_deleted': 'Section supprimée',
    'stock_moved_out': 'Déplacement sortant',
    'stock_moved_in': 'Déplacement entrant',
    'stock_delta': 'Ajustement de stock',
    'item_deleted': 'Pièce supprimée',
    'purchase_request_created': 'Demande d’achat créée',
    'purchase_request_qty_updated': 'Quantité mise à jour',
    'purchase_request_marked_to_place': 'Demande à placer',
    'purchase_request_completed': 'Demande complétée',
    'purchase_request_deleted': 'Demande supprimée',
    'purchase_stock_added': 'Stock ajouté (achat)',
    'note': 'Note',
  };
  if (labels.containsKey(key)) {
    return labels[key]!;
  }
  final fallback = key.replaceAll('_', ' ');
  return _sentenceCase(fallback);
}

String friendlyJournalLoadError(Object error) {
  final message = error.toString();
  if (message.contains('journal_entries')) {
    return 'Journal indisponible. Vérifie que la migration journal_entries est appliquée.';
  }
  return 'Impossible de charger le journal.';
}

String _formatJournalUserName(String? firstName, String? lastName) {
  final buffer = StringBuffer();
  if (firstName != null && firstName.trim().isNotEmpty) {
    buffer.write(firstName.trim());
  }
  if (lastName != null && lastName.trim().isNotEmpty) {
    if (buffer.isNotEmpty) buffer.write(' ');
    buffer.write(lastName.trim());
  }
  if (buffer.isEmpty) {
    return 'Utilisateur';
  }
  return buffer.toString();
}

String _sentenceCase(String input) {
  if (input.isEmpty) return input;
  return input[0].toUpperCase() + input.substring(1);
}
