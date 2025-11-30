# 🚀 Installation des Notifications - Solution Simple

## ⚡ Méthode Recommandée (30 secondes)

Puisque tu as des conflits de migrations, le plus simple est d'appliquer
directement en SQL :

### **Étape 1 : Copier le SQL**

```bash
# Afficher le contenu de la migration
cat supabase/migrations/20251116000000_create_user_notifications.sql
```

### **Étape 2 : Appliquer dans Supabase**

1. Va sur [Supabase Dashboard](https://supabase.com/dashboard)
2. Ouvre ton projet
3. Va dans **SQL Editor** (dans le menu de gauche)
4. **Copie-colle** tout le contenu de la migration
5. Clique **Run** (ou CMD+Enter / Ctrl+Enter)

### **Étape 3 : Vérifier**

Exécute dans le même SQL Editor :

```sql
-- Vérifier que la table existe
SELECT COUNT(*) FROM user_notifications;

-- Devrait retourner: 0 (table vide mais elle existe !)
```

---

## ✅ Alternative : Marquer les Anciennes Migrations

Si tu veux vraiment utiliser `supabase db push`, marque les anciennes migrations
comme déjà appliquées :

```bash
# Ne PAS faire ça si tu n'es pas sûr !
# Ça peut casser des choses si les migrations n'ont pas été appliquées

supabase migration repair 20241113 --status applied
supabase migration repair 20241114 --status applied
supabase db push
```

---

## 🎯 Méthode Rapide (Copier-Coller Direct)

**Ouvre Supabase SQL Editor et exécute ça :**

```sql
-- Table pour les notifications utilisateur (via Supabase Realtime)
CREATE TABLE IF NOT EXISTS user_notifications (
    id UUID DEFAULT gen_random_uuid() PRIMARY KEY,
    user_id UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
    company_id UUID REFERENCES companies(id) ON DELETE CASCADE,
    type TEXT NOT NULL,
    title TEXT NOT NULL,
    body TEXT NOT NULL,
    data JSONB,
    priority TEXT DEFAULT 'normal',
    read_at TIMESTAMP WITH TIME ZONE,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW()
);

-- Index pour performances
CREATE INDEX IF NOT EXISTS idx_user_notifications_user_id 
    ON user_notifications(user_id);
    
CREATE INDEX IF NOT EXISTS idx_user_notifications_created_at 
    ON user_notifications(created_at DESC);

CREATE INDEX IF NOT EXISTS idx_user_notifications_unread 
    ON user_notifications(user_id, read_at) 
    WHERE read_at IS NULL;

-- RLS (Row Level Security)
ALTER TABLE user_notifications ENABLE ROW LEVEL SECURITY;

-- Les utilisateurs peuvent voir leurs propres notifications
CREATE POLICY "Users can view their own notifications"
    ON user_notifications FOR SELECT
    USING (auth.uid() = user_id);

-- Les utilisateurs peuvent marquer leurs notifications comme lues
CREATE POLICY "Users can update their own notifications"
    ON user_notifications FOR UPDATE
    USING (auth.uid() = user_id)
    WITH CHECK (auth.uid() = user_id);

-- Les utilisateurs peuvent supprimer leurs notifications
CREATE POLICY "Users can delete their own notifications"
    ON user_notifications FOR DELETE
    USING (auth.uid() = user_id);

-- Fonction pour envoyer une notification à un utilisateur
CREATE OR REPLACE FUNCTION send_notification_to_user(
    p_user_id UUID,
    p_type TEXT,
    p_title TEXT,
    p_body TEXT,
    p_data JSONB DEFAULT NULL,
    p_priority TEXT DEFAULT 'normal'
)
RETURNS UUID
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
    v_notification_id UUID;
BEGIN
    INSERT INTO user_notifications (
        user_id,
        type,
        title,
        body,
        data,
        priority
    ) VALUES (
        p_user_id,
        p_type,
        p_title,
        p_body,
        p_data,
        p_priority
    )
    RETURNING id INTO v_notification_id;
    
    RETURN v_notification_id;
END;
$$;

-- Fonction pour envoyer une notification à tous les membres d'une entreprise
CREATE OR REPLACE FUNCTION send_notification_to_company(
    p_company_id UUID,
    p_type TEXT,
    p_title TEXT,
    p_body TEXT,
    p_data JSONB DEFAULT NULL,
    p_priority TEXT DEFAULT 'normal'
)
RETURNS INTEGER
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
    v_count INTEGER := 0;
    v_member RECORD;
BEGIN
    FOR v_member IN 
        SELECT user_uid
        FROM memberships
        WHERE company_id = p_company_id
        AND status = 'active'
    LOOP
        INSERT INTO user_notifications (
            user_id,
            company_id,
            type,
            title,
            body,
            data,
            priority
        ) VALUES (
            v_member.user_uid,
            p_company_id,
            p_type,
            p_title,
            p_body,
            p_data,
            p_priority
        );
        
        v_count := v_count + 1;
    END LOOP;
    
    RETURN v_count;
END;
$$;

-- Trigger pour nettoyer les vieilles notifications
CREATE OR REPLACE FUNCTION cleanup_old_notifications()
RETURNS TRIGGER
LANGUAGE plpgsql
AS $$
BEGIN
    DELETE FROM user_notifications
    WHERE user_id = NEW.user_id
    AND id NOT IN (
        SELECT id
        FROM user_notifications
        WHERE user_id = NEW.user_id
        ORDER BY created_at DESC
        LIMIT 100
    );
    
    RETURN NEW;
END;
$$;

CREATE TRIGGER trigger_cleanup_old_notifications
    AFTER INSERT ON user_notifications
    FOR EACH ROW
    EXECUTE FUNCTION cleanup_old_notifications();

-- Activer Realtime pour cette table
ALTER PUBLICATION supabase_realtime ADD TABLE user_notifications;
```

**Puis vérifie :**

```sql
-- Test !
SELECT send_notification_to_user(
    auth.uid(),
    'system_alert',
    'Migration réussie !',
    'Le système de notifications fonctionne ! 🎉'
);

-- Vérifier qu'elle a été créée
SELECT * FROM user_notifications ORDER BY created_at DESC LIMIT 1;
```

---

## ✅ C'est Fait ?

Après avoir exécuté le SQL :

1. **Lance ton app Flutter**
2. Va dans **Plus > Profil > Paramètres de notifications**
3. Clique **"Tester les notifications"**
4. 📱 **BOOM !** Tu vois la notification !

---

**Raison du conflit :** Il y a des migrations locales qui existent déjà sur ton
serveur Supabase. Plutôt que de régler tous les conflits, c'est plus rapide
d'appliquer directement le SQL.

**C'est équivalent !** Que tu utilises `db push` ou le SQL Editor, le résultat
est le même. 🎯
