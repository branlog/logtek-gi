part of 'company_gate.dart';

// ---------------------------------------------------------------------------
// Home tab
// ---------------------------------------------------------------------------

enum _QuickAction {
  pickItem,
  placeOrder,
  logFuel,
  addMechanicTask,
}

class _HomeTab extends StatelessWidget {
  const _HomeTab({
    required this.overview,
    required this.warehouses,
    required this.inventory,
    required this.equipment,
    required this.userProfile,
    required this.lowStockItems,
    required this.onQuickAction,
    this.onViewLowStock,
  });

  final CompanyOverview? overview;
  final List<Map<String, dynamic>> warehouses;
  final List<InventoryEntry> inventory;
  final List<Map<String, dynamic>> equipment;
  final List<InventoryEntry> lowStockItems;
  final Map<String, dynamic>? userProfile;
  final void Function(_QuickAction action) onQuickAction;
  final VoidCallback? onViewLowStock;

  List<_MechanicTaskWithEquipment> _collectMechanicTasks() {
    final tasks = <_MechanicTaskWithEquipment>[];
    for (final equip in equipment) {
      final meta = equip['meta'];
      if (meta is! Map) continue;
      final rawTasks = meta['mechanic_tasks'];
      if (rawTasks is! List) continue;
      for (final raw in rawTasks.whereType<Map>()) {
        final task = _MechanicTask.fromMap(raw);
        tasks.add(
          _MechanicTaskWithEquipment(
            task: task,
            equipmentName: equip['name']?.toString() ?? 'Équipement',
            equipmentId: equip['id']?.toString(),
          ),
        );
      }
    }
    tasks.sort((a, b) => a.task.dueDate.compareTo(b.task.dueDate));
    return tasks;
  }

  void _showTaskListSheet(
    BuildContext context,
    List<_MechanicTaskWithEquipment> tasks, {
    bool overdueOnly = false,
  }) {
    final filtered =
        overdueOnly ? tasks.where((task) => task.isOverdue).toList() : tasks;

    _showWhiteSheet(
      context,
      title: overdueOnly ? 'Tâches en retard' : 'Tâches actives',
      subtitle: overdueOnly
          ? 'Liste des tâches à traiter en priorité.'
          : 'Toutes les tâches avec leur équipement associé.',
      child: filtered.isEmpty
          ? const Padding(
              padding: EdgeInsets.only(bottom: 12),
              child: Text('Aucune tâche à afficher.'),
            )
          : DraggableScrollableSheet(
              expand: false,
              initialChildSize: 0.6,
              maxChildSize: 0.9,
              minChildSize: 0.4,
              builder: (context, controller) {
                return ListView.separated(
                  controller: controller,
                  itemBuilder: (context, index) {
                    final entry = filtered[index];
                    final due = entry.task.dueDate;
                    final dueLabel =
                        '${due.day.toString().padLeft(2, '0')}/${due.month.toString().padLeft(2, '0')}/${due.year}';
                    final overdue = entry.isOverdue;
                    return ListTile(
                      contentPadding:
                          const EdgeInsets.symmetric(horizontal: 4),
                      leading: Icon(
                        overdue
                            ? Icons.warning_amber_rounded
                            : Icons.build_circle_outlined,
                        color:
                            overdue ? Colors.red.shade700 : AppColors.primary,
                      ),
                      title: Text(entry.task.title),
                      subtitle: Text(
                        '${entry.equipmentName} • Échéance : $dueLabel',
                      ),
                      trailing: overdue
                          ? const _Badge(
                              label: 'En retard',
                              color: Colors.red,
                            )
                          : null,
                    );
                  },
                  separatorBuilder: (_, __) =>
                      const Divider(height: 12, thickness: 0.6),
                  itemCount: filtered.length,
                );
              },
            ),
    );
  }

