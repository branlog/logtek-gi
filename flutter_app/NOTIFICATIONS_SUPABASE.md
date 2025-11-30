# 🔔 Système de Notifications - Version Supabase

## ✅ Solution 100% Supabase (Sans Firebase)

Ce système de notifications utilise **uniquement Supabase** :

- ✅ **Supabase Realtime** pour les notifications en temps réel
- ✅ **Notifications locales** pour les alertes sur l'appareil
- ✅ **Aucune configuration Firebase** requise !
- ✅ **Plus simple et rapide** à mettre en place

## 🚀 Installation Rapide

### Étape 1 : Installer les dépendances

```bash
cd /Users/brandon/Downloads/logtek-gi-starter/flutter_app
flutter pub get
```

### Étape 2 : Créer la table Supabase

Exécuter le script SQL dans votre Supabase SQL Editor :

```bash
supabase/migrations/create_user_notifications_table.sql
```

Ou utiliser Supabase CLI :

```bash
supabase db push supabase/migrations/create_user_notifications_table.sql
```

### Étape 3 : C'est tout ! 🎉

Redémarrer votre app et les notifications fonctionnent !

## 📋 Comment ça marche ?

### Architecture Simple

```
┌─────────────────┐
│   Your App      │
│  (Flutter)      │
└────────┬────────┘
         │
         ├─ Écoute Supabase Realtime
         │  (notifications en temps réel)
         │
         └─ Notifications locales
            (alertes sur l'appareil)
         
┌─────────────────┐
│   Supabase      │
│   Database      │
└─────────────────┘
```

### 1. **Notifications en Temps Réel**

L'app s'abonne à la table `user_notifications` via Supabase Realtime :

```dart
// Automatique dans NotificationService
_realtimeChannel = Supa.i
    .channel('notifications:$userId')
    .onPostgresChanges(
      event: PostgresChangeEvent.insert,
      table: 'user_notifications',
      filter: PostgresChangeFilter(column: 'user_id', value: userId),
      callback: (payload) {
        // Afficher la notification localement
      },
    )
    .subscribe();
```

### 2. **Envoi de Notifications**

Depuis votre backend ou Edge Function :

```sql
-- Envoyer à un utilisateur
SELECT send_notification_to_user(
    'user-id'::UUID,
    'low_stock',
    'Stock faible',
    'Vis 10mm : 5 restant (min: 20)',
    '{"item_id": "123"}'::JSONB,
    'high'
);

-- Envoyer à toute une entreprise
SELECT send_notification_to_company(
    'company-id'::UUID,
    'team_message',
    'Réunion d''équipe',
    'Réunion à 14h dans la salle de conférence',
    NULL,
    'normal'
);
```

## 💡 Exemples d'Utilisation

### Dans votre code Flutter

#### Notification de stock faible

```dart
await NotificationService.instance.showLowStockNotification(
  itemName: 'Vis 10mm',
  currentQty: 5,
  minStock: 20,
  itemId: 'item-123',
);
```

#### Vérification automatique des stocks

```dart
// Dans votre _refreshAll()
await NotificationService.instance.scheduleStockChecks(_inventory);
```

### Depuis une Edge Function Supabase

```typescript
import { createClient } from "@supabase/supabase-js";

const supabase = createClient(
    Deno.env.get("SUPABASE_URL")!,
    Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!,
);

// Envoyer une notification
await supabase.rpc("send_notification_to_user", {
    p_user_id: "user-uuid",
    p_type: "low_stock",
    p_title: "Stock faible",
    p_body: "Vis 10mm : 5 restant",
    p_data: { item_id: "123" },
    p_priority: "high",
});
```

### Depuis un Trigger SQL

```sql
-- Trigger quand une demande d'achat est approuvée
CREATE OR REPLACE FUNCTION notify_purchase_approved()
RETURNS TRIGGER
LANGUAGE plpgsql
AS $$
BEGIN
    IF NEW.status = 'approved' AND OLD.status != 'approved' THEN
        PERFORM send_notification_to_user(
            NEW.created_by,
            'purchase_approved',
            'Demande approuvée',
            'Ta demande "' || NEW.name || '" a été approuvée !',
            jsonb_build_object('request_id', NEW.id)
        );
    END IF;
    
    RETURN NEW;
END;
$$;

CREATE TRIGGER trigger_notify_purchase_approved
    AFTER UPDATE ON purchase_requests
    FOR EACH ROW
    EXECUTE FUNCTION notify_purchase_approved();
```

## ⚙️ Configuration

### Activer/Désactiver les Notifications

Aller dans : **Plus** > **Profil** > **Paramètres de notifications**

Vous pouvez configurer :

- ✅ Activer/désactiver par type de notification
- 🔇 Heures de silence (ex: 22h-7h)
- 🔊 Son et vibrations
- 🧪 Tester les notifications

### Types de Notifications Disponibles

| Type                    | Emoji | Description           |
| ----------------------- | ----- | --------------------- |
| `low_stock`             | 📦    | Stock faible          |
| `purchase_approved`     | ✅    | Demande approuvée     |
| `purchase_created`      | 📝    | Nouvelle demande      |
| `equipment_assigned`    | 🔧    | Équipement assigné    |
| `equipment_maintenance` | ⚠️    | Maintenance requise   |
| `inventory_adjustment`  | 📊    | Ajustement inventaire |
| `team_message`          | 💬    | Message d'équipe      |
| `system_alert`          | 🔔    | Alerte système        |

