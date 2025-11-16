part of 'company_gate.dart';

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
    final totalStock =
        inventory.fold<int>(0, (acc, entry) => acc + entry.totalQty);

    final quickActions = <(_QuickAction, String, IconData)>[
      (_QuickAction.newItem, 'Nouvel article', Icons.add_box_outlined),
      (
        _QuickAction.newWarehouse,
        'Nouvel entrepôt',
        Icons.store_mall_directory
      ),
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
            const _EmptyStateCard(
              title: 'Aucun article',
              subtitle: 'Ajoute un article pour démarrer ton inventaire.',
            )
          else
            Column(
              children: topItems
                  .map<Widget>(
                    (entry) => _ListCard(
                      title: entry.item['name']?.toString() ?? 'Article',
                      subtitle:
                          '${entry.totalQty} en stock • SKU ${entry.item['sku'] ?? '-'}',
                      icon: Icons.inventory_2,
                    ),
                  )
                  .toList(growable: false),
            ),
          const SizedBox(height: 24),
          Text('Équipements récents',
              style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 12),
          if (equipment.isEmpty)
            const _EmptyStateCard(
              title: 'Aucun équipement',
              subtitle: 'Ajoute ton premier équipement pour le suivre.',
            )
          else
            Column(
              children: equipment
                  .take(2)
                  .map<Widget>((item) => _EquipmentSummaryCard(data: item))
                  .toList(growable: false),
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
          backgroundColor: AppColors.primary.withValues(alpha: 0.15),
          child: Icon(icon, color: AppColors.primary),
        ),
        title: Text(title, style: const TextStyle(fontWeight: FontWeight.w600)),
        subtitle: Text(subtitle),
        trailing: const Icon(Icons.open_in_new),
      ),
    );
  }
}
