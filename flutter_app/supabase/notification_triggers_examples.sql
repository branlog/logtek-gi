-- Exemple de Triggers pour Envoyer des Notifications Automatiquement
-- (avec filtrage pour éviter les notifications de nos propres actions)

-- =========================================
-- 1. Notification quand une demande d'achat est créée
-- =========================================
CREATE OR REPLACE FUNCTION notify_purchase_request_created()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
    v_creator_name TEXT;
    v_member RECORD;
BEGIN
    -- Récupérer le nom du créateur
    SELECT full_name INTO v_creator_name
    FROM user_profiles
    WHERE user_uid = NEW.created_by;
    
    -- Notifier tous les admins/managers de l'entreprise (sauf le créateur)
    FOR v_member IN
        SELECT user_uid
        FROM memberships
            WHERE company_id = NEW.company_id
            AND role IN ('admin', 'manager')
        AND user_uid != NEW.created_by  -- IMPORTANT: Exclure le créateur
    LOOP
        PERFORM send_notification_to_user(
            v_member.user_uid,
            'purchase_created',
            'Nouvelle demande d''achat',
            (v_creator_name || ' a créé une demande: ' || NEW.name),
            jsonb_build_object(
                'request_id', NEW.id,
                'created_by', NEW.created_by  -- Inclure pour le filtrage côté app
            ),
            'normal'
        );
    END LOOP;
    
    RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trigger_notify_purchase_request_created ON purchase_requests;
CREATE TRIGGER trigger_notify_purchase_request_created
    AFTER INSERT ON purchase_requests
    FOR EACH ROW
    EXECUTE FUNCTION notify_purchase_request_created();

-- =========================================
-- 2. Notification quand une demande est approuvée
-- =========================================
CREATE OR REPLACE FUNCTION notify_purchase_request_approved()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
    v_approver_name TEXT;
BEGIN
    -- Seulement si le statut passe à 'approved'
    IF NEW.status = 'approved' AND OLD.status != 'approved' THEN
        -- Récupérer le nom de celui qui a approuvé
        SELECT full_name INTO v_approver_name
        FROM user_profiles
        WHERE user_uid = auth.uid();
        
        -- Notifier le créateur de la demande
        -- Note: On n'exclut PAS le créateur ici car c'est quelqu'un d'autre qui approuve
        PERFORM send_notification_to_user(
            NEW.created_by,
            'purchase_approved',
            'Demande approuvée ! 🎉',
            'Ta demande "' || NEW.name || '" a été approuvée par ' || COALESCE(v_approver_name, 'un admin'),
            jsonb_build_object(
                'request_id', NEW.id,
                'approved_by', auth.uid(),
                'created_by', auth.uid()  -- L'approbateur, pas le créateur
            ),
            'normal'
        );
    END IF;
    
    RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trigger_notify_purchase_request_approved ON purchase_requests;
CREATE TRIGGER trigger_notify_purchase_request_approved
    AFTER UPDATE ON purchase_requests
    FOR EACH ROW
    EXECUTE FUNCTION notify_purchase_request_approved();

-- =========================================
-- 3. Notification pour stock faible
-- =========================================
CREATE OR REPLACE FUNCTION notify_low_stock()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
    v_total_qty INTEGER;
    v_min_stock INTEGER;
    v_item_name TEXT;
    v_current_user UUID;
