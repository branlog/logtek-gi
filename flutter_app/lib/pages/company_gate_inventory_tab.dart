part of 'company_gate.dart';

// ---------------------------------------------------------------------------
// Inventory tab
// ---------------------------------------------------------------------------

String _inventoryWarehouseEntityId(String warehouseId) =>
    'inventory/warehouse/$warehouseId';

String _inventorySectionEntityId(String warehouseId, String? sectionId) {
  final normalized = (sectionId == null ||
          sectionId.isEmpty ||
          sectionId == InventoryEntry.unassignedSectionKey)
      ? InventoryEntry.unassignedSectionKey
      : sectionId;
  return 'inventory/warehouse/$warehouseId/section/$normalized';
}

class _InventoryTab extends StatelessWidget {
  const _InventoryTab({
    required this.warehouses,
    required this.inventory,
    required this.onViewInventory,
    required this.requests,
    required this.onPlaceRequest,
    required this.updatingRequestIds,
    required this.onManageWarehouse,
  });

  final List<Map<String, dynamic>> warehouses;
  final List<InventoryEntry> inventory;
  final void Function(String warehouseId, {String? sectionId}) onViewInventory;
  final List<Map<String, dynamic>> requests;
  final void Function(Map<String, dynamic> request) onPlaceRequest;
  final Set<String> updatingRequestIds;
  final void Function(Map<String, dynamic> warehouse) onManageWarehouse;

  @override
  Widget build(BuildContext context) {
    final toPlaceRequests = requests
        .where((request) => request['status']?.toString() == 'to_place')
        .toList();

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text('Pièces à placer',
              style: Theme.of(context)
                  .textTheme
                  .titleLarge
                  ?.copyWith(fontWeight: FontWeight.w700)),
          const SizedBox(height: 12),
          if (toPlaceRequests.isEmpty)
            const _EmptyCard(
              title: 'Aucune pièce à placer',
              subtitle: 'Les achats confirmés apparaîtront ici.',
            )
          else
            Column(
              children: toPlaceRequests.map((request) {
                final requestId = request['id']?.toString();
                final placing =
                    requestId != null && updatingRequestIds.contains(requestId);
                return _ToPlaceCard(
                  data: request,
                  placing: placing,
                  onPlace: () => onPlaceRequest(request),
                );
              }).toList(),
            ),
          const SizedBox(height: 24),
          Row(
            children: [
              Text('Entrepôts',
                  style: Theme.of(context)
                      .textTheme
                      .titleLarge
                      ?.copyWith(fontWeight: FontWeight.w700)),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            'Utilise le bouton + pour créer un nouvel entrepôt ou une section.',
            style: Theme.of(context).textTheme.bodySmall,
          ),
          const SizedBox(height: 16),
          if (warehouses.isEmpty)
            const _EmptyCard(
              title: 'Aucun entrepôt',
              subtitle: 'Ajoute ton premier entrepôt pour suivre les stocks.',
            )
          else
            Column(
              children: warehouses.map((warehouse) {
                final warehouseId = warehouse['id']?.toString();
                return _WarehouseCard(
                  data: warehouse,
                  inventory: inventory,
                  onViewInventory: warehouseId == null
                      ? null
                      : ({String? sectionId}) => onViewInventory(
                            warehouseId,
                            sectionId: sectionId,
                          ),
                  onManage:
                      warehouseId == null ? null : () => onManageWarehouse(warehouse),
                );
              }).toList(),
            ),
        ],
      ),
    );
  }
}

class _ToPlaceCard extends StatelessWidget {
  const _ToPlaceCard({
    required this.data,
    required this.onPlace,
    required this.placing,
  });

  final Map<String, dynamic> data;
  final VoidCallback onPlace;
  final bool placing;

  @override
  Widget build(BuildContext context) {
    final name = data['name']?.toString() ?? 'Pièce';
    final qty = data['qty']?.toString() ?? '—';
    final note = data['note']?.toString();
    final warehouse = data['warehouse'] as Map<String, dynamic>?;
    final warehouseName = warehouse?['name']?.toString();
    final section = data['section'] as Map<String, dynamic>?;
    final sectionName = section?['name']?.toString();
    final fallbackSectionId = data['section_id']?.toString();

    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Text(
                  name,
                  style: Theme.of(context)
                      .textTheme
                      .titleMedium
                      ?.copyWith(fontWeight: FontWeight.w700),
                ),
                const Spacer(),
                _Badge(
                  label: 'À placer',
                  color: Colors.orange,
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text('Quantité reçue : $qty'),
            if (warehouseName != null && warehouseName.isNotEmpty)
              Text('Entrepôt prévu : $warehouseName'),
            if ((sectionName != null && sectionName.isNotEmpty) ||
                (sectionName == null && fallbackSectionId != null))
              Text(
                'Section prévue : ${sectionName ?? fallbackSectionId}',
              ),
            if (note != null && note.trim().isNotEmpty) Text('Note : $note'),
            const SizedBox(height: 12),
            FilledButton(
              onPressed: placing ? null : onPlace,
              child: placing
                  ? Row(
                      mainAxisSize: MainAxisSize.min,
                      children: const [
                        SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        ),
                        SizedBox(width: 8),
                        Text('Placement...'),
                      ],
                    )
                  : Row(
                      mainAxisSize: MainAxisSize.min,
                      children: const [
                        Icon(Icons.inventory_2),
                        SizedBox(width: 8),
                        Text('Placer'),
                      ],
                    ),
            ),
          ],
        ),
      ),
    );
  }
}

class _WarehouseCard extends StatelessWidget {
  const _WarehouseCard({
    required this.data,
    required this.inventory,
    required this.onViewInventory,
    this.onManage,
  });

  final Map<String, dynamic> data;
  final List<InventoryEntry> inventory;
  final void Function({String? sectionId})? onViewInventory;
  final VoidCallback? onManage;

