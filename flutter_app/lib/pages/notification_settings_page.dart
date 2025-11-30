import 'package:flutter/material.dart';

import '../services/notification_service.dart'
    show NotificationService, NotificationPreferences, NotificationTimeOfDay;
import '../theme/app_colors.dart';

class NotificationSettingsPage extends StatefulWidget {
  const NotificationSettingsPage({super.key});

  @override
  State<NotificationSettingsPage> createState() =>
      _NotificationSettingsPageState();
}

class _NotificationSettingsPageState extends State<NotificationSettingsPage> {
  late NotificationPreferences _preferences;
  bool _loading = true;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _loadPreferences();
  }

  Future<void> _loadPreferences() async {
    setState(() => _loading = true);
    await Future.delayed(const Duration(milliseconds: 100));
    setState(() {
      _preferences = NotificationService.instance.preferences;
      _loading = false;
    });
  }

  Future<void> _savePreferences() async {
    setState(() => _saving = true);
    await NotificationService.instance.savePreferences(_preferences);
    setState(() => _saving = false);

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('✅ Préférences sauvegardées'),
          duration: Duration(seconds: 2),
        ),
      );
    }
  }

  Future<void> _testNotification() async {
    await NotificationService.instance.testNotification();
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('📨 Notification de test envoyée'),
          duration: Duration(seconds: 2),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Scaffold(
        body: Center(child: CircularProgressIndicator()),
      );
    }

    return Scaffold(
      backgroundColor: AppColors.surface,
      appBar: AppBar(
        title: const Text('Paramètres de notifications'),
        backgroundColor: AppColors.surface,
        actions: [
          if (_saving)
            const Padding(
              padding: EdgeInsets.all(16),
              child: SizedBox(
                width: 24,
                height: 24,
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
            )
          else
            IconButton(
              icon: const Icon(Icons.save),
              onPressed: _savePreferences,
              tooltip: 'Sauvegarder',
            ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          // Activation générale
          _SectionCard(
            title: 'Général',
            children: [
              SwitchListTile(
                title: const Text(
                  'Activer les notifications',
                  style: TextStyle(fontWeight: FontWeight.w600),
                ),
                subtitle: const Text(
                  'Recevoir toutes les notifications',
                ),
                value: _preferences.enabled,
                onChanged: (value) {
                  setState(() {
                    _preferences = _preferences.copyWith(enabled: value);
                  });
                },
              ),
            ],
          ),

          const SizedBox(height: 20),

          // Types de notifications
          _SectionCard(
            title: 'Types de notifications',
            children: [
              _NotificationTypeSwitch(
                icon: Icons.inventory_2,
                title: 'Alertes de stock faible',
                description: 'Quand un article atteint son seuil minimum',
                value: _preferences.lowStockAlerts,
                enabled: _preferences.enabled,
                onChanged: (value) {
                  setState(() {
                    _preferences = _preferences.copyWith(lowStockAlerts: value);
                  });
                },
              ),
              const Divider(height: 1),
              _NotificationTypeSwitch(
                icon: Icons.shopping_cart,
                title: 'Demandes d\'achat',
                description: 'Nouvelles demandes et approbations',
                value: _preferences.purchaseRequestAlerts,
                enabled: _preferences.enabled,
                onChanged: (value) {
                  setState(() {
                    _preferences =
                        _preferences.copyWith(purchaseRequestAlerts: value);
                  });
                },
              ),
              const Divider(height: 1),
              _NotificationTypeSwitch(
                icon: Icons.build,
                title: 'Équipement',
                description: 'Assignations et maintenance',
                value: _preferences.equipmentAlerts,
                enabled: _preferences.enabled,
                onChanged: (value) {
                  setState(() {
                    _preferences =
                        _preferences.copyWith(equipmentAlerts: value);
                  });
                },
              ),
              const Divider(height: 1),
              _NotificationTypeSwitch(
                icon: Icons.analytics,
                title: 'Ajustements d\'inventaire',
                description: 'Modifications importantes de stock',
                value: _preferences.inventoryAlerts,
                enabled: _preferences.enabled,
                onChanged: (value) {
                  setState(() {
                    _preferences =
                        _preferences.copyWith(inventoryAlerts: value);
                  });
                },
              ),
              const Divider(height: 1),
              _NotificationTypeSwitch(
                icon: Icons.message,
                title: 'Messages d\'équipe',
                description: 'Communications de l\'équipe',
                value: _preferences.teamMessages,
                enabled: _preferences.enabled,
                onChanged: (value) {
                  setState(() {
                    _preferences = _preferences.copyWith(teamMessages: value);
                  });
                },
              ),
              const Divider(height: 1),
              _NotificationTypeSwitch(
                icon: Icons.notifications_active,
                title: 'Alertes système',
                description: 'Mises à jour et alertes importantes',
                value: _preferences.systemAlerts,
                enabled: _preferences.enabled,
                onChanged: (value) {
                  setState(() {
                    _preferences = _preferences.copyWith(systemAlerts: value);
                  });
                },
              ),
            ],
          ),

          const SizedBox(height: 20),

          // Options sonores et vibreur
          _SectionCard(
            title: 'Son et vibrations',
            children: [
              SwitchListTile(
                title: const Text('Son'),
                subtitle: const Text('Jouer un son pour les notifications'),
                value: _preferences.soundEnabled,
                onChanged: _preferences.enabled
                    ? (value) {
                        setState(() {
                          _preferences =
                              _preferences.copyWith(soundEnabled: value);
                        });
                      }
                    : null,
              ),
              const Divider(height: 1),
              SwitchListTile(
                title: const Text('Vibration'),
                subtitle: const Text('Vibrer pour les notifications'),
                value: _preferences.vibrationEnabled,
                onChanged: _preferences.enabled
                    ? (value) {
                        setState(() {
                          _preferences =
                              _preferences.copyWith(vibrationEnabled: value);
                        });
                      }
                    : null,
              ),
            ],
          ),

          const SizedBox(height: 20),

          // Heures de silence
          _SectionCard(
            title: 'Heures de silence',
            children: [
              SwitchListTile(
                title: const Text('Activer le mode silencieux'),
                subtitle: Text(
                  _preferences.quietHoursEnabled
                      ? 'De ${_preferences.quietHoursStart} à ${_preferences.quietHoursEnd}'
                      : 'Aucune restriction horaire',
                ),
                value: _preferences.quietHoursEnabled,
                onChanged: _preferences.enabled
                    ? (value) {
                        setState(() {
                          _preferences =
                              _preferences.copyWith(quietHoursEnabled: value);
                        });
                      }
                    : null,
              ),
              if (_preferences.quietHoursEnabled) ...[
                const Divider(height: 1),
                ListTile(
                  title: const Text('Début'),
                  trailing: Text(
                    _preferences.quietHoursStart.toString(),
                    style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                  onTap: () => _selectTime(isStart: true),
                ),
                const Divider(height: 1),
                ListTile(
                  title: const Text('Fin'),
                  trailing: Text(
                    _preferences.quietHoursEnd.toString(),
                    style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                  onTap: () => _selectTime(isStart: false),
                ),
              ],
            ],
          ),

          const SizedBox(height: 20),

          // Bouton de test
          _SectionCard(
            children: [
              ListTile(
                leading: const Icon(Icons.bug_report, color: AppColors.accent),
                title: const Text(
                  'Tester les notifications',
                  style: TextStyle(fontWeight: FontWeight.w600),
                ),
                subtitle: const Text(
                  'Envoyer une notification de test',
                ),
                trailing: const Icon(Icons.send),
                onTap: _testNotification,
              ),
            ],
          ),

          const SizedBox(height: 40),
        ],
      ),
    );
  }

  Future<void> _selectTime({required bool isStart}) async {
    final currentTime =
        isStart ? _preferences.quietHoursStart : _preferences.quietHoursEnd;

    final picked = await showTimePicker(
      context: context,
      initialTime:
          TimeOfDay(hour: currentTime.hour, minute: currentTime.minute),
    );

    if (picked != null) {
      final newTime =
          NotificationTimeOfDay(hour: picked.hour, minute: picked.minute);
      setState(() {
        _preferences = isStart
            ? _preferences.copyWith(quietHoursStart: newTime)
            : _preferences.copyWith(quietHoursEnd: newTime);
      });
    }
  }
}

class _SectionCard extends StatelessWidget {
  const _SectionCard({
    this.title,
    required this.children,
  });

  final String? title;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (title != null)
          Padding(
            padding: const EdgeInsets.only(left: 8, bottom: 8),
            child: Text(
              title!,
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: Colors.grey[600],
                letterSpacing: 0.5,
              ),
            ),
          ),
        Container(
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(16),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.04),
                blurRadius: 10,
                offset: const Offset(0, 2),
              ),
            ],
          ),
          child: Column(
            children: children,
          ),
        ),
      ],
    );
  }
}

class _NotificationTypeSwitch extends StatelessWidget {
  const _NotificationTypeSwitch({
    required this.icon,
    required this.title,
    required this.description,
    required this.value,
    required this.enabled,
    required this.onChanged,
  });

  final IconData icon;
  final String title;
  final String description;
  final bool value;
  final bool enabled;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    return SwitchListTile(
      secondary: Icon(
        icon,
        color: enabled ? AppColors.accent : Colors.grey[400],
      ),
      title: Text(
        title,
        style: TextStyle(
          fontWeight: FontWeight.w500,
          color: enabled ? null : Colors.grey[600],
        ),
      ),
      subtitle: Text(
        description,
        style: TextStyle(
          fontSize: 12,
          color: enabled ? Colors.grey[600] : Colors.grey[400],
        ),
      ),
      value: value,
      onChanged: enabled ? onChanged : null,
    );
  }
}
