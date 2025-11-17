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
    final equipmentCount = equipment.length;
    final fuelAverage = _computeAverageFuelPerDay(equipment);
    final taskStats = _computeTaskOverview(equipment);

    final quickActions = <(_QuickAction, String, IconData)>[
      (
        _QuickAction.pickItem,
        'Prendre une pièce',
        Icons.inventory_2_outlined,
      ),
      (_QuickAction.placeOrder, 'Mettre en commande', Icons.playlist_add),
      (_QuickAction.logFuel, 'Faire le plein', Icons.local_gas_station_outlined),
      (_QuickAction.addMechanicTask, 'Tâche mécanique', Icons.build_circle_outlined),
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
              ),
              _MetricCard(
                icon: Icons.build_outlined,
                label: 'Équipements',
                value: '$equipmentCount',
              ),
              _MetricCard(
                icon: Icons.local_gas_station,
                label: 'Carburant / jour',
                value: '${fuelAverage.toStringAsFixed(1)} L',
              ),
              _MetricCard(
                icon: Icons.list_alt,
                label: 'Tâches actives',
                value: '${taskStats.total}',
              ),
              _MetricCard(
                icon: Icons.warning_amber_outlined,
                label: 'Tâches en retard',
                value: '${taskStats.overdue}',
              ),
            ],
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
      child: expanded
          ? SizedBox(width: double.infinity, child: card)
          : card,
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

class _EquipmentSummaryCard extends StatelessWidget {
  const _EquipmentSummaryCard({required this.data});

  final Map<String, dynamic> data;

  @override
  Widget build(BuildContext context) {
    final name = (data['name'] as String?) ?? 'Équipement';
    final brand = (data['brand'] as String?) ?? '—';
    final model = (data['model'] as String?) ?? '—';
    final createdAt = _formatDate(data['created_at']);
    final active = (data['active'] as bool?) ?? true;

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
                  label: active ? 'Actif' : 'Inactif',
                  color: active ? AppColors.primary : Colors.grey,
                ),
              ],
            ),
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                _Pill(label: brand),
                _Pill(label: model),
              ],
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                const Icon(Icons.calendar_today, size: 16),
                const SizedBox(width: 8),
                Text('Ajouté le ${createdAt ?? '—'}'),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _TaskOverviewStats {
  const _TaskOverviewStats({
    required this.total,
    required this.overdue,
  });

  final int total;
  final int overdue;
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
              value: _priority,
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
            final repeat =
                repeatText.isEmpty ? null : int.tryParse(repeatText);
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