  void _showEquipmentSheet(BuildContext context) {
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

    final grouped = <String, List<Map<String, dynamic>>>{};
    for (final raw in equipment) {
      final item = raw is Map
          ? Map<String, dynamic>.from(raw as Map)
          : <String, dynamic>{};
      final category = _categoryFor(item);
      grouped.putIfAbsent(category, () => <Map<String, dynamic>>[]).add(item);
    }

    final orderedCategories = <String>[
      'Abatteuse',
      'Débardeur',
      'Camion transporteur',
      'Camion pick-up',
      'Autres',
    ].where((cat) => grouped[cat]?.isNotEmpty == true).toList();

    _showWhiteSheet(
      context,
      title: 'Équipements',
      subtitle: 'Aperçu rapide des équipements enregistrés.',
      child: SizedBox(
        height: 320,
        child: equipment.isEmpty
            ? const Center(child: Text('Aucun équipement.'))
            : ListView.builder(
                itemCount: orderedCategories.length,
                itemBuilder: (context, index) {
                  final category = orderedCategories[index];
                  final items = grouped[category] ?? const <Map<String, dynamic>>[];
                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Padding(
                        padding:
                            const EdgeInsets.symmetric(vertical: 8, horizontal: 4),
                        child: Text(
                          category,
                          style: Theme.of(context)
                              .textTheme
                              .titleMedium
                              ?.copyWith(fontWeight: FontWeight.w700),
                        ),
                      ),
                      ...items.map((item) {
                        final name = item['name']?.toString() ?? 'Équipement';
                        final code = item['code']?.toString();
                        return Column(
                          children: [
                            ListTile(
                              leading: const Icon(Icons.build_outlined),
                              title: Text(name),
                              subtitle: code != null && code.isNotEmpty
                                  ? Text(code)
                                  : null,
                            ),
                            const Divider(height: 1, thickness: 0.4),
                          ],
                        );
                      }),
                    ],
                  );
                },
              ),
      ),
    );
  }

  void _showMembersSheet(BuildContext context) {
    final members = overview?.members ?? const <dynamic>[];
    _showWhiteSheet(
      context,
      title: 'Membres',
      subtitle: 'Personnes actives dans l’entreprise.',
      child: SizedBox(
        height: 320,
        child: members.isEmpty
            ? const Center(child: Text('Aucun membre.'))
            : ListView.separated(
                itemCount: members.length,
                separatorBuilder: (_, __) =>
                    const Divider(height: 12, thickness: 0.6),
                itemBuilder: (context, index) {
                  final member = members[index];
                  final memberMap =
                      member is Map ? member : <String, dynamic>{};
                  final user = memberMap['user'] is Map
                      ? Map<String, dynamic>.from(memberMap['user'] as Map)
                      : null;
                  final name = user?['full_name']?.toString() ??
                      memberMap['full_name']?.toString() ??
                      memberMap['display_name']?.toString() ??
                      memberMap['name']?.toString();
                  final email = user?['email']?.toString() ??
                      memberMap['email']?.toString();
                  final role = memberMap['role']?.toString();
                  final displayName = name?.isNotEmpty == true
                      ? name!
                      : (email?.isNotEmpty == true ? email! : 'Membre');
                  return ListTile(
                    leading: const Icon(Icons.person_outline),
                    title: Text(displayName),
                    subtitle: () {
                      final subtitleParts = <String>[];
                      if (role != null && role.isNotEmpty) {
                        subtitleParts.add(role);
                      }
                      if (email != null && email.isNotEmpty) {
                        subtitleParts.add(email);
                      }
                      if (subtitleParts.isEmpty) return null;
                      return Text(subtitleParts.join(' • '));
                    }(),
                  );
                },
              ),
      ),
    );
  }

  void _showFuelSheet(BuildContext context, double avg) {
    _showWhiteSheet(
      context,
      title: 'Carburant / jour',
      subtitle: 'Moyenne calculée sur 30 jours (logs diesel).',
      child: Padding(
        padding: const EdgeInsets.only(bottom: 12),
        child: Text(
          avg > 0
              ? 'Consommation moyenne : ${avg.toStringAsFixed(1)} L par jour basé sur les entrées “Carburant”.'
              : 'Aucune donnée de carburant disponible.',
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final user = Supabase.instance.client.auth.currentUser;
    final firstName = (userProfile?['first_name'] as String?)?.trim();
    final greetingName = firstName?.isNotEmpty == true
        ? firstName!
        : user?.email?.split('@').first ?? 'Utilisateur';

    final memberCount = overview?.members.length ?? 0;
    final equipmentCount = equipment.length;
    final fuelAverage = _computeAverageFuelPerDay(equipment);
    final taskStats = _computeTaskOverview(equipment);
    final mechanicTasks = _collectMechanicTasks();

    final quickActions = <(_QuickAction, String, IconData)>[
      (
        _QuickAction.pickItem,
        'Prendre une pièce',
        Icons.inventory_2_outlined,
      ),
      (_QuickAction.placeOrder, 'Mettre en commande', Icons.playlist_add),
      (
        _QuickAction.logFuel,
        'Faire le plein',
        Icons.local_gas_station_outlined
      ),
      (
        _QuickAction.addMechanicTask,
        'Tâche mécanique',
        Icons.build_circle_outlined
      ),
    ];

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
          Text('Actions rapides',
              style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 12),
          GridView.builder(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            itemCount: quickActions.length,
            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: 2,
              crossAxisSpacing: 12,
              mainAxisSpacing: 12,
              childAspectRatio: 1.3,
            ),
            itemBuilder: (context, index) {
              final action = quickActions[index];
              return _QuickActionButton(
                icon: action.$3,
                label: action.$2,
                expanded: true,
                onTap: () => onQuickAction(action.$1),
              );
            },
          ),
          if (lowStockItems.isNotEmpty) ...[
            const SizedBox(height: 24),
            _LowStockWarningCard(
              lowStockItems: lowStockItems,
              onTap: onViewLowStock,
            ),
          ],
          const SizedBox(height: 28),
          Text('Aperçu rapide', style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 12),
          Wrap(
            runSpacing: 12,
            spacing: 12,
            children: [
              _MetricCard(
                icon: Icons.person_outline,
                label: 'Membres',
                value: '$memberCount',
                onTap: memberCount > 0
                    ? () => _showMembersSheet(context)
                    : null,
              ),
              _MetricCard(
                icon: Icons.build_outlined,
                label: 'Équipements',
                value: '$equipmentCount',
                onTap: equipmentCount > 0
                    ? () => _showEquipmentSheet(context)
                    : null,
              ),
              _MetricCard(
                icon: Icons.local_gas_station,
                label: 'Carburant / jour',
                value: '${fuelAverage.toStringAsFixed(1)} L',
                onTap:
                    () => _showFuelSheet(context, fuelAverage),
              ),
              _MetricCard(
                icon: Icons.list_alt,
                label: 'Tâches actives',
                value: '${taskStats.total}',
                onTap: taskStats.total > 0
                    ? () => _showTaskListSheet(
                          context,
                          mechanicTasks,
                          overdueOnly: false,
                        )
                    : null,
              ),
              _MetricCard(
                icon: Icons.warning_amber_outlined,
                label: 'Tâches en retard',
                value: '${taskStats.overdue}',
                onTap: taskStats.overdue > 0
                    ? () => _showTaskListSheet(
                          context,
                          mechanicTasks,
                          overdueOnly: true,
                        )
                    : null,
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _LowStockWarningCard extends StatelessWidget {
  const _LowStockWarningCard({
    required this.lowStockItems,
    this.onTap,
  });

  final List<InventoryEntry> lowStockItems;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final count = lowStockItems.length;
    return Card(
      clipBehavior: Clip.antiAlias,
      color: Colors.orange.shade50,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              Icon(Icons.warning_amber_rounded, color: Colors.orange.shade800),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '$count article${count > 1 ? 's' : ''} en stock bas',
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        color: Colors.orange.shade900,
                      ),
                    ),
                    const Text('Pense à passer une commande.'),
                  ],
                ),
              ),
              const Icon(Icons.chevron_right),
            ],
          ),
        ),
      ),
    );
  }
}