  @override
  Widget build(BuildContext context) {
    final name = (data['name'] as String?) ?? 'Entrepôt';
    final createdAt = _formatDate(data['created_at']);
    final active = (data['active'] as bool?) ?? true;
    final id = data['id']?.toString();

    final entryCount = inventory
        .where((entry) => entry.warehouseSplit.containsKey(id))
        .fold<int>(0, (acc, entry) => acc + (entry.warehouseSplit[id] ?? 0));
    final itemsCount =
        inventory.where((entry) => entry.warehouseSplit.containsKey(id)).length;

    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onViewInventory == null ? null : () => onViewInventory!(),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const CircleAvatar(
                    backgroundColor: Color(0xFFF8D8C5),
                    child: Icon(Icons.home_work, color: AppColors.primary),
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
                        Text('Créé le ${createdAt ?? '—'}'),
                        Text('$itemsCount article(s) • $entryCount en stock'),
                      ],
                    ),
                  ),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      _Badge(
                        label: active ? 'Actif' : 'Inactif',
                        color: active ? AppColors.primary : Colors.grey,
                      ),
                      if (onManage != null)
                        IconButton(
                          icon: const Icon(Icons.more_horiz),
                          tooltip: 'Gérer l’entrepôt',
                          onPressed: onManage,
                        ),
                    ],
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Text(
                'Touchez pour ouvrir l’inventaire.',
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _WarehouseInventoryPage extends StatefulWidget {
  const _WarehouseInventoryPage({
    required this.companyId,
    required this.warehouseId,
    required this.warehouseProvider,
    required this.warehousesProvider,
    required this.inventoryProvider,
    required this.commands,
    required this.describeError,
    required this.onRefresh,
    required this.isOnline,
    this.initialSectionId,
    this.onShowJournal,
    this.onManageWarehouse,
  });

  final String companyId;
  final String warehouseId;
  final Map<String, dynamic>? Function() warehouseProvider;
  final List<Map<String, dynamic>> Function() warehousesProvider;
  final List<InventoryEntry> Function() inventoryProvider;
  final CompanyCommands commands;
  final String? Function(Object? error) describeError;
  final Future<void> Function() onRefresh;
  final bool Function() isOnline;
  final String? initialSectionId;
  final Future<void> Function({String? scopeOverride, String? entityId})?
      onShowJournal;
  final Future<void> Function(Map<String, dynamic> warehouse)?
      onManageWarehouse;

  @override
  State<_WarehouseInventoryPage> createState() =>
      _WarehouseInventoryPageState();
}

class _WarehouseInventoryPageState extends State<_WarehouseInventoryPage> {
  String? _focusedSectionId;
  bool _processing = false;
  final Map<String, _SectionSnapshot> _offlineSectionOverrides =
      <String, _SectionSnapshot>{};

  bool get _isOnline => widget.isOnline();

  @override
  void initState() {
    super.initState();
    _focusedSectionId = widget.initialSectionId;
  }

  Map<String, dynamic>? get _warehouse => widget.warehouseProvider();

  String get _warehouseName =>
      _warehouse?['name']?.toString() ?? 'Entrepôt sans nom';

  List<Map<String, dynamic>> get _sections {
    final raw = _warehouse?['sections'];
    if (raw is List) {
      return raw
          .whereType<Map>()
          .map((section) => Map<String, dynamic>.from(section))
          .toList(growable: false);
    }
    return const <Map<String, dynamic>>[];
  }

  Map<String, dynamic>? _sectionDataById(String sectionId) {
    return _sections.firstWhere(
      (section) => section['id']?.toString() == sectionId,
      orElse: () => const <String, dynamic>{},
    );
  }

  List<Map<String, dynamic>> get _allWarehouses => widget
      .warehousesProvider()
      .whereType<Map>()
      .map((warehouse) => Map<String, dynamic>.from(warehouse))
      .toList(growable: false);

  List<InventoryEntry> get _inventory => widget.inventoryProvider();

  String get _warehouseJournalEntityId =>
      _inventoryWarehouseEntityId(widget.warehouseId);

  String _sectionJournalEntityId(
    String? sectionId, {
    String? warehouseIdOverride,
  }) {
    return _inventorySectionEntityId(
      warehouseIdOverride ?? widget.warehouseId,
      sectionId,
    );
  }

  Future<void> _openWarehouseJournal() async {
    final callback = widget.onShowJournal;
    if (callback == null) return;
    await callback(
      scopeOverride: 'inventory',
      entityId: _warehouseJournalEntityId,
    );
  }

  Future<void> _openSectionJournal(
    String? sectionId, {
    String? warehouseIdOverride,
  }) async {
    final callback = widget.onShowJournal;
    if (callback == null) return;
    await callback(
      scopeOverride: 'inventory',
      entityId: _sectionJournalEntityId(
        sectionId,
        warehouseIdOverride: warehouseIdOverride,
      ),
    );
  }

  Future<void> _handleManageCurrentWarehouse() async {
    final callback = widget.onManageWarehouse;
    final warehouse = _warehouse;
    if (callback == null || warehouse == null || warehouse.isEmpty) return;
    await callback(warehouse);
    if (mounted) {
      setState(() {});
    }
  }

  @override
  Widget build(BuildContext context) {
    final warehouse = _warehouse;
    if (warehouse == null || warehouse.isEmpty) {
      return Scaffold(
        appBar: AppBar(
          title: const Text('Entrepôt introuvable'),
        ),
        body: const Center(
          child: Text('Entrepôt introuvable. Recharge les données.'),
        ),
      );
    }

    final sectionSnapshots = _buildSections();
    final totalStock =
        sectionSnapshots.fold<int>(0, (acc, item) => acc + item.totalQty);
    final totalItems =
        sectionSnapshots.fold<int>(0, (acc, item) => acc + item.lines.length);

    return Scaffold(
      appBar: AppBar(
        title: Text(_warehouseName),
        actions: [
          if (widget.onManageWarehouse != null)
            IconButton(
              onPressed:
                  _processing ? null : () => _handleManageCurrentWarehouse(),
              tooltip: 'Gérer l’entrepôt',
              icon: const Icon(Icons.more_horiz),
            ),
          IconButton(
            onPressed: widget.onShowJournal == null
                ? null
                : () => _openWarehouseJournal(),
            tooltip: 'Journal',
            icon: const Icon(Icons.history),
          ),
          IconButton(
            onPressed: _processing ? null : _handleCreateSection,
            tooltip: 'Nouvelle section',
            icon: const Icon(Icons.add_business),
          ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: _handleFullRefresh,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(20, 16, 20, 32),
          physics: const AlwaysScrollableScrollPhysics(),
          children: [
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Résumé',
                      style: Theme.of(context)
                          .textTheme
                          .titleMedium
                          ?.copyWith(fontWeight: FontWeight.w700),
                    ),
                    const SizedBox(height: 12),
                    Wrap(
                      spacing: 16,
                      runSpacing: 16,
                      children: [
                        _SummaryMetric(
                          label: 'Stock total',
                          value: '$totalStock',
                          icon: Icons.inventory_2,
                        ),
                        _SummaryMetric(
                          label: 'Sections',
                          value: '${sectionSnapshots.length}',
                          icon: Icons.view_day,
                        ),
                        _SummaryMetric(
                          label: 'Articles',
                          value: '$totalItems',
                          icon: Icons.category,
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 16),
            if (sectionSnapshots.isEmpty)
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'Aucune section créée pour cet entrepôt.',
                        style: TextStyle(fontWeight: FontWeight.w600),
                      ),
                      const SizedBox(height: 8),
                      const Text(
                        'Ajoute une section avec le bouton + en bas à droite.',
                      ),
                    ],
                  ),
                ),
              )
            else
              ...sectionSnapshots.map(
                (section) => _SectionInventoryCard(
                  data: section,
                  busy: _processing,
                  onOpen: () => _showSectionDetails(section),
                  onManage: (section.renamable || section.deletable)
                      ? () => _showSectionActions(section)
                      : null,
                ),
              ),
          ],
        ),
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: _processing
            ? null
            : () async {
                final target = await _promptSectionChoice();
                if (target == null && _sections.isNotEmpty) return;
                await _handleAddPieces(target);
              },
        tooltip: 'Ajouter des pièces',
        child: const Icon(Icons.add),
      ),
    );
  }

  List<_SectionSnapshot> _buildSections() {
    final base = _composeSections();
    if (_offlineSectionOverrides.isEmpty) return base;
    final resolved = base
        .map((snapshot) =>
            _offlineSectionOverrides[_sectionKey(snapshot.id)] ?? snapshot)
        .toList(growable: true);
    _offlineSectionOverrides.forEach((key, snapshot) {
      final exists =
          resolved.any((section) => _sectionKey(section.id) == key);
      if (!exists) {
        resolved.add(snapshot);
      }
    });
    return resolved;
  }

  List<_SectionSnapshot> _composeSections() {
    final linesBySection = <String?, List<_InventoryBreakdownLine>>{};
    for (final entry in _inventory) {
      final itemId = entry.item['id']?.toString();
      if (itemId == null) continue;
      final totalInWarehouse = entry.warehouseSplit[widget.warehouseId] ?? 0;
      if (totalInWarehouse <= 0) continue;

      final perSection = entry.sectionSplit[widget.warehouseId];
      if (perSection == null || perSection.isEmpty) {
        linesBySection
            .putIfAbsent(InventoryEntry.unassignedSectionKey,
                () => <_InventoryBreakdownLine>[])
            .add(_InventoryBreakdownLine(
              itemId: itemId,
              name: entry.item['name']?.toString() ?? 'Article',
              sku: entry.item['sku']?.toString(),
              unit: entry.item['unit']?.toString(),
              qty: totalInWarehouse,
            ));
        continue;
      }

      var assigned = 0;
      perSection.forEach((sectionKey, qty) {
        if (qty <= 0) return;
        assigned += qty;
        linesBySection
            .putIfAbsent(sectionKey, () => <_InventoryBreakdownLine>[])
            .add(_InventoryBreakdownLine(
              itemId: itemId,
              name: entry.item['name']?.toString() ?? 'Article',
              sku: entry.item['sku']?.toString(),
              unit: entry.item['unit']?.toString(),
              qty: qty,
            ));
      });

      final remainder = totalInWarehouse - assigned;
      if (remainder > 0) {
        linesBySection
            .putIfAbsent(InventoryEntry.unassignedSectionKey,
                () => <_InventoryBreakdownLine>[])
            .add(_InventoryBreakdownLine(
              itemId: itemId,
              name: entry.item['name']?.toString() ?? 'Article',
              sku: entry.item['sku']?.toString(),
              unit: entry.item['unit']?.toString(),
              qty: remainder,
            ));
      }
    }

    final snapshots = <_SectionSnapshot>[];

    for (final section in _sections) {
      final id = section['id']?.toString();
      if (id == null) continue;
      final name = section['name']?.toString() ?? 'Section';
      final lines =
          linesBySection.remove(id) ?? const <_InventoryBreakdownLine>[];
      snapshots.add(
        _SectionSnapshot(
          id: id,
          label: name,
          lines: lines,
          deletable: true,
          renamable: true,
        ),
      );
    }

    final unassignedLines =
        linesBySection.remove(InventoryEntry.unassignedSectionKey);
    if (unassignedLines != null && unassignedLines.isNotEmpty) {
      snapshots.add(
        _SectionSnapshot(
          id: InventoryEntry.unassignedSectionKey,
          label: 'Sans section',
          lines: unassignedLines,
          deletable: false,
          renamable: false,
        ),
      );
    }

    if (linesBySection.isNotEmpty) {
      linesBySection.forEach((rawId, lines) {
        if (lines.isEmpty) return;
        snapshots.add(
          _SectionSnapshot(
            id: rawId,
            label: rawId == null ? 'Section inconnue' : 'Section $rawId',
            lines: lines,
            deletable: false,
            renamable: false,
          ),
        );
      });
    }

    if (_focusedSectionId != null) {
      snapshots.sort((a, b) {
        if (a.id == _focusedSectionId) return -1;
        if (b.id == _focusedSectionId) return 1;
        return 0;
      });
    }

    return snapshots;
  }

  Future<void> _handleCreateSection() async {
    final warehouse = _warehouse;
    if (warehouse == null || warehouse.isEmpty) return;
    final name = warehouse['name']?.toString() ?? 'Entrepôt';

    final created = await showDialog<Map<String, dynamic>?>(
      context: context,
      builder: (context) => _InventorySectionDialog(
        commands: widget.commands,
        companyId: widget.companyId,
        warehouseId: widget.warehouseId,
        warehouseName: name,
        describeError: widget.describeError,
      ),
    );

    if (created != null) {
      final sectionId = created['id']?.toString();
      await _handleFullRefresh();
      if (mounted) {
        setState(() {
          _focusedSectionId = sectionId;
        });
      }
      await _logInventoryEvent(
        event: 'section_created',
        entityId: sectionId == null
            ? _warehouseJournalEntityId
            : _sectionJournalEntityId(sectionId),
        note: created['name']?.toString(),
        payload: {
          'section_id': sectionId,
          'code': created['code'],
        },
      );
    }
  }

  Future<void> _handleDeleteSection(String sectionId) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Supprimer la section ?'),
        content: const Text(
          'La section sera supprimée et les pièces deviendront “Sans section”.',
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

    final section = _sections.firstWhere(
      (candidate) => candidate['id']?.toString() == sectionId,
      orElse: () => const <String, dynamic>{},
    );
    final sectionName = section['name']?.toString();

    setState(() => _processing = true);
    final result =
        await widget.commands.deleteInventorySection(sectionId: sectionId);
    setState(() => _processing = false);

    if (!result.ok) {
      _showSnack(
        widget.describeError(result.error) ??
            'Impossible de supprimer cette section.',
        error: true,
      );
      return;
    }

    await _logInventoryEvent(
      event: 'section_deleted',
      entityId: _sectionJournalEntityId(sectionId),
      note: sectionName,
      payload: {'section_id': sectionId},
    );
    await _handleFullRefresh();
    _showSnack('Section supprimée.');
  }

  Future<void> _handleAddPieces(String? sectionId) async {
    final request = await _promptAddPiecesDialog(sectionId: sectionId);
    if (request == null) return;
    final resolved =
        await _resolveItemForRequest(request, allowCreate: _isOnline);
    if (resolved == null) return;
    await _applyStockDelta(
      itemId: resolved.itemId,
      delta: request.qty,
      sectionId: sectionId,
      successMessage:
          resolved.created ? 'Pièce créée et ajoutée.' : 'Pièce ajoutée.',
      action: 'add_dialog',
      note: request.note,
      itemName: request.name,
      sku: request.sku,
      metadata: {
        'source': resolved.created ? 'new_item' : 'existing_item',
        'requested_qty': request.qty,
        if (request.sku != null && request.sku!.isNotEmpty)
          'sku': request.sku,
      },
    );
  }

  Future<void> _handleAdjustExisting(
    String? sectionId,
    _InventoryBreakdownLine line, {
    required bool increase,
  }) async {
    final qty = await _promptQuantityDialog(
      title: increase ? 'Ajouter ${line.name}' : 'Retirer ${line.name}',
      confirmLabel: increase ? 'Ajouter' : 'Retirer',
      max: increase ? null : line.qty,
    );
    if (qty == null) return;
    await _applyStockDelta(
      itemId: line.itemId,
      delta: increase ? qty : -qty,
      sectionId: sectionId,
      successMessage:
          increase ? 'Stock ajouté.' : 'Stock retiré de cette section.',
      action: increase ? 'manual_add' : 'manual_remove',
      itemName: line.name,
      sku: line.sku,
      metadata: {
        'trigger': 'adjust_dialog',
      },
    );
  }

  Future<void> _handleQuickAdjust(
    String? sectionId,
    _InventoryBreakdownLine line, {
    required bool increase,
  }) async {
    if (!increase && line.qty <= 0) {
      _showSnack('Quantité déjà à zéro.', error: true);
      return;
    }
    await _applyStockDelta(
      itemId: line.itemId,
      delta: increase ? 1 : -1,
      sectionId: sectionId,
      successMessage: increase ? 'Pièce ajoutée.' : 'Pièce retirée.',
      action: increase ? 'quick_add' : 'quick_remove',
      itemName: line.name,
      sku: line.sku,
      metadata: {
        'trigger': 'quick_tap',
      },
    );
  }

  Future<void> _handleMoveStock(
    String? fromSectionId,
    _InventoryBreakdownLine line,
  ) async {
    final destination = await _promptMoveDestination(line: line);
    if (destination == null) return;

    setState(() => _processing = true);
    final removeResult = await widget.commands.applyStockDelta(
      companyId: widget.companyId,
      itemId: line.itemId,
      warehouseId: widget.warehouseId,
      delta: -destination.qty,
      sectionId: _dbSectionId(fromSectionId),
    );

    if (!removeResult.ok) {
      setState(() => _processing = false);
      _showSnack(
        widget.describeError(removeResult.error) ??
            'Impossible de retirer la pièce de la section.',
        error: true,
      );
      return;
    }

    final addResult = await widget.commands.applyStockDelta(
      companyId: widget.companyId,
      itemId: line.itemId,
      warehouseId: destination.warehouseId,
      delta: destination.qty,
      sectionId: _dbSectionId(destination.sectionId),
    );

    if (!addResult.ok) {
      await widget.commands.applyStockDelta(
        companyId: widget.companyId,
        itemId: line.itemId,
        warehouseId: widget.warehouseId,
        delta: destination.qty,
        sectionId: _dbSectionId(fromSectionId),
      );
      setState(() => _processing = false);
      _showSnack(
        widget.describeError(addResult.error) ??
            'Déplacement impossible, opération annulée.',
        error: true,
      );
      return;
    }

    setState(() {
      _processing = false;
      _focusedSectionId = destination.warehouseId == widget.warehouseId
          ? destination.sectionId
          : null;
    });
    await _logInventoryEvent(
      event: 'stock_moved_out',
      entityId: _sectionJournalEntityId(fromSectionId),
      note: line.name,
      payload: {
        'item_id': line.itemId,
        'qty': destination.qty,
        'from_section_id': _dbSectionId(fromSectionId),
        'to_warehouse_id': destination.warehouseId,
        'to_section_id': _dbSectionId(destination.sectionId),
      },
    );
    await _logInventoryEvent(
      event: 'stock_moved_in',
      entityId: _sectionJournalEntityId(
        destination.sectionId,
        warehouseIdOverride: destination.warehouseId,
      ),
      note: line.name,
      warehouseIdOverride: destination.warehouseId,
      payload: {
        'item_id': line.itemId,
        'qty': destination.qty,
        'from_warehouse_id': widget.warehouseId,
        'from_section_id': _dbSectionId(fromSectionId),
      },
    );
    await _handleFullRefresh();
    _showSnack('Pièce déplacée.');
  }

  Future<void> _applyStockDelta({
    required String itemId,
    required int delta,
    required String? sectionId,
    required String successMessage,
    required String itemName,
    String? sku,
    String action = 'manual',
    String? note,
    Map<String, dynamic>? metadata,
  }) async {
    if (!_isOnline) {
      await _queueOfflineStockDelta(
        itemId: itemId,
        delta: delta,
        sectionId: sectionId,
        successMessage: successMessage,
        itemName: itemName,
        sku: sku,
        action: action,
        note: note,
        metadata: metadata,
      );
      return;
    }
    setState(() => _processing = true);
    final result = await widget.commands.applyStockDelta(
      companyId: widget.companyId,
      itemId: itemId,
      warehouseId: widget.warehouseId,
      delta: delta,
      sectionId: _dbSectionId(sectionId),
    );
    setState(() => _processing = false);

    if (!result.ok) {
      _showSnack(
        widget.describeError(result.error) ?? 'Opération impossible.',
        error: true,
      );
      return;
    }

    final dbSectionId = _dbSectionId(sectionId);
    final newQty = result.data ?? 0;
    await _handleFullRefresh();
    await _logInventoryEvent(
      event: 'stock_delta',
      entityId: _sectionJournalEntityId(sectionId),
      note: note,
      payload: {
        'item_id': itemId,
        'delta': delta,
        'new_qty': newQty,
        'section_id': dbSectionId,
        'action': action,
        if (metadata != null) ...metadata,
      },
    );
    _showSnack(successMessage);
  }

  Future<void> _queueOfflineStockDelta({
    required String itemId,
    required int delta,
    required String? sectionId,
    required String successMessage,
    required String itemName,
    String? sku,
    String action = 'manual',
    String? note,
    Map<String, dynamic>? metadata,
  }) async {
    await OfflineActionsService.instance.enqueue(
      OfflineActionTypes.inventoryStockDelta,
      {
        'company_id': widget.companyId,
        'warehouse_id': widget.warehouseId,
        'item_id': itemId,
        'delta': delta,
        'section_id': _dbSectionId(sectionId),
        'note': note,
        'action': action,
        'metadata': metadata,
        'event': 'stock_delta',
      },
    );
    _applyLocalStockDelta(
      itemId: itemId,
      itemName: itemName,
      delta: delta,
      sectionId: sectionId,
      sku: sku,
    );
    _showSnack('$successMessage (hors ligne).');
  }

  void _applyLocalStockDelta({
    required String itemId,
    required String itemName,
    required int delta,
    required String? sectionId,
    String? sku,
  }) {
    final key = _sectionKey(sectionId);
    final base = _offlineSectionOverrides[key] ?? _resolveBaseSection(sectionId);
    final lines = base.lines.map((line) => line).toList();
    final index = lines.indexWhere((line) => line.itemId == itemId);
    if (index >= 0) {
      final line = lines[index];
      final newQty = line.qty + delta;
      if (newQty <= 0) {
        lines.removeAt(index);
      } else {
        lines[index] = line.copyWith(qty: newQty);
      }
    } else if (delta > 0) {
      lines.add(
        _InventoryBreakdownLine(
          itemId: itemId,
          name: itemName,
          sku: sku,
          qty: delta,
          unit: null,
        ),
      );
    }
    _offlineSectionOverrides[key] =
        base.copyWith(lines: List<_InventoryBreakdownLine>.from(lines));
    setState(() {});
  }

  _SectionSnapshot _resolveBaseSection(String? sectionId) {
    final key = _sectionKey(sectionId);
    final sections = _composeSections();
    final match = sections.firstWhere(
      (section) => _sectionKey(section.id) == key,
      orElse: () => _SectionSnapshot(
        id: sectionId ?? InventoryEntry.unassignedSectionKey,
        label: sectionId == null ? 'Sans section' : 'Section',
        lines: const <_InventoryBreakdownLine>[],
        deletable: sectionId != null,
        renamable: sectionId != null,
      ),
    );
    return match;
  }

  Future<void> _queueOfflineDeleteItem(
    _InventoryBreakdownLine line, {
    required String? sectionId,
  }) async {
    await OfflineActionsService.instance.enqueue(
      OfflineActionTypes.inventoryDeleteItem,
      {
        'company_id': widget.companyId,
        'warehouse_id': widget.warehouseId,
        'item_id': line.itemId,
        'section_id': _dbSectionId(sectionId),
        'note': line.name,
      },
    );
    _applyLocalStockDelta(
      itemId: line.itemId,
      itemName: line.name,
      delta: -line.qty,
      sectionId: sectionId,
      sku: line.sku,
    );
    _showSnack('Pièce supprimée (hors ligne).');
  }

  Future<void> _handleDeleteItem(
    _InventoryBreakdownLine line, {
    required String? sectionId,
  }) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Supprimer la pièce ?'),
        content: Text(
          '“La pièce ${line.name}” sera supprimée définitivement de l’inventaire.',
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
      await _queueOfflineDeleteItem(
        line,
        sectionId: sectionId,
      );
      return;
    }

    setState(() => _processing = true);
    final result = await widget.commands.deleteItem(
      companyId: widget.companyId,
      itemId: line.itemId,
    );
    setState(() => _processing = false);

    if (!result.ok) {
      _showSnack(
        widget.describeError(result.error) ??
            'Impossible de supprimer cette pièce.',
        error: true,
      );
      return;
    }

    await _handleFullRefresh();
    await _logInventoryEvent(
      event: 'item_deleted',
      entityId: _sectionJournalEntityId(sectionId),
      note: line.name,
      payload: {
        'item_id': line.itemId,
        'section_id': _dbSectionId(sectionId),
      },
    );
    _showSnack('Pièce supprimée.');
  }

  Future<void> _handleFullRefresh() async {
    await widget.onRefresh();
    if (mounted) {
      setState(() {
        if (_isOnline) {
          _offlineSectionOverrides.clear();
        }
      });
    }
  }

  Future<void> _showSectionDetails(_SectionSnapshot snapshot) async {
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => _SectionDetailPage(
          parent: this,
          initialSnapshot: snapshot,
        ),
      ),
    );
  }

  Future<void> _showSectionActions(
    _SectionSnapshot section, {
    VoidCallback? onChanged,
  }) async {
    if (!section.renamable && !section.deletable) return;
    await showModalBottomSheet<void>(
      context: context,
      builder: (context) {
        return SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (section.renamable && section.id != null)
                ListTile(
                  leading: const Icon(Icons.edit),
                  title: const Text('Renommer la section'),
                  onTap: () async {
                    Navigator.of(context).pop();
                    await _handleRenameSection(section);
                    onChanged?.call();
                  },
                ),
              if (section.deletable && section.id != null)
                ListTile(
                  leading: const Icon(Icons.delete_outline, color: Colors.red),
                  title: const Text('Supprimer'),
                  onTap: () async {
                    Navigator.of(context).pop();
                    await _handleDeleteSection(section.id!);
                    onChanged?.call();
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

  Future<void> _handleRenameSection(_SectionSnapshot section) async {
    final sectionId = section.id;
    if (sectionId == null) return;
    final raw = _sectionDataById(sectionId);
    final currentName = raw?['name']?.toString() ?? section.label;
    final currentCode = raw?['code']?.toString() ?? '';
    final formKey = GlobalKey<FormState>();
    final nameCtrl = TextEditingController(text: currentName);
    final codeCtrl = TextEditingController(text: currentCode);

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text('Renommer la section'),
          content: Form(
            key: formKey,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextFormField(
                  controller: nameCtrl,
                  decoration: const InputDecoration(labelText: 'Nom'),
                  validator: (value) =>
                      value == null || value.trim().isEmpty
                          ? 'Nom requis'
                          : null,
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: codeCtrl,
                  decoration:
                      const InputDecoration(labelText: 'Code (optionnel)'),
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
              child: const Text('Enregistrer'),
            ),
          ],
        );
      },
    );

    if (confirmed != true) {
      nameCtrl.dispose();
      codeCtrl.dispose();
      return;
    }

    setState(() => _processing = true);
    final result = await widget.commands.updateInventorySection(
      sectionId: sectionId,
      patch: {
        'name': nameCtrl.text.trim(),
        'code':
            codeCtrl.text.trim().isEmpty ? null : codeCtrl.text.trim(),
      },
    );
    setState(() => _processing = false);
    nameCtrl.dispose();
    codeCtrl.dispose();

    if (!result.ok) {
      _showSnack(
        widget.describeError(result.error) ?? 'Impossible de renommer.',
        error: true,
      );
      return;
    }

    _showSnack('Section renommée.');
    await _handleFullRefresh();
  }

  Future<String?> _promptSectionChoice() async {
    final options = <_SectionOption>[
      ..._sections
          .map(
            (section) => _SectionOption(
              id: section['id']?.toString() ?? '',
              label: section['name']?.toString() ?? 'Section',
            ),
          )
          .where((option) => option.id.isNotEmpty),
      const _SectionOption(
        id: InventoryEntry.unassignedSectionKey,
        label: 'Sans section',
      ),
    ];

    if (options.isEmpty) {
      return InventoryEntry.unassignedSectionKey;
    }

    return showDialog<String?>(
      context: context,
      builder: (context) => SimpleDialog(
        title: const Text('Choisir une section'),
        children: [
          for (final option in options)
            SimpleDialogOption(
              onPressed: () => Navigator.of(context).pop(option.id),
              child: Text(option.label),
            ),
          SimpleDialogOption(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Annuler'),
          ),
        ],
      ),
    );
  }

  Future<_MoveDestination?> _promptMoveDestination({
    required _InventoryBreakdownLine line,
  }) async {
    return showDialog<_MoveDestination>(
      context: context,
      builder: (context) => _MoveItemDialog(
        warehouses: _allWarehouses,
        currentWarehouseId: widget.warehouseId,
        maxQty: line.qty,
        buildSectionsForWarehouse: _sectionOptionsForWarehouse,
      ),
    );
  }

  List<_SectionOption> _sectionTargets(String? exclude) {
    final options = _sectionOptionsForWarehouse(widget.warehouseId);
    return options.where((option) => option.id != exclude).toList();
  }

  bool _hasMoveDestinations(String? fromSectionId) {
    if (_sectionTargets(fromSectionId).isNotEmpty) return true;
    return _allWarehouses.any(
      (warehouse) => warehouse['id']?.toString() != widget.warehouseId,
    );
  }

  List<_SectionOption> _sectionOptionsForWarehouse(String warehouseId) {
    final warehouse = _allWarehouses.firstWhere(
      (candidate) => candidate['id']?.toString() == warehouseId,
      orElse: () => const <String, dynamic>{},
    );
    final sections = (warehouse['sections'] as List?)
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

    final hasSansSection = options.any(
      (option) => option.id == InventoryEntry.unassignedSectionKey,
    );
    if (!hasSansSection) {
      options.add(
        const _SectionOption(
          id: InventoryEntry.unassignedSectionKey,
          label: 'Sans section',
        ),
      );
    }
    return options;
  }

  Future<_AddStockRequest?> _promptAddPiecesDialog({
    required String? sectionId,
  }) async {
    return showDialog<_AddStockRequest>(
      context: context,
      builder: (context) => const _AddStockDialog(),
    );
  }

  Future<int?> _promptQuantityDialog({
    required String title,
    required String confirmLabel,
    int? max,
  }) async {
    final controller = TextEditingController(text: '1');
    final formKey = GlobalKey<FormState>();
    final result = await showDialog<int>(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: Text(title),
          content: Form(
            key: formKey,
            child: TextFormField(
              controller: controller,
              keyboardType: TextInputType.number,
              decoration: InputDecoration(
                labelText: max == null ? 'Quantité' : 'Quantité (max $max)',
              ),
              validator: (value) {
                final parsed = int.tryParse(value ?? '');
                if (parsed == null || parsed <= 0) {
                  return 'Quantité invalide';
                }
                if (max != null && parsed > max) {
                  return 'Maximum $max';
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
                if (!formKey.currentState!.validate()) return;
                Navigator.of(context).pop(int.parse(controller.text.trim()));
              },
              child: Text(confirmLabel),
            ),
          ],
        );
      },
    );
    controller.dispose();
    return result;
  }

  Future<void> _logInventoryEvent({
    required String event,
    String? entityId,
    String? note,
    Map<String, dynamic>? payload,
    String? warehouseIdOverride,
  }) async {
    await widget.commands.logJournalEntry(
      companyId: widget.companyId,
      scope: 'inventory',
      entityId: entityId ?? _warehouseJournalEntityId,
      event: event,
      note: note,
      payload: {
        'warehouse_id': warehouseIdOverride ?? widget.warehouseId,
        if (payload != null) ...payload,
      },
    );
  }

  void _showSnack(String message, {bool error = false}) {
    if (!mounted) return;
    final theme = Theme.of(context);
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor:
            error ? theme.colorScheme.error : theme.colorScheme.primary,
      ),
    );
  }

  String? _dbSectionId(String? sectionId) {
    if (sectionId == null || sectionId == InventoryEntry.unassignedSectionKey) {
      return null;
    }
    return sectionId;
  }

  String _sectionKey(String? sectionId) {
    return sectionId ?? InventoryEntry.unassignedSectionKey;
  }

  Future<_ResolvedItem?> _resolveItemForRequest(
    _AddStockRequest request, {
    bool allowCreate = true,
  }) async {
    final name = request.name.trim();
    if (name.isEmpty) {
      _showSnack('Nom requis.', error: true);
      return null;
    }
    final normalized = name.toLowerCase();
    for (final entry in _inventory) {
      final entryName = entry.item['name']?.toString();
      final entryId = entry.item['id']?.toString();
      if (entryName != null &&
          entryId != null &&
          entryName.trim().toLowerCase() == normalized) {
        return _ResolvedItem(itemId: entryId, created: false);
      }
    }

    if (!allowCreate) {
      _showSnack(
        'Connexion requise pour créer une nouvelle pièce.',
        error: true,
      );
      return null;
    }

    final result = await widget.commands.createItem(
      companyId: widget.companyId,
      name: name,
      sku: request.sku,
    );
    if (!result.ok) {
      _showSnack(
        widget.describeError(result.error) ??
            'Impossible de créer cette pièce.',
        error: true,
      );
      return null;
    }
    final id = result.data?['id']?.toString();
    if (id == null || id.isEmpty) {
      _showSnack('Pièce créée mais identifiant manquant.', error: true);
      return null;
    }
    return _ResolvedItem(itemId: id, created: true);
  }
}

