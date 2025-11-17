part of 'company_gate.dart';

// ---------------------------------------------------------------------------
// Equipment tab
// ---------------------------------------------------------------------------

enum _EquipmentFilter { active, inactive }

class _EquipmentTab extends StatefulWidget {
  const _EquipmentTab({
    required this.equipment,
    required this.commands,
    required this.onRefresh,
    this.companyId,
  });

  final List<Map<String, dynamic>> equipment;
  final CompanyCommands commands;
  final Future<void> Function() onRefresh;
  final String? companyId;

  @override
  State<_EquipmentTab> createState() => _EquipmentTabState();
}

class _EquipmentTabState extends State<_EquipmentTab> {
  _EquipmentFilter _filter = _EquipmentFilter.active;
  final Set<String> _updatingIds = <String>{};

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
              children: filtered
                  .map<Widget>(
                    (item) => _EquipmentListCard(
                      data: item,
                      onTap: () => _showEquipmentDetail(context, item),
                      footer: _filter == _EquipmentFilter.inactive
                          ? Align(
                              alignment: Alignment.centerLeft,
                              child: TextButton.icon(
                                onPressed: _updatingIds.contains(
                                        item['id']?.toString() ?? '')
                                    ? null
                                    : () => _setEquipmentActive(item, true),
                                icon: _updatingIds.contains(
                                        item['id']?.toString() ?? '')
                                    ? const SizedBox(
                                        width: 16,
                                        height: 16,
                                        child:
                                            CircularProgressIndicator(strokeWidth: 2),
                                      )
                                    : const Icon(Icons.refresh_outlined),
                                label: const Text('Réactiver'),
                              ),
                            )
                          : null,
                    ),
                  )
                  .toList(growable: false),
            ),
        ],
      ),
    );
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
    final subtitle = [
      if (brand != null) brand,
      if (model != null) model,
      if (serial != null) 'SN $serial',
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
    this.onUpdated,
    this.companyId,
  });

  final Map<String, dynamic> data;
  final CompanyCommands commands;
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
  final Map<String, String> _userNameCache = <String, String>{};

  @override
  void initState() {
    super.initState();
    _equipment = Map<String, dynamic>.from(widget.data);
    _tabController = TabController(length: 4, vsync: this)
      ..addListener(_handleTabChanged);
    _inventorySearchCtrl = TextEditingController()
      ..addListener(() => setState(() {}));
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

  bool get _isOnline => ConnectivityService.instance.isOnline;

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

  String get _equipmentName => _equipment['name']?.toString() ?? 'Équipement';
  String get _equipmentId => _equipment['id']?.toString() ?? '';
  String? get _companyId =>
      _equipment['company_id']?.toString() ?? widget.companyId;
  String _journalEntityId(String category) {
    if (_equipmentId.isEmpty) return '';
    if (category.isEmpty || category == 'general') return _equipmentId;
    return '${_equipmentId}::$category';
  }
  void _openJournalForCurrentTab() {
    final index = _tabController.index;
    final category = _journalCategoryForIndex(index);
    final label = _tabLabelForIndex(index);
    _openJournalSheet(
      category: category,
      title: '${_equipmentName} — $label',
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

  String _tabLabelForIndex(int index) {
    switch (index) {
      case 0:
        return 'Mécanique';
      case 1:
        return 'Diesel';
      case 2:
        return 'Inventaire';
      case 3:
        return 'Documentation';
      default:
        return 'Journal';
    }
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
        if (_savingTask)
          const LinearProgressIndicator(minHeight: 2)
        else if (tasks.isEmpty)
          const Text('Aucune tâche enregistrée.')
        else
          Column(
            children: tasks
                .map(
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
                          child:
                              Text(task.priority.substring(0, 1).toUpperCase()),
                        ),
                        title: Text(task.title),
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
                              onPressed: _savingTask
                                  ? null
                                  : () => _confirmRemoveTask(task),
                            ),
                          ],
                        ),
                      ),
                    );
                  },
                )
                .toList(growable: false),
          ),
      ],
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
      return Card(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: const [
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
                  onIncrement: () => _adjustInventoryItemQty(
                      filteredItems[i],
                      increase: true),
                  onDecrement: () => _adjustInventoryItemQty(
                      filteredItems[i],
                      increase: false),
                  onEdit: () => _editInventoryItem(item: filteredItems[i]),
                  onDelete: () =>
                      _confirmRemoveInventoryItem(filteredItems[i]),
                  ),
                  if (i != filteredItems.length - 1)
                    const Divider(height: 1),
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
    final nameCtrl = TextEditingController(text: _equipment['name']?.toString() ?? '');
    final brandCtrl = TextEditingController(text: _equipment['brand']?.toString() ?? '');
    final modelCtrl = TextEditingController(text: _equipment['model']?.toString() ?? '');
    final serialCtrl = TextEditingController(text: _equipment['serial']?.toString() ?? '');
    var active = _equipment['active'] != false;
    var submitting = false;
    String? dialogError;

    await showDialog<void>(
      context: context,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            InputDecoration decoration(String label, TextEditingController ctrl) {
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
                        controller: serialCtrl,
                        decoration: decoration('Numéro de série', serialCtrl),
                        onChanged: (_) => setDialogState(() {}),
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

    final result =
        await widget.commands.deleteEquipment(equipmentId: _equipmentId);

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
                value: priority,
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

    await _saveMechanicTasks(
      updatedTasks,
      successMessage: 'Tâche marquée comme faite.',
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
            keyboardType:
                const TextInputType.numberWithOptions(decimal: true),
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
          title: Text(item == null ? 'Ajouter des pièces' : 'Modifier la pièce'),
          content: Form(
            key: formKey,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  TextFormField(
                    controller: titleCtrl,
                    decoration: const InputDecoration(labelText: 'Nom de la pièce'),
                    textCapitalization: TextCapitalization.sentences,
                    validator: (value) =>
                        value == null || value.trim().isEmpty ? 'Nom requis' : null,
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
                    decoration: const InputDecoration(labelText: 'Note (optionnel)'),
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

    if (confirmed != true) {
      return;
    }

    final nextItems = [..._inventoryItems];
    final updatedItem = _EquipmentInventoryItem(
      id: item?.id ?? DateTime.now().microsecondsSinceEpoch.toString(),
      name: titleCtrl.text.trim(),
      qty: qtyValue.toDouble(),
      sku: skuCtrl.text.trim().isEmpty ? null : skuCtrl.text.trim(),
      note: noteCtrl.text.trim().isEmpty ? null : noteCtrl.text.trim(),
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
    nextMeta['inventory_items'] =
        items.map((item) => item.toMap()).toList();
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
        _equipment = Map<String, dynamic>.from(_equipment)
          ..['meta'] = nextMeta;
      });
      await _queueEquipmentMetaUpdate(
        companyId: companyId,
        nextMeta: nextMeta,
        events: events,
      );
      if (successMessage != null) {
        _showSnack('$successMessage (hors ligne).');
      } else {
        _showSnack('Modification enregistrée hors ligne.');
      }
      return true;
    }
  }

  Future<void> _queueEquipmentMetaUpdate({
    required String companyId,
    required Map<String, dynamic> nextMeta,
    List<_QueuedEquipmentEvent>? events,
  }) async {
    await OfflineActionsService.instance.enqueue(
      OfflineActionTypes.equipmentMetaUpdate,
      {
        'company_id': companyId,
        'equipment_id': _equipmentId,
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
          icon: Icons.local_gas_station,
          label: 'Nouvelle entrée diesel',
          onPressed: _addDieselEntry,
        );
      case 2:
        return _EquipmentFabAction(
          icon: Icons.inventory_2,
          label: 'Ajouter des pièces',
          onPressed: () => _editInventoryItem(),
        );
      default:
        return null;
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
  });

  final String id;
  final String title;
  final int delayDays;
  final String priority;
  final DateTime createdAt;
  final int? repeatEveryDays;

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
    );
  }

  Map<String, dynamic> toMap() {
    final data = <String, dynamic>{
      'id': id,
      'title': title,
      'delay_days': delayDays,
      'priority': priority,
      'created_at': createdAt.toIso8601String(),
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

class _EquipmentInventoryItemRow extends StatelessWidget {
  const _EquipmentInventoryItemRow({
    required this.item,
    required this.busy,
    this.onIncrement,
    this.onDecrement,
    this.onEdit,
    this.onDelete,
  });

  final _EquipmentInventoryItem item;
  final bool busy;
  final VoidCallback? onIncrement;
  final VoidCallback? onDecrement;
  final VoidCallback? onEdit;
  final VoidCallback? onDelete;

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
  });

  final String id;
  final String name;
  final double? qty;
  final String? sku;
  final String? note;

  _EquipmentInventoryItem copyWith({
    String? name,
    double? qty,
    String? sku,
    String? note,
  }) {
    return _EquipmentInventoryItem(
      id: id,
      name: name ?? this.name,
      qty: qty ?? this.qty,
      sku: sku ?? this.sku,
      note: note ?? this.note,
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
    );
  }

  Map<String, dynamic> toMap() {
    return <String, dynamic>{
      'id': id,
      'name': name,
      if (qty != null) 'qty': qty,
      if (sku != null && sku!.isNotEmpty) 'sku': sku,
      if (note != null && note!.isNotEmpty) 'note': note,
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