class _MetricCard extends StatelessWidget {
  const _MetricCard({
    required this.icon,
    required this.label,
    required this.value,
    this.onTap,
  });

  final IconData icon;
  final String label;
  final String value;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 150,
      child: Card(
        child: InkWell(
          borderRadius: BorderRadius.circular(12),
          onTap: onTap,
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
      ),
    );
  }
}

class _QuickActionButton extends StatelessWidget {
  const _QuickActionButton({
    required this.icon,
    required this.label,
    required this.onTap,
    this.expanded = false,
  });

  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final bool expanded;

  @override
  Widget build(BuildContext context) {
    final card = Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
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
      child: Column(
        mainAxisSize: MainAxisSize.min,
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(icon, color: AppColors.primary, size: 28),
          const SizedBox(height: 6),
          Text(
            label,
            style: const TextStyle(fontWeight: FontWeight.w600),
            textAlign: TextAlign.center,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
          ),
        ],
      ),
    );

    return GestureDetector(
      onTap: onTap,
      child: expanded ? SizedBox(width: double.infinity, child: card) : card,
    );
  }
}

class _EmptyStateCard extends StatelessWidget {
  const _EmptyStateCard({
    required this.title,
    required this.subtitle,
  });

  final String title;
  final String subtitle;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              title,
              style: Theme.of(context)
                  .textTheme
                  .titleMedium
                  ?.copyWith(fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 8),
            Text(subtitle),
          ],
        ),
      ),
    );
  }
}