class _SectionInventoryCard extends StatelessWidget {
  const _SectionInventoryCard({
    required this.data,
    required this.busy,
    required this.onOpen,
    this.onManage,
  });

  final _SectionSnapshot data;
  final bool busy;
  final VoidCallback onOpen;
  final VoidCallback? onManage;

  @override
  Widget build(BuildContext context) {
    final total = data.totalQty;
    final title = data.label;
    final canManage = onManage != null;
    return Card(
      margin: const EdgeInsets.only(bottom: 16),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: busy ? null : onOpen,
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
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
                          style: Theme.of(context)
                              .textTheme
                              .titleMedium
                              ?.copyWith(fontWeight: FontWeight.w700),
                        ),
                        const SizedBox(height: 4),
                        Text('$total pièce(s)'),
                      ],
                    ),
                  ),
                  if (canManage)
                    IconButton(
                      onPressed: busy ? null : onManage,
                      icon: const Icon(Icons.more_horiz),
                      tooltip: 'Gérer la section',
                    ),
                ],
              ),
              const SizedBox(height: 12),
              Text(
                data.lines.isEmpty
                    ? 'Aucune pièce dans cette section.'
                    : '${data.lines.length} article(s)',
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _SectionDetailPage extends StatefulWidget {
  const _SectionDetailPage({
    required this.parent,
    required this.initialSnapshot,
  });

  final _WarehouseInventoryPageState parent;
  final _SectionSnapshot initialSnapshot;

  @override
  State<_SectionDetailPage> createState() => _SectionDetailPageState();
}

class _SectionDetailPageState extends State<_SectionDetailPage> {
  late String? _sectionId;
  late _SectionSnapshot _lastSnapshot;
  final TextEditingController _searchCtrl = TextEditingController();

  @override
  void initState() {
    super.initState();
    _sectionId = widget.initialSnapshot.id;
    _lastSnapshot = widget.initialSnapshot;
    _searchCtrl.addListener(() => setState(() {}));
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  _SectionSnapshot _currentSection() {
    final sections = widget.parent._buildSections();
    final match = sections.firstWhere(
      (candidate) => candidate.id == _sectionId,
      orElse: () => _lastSnapshot,
    );
    _lastSnapshot = match;
    return match;
  }

  @override
  Widget build(BuildContext context) {
    final section = _currentSection();
    final search = _searchCtrl.text.trim().toLowerCase();
    final lines = search.isEmpty
        ? section.lines
        : section.lines
            .where((line) =>
                line.name.toLowerCase().contains(search) ||
                (line.sku?.toLowerCase().contains(search) ?? false))
            .toList();
    final processing = widget.parent._processing;
    final canMove = widget.parent._hasMoveDestinations(section.id);

    return Scaffold(
      appBar: AppBar(
        title: Text(section.label),
        actions: [
          if (section.renamable || section.deletable)
            IconButton(
              tooltip: 'Gérer la section',
              icon: const Icon(Icons.more_horiz),
              onPressed: processing
                  ? null
                  : () async {
                      await widget.parent._showSectionActions(
                        section,
                        onChanged: () => setState(() {}),
                      );
                    },
            ),
          if (widget.parent.widget.onShowJournal != null)
            IconButton(
              tooltip: 'Journal',
              icon: const Icon(Icons.history),
              onPressed: () =>
                  widget.parent._openSectionJournal(section.id),
            ),
        ],
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: processing
            ? null
            : () async {
                await widget.parent._handleAddPieces(section.id);
                if (mounted) setState(() {});
              },
        tooltip: 'Ajouter une pièce',
        child: const Icon(Icons.add),
      ),
      body: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              '${section.totalQty} pièce(s)',
              style: Theme.of(context)
                  .textTheme
                  .titleMedium
                  ?.copyWith(fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _searchCtrl,
              decoration: InputDecoration(
                hintText: 'Rechercher une pièce',
                prefixIcon: const Icon(Icons.search),
                suffixIcon: _searchCtrl.text.isEmpty
                    ? null
                    : IconButton(
                        icon: const Icon(Icons.clear),
                        onPressed: () => _searchCtrl.clear(),
                      ),
                border: const OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 16),
            Expanded(
              child: lines.isEmpty
                  ? const Center(
                      child: Text('Aucune pièce trouvée pour cette section.'),
                    )
                  : ListView.separated(
                      itemCount: lines.length,
                      separatorBuilder: (_, __) => const Divider(height: 1),
                      itemBuilder: (context, index) {
                        final line = lines[index];
                        return _InventoryLineRow(
                          line: line,
                          busy: processing,
                          onIncrement: () async {
                            await widget.parent._handleQuickAdjust(
                              section.id,
                              line,
                              increase: true,
                            );
                            if (mounted) setState(() {});
                          },
                          onDecrement: () async {
                            await widget.parent._handleQuickAdjust(
                              section.id,
                              line,
                              increase: false,
                            );
                            if (mounted) setState(() {});
                          },
                          onDelete: () async {
                            await widget.parent._handleDeleteItem(
                              line,
                              sectionId: section.id,
                            );
                            if (mounted) setState(() {});
                          },
                          onMove: canMove
                              ? () async {
                                  await widget.parent._handleMoveStock(
                                    section.id,
                                    line,
                                  );
                                  if (mounted) setState(() {});
                                }
                              : null,
                        );
                      },
                    ),
            ),
            if (section.deletable)
              TextButton.icon(
                onPressed: processing
                    ? null
                    : () async {
                        await widget.parent._handleDeleteSection(section.id!);
                        if (mounted) Navigator.of(context).pop();
                      },
                icon: const Icon(Icons.delete_outline),
                label: const Text('Supprimer cette section'),
                style: TextButton.styleFrom(foregroundColor: Colors.red),
              ),
          ],
        ),
      ),
    );
  }
}


