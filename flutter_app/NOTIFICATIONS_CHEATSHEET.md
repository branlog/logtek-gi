# 🎯 Notifications - Commandes Essentielles

## ⚡ Installation (2 commandes)

```bash
# Si pas encore lié à Supabase
supabase link --project-ref=TON_PROJECT_REF

# Pusher la migration
supabase db push
```

**C'est tout ! Les notifications sont activées ! 🎉**

---

## ✅ Validation (Optionnel)

Dans Supabase SQL Editor, exécuter :

```bash
# Copier-coller le contenu de: supabase/validate_notifications.sql
```

Vous verrez :

```
✅ Table user_notifications existe
✅ Index créés (3 trouvés)
✅ RLS activé
✅ Fonction send_notification_to_user existe
✅ Fonction send_notification_to_company existe
✅ Fonction cleanup_old_notifications existe
✅ Realtime activé pour user_notifications
✅ Notification de test envoyée
```

---

## 🧪 Tester dans l'App

1. Lance l'app
2. **Plus** > **Profil** > **Paramètres de notifications**
3. Clique **"Tester les notifications"**
4. 📱 Tu vois une notification !

---

## 💡 Envoyer Manuellement (SQL)

```sql
-- À toi-même
SELECT send_notification_to_user(
    auth.uid(),
    'system_alert',
    'Mon test',
    'Ça marche ! 🎉'
);

-- À toute ton entreprise
SELECT send_notification_to_company(
    'ton-company-id'::UUID,
    'team_message',
    'Annonce',
    'Message pour tous'
);
```

---

## 🔗 Documentation Complète

- 📋 **Démarrage rapide** : `QUICKSTART_NOTIFICATIONS.md`
- 📖 **Guide complet** : `NOTIFICATIONS_SUPABASE.md`
- 🛠️ **Supabase** : `supabase/README.md`

---

**Temps total : 30 secondes** ⚡
