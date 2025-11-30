# 🚀 Exemples Avancés - Système de Notifications

## Table des Matières

1. [Notifications Automatiques de Stock](#1-notifications-automatiques-de-stock)
2. [Notifications d'Équipe](#2-notifications-déquipe)
3. [Notifications Planifiées](#3-notifications-planifiées)
4. [Gestion des Clics](#4-gestion-des-clics)
5. [Notifications Riches](#5-notifications-riches)

---

## 1. Notifications Automatiques de Stock

### Surveiller le stock en continu

Intégrer dans votre logique de rafraîchissement :

```dart
// Dans company_gate.dart, méthode _refreshAll()
@override
Future<void> _refreshAll() async {
  // ... code existant ...
  
  // Après avoir chargé l'inventaire
  if (_inventory.isNotEmpty) {
    // Vérifier et envoyer les notifications de stock faible
    await NotificationService.instance.scheduleStockChecks(
      _inventory.map((entry) => {
        'item': entry.item,
        'total_qty': entry.totalQty,
      }).toList(),
    );
  }
}
```

### Notification sur ajustement de stock

Quand un utilisateur modifie le stock :

```dart
Future<void> _handleStockAdjustment({
  required String itemName,
  required int oldQty,
  required int newQty,
}) async {
  final delta = newQty - oldQty;
  
  // Si c'est un gros changement, notifier
  if (delta.abs() > 100) {
    await NotificationService.instance._showLocalNotification(
      title: 'Ajustement important',
      body: '$itemName : ${delta > 0 ? '+' : ''}$delta unités',
      type: NotificationType.inventoryAdjustment,
      highPriority: true,
      payload: jsonEncode({
        'type': 'inventory_adjustment',
        'item_name': itemName,
        'delta': delta,
      }),
    );
  }
}
```

---

## 2. Notifications d'Équipe

### Notifier tous les membres quand une demande est approuvée

Dans votre service backend (Supabase Edge Function) :

```typescript
// Quand une demande est approuvée
const approvedRequestId = "...";

// Récupérer les détails de la demande
const { data: request } = await supabase
    .from("purchase_requests")
    .select("*, created_by")
    .eq("id", approvedRequestId)
    .single();

if (request) {
    // Notifier le créateur
    await supabase.functions.invoke("send-notification", {
        body: {
            user_id: request.created_by,
            type: "purchase_approved",
            title: "Demande approuvée",
            body: `Ta demande "${request.name}" a été approuvée ! 🎉`,
            data: {
                request_id: approvedRequestId,
            },
        },
    });
}
```

### Notifier un utilisateur quand un équipement lui est assigné

```dart
Future<void> _notifyEquipmentAssignment({
  required String equipmentId,
  required String equipmentName,
  required String userId,
  required String userName,
}) async {
  // Appeler la fonction Edge
  final response = await Supa.i.functions.invoke(
    'send-notification',
    body: {
      'user_id': userId,
      'type': 'equipment_assigned',
      'title': 'Équipement assigné',
      'body': '$equipmentName a été assigné à $userName',
      'data': {
        'equipment_id': equipmentId,
        'equipment_name': equipmentName,
      },
    },
  );
}
```

---

## 3. Notifications Planifiées

### Rappel quotidien pour vérifier le stock

Utiliser `flutter_local_notifications` pour planifier :

```dart
import 'package:timezone/timezone.dart' as tz;

Future<void> scheduleDailyStockCheck() async {
  await NotificationService.instance._localNotifications.zonedSchedule(
    0, // ID unique
    '📦 Vérification de stock',
    'N\'oublie pas de vérifier les niveaux de stock aujourd\'hui',
    _nextInstanceOf10AM(),
    const NotificationDetails(
      android: AndroidNotificationDetails(
        'daily_reminders',
        'Rappels quotidiens',
        channelDescription: 'Rappels quotidiens importants',
        importance: Importance.defaultImportance,
      ),
      iOS: DarwinNotificationDetails(),
    ),
    androidScheduleMode: AndroidScheduleMode.exactAllowWhileIdle,
    uiLocalNotificationDateInterpretation:
        UILocalNotificationDateInterpretation.absoluteTime,
    matchDateTimeComponents: DateTimeComponents.time,
  );
}

tz.TZDateTime _nextInstanceOf10AM() {
  final now = tz.TZDateTime.now(tz.local);
  var scheduledDate = tz.TZDateTime(
    tz.local,
    now.year,
    now.month,
    now.day,
    10, // 10h00
  );
  
  if (scheduledDate.isBefore(now)) {
    scheduledDate = scheduledDate.add(const Duration(days: 1));
  }
  
  return scheduledDate;
}
```

### Rappel hebdomadaire pour la maintenance

```dart
Future<void> scheduleWeeklyMaintenanceReminder() async {
  await NotificationService.instance._localNotifications.zonedSchedule(
    1, // ID unique
    '🔧 Maintenance hebdomadaire',
    'C\'est l\'heure de vérifier ton équipement',
    _nextMonday9AM(),
    const NotificationDetails(
      android: AndroidNotificationDetails(
        'weekly_reminders',
        'Rappels hebdomadaires',
        importance: Importance.high,
      ),
      iOS: DarwinNotificationDetails(),
    ),
    androidScheduleMode: AndroidScheduleMode.exactAllowWhileIdle,
    uiLocalNotificationDateInterpretation:
        UILocalNotificationDateInterpretation.absoluteTime,
    matchDateTimeComponents: DateTimeComponents.dayOfWeekAndTime,
  );
}
```

---

## 4. Gestion des Clics

### Naviguer vers la bonne page au clic

Dans `main.dart` ou `company_gate.dart` :

```dart
@override
void initState() {
  super.initState();
  
  // Écouter les clics sur notifications
  NotificationService.instance.onNotificationTap.listen((data) {
    _handleNotificationClick(data);
  });
}

void _handleNotificationClick(Map<String, dynamic> data) {
  final type = data['type'] as String?;
  
  switch (type) {
    case 'low_stock':
      final itemId = data['item_id'] as String?;
      if (itemId != null) {
        // Naviguer vers l'onglet inventaire et filtrer sur l'item
        setState(() => _currentTab = _GateTab.inventory);
        // Optionnel: scroller vers l'item ou le mettre en surbrillance
      }
      break;
      
    case 'purchase_approved':
      final requestId = data['request_id'] as String?;
      if (requestId != null) {
        // Naviguer vers l'onglet liste et ouvrir la demande
        setState(() => _currentTab = _GateTab.list);
        // Optionnel: ouvrir un dialog avec les détails
      }
      break;
      
    case 'equipment_assigned':
      final equipmentId = data['equipment_id'] as String?;
      if (equipmentId != null) {
        // Naviguer vers l'onglet équipement
        setState(() => _currentTab = _GateTab.equipment);
      }
      break;
      
    default:
      // Notification inconnue, aller à l'accueil
      setState(() => _currentTab = _GateTab.home);
  }
}
```

---

## 5. Notifications Riches

### Notification avec image (Android)

```dart
Future<void> showRichNotification({
  required String title,
  required String body,
  required String imageUrl,
}) async {
  // Télécharger l'image
  final response = await http.get(Uri.parse(imageUrl));
  final bytes = response.bodyBytes;
  
  final bigPictureStyleInformation = BigPictureStyleInformation(
    ByteArrayAndroidBitmap.fromBase64String(base64Encode(bytes)),
    largeIcon: ByteArrayAndroidBitmap.fromBase64String(base64Encode(bytes)),
    contentTitle: title,
    summaryText: body,
  );
  
  final androidDetails = AndroidNotificationDetails(
    'rich_notifications',
    'Notifications enrichies',
    styleInformation: bigPictureStyleInformation,
    importance: Importance.high,
  );
  
  await NotificationService.instance._localNotifications.show(
    DateTime.now().millisecondsSinceEpoch ~/ 1000,
    title,
    body,
    NotificationDetails(android: androidDetails),
  );
}
```

### Notification avec actions rapides

```dart
const androidDetails = AndroidNotificationDetails(
  'actionable_channel',
  'Notifications avec actions',
  importance: Importance.high,
  actions: <AndroidNotificationAction>[
    AndroidNotificationAction(
      'approve',
      'Approuver',
      showsUserInterface: true,
    ),
    AndroidNotificationAction(
      'reject',
      'Rejeter',
      showsUserInterface: true,
    ),
  ],
);

// Gérer les actions
NotificationService.instance._localNotifications
    .resolvePlatformSpecificImplementation<
        AndroidFlutterLocalNotificationsPlugin>()
    ?.setOnNotificationActionReceived((response) {
  final actionId = response.actionId;
  
  if (actionId == 'approve') {
    // Logique d'approbation
  } else if (actionId == 'reject') {
    // Logique de rejet
  }
});
```

---

## 6. Analytics et Tracking

### Logger les notifications envoyées

```dart
Future<void> _logNotificationSent({
  required String type,
  required String userId,
  Map<String, dynamic>? data,
}) async {
  await Supa.i.from('notification_logs').insert({
    'type': type,
    'target_user_id': userId,
    'data': data,
    'sent_at': DateTime.now().toUtc().toIso8601String(),
  });
}
```

### Tracker l'engagement

Créer une table `notification_engagement` :

```sql
CREATE TABLE notification_engagement (
    id UUID DEFAULT gen_random_uuid() PRIMARY KEY,
    notification_id UUID REFERENCES notification_logs(id),
    user_id UUID REFERENCES auth.users(id),
    action TEXT NOT NULL, -- 'opened', 'dismissed', 'clicked_action'
    created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW()
);
```

Puis logger les actions :

```dart
void _handleNotificationClick(Map<String, dynamic> data) {
  final notificationId = data['notification_id'] as String?;
  
  if (notificationId != null) {
    Supa.i.from('notification_engagement').insert({
      'notification_id': notificationId,
      'user_id': Supa.i.auth.currentUser?.id,
      'action': 'opened',
    });
  }
  
  // ... reste de la logique de navigation
}
```

---

## 7. Notifications Groupées

### Grouper les notifications similaires (Android)

```dart
Future<void> showGroupedNotifications(List<String> messages) async {
  const groupKey = 'com.yourcompany.logtekgi.STOCK_ALERTS';
  
  // Envoyer les notifications individuelles
  for (var i = 0; i < messages.length; i++) {
    await NotificationService.instance._localNotifications.show(
      i,
      'Stock faible',
      messages[i],
      NotificationDetails(
        android: AndroidNotificationDetails(
          'stock_alerts',
          'Alertes de stock',
          groupKey: groupKey,
        ),
      ),
    );
  }
  
  // Notification de résumé du groupe
  await NotificationService.instance._localNotifications.show(
    99999,
    'Alertes de stock',
    '${messages.length} articles en stock faible',
    const NotificationDetails(
      android: AndroidNotificationDetails(
        'stock_alerts',
        'Alertes de stock',
        setAsGroupSummary: true,
      ),
    ),
  );
}
```

---

## 8. Badge d'App (iOS)

### Mettre à jour le badge

```dart
Future<void> updateBadgeCount(int count) async {
  await NotificationService.instance._localNotifications
      .resolvePlatformSpecificImplementation<
          IOSFlutterLocalNotificationsPlugin>()
      ?.requestPermissions(badge: true);
  
  // Sur iOS, le badge se met à jour automatiquement
  // Pour le contrôler manuellement:
  // FlutterAppBadger.updateBadgeCount(count);
}
```

---

## Ressources

- [Flutter Local Notifications Docs](https://pub.dev/packages/flutter_local_notifications)
- [Firebase Cloud Messaging](https://firebase.google.com/docs/cloud-messaging)
- [Timezone Package](https://pub.dev/packages/timezone)