class _InventoryLineRow extends StatelessWidget {
  const _InventoryLineRow({
    required this.line,
    required this.busy,
    this.onIncrement,
    this.onDecrement,
    this.onMove,
    this.onDelete,
  });

  final _InventoryBreakdownLine line;
  final bool busy;
  final VoidCallback? onIncrement;
  final VoidCallback? onDecrement;
  final VoidCallback? onMove;
  final VoidCallback? onDelete;

  @override
  Widget build(BuildContext context) {
    final subtitleParts = <String>[];
    if (line.sku != null && line.sku!.isNotEmpty) {
      subtitleParts.add('SKU ${line.sku}');
    }
    if (line.unit != null && line.unit!.isNotEmpty) {
      subtitleParts.add(line.unit!);
    }
    return ListTile(
      contentPadding: EdgeInsets.zero,
      title: Text(
        line.name,
        style: const TextStyle(fontWeight: FontWeight.w600),
      ),
      subtitle: subtitleParts.isEmpty ? null : Text(subtitleParts.join(' • ')),
      trailing: Wrap(
        spacing: 4,
        children: [
          IconButton(
            tooltip: 'Ajouter',
            onPressed: busy ? null : onIncrement,
            icon: const Icon(Icons.add),
          ),
          IconButton(
            tooltip: 'Retirer',
            onPressed: busy ? null : onDecrement,
            icon: const Icon(Icons.remove_circle_outline),
          ),
          IconButton(
            tooltip: 'Déplacer',
            onPressed: busy ? null : onMove,
            icon: const Icon(Icons.compare_arrows),
          ),
          IconButton(
            tooltip: 'Supprimer',
            onPressed: busy ? null : onDelete,
            icon: const Icon(Icons.delete_outline),
          ),
        ],
      ),
      leading: CircleAvatar(
        backgroundColor: AppColors.surfaceAlt,
        child: Text(
          line.qty.toString(),
          style: const TextStyle(fontWeight: FontWeight.w700),
        ),
      ),
    );
  }
}