BEGIN
    v_current_user := auth.uid();
    
    -- Calculer le stock total pour cet article
    SELECT COALESCE(SUM(qty), 0) INTO v_total_qty
    FROM stock
    WHERE item_id = NEW.item_id;
    
    -- Récupérer le seuil minimum et le nom
    SELECT 
        (meta->>'min_stock')::INTEGER,
        name
    INTO v_min_stock, v_item_name
    FROM items
    WHERE id = NEW.item_id;
    
    -- Si le stock est en dessous du minimum
    IF v_min_stock IS NOT NULL AND v_total_qty < v_min_stock THEN
        -- Notifier tous les gestionnaires (sauf celui qui a fait la modification)
        INSERT INTO user_notifications (user_id, company_id, type, title, body, data, priority)
        SELECT 
            m.user_uid,
            NEW.company_id,
            'low_stock',
            'Stock faible 📦',
            v_item_name || ' : ' || v_total_qty || ' restant (min: ' || v_min_stock || ')',
            jsonb_build_object(
                'item_id', NEW.item_id,
                'current_qty', v_total_qty,
                'min_stock', v_min_stock,
                'created_by', v_current_user  -- Pour filtrage
            ),
            'high'
        FROM memberships m
        WHERE m.company_id = NEW.company_id
        AND m.role IN ('admin', 'manager')
        AND m.user_uid != v_current_user;  -- Exclure l'utilisateur actuel
    END IF;
    
    RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trigger_notify_low_stock ON stock;
CREATE TRIGGER trigger_notify_low_stock
    AFTER INSERT OR UPDATE ON stock
    FOR EACH ROW
    EXECUTE FUNCTION notify_low_stock();

-- =========================================
-- 4. Notification pour équipement assigné
-- =========================================
CREATE OR REPLACE FUNCTION notify_equipment_assigned()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
    v_equipment_name TEXT;
    v_assigned_to UUID;
    v_assigner UUID;
BEGIN
    v_assigner := auth.uid();
    
    -- Récupérer le nom de l'équipement
    SELECT name INTO v_equipment_name
    FROM equipment
    WHERE id = NEW.id;
    
    -- Vérifier si quelqu'un vient d'être assigné
    v_assigned_to := (NEW.meta->>'assigned_to')::UUID;
    
    IF v_assigned_to IS NOT NULL AND 
       (OLD.meta->>'assigned_to')::UUID IS DISTINCT FROM v_assigned_to AND
       v_assigned_to != v_assigner THEN  -- Ne pas notifier si on s'assigne soi-même
        
        -- Notifier la personne assignée
        PERFORM send_notification_to_user(
            v_assigned_to,
            'equipment_assigned',
            'Équipement assigné 🔧',
            v_equipment_name || ' t''a été assigné',
            jsonb_build_object(
                'equipment_id', NEW.id,
                'created_by', v_assigner
            ),
            'normal'
        );
    END IF;
    
    RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trigger_notify_equipment_assigned ON equipment;
CREATE TRIGGER trigger_notify_equipment_assigned
    AFTER UPDATE ON equipment
    FOR EACH ROW
    EXECUTE FUNCTION notify_equipment_assigned();

-- =========================================
-- EXEMPLES D'USAGE
-- =========================================

/*
-- Les triggers ci-dessus s'activent automatiquement !

-- Exemple 1: Créer une demande d'achat
-- → Tous les admins/managers reçoivent une notification (sauf toi)
INSERT INTO purchase_requests (company_id, name, created_by, ...)
VALUES ('company-id', 'Gants de sécurité', auth.uid(), ...);

-- Exemple 2: Approuver une demande
-- → Le créateur reçoit une notification (pas toi)
UPDATE purchase_requests 
SET status = 'approved' 
WHERE id = 'request-id';

-- Exemple 3: Ajuster le stock (devient faible)
-- → Les gestionnaires reçoivent une alerte (sauf toi)
UPDATE stock 
SET qty = 5 
WHERE item_id = 'item-id';

-- Exemple 4: Assigner un équipement
-- → La personne assignée reçoit une notification (pas toi)
UPDATE equipment 
SET meta = jsonb_set(meta, '{assigned_to}', '"user-id"')
WHERE id = 'equipment-id';

-- IMPORTANT: Chaque notification inclut 'created_by' dans le champ 'data'
-- Le NotificationService côté Flutter filtre automatiquement les notifications
-- où created_by = utilisateur actuel
*/