class _EmptyCard extends _EmptyStateCard {
  const _EmptyCard({required super.title, required super.subtitle});
}

class _TaskOverviewStats {
  const _TaskOverviewStats({
    required this.total,
    required this.overdue,
  });

  final int total;
  final int overdue;
}

class _MechanicTaskWithEquipment {
  const _MechanicTaskWithEquipment({
    required this.task,
    required this.equipmentName,
    this.equipmentId,
  });

  final _MechanicTask task;
  final String equipmentName;
  final String? equipmentId;

  bool get isOverdue => task.dueDate.isBefore(DateTime.now());
}

void _showWhiteSheet(
  BuildContext context, {
  required String title,
  String? subtitle,
  required Widget child,
}) {
  showModalBottomSheet(
    context: context,
    backgroundColor: Colors.white,
    showDragHandle: true,
    isScrollControlled: true,
    builder: (context) => Container(
      color: Colors.white,
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
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
          if (subtitle != null) ...[
            const SizedBox(height: 4),
            Text(
              subtitle,
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ],
          const SizedBox(height: 12),
          Flexible(child: child),
        ],
      ),
    ),
  );
}

double _computeAverageFuelPerDay(
  List<Map<String, dynamic>> equipment, {
  int windowDays = 30,
}) {
  if (equipment.isEmpty || windowDays <= 0) return 0;
  final now = DateTime.now();
  final cutoff = now.subtract(Duration(days: windowDays));
  var totalLiters = 0.0;
  final Set<DateTime> activeDays = <DateTime>{};

  for (final equip in equipment) {
    final meta = equip['meta'];
    if (meta is! Map) continue;
    final logs = meta['diesel_logs'];
    if (logs is! List) continue;
    for (final raw in logs) {
      if (raw is! Map) continue;
      final created = _parseDateTime(raw['created_at']);
      final liters = (raw['liters'] as num?)?.toDouble();
      if (created == null || liters == null) continue;
      if (created.isBefore(cutoff) || created.isAfter(now)) continue;
      totalLiters += liters;
      final dateOnly = DateTime(created.year, created.month, created.day);
      activeDays.add(dateOnly);
    }
  }
  if (totalLiters <= 0 || activeDays.isEmpty) return 0;
  return totalLiters / activeDays.length;
}

_TaskOverviewStats _computeTaskOverview(
  List<Map<String, dynamic>> equipment,
) {
  var total = 0;
  var overdue = 0;
  final now = DateTime.now();

  for (final equip in equipment) {
    final meta = equip['meta'];
    if (meta is! Map) continue;
    final tasks = meta['mechanic_tasks'];
    if (tasks is! List) continue;
    for (final raw in tasks) {
      if (raw is! Map) continue;
      final created = _parseDateTime(raw['created_at']);
      final delay = (raw['delay_days'] as num?)?.round();
      if (created == null || delay == null) continue;
      total++;
      final due = created.add(Duration(days: delay));
      if (due.isBefore(now)) {
        overdue++;
      }
    }
  }
  return _TaskOverviewStats(total: total, overdue: overdue);
}

