-- Script de validation après migration des notifications
-- Exécute ce script dans Supabase SQL Editor pour vérifier que tout fonctionne

-- 1. Vérifier que la table existe
DO $$
BEGIN
    IF EXISTS (SELECT FROM pg_tables WHERE tablename = 'user_notifications') THEN
        RAISE NOTICE '✅ Table user_notifications existe';
    ELSE
        RAISE EXCEPTION '❌ Table user_notifications n''existe pas';
    END IF;
END $$;

-- 2. Vérifier les index
DO $$
DECLARE
    v_count INTEGER;
BEGIN
    SELECT COUNT(*) INTO v_count
    FROM pg_indexes
    WHERE tablename = 'user_notifications';
    
    IF v_count >= 3 THEN
        RAISE NOTICE '✅ Index créés (% trouvés)', v_count;
    ELSE
        RAISE WARNING '⚠️ Seulement % index trouvés (attendu: 3+)', v_count;
    END IF;
END $$;

-- 3. Vérifier RLS
DO $$
DECLARE
    v_enabled BOOLEAN;
BEGIN
    SELECT relrowsecurity INTO v_enabled
    FROM pg_class
    WHERE relname = 'user_notifications';
    
    IF v_enabled THEN
        RAISE NOTICE '✅ RLS activé';
    ELSE
        RAISE EXCEPTION '❌ RLS non activé';
    END IF;
END $$;

-- 4. Vérifier les fonctions
DO $$
BEGIN
    IF EXISTS (SELECT FROM pg_proc WHERE proname = 'send_notification_to_user') THEN
        RAISE NOTICE '✅ Fonction send_notification_to_user existe';
    ELSE
        RAISE EXCEPTION '❌ Fonction send_notification_to_user manquante';
    END IF;
    
    IF EXISTS (SELECT FROM pg_proc WHERE proname = 'send_notification_to_company') THEN
        RAISE NOTICE '✅ Fonction send_notification_to_company existe';
    ELSE
        RAISE EXCEPTION '❌ Fonction send_notification_to_company manquante';
    END IF;
    
    IF EXISTS (SELECT FROM pg_proc WHERE proname = 'cleanup_old_notifications') THEN
        RAISE NOTICE '✅ Fonction cleanup_old_notifications existe';
    ELSE
        RAISE EXCEPTION '❌ Fonction cleanup_old_notifications manquante';
    END IF;
END $$;

-- 5. Vérifier Realtime
DO $$
DECLARE
    v_realtime_enabled BOOLEAN;
BEGIN
    SELECT EXISTS (
        SELECT 1 
        FROM pg_publication_tables 
        WHERE pubname = 'supabase_realtime' 
        AND tablename = 'user_notifications'
    ) INTO v_realtime_enabled;
    
    IF v_realtime_enabled THEN
        RAISE NOTICE '✅ Realtime activé pour user_notifications';
    ELSE
        RAISE WARNING '⚠️ Realtime NON activé - Exécute: ALTER PUBLICATION supabase_realtime ADD TABLE user_notifications;';
    END IF;
END $$;

-- 6. Test fonctionnel (envoyer une notification de test)
DO $$
DECLARE
    v_user_id UUID;
    v_notification_id UUID;
BEGIN
    -- Prendre le premier utilisateur
    SELECT id INTO v_user_id FROM auth.users LIMIT 1;
    
    IF v_user_id IS NULL THEN
        RAISE WARNING '⚠️ Aucun utilisateur trouvé pour tester';
    ELSE
        -- Envoyer une notification de test
        SELECT send_notification_to_user(
            v_user_id,
            'system_alert',
            'Test de validation',
            'Migration réussie ! Le système de notifications fonctionne 🎉',
            jsonb_build_object('test', true),
            'normal'
        ) INTO v_notification_id;
        
        IF v_notification_id IS NOT NULL THEN
            RAISE NOTICE '✅ Notification de test envoyée (ID: %)', v_notification_id;
            RAISE NOTICE '   → Vérifie dans ton app Flutter !';
        ELSE
            RAISE EXCEPTION '❌ Échec de l''envoi de notification';
        END IF;
    END IF;
END $$;

-- 7. Afficher un résumé
DO $$
DECLARE
    v_count INTEGER;
BEGIN
    SELECT COUNT(*) INTO v_count FROM user_notifications;
    
    RAISE NOTICE '';
    RAISE NOTICE '━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━';
    RAISE NOTICE '📊 RÉSUMÉ DE LA VALIDATION';
    RAISE NOTICE '━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━';
    RAISE NOTICE 'Notifications dans la DB: %', v_count;
    RAISE NOTICE '';
    RAISE NOTICE '✅ Migration validée avec succès !';
    RAISE NOTICE '';
    RAISE NOTICE '🚀 PROCHAINES ÉTAPES:';
    RAISE NOTICE '1. Lance ton app Flutter';
    RAISE NOTICE '2. Va dans Plus > Profil > Paramètres de notifications';
    RAISE NOTICE '3. Clique sur "Tester les notifications"';
    RAISE NOTICE '';
    RAISE NOTICE '💡 Pour envoyer manuellement:';
    RAISE NOTICE '   SELECT send_notification_to_user(';
    RAISE NOTICE '       ''ton-user-id''::UUID,';
    RAISE NOTICE '       ''system_alert'',';
    RAISE NOTICE '       ''Titre'',';
    RAISE NOTICE '       ''Message''';
    RAISE NOTICE '   );';
    RAISE NOTICE '━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━';
END $$;
