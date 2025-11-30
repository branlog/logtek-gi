import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'offline_storage.dart';
import 'supabase_service.dart';

/// Types de notifications disponibles
enum NotificationType {
  lowStock('low_stock', 'Stock faible', '📦'),
  purchaseRequestApproved('purchase_approved', 'Demande approuvée', '✅'),
  purchaseRequestCreated('purchase_created', 'Nouvelle demande', '📝'),
  equipmentAssigned('equipment_assigned', 'Équipement assigné', '🔧'),
  equipmentMaintenanceDue('equipment_maintenance', 'Maintenance requise', '⚠️'),
  inventoryAdjustment('inventory_adjustment', 'Ajustement inventaire', '📊'),
  teamMessage('team_message', 'Message d\'équipe', '💬'),
  systemAlert('system_alert', 'Alerte système', '🔔');

  const NotificationType(this.key, this.label, this.emoji);

  final String key;
  final String label;
  final String emoji;

  static NotificationType? fromKey(String key) {
    for (final type in NotificationType.values) {
      if (type.key == key) return type;
    }
    return null;
  }
}

/// Préférences de notifications
class NotificationPreferences {
  NotificationPreferences({
    this.enabled = true,
    this.lowStockAlerts = true,
    this.purchaseRequestAlerts = true,
    this.equipmentAlerts = true,
    this.inventoryAlerts = true,
    this.teamMessages = true,
    this.systemAlerts = true,
    this.soundEnabled = true,
    this.vibrationEnabled = true,
    this.quietHoursEnabled = false,
    this.quietHoursStart = const NotificationTimeOfDay(hour: 22, minute: 0),
    this.quietHoursEnd = const NotificationTimeOfDay(hour: 7, minute: 0),
  });

  final bool enabled;
  final bool lowStockAlerts;
  final bool purchaseRequestAlerts;
  final bool equipmentAlerts;
  final bool inventoryAlerts;
  final bool teamMessages;
  final bool systemAlerts;
  final bool soundEnabled;
  final bool vibrationEnabled;
  final bool quietHoursEnabled;
  final NotificationTimeOfDay quietHoursStart;
  final NotificationTimeOfDay quietHoursEnd;

  Map<String, dynamic> toJson() => {
        'enabled': enabled,
        'low_stock_alerts': lowStockAlerts,
        'purchase_request_alerts': purchaseRequestAlerts,
        'equipment_alerts': equipmentAlerts,
        'inventory_alerts': inventoryAlerts,
        'team_messages': teamMessages,
        'system_alerts': systemAlerts,
        'sound_enabled': soundEnabled,
        'vibration_enabled': vibrationEnabled,
        'quiet_hours_enabled': quietHoursEnabled,
        'quiet_hours_start':
            '${quietHoursStart.hour}:${quietHoursStart.minute}',
        'quiet_hours_end': '${quietHoursEnd.hour}:${quietHoursEnd.minute}',
      };

  factory NotificationPreferences.fromJson(Map<String, dynamic> json) {
    NotificationTimeOfDay parseTime(
        String? timeStr, NotificationTimeOfDay fallback) {
      if (timeStr == null) return fallback;
      final parts = timeStr.split(':');
      if (parts.length != 2) return fallback;
      final hour = int.tryParse(parts[0]);
      final minute = int.tryParse(parts[1]);
      if (hour == null || minute == null) return fallback;
      return NotificationTimeOfDay(hour: hour, minute: minute);
    }

    return NotificationPreferences(
      enabled: json['enabled'] as bool? ?? true,
      lowStockAlerts: json['low_stock_alerts'] as bool? ?? true,
      purchaseRequestAlerts: json['purchase_request_alerts'] as bool? ?? true,
      equipmentAlerts: json['equipment_alerts'] as bool? ?? true,
      inventoryAlerts: json['inventory_alerts'] as bool? ?? true,
      teamMessages: json['team_messages'] as bool? ?? true,
      systemAlerts: json['system_alerts'] as bool? ?? true,
      soundEnabled: json['sound_enabled'] as bool? ?? true,
      vibrationEnabled: json['vibration_enabled'] as bool? ?? true,
      quietHoursEnabled: json['quiet_hours_enabled'] as bool? ?? false,
      quietHoursStart: parseTime(
        json['quiet_hours_start'] as String?,
        const NotificationTimeOfDay(hour: 22, minute: 0),
      ),
      quietHoursEnd: parseTime(
        json['quiet_hours_end'] as String?,
        const NotificationTimeOfDay(hour: 7, minute: 0),
      ),
    );
  }

