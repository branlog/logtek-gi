# 🚀 Démarrage Rapide - Notifications

## ⚡ 3 Commandes pour Activer les Notifications

```bash
# 1. Aller dans le dossier du projet
cd /Users/brandon/Downloads/logtek-gi-starter/flutter_app

# 2. Pusher la migration vers Supabase
supabase db push

# 3. C'est tout ! 🎉
```

## ✅ Que faire si tu n'as pas encore lié ton projet Supabase ?

```bash
# Lier ton projet (une seule fois)
supabase link --project-ref=TON_PROJECT_REF

# Tu peux trouver ton project-ref dans:
# https://supabase.com/dashboard > Ton Projet > Settings > General > Reference ID
```

## 🧪 Tester

### Dans l'App Flutter

1. Lance l'app
2. Va dans **Plus > Profil**
3. Clique sur **"Paramètres de notifications"**
4. Clique sur **"Tester les notifications"**
5. 📱 **BOOM !** Tu verras une notification !

### En SQL (dans Supabase Dashboard)

```sql
-- Remplace par TON user ID
SELECT send_notification_to_user(
    'ton-user-id-ici'::UUID,
    'system_alert',
    'Test depuis SQL',
    'Si tu vois ça, tout fonctionne parfaitement ! 🎉',
    NULL,
    'high'
);
```

**Comment trouver ton user ID ?**

```sql
-- Dans Supabase SQL Editor
SELECT id, email FROM auth.users;
```

## 🎯 Premiers Cas d'Usage

### 1. Notification de Stock Faible (Automatique)

```sql
-- Créer un trigger pour notifier automatiquement
CREATE OR REPLACE FUNCTION check_low_stock_on_update()
RETURNS TRIGGER
LANGUAGE plpgsql
AS $$
DECLARE
    v_total INTEGER;
    v_min INTEGER;
    v_name TEXT;
BEGIN
    -- Calculer stock total
    SELECT COALESCE(SUM(qty), 0) INTO v_total
    FROM stock WHERE item_id = NEW.item_id;
    
    -- Récupérer minimum et nom
    SELECT (meta->>'min_stock')::INTEGER, name
    INTO v_min, v_name
    FROM items WHERE id = NEW.item_id;
    
    -- Si bas, notifier
    IF v_min IS NOT NULL AND v_total < v_min THEN
        PERFORM send_notification_to_company(
            NEW.company_id,
            'low_stock',
            'Stock faible 📦',
            v_name || ' : ' || v_total || ' restant (min: ' || v_min || ')',
            jsonb_build_object('item_id', NEW.item_id),
            'high'
        );
    END IF;
    
    RETURN NEW;
END;
$$;

-- Activer le trigger
DROP TRIGGER IF EXISTS trigger_check_low_stock ON stock;
CREATE TRIGGER trigger_check_low_stock
    AFTER INSERT OR UPDATE ON stock
    FOR EACH ROW
    EXECUTE FUNCTION check_low_stock_on_update();
```

### 2. Notification Manuelle depuis l'App

```dart
// Dans ton code Flutter
await Supa.i.rpc('send_notification_to_company', params: {
  'p_company_id': companyId,
  'p_type': 'team_message',
  'p_title': 'Réunion d\'équipe',
  'p_body': 'Réunion à 14h dans la salle de conférence',
  'p_priority': 'normal',
});
```

## 🐛 Résolution Rapide

### Erreur: "relation user_notifications does not exist"

➡️ La migration n'a pas été appliquée

```bash
supabase db push
```

### Erreur: "project not linked"

➡️ Lier ton projet d'abord

```bash
supabase link --project-ref=TON_PROJECT_REF
```

### Les notifications ne s'affichent pas

1. ✅ Vérifier que la table existe: `SELECT * FROM user_notifications;`
2. ✅ Vérifier Realtime dans Dashboard > Database > Replication
3. ✅ Redémarrer l'app Flutter

## 📚 Documentation Complète

- 📖 **Guide complet**: `NOTIFICATIONS_SUPABASE.md`
- 🛠️ **Supabase README**: `supabase/README.md`
- 💡 **Exemples avancés**: Voir `NOTIFICATIONS_SUPABASE.md`

## ⏱️ Temps Total d'Installation

- ✅ Migration: **30 secondes**
- ✅ Test: **30 secondes**
- ✅ Premier trigger: **2 minutes**

**Total: Moins de 3 minutes !** 🚀

---

**C'est prêt !** Lance `supabase db push` et tu es bon ! 🎉