## 🎯 Automatisations Possibles

### 1. Alertes de Stock Automatiques

➡️ **Déjà inclus** : la migration `20251122_schedule_low_stock_checks.sql` crée `public.check_low_stock()` et programme automatiquement un job `pg_cron` quotidien (09h UTC) pour notifier toutes les entreprises ayant un article sous le seuil.

Tester l'audit immédiatement :

```sql
SELECT public.check_low_stock();
```

Adapter l'horaire (ex. 7h UTC) :

```sql
SELECT cron.unschedule('check-low-stock');
SELECT cron.schedule(
    'check-low-stock',
    '0 7 * * *',
    $$ SELECT public.check_low_stock(); $$
);
```

### 2. Notification sur Nouvel Équipement Assigné

```sql
CREATE OR REPLACE FUNCTION notify_equipment_assignment()
RETURNS TRIGGER
LANGUAGE plpgsql
AS $$
DECLARE
    v_equipment_name TEXT;
    v_assigned_to_uid UUID;
    v_assigned_to_name TEXT;
BEGIN
    -- Récupérer le nom de l'équipement
    SELECT name INTO v_equipment_name
    FROM equipment
    WHERE id = NEW.equipment_id;
    
    -- Récupérer l'info de l'utilisateur assigné
    v_assigned_to_uid := (NEW.meta->>'assigned_to')::UUID;
    
    IF v_assigned_to_uid IS NOT NULL THEN
        -- Notifier l'utilisateur
        PERFORM send_notification_to_user(
            v_assigned_to_uid,
            'equipment_assigned',
            'Équipement assigné',
            v_equipment_name || ' t''a été assigné',
            jsonb_build_object('equipment_id', NEW.equipment_id)
        );
    END IF;
    
    RETURN NEW;
END;
$$;
```

## 📱 Gestion des Clics

Écouter les clics sur notifications dans votre app :

```dart
@override
void initState() {
  super.initState();
  
  // Écouter les clics
  NotificationService.instance.onNotificationTap.listen((data) {
    final type = data['type'] as String?;
    
    switch (type) {
      case 'low_stock':
        // Naviguer vers l'inventaire
        final itemId = data['item_id'];
        _navigateToInventory(itemId);
        break;
        
      case 'purchase_approved':
        // Naviguer vers la liste
        _navigateToPurchaseRequests();
        break;
    }
  });
}
```

## 🎨 Personnalisation

### Ajouter un Nouveau Type de Notification

1. **Ajouter dans l'enum** (`notification_service.dart`)

```dart
enum NotificationType {
  // ... existants
  myCustomType('my_custom', 'Mon Type', '🎯'),
}
```

2. **Ajouter les préférences** (`NotificationPreferences`)

```dart
final bool myCustomAlerts;
```

3. **Mettre à jour la page de paramètres**

```dart
_NotificationTypeSwitch(
  icon: Icons.star,
  title: 'Mon type personnalisé',
  value: _preferences.myCustomAlerts,
  onChanged: (value) { ... },
),
```

## 🐛 Dépannage

### Les notifications ne s'affichent pas

1. **Vérifier que Realtime est activé**
   - Aller dans Supabase Dashboard > Database > Replication
   - Vérifier que `user_notifications` est dans la publication

2. **Vérifier les RLS**
   ```sql
   -- Tester manuellement
   SELECT * FROM user_notifications WHERE user_id = 'your-user-id';
   ```

3. **Vérifier les logs**
   ```dart
   // Dans la console Flutter
   // Vous devriez voir:
   // "✅ Abonné aux notifications Realtime Supabase"
   // "📬 Notification Realtime reçue: ..."
   ```

### La table n'apparaît pas dans Realtime

Exécuter manuellement :

```sql
ALTER PUBLICATION supabase_realtime ADD TABLE user_notifications;
```

## 🔒 Sécurité

- ✅ **RLS activé** - Les utilisateurs ne voient que leurs notifications
- ✅ **SECURITY DEFINER** - Les fonctions s'exécutent avec les bons privilèges
- ✅ **Nettoyage automatique** - Garde seulement les 100 dernières notifications
- ✅ **Stockage local** - Les préférences sont sauvegardées localement

## 📊 Avantages vs Firebase

| Fonctionnalité  | Supabase       | Firebase               |
| --------------- | -------------- | ---------------------- |
| Configuration   | ✅ Simple      | ❌ Complexe            |
| Dépendances     | 1 package      | 3+ packages            |
| Backend intégré | ✅ SQL         | ❌ Séparé              |
| Coût            | Gratuit (50k+) | Limites strictes       |
| Realtime        | ✅ Built-in    | ❌ Nécessite Firestore |
| Debugging       | ✅ SQL direct  | ❌ Console séparée     |

## 🚀 Prochaines Étapes

1. ✅ Installer les dépendances : `flutter pub get`
2. ✅ Créer la table : Exécuter `create_user_notifications_table.sql`
3. ✅ Tester : Aller dans Plus > Profil > Notifications > Test
4. ✅ Automatiser : Ajouter des triggers SQL pour vos cas d'usage

---

**C'est prêt à l'emploi !** Plus simple, plus rapide, 100% Supabase ! 🎉