  NotificationPreferences copyWith({
    bool? enabled,
    bool? lowStockAlerts,
    bool? purchaseRequestAlerts,
    bool? equipmentAlerts,
    bool? inventoryAlerts,
    bool? teamMessages,
    bool? systemAlerts,
    bool? soundEnabled,
    bool? vibrationEnabled,
    bool? quietHoursEnabled,
    NotificationTimeOfDay? quietHoursStart,
    NotificationTimeOfDay? quietHoursEnd,
  }) {
    return NotificationPreferences(
      enabled: enabled ?? this.enabled,
      lowStockAlerts: lowStockAlerts ?? this.lowStockAlerts,
      purchaseRequestAlerts:
          purchaseRequestAlerts ?? this.purchaseRequestAlerts,
      equipmentAlerts: equipmentAlerts ?? this.equipmentAlerts,
      inventoryAlerts: inventoryAlerts ?? this.inventoryAlerts,
      teamMessages: teamMessages ?? this.teamMessages,
      systemAlerts: systemAlerts ?? this.systemAlerts,
      soundEnabled: soundEnabled ?? this.soundEnabled,
      vibrationEnabled: vibrationEnabled ?? this.vibrationEnabled,
      quietHoursEnabled: quietHoursEnabled ?? this.quietHoursEnabled,
      quietHoursStart: quietHoursStart ?? this.quietHoursStart,
      quietHoursEnd: quietHoursEnd ?? this.quietHoursEnd,
    );
  }
}

/// Classe personnalisée pour éviter le conflit avec flutter/material TimeOfDay
class NotificationTimeOfDay {
  const NotificationTimeOfDay({required this.hour, required this.minute});

  final int hour;
  final int minute;

  @override
  String toString() => '$hour:${minute.toString().padLeft(2, '0')}';

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is NotificationTimeOfDay &&
          runtimeType == other.runtimeType &&
          hour == other.hour &&
          minute == other.minute;

  @override
  int get hashCode => hour.hashCode ^ minute.hashCode;
}

/// Service de gestion des notifications (version Supabase uniquement)
class NotificationService {
  NotificationService._();

  static final NotificationService instance = NotificationService._();

  final FlutterLocalNotificationsPlugin _localNotifications =
      FlutterLocalNotificationsPlugin();

  bool _initialized = false;
  NotificationPreferences _preferences = NotificationPreferences();
  RealtimeChannel? _realtimeChannel;

  final StreamController<Map<String, dynamic>> _notificationTapController =
      StreamController<Map<String, dynamic>>.broadcast();

  Stream<Map<String, dynamic>> get onNotificationTap =>
      _notificationTapController.stream;

  /// Initialise le service de notifications
  Future<void> initialize() async {
    if (_initialized) return;

    try {
      // Charger les préférences
      await _loadPreferences();

      // Initialiser les notifications locales
      await _initializeLocalNotifications();

      // S'abonner au canal Realtime Supabase pour les notifications
      await _setupRealtimeNotifications();

      _initialized = true;
      debugPrint('✅ Service de notifications initialisé (Supabase)');
    } catch (e) {
      debugPrint('❌ Erreur d\'initialisation des notifications: $e');
    }
  }

  /// Initialise les notifications locales
  Future<void> _initializeLocalNotifications() async {
    const androidSettings =
        AndroidInitializationSettings('@mipmap/ic_launcher');
    const iosSettings = DarwinInitializationSettings(
      requestAlertPermission: true,
      requestBadgePermission: true,
      requestSoundPermission: true,
    );

    const initSettings = InitializationSettings(
      android: androidSettings,
      iOS: iosSettings,
    );

    await _localNotifications.initialize(
      initSettings,
      onDidReceiveNotificationResponse: _onNotificationTapped,
    );

    debugPrint('✅ Notifications locales initialisées');
  }

  /// Configure l'écoute des notifications via Supabase Realtime
  Future<void> _setupRealtimeNotifications() async {
    final userId = Supa.i.auth.currentUser?.id;
    if (userId == null) return;

    // S'abonner à la table notifications pour cet utilisateur
    _realtimeChannel = Supa.i
        .channel('notifications:$userId')
        .onPostgresChanges(
          event: PostgresChangeEvent.insert,
          schema: 'public',
          table: 'user_notifications',
          filter: PostgresChangeFilter(
            type: PostgresChangeFilterType.eq,
            column: 'user_id',
            value: userId,
          ),
          callback: (payload) {
            _handleRealtimeNotification(payload.newRecord);
          },
        )
        .subscribe();

    debugPrint('✅ Abonné aux notifications Realtime Supabase');
  }

  /// Force une reconnexion au canal Realtime (utilisé après un retour en ligne)
  Future<void> reconnect() async {
    try {
      await _realtimeChannel?.unsubscribe();
    } catch (_) {}
    _realtimeChannel = null;
    await _setupRealtimeNotifications();
  }

