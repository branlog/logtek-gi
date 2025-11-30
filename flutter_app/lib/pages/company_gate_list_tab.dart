part of 'company_gate.dart';

// ---------------------------------------------------------------------------
// List tab
// ---------------------------------------------------------------------------

class _ListTab extends StatelessWidget {
  const _ListTab({
    required this.requests,
    required this.onAddRequest,
    required this.onReviewInventory,
    required this.onIncreaseQty,
    required this.onDecreaseQty,
    required this.onDeleteRequest,
    required this.onShowDetails,
    required this.onMarkPurchased,
    required this.updatingRequestIds,
  });

  final List<Map<String, dynamic>> requests;
  final VoidCallback onAddRequest;
  final VoidCallback onReviewInventory;
  final void Function(Map<String, dynamic> request) onIncreaseQty;
  final void Function(Map<String, dynamic> request) onDecreaseQty;
  final void Function(Map<String, dynamic> request) onShowDetails;
  final void Function(Map<String, dynamic> request) onDeleteRequest;
  final void Function(Map<String, dynamic> request) onMarkPurchased;
  final Set<String> updatingRequestIds;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Card(
            child: Padding(
              padding: const EdgeInsets.all(20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text('Organise tes achats',
                      style: Theme.of(context)
                          .textTheme
                          .titleMedium
                          ?.copyWith(fontWeight: FontWeight.w700)),
                  const SizedBox(height: 8),
                  const Text(
                    'Ajoute les pièces à acheter ou commander. Tu peux aussi revoir l’inventaire.',
                  ),
                  const SizedBox(height: 16),
                  Text(
                    'Appuie sur le bouton + pour ajouter une nouvelle pièce à suivre.',
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                  const SizedBox(height: 12),
                  OutlinedButton.icon(
                    onPressed: onReviewInventory,
                    icon: const Icon(Icons.inventory),
                    label: const Text('Revoir l’inventaire'),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),
          if (requests.isEmpty)
            const _EmptyCard(
              title: 'Aucune pièce en attente',
              subtitle: 'Ajoute une pièce à acheter pour démarrer ta liste.',
            )
          else
            Column(
              children: requests.map((request) {
                final requestId = request['id']?.toString();
                return _PurchaseCard(
                  data: request,
                  onIncrementQty: () => onIncreaseQty(request),
                  onDecrementQty: () => onDecreaseQty(request),
                  onShowDetails: () => onShowDetails(request),
                  onDelete: () => onDeleteRequest(request),
                  onMarkPurchased: () => onMarkPurchased(request),
                  updating: requestId != null &&
                      updatingRequestIds.contains(requestId),
                );
              }).toList(),
            ),
        ],
      ),
    );
  }
}

class _PurchaseCard extends StatelessWidget {
  const _PurchaseCard({
    required this.data,
    required this.onIncrementQty,
    required this.onDecrementQty,
    required this.onShowDetails,
    required this.onDelete,
    required this.onMarkPurchased,
    required this.updating,
  });

  final Map<String, dynamic> data;
  final VoidCallback onIncrementQty;
  final VoidCallback onDecrementQty;
  final VoidCallback onShowDetails;
  final VoidCallback onDelete;
  final VoidCallback onMarkPurchased;
  final bool updating;

  @override
  Widget build(BuildContext context) {
    final name = data['name']?.toString() ?? 'Pièce';
    final qtyValue = int.tryParse(data['qty']?.toString() ?? '') ?? 0;
    final qtyLabel = qtyValue > 0 ? qtyValue.toString() : '—';
    final status = data['status']?.toString() ?? 'pending';
    final warehouse = data['warehouse'] as Map<String, dynamic>?;
    final section = data['section'] as Map<String, dynamic>?;
    final sectionName = section?['name']?.toString();
    final fallbackSectionId = data['section_id']?.toString();
    final noteText = data['note']?.toString().trim();
    final statusLabel = _statusLabel(status);
    final badgeColor = _statusColor(status);
    final isPending = status == 'pending';
    final canEdit = status != 'done';
    final canDecrease = canEdit && qtyValue > 1 && !updating;
    final canIncrease = canEdit && !updating;

    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Text(
                    name,
                    style: Theme.of(context)
                        .textTheme
                        .titleMedium
                        ?.copyWith(fontWeight: FontWeight.w700),
                  ),
                ),
                _Badge(
                  label: statusLabel,
                  color: badgeColor,
                ),
              ],
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                const Text('Quantité souhaitée'),
                const Spacer(),
                IconButton(
                  icon: const Icon(Icons.remove),
                  onPressed: canDecrease ? onDecrementQty : null,
                ),
                SizedBox(
                  width: 32,
                  child: updating
                      ? const Center(
                          child: SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          ),
                        )
                      : Center(
                          child: Text(
                            qtyLabel,
                            style: const TextStyle(
                              fontWeight: FontWeight.w600,
                              fontSize: 16,
                            ),
                          ),
                        ),
                ),
                IconButton(
                  icon: const Icon(Icons.add),
                  onPressed: canIncrease ? onIncrementQty : null,
                ),
              ],
            ),
            if (warehouse != null)
              Text('Entrepôt : ${warehouse['name'] ?? '-'}'),
            if ((sectionName != null && sectionName.isNotEmpty) ||
                (sectionName == null && fallbackSectionId != null))
              Text(
                'Section : ${sectionName ?? fallbackSectionId}',
              ),
            if (noteText != null && noteText.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Text(
                  noteText,
                  style: Theme.of(context)
                      .textTheme
                      .bodySmall
                      ?.copyWith(color: Colors.black54),
                ),
              ),
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                OutlinedButton.icon(
                  onPressed: onShowDetails,
                  icon: const Icon(Icons.info_outline),
                  label: const Text('Détails'),
                ),
                if (isPending)
                  FilledButton.icon(
                    onPressed: onMarkPurchased,
                    icon: const Icon(Icons.shopping_bag),
                    label: const Text('Acheter'),
                  ),
                TextButton.icon(
                  onPressed: onDelete,
                  icon: const Icon(Icons.delete_outline),
                  label: const Text('Supprimer'),
                  style: TextButton.styleFrom(
                    foregroundColor: Colors.red,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  static String _statusLabel(String status) {
    switch (status) {
      case 'pending':
        return 'À acheter';
      case 'to_place':
        return 'À placer';
      case 'done':
        return 'Terminé';
      default:
        return status;
    }
  }

  static Color _statusColor(String status) {
    switch (status) {
      case 'done':
        return Colors.green;
      case 'to_place':
        return Colors.orange;
      default:
        return AppColors.primary;
    }
  }
}
