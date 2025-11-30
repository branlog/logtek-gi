-- Table pour les notifications utilisateur (via Supabase Realtime)
CREATE TABLE IF NOT EXISTS user_notifications (
    id UUID DEFAULT gen_random_uuid() PRIMARY KEY,
    user_id UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
    company_id UUID REFERENCES companies(id) ON DELETE CASCADE,
    type TEXT NOT NULL,
    title TEXT NOT NULL,
    body TEXT NOT NULL,
    data JSONB,
    priority TEXT DEFAULT 'normal', -- 'high' or 'normal'
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

DO $$
BEGIN
    IF EXISTS (
        SELECT 1 FROM pg_policies
        WHERE schemaname = 'public'
          AND tablename = 'user_notifications'
          AND policyname = 'Users can view their own notifications'
    ) THEN
        EXECUTE 'DROP POLICY "Users can view their own notifications" ON public.user_notifications';
    END IF;

    EXECUTE $$
        CREATE POLICY "Users can view their own notifications"
        ON public.user_notifications FOR SELECT
        USING (auth.uid() = user_id)
    $$;
END;
$$;

DO $$
BEGIN
    IF EXISTS (
        SELECT 1 FROM pg_policies
        WHERE schemaname = 'public'
          AND tablename = 'user_notifications'
          AND policyname = 'Users can update their own notifications'
    ) THEN
        EXECUTE 'DROP POLICY "Users can update their own notifications" ON public.user_notifications';
    END IF;

    EXECUTE $$
        CREATE POLICY "Users can update their own notifications"
        ON public.user_notifications FOR UPDATE
        USING (auth.uid() = user_id)
        WITH CHECK (auth.uid() = user_id)
    $$;
END;
$$;

DO $$
BEGIN
    IF EXISTS (
        SELECT 1 FROM pg_policies
        WHERE schemaname = 'public'
          AND tablename = 'user_notifications'
          AND policyname = 'Users can delete their own notifications'
    ) THEN
        EXECUTE 'DROP POLICY "Users can delete their own notifications" ON public.user_notifications';
    END IF;

    EXECUTE $$
        CREATE POLICY "Users can delete their own notifications"
        ON public.user_notifications FOR DELETE
        USING (auth.uid() = user_id)
    $$;
END;
$$;

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
    -- Parcourir tous les membres actifs de l'entreprise
    FOR v_member IN 
    SELECT user_uid
    FROM memberships
    WHERE company_id = p_company_id
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

-- Trigger pour nettoyer les vieilles notifications (optionnel)
-- Garde seulement les 100 dernières notifications par utilisateur
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
