import 'package:flutter/material.dart';

class SyncStatusChip extends StatelessWidget {
  const SyncStatusChip({
    super.key,
    required this.online,
    required this.pendingActions,
    this.onSync,
  });

  final bool online;
  final int pendingActions;
  final VoidCallback? onSync;

  @override
  Widget build(BuildContext context) {
    final Color color;
    if (!online) {
      color = Colors.orange;
    } else if (pendingActions > 0) {
      color = Colors.blue;
    } else {
      color = Colors.green;
    }

    return GestureDetector(
      onTap: onSync,
      child: Container(
        width: 14,
        height: 14,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: color,
          boxShadow: [
            BoxShadow(
              color: color.withValues(alpha: 0.5),
              blurRadius: 6,
            ),
          ],
        ),
      ),
    );
  }
}
