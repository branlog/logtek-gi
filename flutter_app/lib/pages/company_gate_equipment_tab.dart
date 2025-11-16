part of 'company_gate.dart';

// ---------------------------------------------------------------------------
// Equipment tab
// ---------------------------------------------------------------------------

class _EquipmentTab extends StatelessWidget {
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
  Widget build(BuildContext context) {
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
          if (equipment.isEmpty)
            const _EmptyCard(
              title: 'Aucun équipement',
              subtitle: 'Ajoute ton premier équipement pour le suivre.',
            )
          else
            Column(
              children: equipment
                  .map<Widget>(
                    (item) => _EquipmentListCard(
                      data: item,
                      onTap: () => _showEquipmentDetail(context, item),
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
          commands: commands,
          onUpdated: onRefresh,
          companyId: companyId,
        ),
      ),
    );
  }
}

class _EquipmentListCard extends StatelessWidget {
  const _EquipmentListCard({required this.data, required this.onTap});

  final Map<String, dynamic> data;
  final VoidCallback onTap;

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
  bool _savingTask = false;
  final Map<String, String> _userNameCache = <String, String>{};

  @override
  void initState() {
    super.initState();
    _equipment = Map<String, dynamic>.from(widget.data);
    _tabController = TabController(length: 4, vsync: this);
  }

  @override
  void dispose() {
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
        Row(
          children: [
            Text(
              'Tâches à faire',
              style: Theme.of(context)
                  .textTheme
                  .titleSmall
                  ?.copyWith(fontWeight: FontWeight.w600),
            ),
            const Spacer(),
            TextButton.icon(
              onPressed: _savingTask ? null : _addMechanicTask,
              icon: const Icon(Icons.add),
              label: const Text('Nouvelle tâche'),
            ),
          ],
        ),
        if (_savingTask)
          const LinearProgressIndicator(minHeight: 2)
        else if (tasks.isEmpty)
          const Text('Aucune tâche enregistrée.')
        else
          Column(
            children: tasks
                .map(
                  (task) => Card(
                    child: ListTile(
                      leading: CircleAvatar(
                        backgroundColor: _priorityColor(task.priority),
                        child:
                            Text(task.priority.substring(0, 1).toUpperCase()),
                      ),
                      title: Text(task.title),
                      subtitle: Text(
                        'À faire sous ${task.delayDays} jour(s) • Échéance ${_formatDate(task.dueDate.toIso8601String()) ?? '—'}',
                      ),
                      trailing: IconButton(
                        icon: const Icon(Icons.delete_outline),
                        onPressed:
                            _savingTask ? null : () => _confirmRemoveTask(task),
                      ),
                    ),
                  ),
                )
                .toList(growable: false),
          ),
      ],
    );
  }

  Widget _buildDieselSection(BuildContext context) {
    final meta = _meta;
    final avg = meta['diesel_avg']?.toString() ?? '—';
    final tank = meta['diesel_tank']?.toString() ?? '—';
    final entries = _dieselEntries;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Consommation moyenne : $avg L/h'),
        Text('Capacité réservoir : $tank L'),
        const SizedBox(height: 16),
        Row(
          children: [
            Text(
              'Journal diesel',
              style: Theme.of(context)
                  .textTheme
                  .titleSmall
                  ?.copyWith(fontWeight: FontWeight.w600),
            ),
            const Spacer(),
            TextButton.icon(
              onPressed: _savingTask ? null : _addDieselEntry,
              icon: const Icon(Icons.local_gas_station),
              label: const Text('Nouvel ajout'),
            ),
          ],
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
    final inventory = (_equipment['inventory'] as List?)
            ?.whereType<Map>()
            .map((item) => Map<String, dynamic>.from(item))
            .toList() ??
        const <Map<String, dynamic>>[];
    if (inventory.isEmpty) {
      return const Text('Aucun article lié. Utilise l’inventaire principal.');
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: inventory
          .map(
            (item) => ListTile(
              contentPadding: EdgeInsets.zero,
              title: Text(item['name']?.toString() ?? 'Pièce'),
              subtitle: Text('Qté : ${item['qty'] ?? '—'}'),
            ),
          )
          .toList(growable: false),
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
    final saved = await _saveMechanicTasks(tasks);
    if (saved) {
      await _recordJournalEvent(
        'mechanic_task_added',
        category: 'mechanic',
        note: task.title,
        payload: {
          'delay_days': delay,
          'priority': priority,
        },
      );
    }
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
      final saved = await _saveMechanicTasks(tasks);
      if (saved) {
        await _recordJournalEvent(
          'mechanic_task_removed',
          category: 'mechanic',
          note: task.title,
        );
      }
    }
  }

  Future<bool> _saveMechanicTasks(List<_MechanicTask> tasks) async {
    if (_equipmentId.isEmpty) {
      _showSnack('Équipement inconnu.', error: true);
      return false;
    }
    setState(() => _savingTask = true);
    final nextMeta = _meta;
    nextMeta['mechanic_tasks'] = tasks.map((task) => task.toMap()).toList();

    final result = await widget.commands.updateEquipmentMeta(
      equipmentId: _equipmentId,
      meta: nextMeta,
    );
    setState(() => _savingTask = false);

    if (!result.ok || result.data == null) {
      _showSnack(
        _describeError(result.error) ??
            'Impossible de mettre à jour les tâches.',
        error: true,
      );
      return false;
    }

    setState(() {
      _equipment = result.data!;
    });
    await widget.onUpdated?.call();
    return true;
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
    final saved = await _saveDieselEntries(entries);
    if (saved) {
      await _recordJournalEvent(
        'diesel_entry_added',
        category: 'diesel',
        note: '${entry.liters.toStringAsFixed(1)} L',
        payload: {'liters': entry.liters},
      );
    }
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
      final saved = await _saveDieselEntries(entries);
      if (saved) {
        await _recordJournalEvent(
          'diesel_entry_removed',
          category: 'diesel',
          note: '${entry.liters.toStringAsFixed(1)} L',
        );
      }
    }
  }

  Future<bool> _saveDieselEntries(List<_DieselEntry> entries) async {
    if (_equipmentId.isEmpty) {
      _showSnack('Équipement inconnu.', error: true);
      return false;
    }
    setState(() => _savingTask = true);
    final nextMeta = _meta;
    nextMeta['diesel_logs'] = entries.map((entry) => entry.toMap()).toList();

    final result = await widget.commands.updateEquipmentMeta(
      equipmentId: _equipmentId,
      meta: nextMeta,
    );
    setState(() => _savingTask = false);

    if (!result.ok || result.data == null) {
      _showSnack(
        _describeError(result.error) ??
            'Impossible de mettre à jour le journal.',
        error: true,
      );
      return false;
    }

    setState(() {
      _equipment = result.data!;
    });
    await widget.onUpdated?.call();
    return true;
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
  });

  final String id;
  final String title;
  final int delayDays;
  final String priority;
  final DateTime createdAt;

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
    );
  }

  Map<String, dynamic> toMap() {
    return <String, dynamic>{
      'id': id,
      'title': title,
      'delay_days': delayDays,
      'priority': priority,
      'created_at': createdAt.toIso8601String(),
    };
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
    'diesel_entry_added': 'Entrée diesel ajoutée',
    'diesel_entry_removed': 'Entrée diesel supprimée',
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