DateTime? _parseDateTime(dynamic raw) {
  if (raw is DateTime) return raw;
  if (raw is String) {
    return DateTime.tryParse(raw);
  }
  return null;
}

class _Badge extends StatelessWidget {
  const _Badge({required this.label, required this.color});

  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: color),
      ),
      child: Text(label,
          style: TextStyle(color: color, fontWeight: FontWeight.w600)),
    );
  }
}

class _Pill extends StatelessWidget {
  const _Pill({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: const Color(0xFFD7C2B4)),
      ),
      child: Text(label, style: const TextStyle(fontWeight: FontWeight.w600)),
    );
  }
}

class _MechanicTaskDialog extends StatefulWidget {
  const _MechanicTaskDialog();

  @override
  State<_MechanicTaskDialog> createState() => _MechanicTaskDialogState();
}

class _MechanicTaskDialogState extends State<_MechanicTaskDialog> {
  final GlobalKey<FormState> _formKey = GlobalKey<FormState>();
  final TextEditingController _titleCtrl = TextEditingController();
  final TextEditingController _delayCtrl = TextEditingController(text: '7');
  final TextEditingController _repeatCtrl = TextEditingController();
  String _priority = 'moyen';

  @override
  void dispose() {
    _titleCtrl.dispose();
    _delayCtrl.dispose();
    _repeatCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      backgroundColor: Colors.white,
      title: const Text('Nouvelle tâche mécanique'),
      content: Form(
        key: _formKey,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextFormField(
              controller: _titleCtrl,
              decoration:
                  const InputDecoration(labelText: 'Description de la tâche'),
              validator: (value) =>
                  value == null || value.trim().isEmpty ? 'Nom requis' : null,
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: _delayCtrl,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(labelText: 'Délai (en jours)'),
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
              initialValue: _priority,
              decoration: const InputDecoration(labelText: 'Priorité'),
              items: const [
                DropdownMenuItem(value: 'faible', child: Text('Faible')),
                DropdownMenuItem(value: 'moyen', child: Text('Moyenne')),
                DropdownMenuItem(value: 'eleve', child: Text('Élevée')),
              ],
              onChanged: (value) {
                if (value != null) {
                  setState(() => _priority = value);
                }
              },
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: _repeatCtrl,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(
                labelText: 'Rappel (jours, optionnel)',
              ),
            ),
          ],
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
            final delay = int.parse(_delayCtrl.text.trim());
            final repeatText = _repeatCtrl.text.trim();
            final repeat = repeatText.isEmpty ? null : int.tryParse(repeatText);
            Navigator.of(context).pop({
              'title': _titleCtrl.text.trim(),
              'delay_days': delay,
              'priority': _priority,
              'repeat_days': repeat,
            });
          },
          child: const Text('Ajouter'),
        ),
      ],
    );
  }
}

class _LowStockPage extends StatelessWidget {
  const _LowStockPage({
    required this.items,
    required this.onOrder,
  });

  final List<InventoryEntry> items;
  final void Function(InventoryEntry item) onOrder;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Stock faible'),
      ),
      body: items.isEmpty
          ? const Center(child: Text('Tout est en ordre !'))
          : ListView.separated(
              padding: const EdgeInsets.all(16),
              itemCount: items.length,
              separatorBuilder: (context, index) => const SizedBox(height: 12),
              itemBuilder: (context, index) {
                final item = items[index];
                final name = item.item['name']?.toString() ?? 'Inconnu';
                final qty = item.totalQty;
                final meta = item.item['meta'] as Map?;
                final minStock = (meta?['min_stock'] as num?)?.toInt();

                return Card(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(vertical: 8),
                    child: ListTile(
                      title: Text(name,
                          style: const TextStyle(fontWeight: FontWeight.bold)),
                      subtitle: Text(
                        'Stock actuel : $qty\nMinimum requis : $minStock (alerte si < $minStock)',
                        style: TextStyle(color: Colors.grey.shade700),
                      ),
                      trailing: FilledButton.icon(
                        onPressed: () => onOrder(item),
                        icon: const Icon(Icons.add_shopping_cart, size: 18),
                        label: const Text('Commander'),
                      ),
                    ),
                  ),
                );
              },
            ),
    );
  }
}
