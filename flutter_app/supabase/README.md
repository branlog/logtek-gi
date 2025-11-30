# 🗄️ Supabase - Migrations & Functions

## 📋 Migrations Disponibles

### `20241122000001_create_user_notifications.sql`

Crée le système de notifications en temps réel :

- ✅ Table `user_notifications`
- ✅ Fonction `send_notification_to_user()`
- ✅ Fonction `send_notification_to_company()`
- ✅ Trigger de nettoyage automatique
- ✅ RLS (Row Level Security)
- ✅ Realtime activé

## 🚀 Installation Rapide

### Méthode 1 : Script Automatique (Recommandé)

```bash
cd supabase
./push-notifications-migration.sh
```

### Méthode 2 : Commande Directe

```bash
# Dans le dossier flutter_app/
supabase db push
```

### Méthode 3 : Manuel (SQL Editor)

1. Aller sur [Supabase Dashboard](https://supabase.com/dashboard)
2. Ouvrir SQL Editor
3. Copier/coller le contenu de
   `migrations/20241122000001_create_user_notifications.sql`
4. Exécuter

## ✅ Vérification

Après le push, vérifier que tout fonctionne :

```sql
-- 1. Vérifier que la table existe
SELECT * FROM user_notifications LIMIT 1;

-- 2. Vérifier que les fonctions existent
SELECT send_notification_to_user(
    auth.uid(),
    'system_alert',
    'Test',
    'Ça fonctionne ! 🎉'
);

-- 3. Vérifier Realtime
-- Dans Supabase Dashboard > Database > Replication
-- `user_notifications` doit être coché
```

## 📡 Edge Functions

### `send-notification-supabase`

Fonction serverless pour envoyer des notifications via API.

**Déployer :**

```bash
supabase functions deploy send-notification-supabase
```

**Utiliser :**

```bash
curl -X POST \
  https://[ton-projet].supabase.co/functions/v1/send-notification-supabase \
  -H "Authorization: Bearer [ton-anon-key]" \
  -H "Content-Type: application/json" \
  -d '{
    "user_id": "user-uuid",
    "type": "low_stock",
    "title": "Stock faible",
    "body": "Vis 10mm : 5 restant",
    "priority": "high"
  }'
```

## 🛠️ Commandes Utiles

```bash
# Lier à un projet Supabase
supabase link --project-ref=ton-project-ref

# Voir le statut
supabase status

# Pusher toutes les migrations
supabase db push

# Créer une nouvelle migration
supabase migration new nom_de_la_migration

# Reset la base (ATTENTION: efface les données)
supabase db reset

# Voir les différences
supabase db diff
```

## 📚 Documentation

- 📖 Guide complet: `../NOTIFICATIONS_SUPABASE.md`
- 🚀 Exemples d'usage: Voir le guide
- 🔧 Dépannage: Voir `NOTIFICATIONS_SUPABASE.md`

## 🔗 Liens Utiles

- [Supabase Dashboard](https://supabase.com/dashboard)
- [Supabase CLI Docs](https://supabase.com/docs/guides/cli)
- [Supabase Realtime](https://supabase.com/docs/guides/realtime)