  /// Gère les notifications reçues via Realtime
  Future<void> _handleRealtimeNotification(Map<String, dynamic> data) async {
    debugPrint('📬 Notification Realtime reçue: ${data['title']}');

    final type = NotificationType.fromKey(data['type'] as String? ?? '');

    if (!_shouldShowNotification(type)) {
      return;
    }

    await _showLocalNotification(
      title: data['title'] as String? ?? 'Notification',
      body: data['body'] as String? ?? '',
      payload: jsonEncode(data['data'] ?? {}),
      type: type,
      highPriority: data['priority'] == 'high',
    );

    // Marquer comme lue
    final notificationId = data['id'];
    if (notificationId != null) {
      await Supa.i
          .from('user_notifications')
          .update({'read_at': DateTime.now().toUtc().toIso8601String()}).eq(
              'id', notificationId);
    }
  }

  /// Callback quand une notification locale est tapée
  void _onNotificationTapped(NotificationResponse response) {
    final payload = response.payload;
    if (payload != null && payload.isNotEmpty) {
      try {
        final data = jsonDecode(payload) as Map<String, dynamic>;
        _notificationTapController.add(data);
      } catch (e) {
        debugPrint('❌ Erreur de parsing du payload: $e');
      }
    }
  }

  /// Détermine si la notification doit être affichée
  bool _shouldShowNotification(NotificationType? type) {
    if (!_preferences.enabled) return false;

    // Vérifier les heures de silence
    if (_preferences.quietHoursEnabled && _isQuietHours()) {
      return false;
    }

    if (type == null) return true;

    switch (type) {
      case NotificationType.lowStock:
        return _preferences.lowStockAlerts;
      case NotificationType.purchaseRequestApproved:
      case NotificationType.purchaseRequestCreated:
        return _preferences.purchaseRequestAlerts;
      case NotificationType.equipmentAssigned:
      case NotificationType.equipmentMaintenanceDue:
        return _preferences.equipmentAlerts;
      case NotificationType.inventoryAdjustment:
        return _preferences.inventoryAlerts;
      case NotificationType.teamMessage:
        return _preferences.teamMessages;
      case NotificationType.systemAlert:
        return _preferences.systemAlerts;
    }
  }

  /// Vérifie si on est en heures de silence
  bool _isQuietHours() {
    final now = DateTime.now();
    final currentMinutes = now.hour * 60 + now.minute;
    final startMinutes = _preferences.quietHoursStart.hour * 60 +
        _preferences.quietHoursStart.minute;
    final endMinutes = _preferences.quietHoursEnd.hour * 60 +
        _preferences.quietHoursEnd.minute;

    if (startMinutes < endMinutes) {
      return currentMinutes >= startMinutes && currentMinutes < endMinutes;
    } else {
      // Les heures traversent minuit
      return currentMinutes >= startMinutes || currentMinutes < endMinutes;
    }
  }

  /// Affiche une notification locale
  Future<void> _showLocalNotification({
    required String title,
    required String body,
    String? payload,
    NotificationType? type,
    bool highPriority = false,
  }) async {
    final emoji = type?.emoji ?? '🔔';
    final channelId =
        highPriority ? 'high_priority_channel' : 'default_channel';

    final androidDetails = AndroidNotificationDetails(
      channelId,
      highPriority ? 'Notifications importantes' : 'Notifications générales',
      channelDescription: highPriority
          ? 'Pour les alertes critiques et urgentes'
          : 'Pour les notifications d\'information générale',
      importance: highPriority ? Importance.high : Importance.defaultImportance,
      priority: highPriority ? Priority.high : Priority.defaultPriority,
      playSound: _preferences.soundEnabled,
      enableVibration: _preferences.vibrationEnabled,
      icon: '@mipmap/ic_launcher',
    );

    const iosDetails = DarwinNotificationDetails(
      presentAlert: true,
      presentBadge: true,
      presentSound: true,
    );

    final details = NotificationDetails(
      android: androidDetails,
      iOS: iosDetails,
    );

    debugPrint('📱 Affichage notification: "$title"');
    debugPrint('📱 Body: "$body"');
    debugPrint('📱 Type: ${type?.key}');
    debugPrint('📱 High priority: $highPriority');

    try {
      await _localNotifications.show(
        DateTime.now().millisecondsSinceEpoch ~/ 1000,
        '$emoji $title',
        body,
        details,
        payload: payload,
      );
      debugPrint('✅ Notification affichée avec succès');
    } catch (e) {
      debugPrint('❌ Erreur d\'affichage de la notification: $e');
      rethrow;
    }
  }