class _SummaryMetric extends StatelessWidget {
  const _SummaryMetric({
    required this.label,
    required this.value,
    required this.icon,
  });

  final String label;
  final String value;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 150,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          CircleAvatar(
            backgroundColor: AppColors.primary.withValues(alpha: 0.1),
            child: Icon(icon, color: AppColors.primary),
          ),
          const SizedBox(height: 8),
          Text(
            value,
            style: Theme.of(context)
                .textTheme
                .titleMedium
                ?.copyWith(fontWeight: FontWeight.w700),
          ),
          Text(label),
        ],
      ),
    );
  }
}

class _AddStockDialog extends StatefulWidget {
  const _AddStockDialog();

  @override
  State<_AddStockDialog> createState() => _AddStockDialogState();
}

class _AddStockDialogState extends State<_AddStockDialog> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _nameCtrl;
  late final TextEditingController _skuCtrl;
  late final TextEditingController _noteCtrl;
  int _qty = 1;

  @override
  void initState() {
    super.initState();
    _nameCtrl = TextEditingController();
    _skuCtrl = TextEditingController();
    _noteCtrl = TextEditingController();
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    _skuCtrl.dispose();
    _noteCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Ajouter des pièces'),
      content: Form(
        key: _formKey,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextFormField(
                controller: _nameCtrl,
                decoration: const InputDecoration(
                  labelText: 'Nom de la pièce',
                ),
                validator: (value) {
                  if (value == null || value.trim().isEmpty) {
                    return 'Nom requis';
                  }
                  return null;
                },
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _skuCtrl,
                decoration: const InputDecoration(
                  labelText: 'SKU (optionnel)',
                ),
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _noteCtrl,
                decoration: const InputDecoration(
                  labelText: 'Note (optionnel)',
                ),
                minLines: 2,
                maxLines: 3,
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  const Text('Quantité'),
                  const Spacer(),
                  IconButton(
                    onPressed: _qty > 1 ? _decrementQty : null,
                    icon: const Icon(Icons.remove),
                  ),
                  Text(
                    '$_qty',
                    style: const TextStyle(
                      fontWeight: FontWeight.w600,
                      fontSize: 18,
                    ),
                  ),
                  IconButton(
                    onPressed: _incrementQty,
                    icon: const Icon(Icons.add),
                  ),
                ],
              ),
            ],
          ),
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
              _AddStockRequest(
                name: _nameCtrl.text.trim(),
                sku: _skuCtrl.text.trim().isEmpty ? null : _skuCtrl.text.trim(),
                note: _noteCtrl.text.trim().isEmpty
                    ? null
                    : _noteCtrl.text.trim(),
                qty: _qty,
              ),
            );
          },
          child: const Text('Ajouter'),
        ),
      ],
    );
  }

  void _incrementQty() {
    setState(() => _qty++);
  }

  void _decrementQty() {
    if (_qty <= 1) return;
    setState(() => _qty--);
  }
}