  /// Affiche une notification de stock faible
  Future<void> showLowStockNotification({
    required String itemName,
    required int currentQty,
    required int minStock,
    String? itemId,
  }) async {
    if (!_preferences.enabled || !_preferences.lowStockAlerts) return;

    await _showLocalNotification(
      title: 'Stock faible',
      body: '$itemName : $currentQty restant (min: $minStock)',
      type: NotificationType.lowStock,
      highPriority: true,
      payload: jsonEncode({
        'type': NotificationType.lowStock.key,
        'item_id': itemId,
        'item_name': itemName,
        'current_qty': currentQty,
        'min_stock': minStock,
      }),
    );
  }

  /// Affiche une notification pour une demande d'achat approuvée
  Future<void> showPurchaseApprovedNotification({
    required String requestName,
    required String requestId,
  }) async {
    if (!_preferences.enabled || !_preferences.purchaseRequestAlerts) return;

    await _showLocalNotification(
      title: 'Demande approuvée',
      body: '"$requestName" a été approuvée',
      type: NotificationType.purchaseRequestApproved,
      payload: jsonEncode({
        'type': NotificationType.purchaseRequestApproved.key,
        'request_id': requestId,
        'request_name': requestName,
      }),
    );
  }

  /// Affiche une notification pour un équipement assigné
  Future<void> showEquipmentAssignedNotification({
    required String equipmentName,
    required String assignedTo,
    String? equipmentId,
  }) async {
    if (!_preferences.enabled || !_preferences.equipmentAlerts) return;

    await _showLocalNotification(
      title: 'Équipement assigné',
      body: '$equipmentName a été assigné à $assignedTo',
      type: NotificationType.equipmentAssigned,
      payload: jsonEncode({
        'type': NotificationType.equipmentAssigned.key,
        'equipment_id': equipmentId,
        'equipment_name': equipmentName,
        'assigned_to': assignedTo,
      }),
    );
  }

  /// Planifie des vérifications de stock faible
  Future<void> scheduleStockChecks(List<Map<String, dynamic>> inventory) async {
    if (!_preferences.enabled || !_preferences.lowStockAlerts) return;

    for (final entry in inventory) {
      final item = entry['item'] as Map<String, dynamic>?;
      if (item == null) continue;

      final meta = item['meta'] as Map<String, dynamic>?;
      final minStock = (meta?['min_stock'] as num?)?.toInt();
      if (minStock == null) continue;

      final totalQty = (entry['total_qty'] as num?)?.toInt() ?? 0;
      if (totalQty < minStock) {
        await showLowStockNotification(
          itemName: item['name']?.toString() ?? 'Article inconnu',
          currentQty: totalQty,
          minStock: minStock,
          itemId: item['id']?.toString(),
        );
      }
    }
  }

  /// Charge les préférences depuis le stockage local
  Future<void> _loadPreferences() async {
    try {
      final userId = Supa.i.auth.currentUser?.id;
      if (userId == null) return;

      final data = await OfflineStorage.instance
          .getPreference('notification_preferences_$userId');
      if (data != null) {
        _preferences = NotificationPreferences.fromJson(
          jsonDecode(data) as Map<String, dynamic>,
        );
      }
    } catch (e) {
      debugPrint('❌ Erreur de chargement des préférences: $e');
    }
  }

  /// Sauvegarde les préférences
  Future<void> savePreferences(NotificationPreferences preferences) async {
    try {
      final userId = Supa.i.auth.currentUser?.id;
      if (userId == null) return;

      _preferences = preferences;
      await OfflineStorage.instance.setPreference(
        'notification_preferences_$userId',
        jsonEncode(preferences.toJson()),
      );

      debugPrint('✅ Préférences de notifications sauvegardées');
    } catch (e) {
      debugPrint('❌ Erreur de sauvegarde des préférences: $e');
    }
  }

  /// Récupère les préférences actuelles
  NotificationPreferences get preferences => _preferences;

  /// Teste les notifications
  Future<void> testNotification() async {
    debugPrint('🧪 TEST: Début du test de notification');
    debugPrint('🧪 TEST: Préférences enabled = ${_preferences.enabled}');
    debugPrint(
        '🧪 TEST: Préférences systemAlerts = ${_preferences.systemAlerts}');

    try {
      await _showLocalNotification(
        title: 'Test de notification',
        body: 'Si tu vois ce message, les notifications fonctionnent ! 🎉',
        type: NotificationType.systemAlert,
        highPriority: true,
      );
      debugPrint('✅ TEST: Notification envoyée avec succès');
    } catch (e) {
      debugPrint('❌ TEST: Erreur lors de l\'envoi: $e');
    }
  }

  /// Nettoie les ressources
  void dispose() {
    _realtimeChannel?.unsubscribe();
    _notificationTapController.close();
  }
}