class _MoveItemDialog extends StatefulWidget {
  const _MoveItemDialog({
    required this.warehouses,
    required this.currentWarehouseId,
    required this.maxQty,
    required this.buildSectionsForWarehouse,
  });

  final List<Map<String, dynamic>> warehouses;
  final String currentWarehouseId;
  final int maxQty;
  final List<_SectionOption> Function(String warehouseId)
      buildSectionsForWarehouse;

  @override
  State<_MoveItemDialog> createState() => _MoveItemDialogState();
}

class _MoveItemDialogState extends State<_MoveItemDialog> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _qtyCtrl;
  late String _selectedWarehouseId;
  late String _selectedSectionId;
  late List<_SectionOption> _sections;

  @override
  void initState() {
    super.initState();
    _qtyCtrl = TextEditingController(text: '${widget.maxQty}');
    _selectedWarehouseId = widget.currentWarehouseId;
    _sections = widget.buildSectionsForWarehouse(_selectedWarehouseId);
    _selectedSectionId = _sections.isNotEmpty
        ? _sections.first.id
        : InventoryEntry.unassignedSectionKey;
  }

  @override
  void dispose() {
    _qtyCtrl.dispose();
    super.dispose();
  }

  void _updateSections(String warehouseId) {
    _sections = widget.buildSectionsForWarehouse(warehouseId);
    _selectedSectionId = _sections.isNotEmpty
        ? _sections.first.id
        : InventoryEntry.unassignedSectionKey;
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Déplacer la pièce'),
      content: Form(
        key: _formKey,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              DropdownButtonFormField<String>(
                value: _selectedWarehouseId,
                decoration:
                    const InputDecoration(labelText: 'Entrepôt de destination'),
                items: widget.warehouses
                    .map(
                      (warehouse) => DropdownMenuItem<String>(
                        value: warehouse['id']?.toString(),
                        child: Text(
                          warehouse['name']?.toString() ?? 'Entrepôt',
                        ),
                      ),
                    )
                    .where((item) => item.value != null)
                    .cast<DropdownMenuItem<String>>()
                    .toList(),
                onChanged: (value) {
                  if (value == null) return;
                  setState(() {
                    _selectedWarehouseId = value;
                    _updateSections(value);
                  });
                },
              ),
              const SizedBox(height: 12),
              DropdownButtonFormField<String>(
                value: _selectedSectionId,
                decoration: const InputDecoration(labelText: 'Section cible'),
                items: _sections
                    .map(
                      (option) => DropdownMenuItem<String>(
                        value: option.id,
                        child: Text(option.label),
                      ),
                    )
                    .toList(),
                onChanged: (value) {
                  if (value == null) return;
                  setState(() => _selectedSectionId = value);
                },
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _qtyCtrl,
                keyboardType: TextInputType.number,
                decoration: InputDecoration(
                  labelText: 'Quantité (max ${widget.maxQty})',
                ),
                validator: (value) {
                  final parsed = int.tryParse(value ?? '');
                  if (parsed == null || parsed <= 0) {
                    return 'Quantité invalide';
                  }
                  if (parsed > widget.maxQty) {
                    return 'Maximum ${widget.maxQty}';
                  }
                  return null;
                },
              ),
            ],
          ),
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
              _MoveDestination(
                warehouseId: _selectedWarehouseId,
                sectionId: _selectedSectionId,
                qty: int.parse(_qtyCtrl.text.trim()),
              ),
            );
          },
          child: const Text('Déplacer'),
        ),
      ],
    );
  }
}

class _SectionSnapshot {
  const _SectionSnapshot({
    required this.id,
    required this.label,
    required this.lines,
    required this.deletable,
    required this.renamable,
  });

  final String? id;
  final String label;
  final List<_InventoryBreakdownLine> lines;
  final bool deletable;
  final bool renamable;

  int get totalQty => lines.fold<int>(
      0, (previousValue, element) => previousValue + element.qty);

  _SectionSnapshot copyWith({
    String? label,
    List<_InventoryBreakdownLine>? lines,
    bool? deletable,
    bool? renamable,
  }) {
    return _SectionSnapshot(
      id: id,
      label: label ?? this.label,
      lines: lines ?? this.lines,
      deletable: deletable ?? this.deletable,
      renamable: renamable ?? this.renamable,
    );
  }
}

class _AddStockRequest {
  const _AddStockRequest({
    required this.name,
    required this.qty,
    this.sku,
    this.note,
  });
  final String name;
  final int qty;
  final String? sku;
  final String? note;
}

class _SectionOption {
  const _SectionOption({required this.id, required this.label});
  final String id;
  final String label;
}

class _ResolvedItem {
  const _ResolvedItem({required this.itemId, required this.created});
  final String itemId;
  final bool created;
}

class _MoveDestination {
  const _MoveDestination({
    required this.warehouseId,
    required this.sectionId,
    required this.qty,
  });

  final String warehouseId;
  final String? sectionId;
  final int qty;
}
