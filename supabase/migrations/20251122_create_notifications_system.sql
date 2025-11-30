-- Notifications system (table, policies, helper functions, automation triggers)
CREATE EXTENSION IF NOT EXISTS "pgcrypto";
DROP FUNCTION IF EXISTS public.send_notification_to_user(UUID, TEXT, TEXT, TEXT, JSONB, TEXT);

-- =====================================================================
-- 1. Table definition + helpful indexes
-- =====================================================================
CREATE TABLE IF NOT EXISTS public.user_notifications (
	id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
	user_id UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
	company_id UUID REFERENCES public.companies(id) ON DELETE CASCADE,
	type TEXT NOT NULL,
	title TEXT NOT NULL,
	body TEXT NOT NULL,
	data JSONB NOT NULL DEFAULT '{}'::jsonb,
	priority TEXT NOT NULL DEFAULT 'normal',
	read_at TIMESTAMPTZ,
	created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS idx_user_notifications_user_id
	ON public.user_notifications (user_id);

CREATE INDEX IF NOT EXISTS idx_user_notifications_created_at
	ON public.user_notifications (created_at DESC);

CREATE INDEX IF NOT EXISTS idx_user_notifications_unread
	ON public.user_notifications (user_id, read_at)
	WHERE read_at IS NULL;

-- =====================================================================
-- 2. RLS policies: users manage only their own notifications
-- =====================================================================
ALTER TABLE public.user_notifications ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "Users can view their own notifications" ON public.user_notifications;
CREATE POLICY "Users can view their own notifications"
	ON public.user_notifications
	FOR SELECT
	USING (auth.uid() = user_id);

DROP POLICY IF EXISTS "Users can update their own notifications" ON public.user_notifications;
CREATE POLICY "Users can update their own notifications"
	ON public.user_notifications
	FOR UPDATE
	USING (auth.uid() = user_id)
	WITH CHECK (auth.uid() = user_id);

DROP POLICY IF EXISTS "Users can delete their own notifications" ON public.user_notifications;
CREATE POLICY "Users can delete their own notifications"
	ON public.user_notifications
	FOR DELETE
	USING (auth.uid() = user_id);

-- =====================================================================
-- 3. Helper routines shared across triggers / RPCs
-- =====================================================================
CREATE OR REPLACE FUNCTION public.send_notification_to_user(
	p_user_id UUID,
	p_type TEXT,
	p_title TEXT,
	p_body TEXT,
	p_data JSONB DEFAULT '{}'::jsonb,
	p_priority TEXT DEFAULT 'normal'
)
RETURNS UUID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
	v_notification_id UUID;
BEGIN
	INSERT INTO public.user_notifications (
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

CREATE OR REPLACE FUNCTION public.send_notification_to_company(
	p_company_id UUID,
	p_type TEXT,
	p_title TEXT,
	p_body TEXT,
	p_data JSONB DEFAULT '{}'::jsonb,
	p_priority TEXT DEFAULT 'normal'
)
RETURNS INTEGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
	v_count INTEGER := 0;
BEGIN
	INSERT INTO public.user_notifications (
		user_id,
		company_id,
		type,
		title,
		body,
		data,
		priority
	)
	SELECT
		m.user_uid,
		p_company_id,
		p_type,
		p_title,
		p_body,
		p_data,
		p_priority
	FROM public.memberships m
	WHERE m.company_id = p_company_id
	  AND m.user_uid IS NOT NULL;

	GET DIAGNOSTICS v_count = ROW_COUNT;
	RETURN v_count;
END;
$$;

CREATE OR REPLACE FUNCTION public.cleanup_old_notifications()
RETURNS TRIGGER
LANGUAGE plpgsql
SET search_path = public
AS $$
BEGIN
	DELETE FROM public.user_notifications
	WHERE user_id = NEW.user_id
	  AND id NOT IN (
		  SELECT id
		  FROM public.user_notifications
		  WHERE user_id = NEW.user_id
		  ORDER BY created_at DESC
		  LIMIT 100
	  );

	RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trigger_cleanup_old_notifications ON public.user_notifications;
CREATE TRIGGER trigger_cleanup_old_notifications
	AFTER INSERT ON public.user_notifications
	FOR EACH ROW
	EXECUTE FUNCTION public.cleanup_old_notifications();

-- =====================================================================
-- 4. Business triggers (automatic notifications)
-- =====================================================================
CREATE OR REPLACE FUNCTION public.notify_purchase_request_created()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
	v_creator_name TEXT;
BEGIN
	SELECT COALESCE(
		NULLIF(TRIM(CONCAT_WS(' ', up.first_name, up.last_name)), ''),
		NULLIF(u.raw_user_meta_data ->> 'full_name', ''),
		NULLIF(u.email, ''),
		NEW.created_by::text
	) INTO v_creator_name
	FROM auth.users u
	LEFT JOIN public.user_profiles up
		ON up.user_uid = NEW.created_by
	WHERE u.id = NEW.created_by;

	INSERT INTO public.user_notifications (
		user_id,
		company_id,
		type,
		title,
		body,
		data,
		priority
	)
	SELECT
		m.user_uid,
		NEW.company_id,
		'purchase_created',
		'Nouvelle demande d''achat',
		COALESCE(v_creator_name, 'Un membre') || ' a créé une demande: ' || NEW.name,
		jsonb_build_object(
			'request_id', NEW.id,
			'created_by', NEW.created_by
		),
		'normal'
	FROM public.memberships m
	WHERE m.company_id = NEW.company_id
	  AND m.role IN ('admin', 'manager')
	  AND m.user_uid != NEW.created_by;

	RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trigger_notify_purchase_request_created ON public.purchase_requests;
CREATE TRIGGER trigger_notify_purchase_request_created
	AFTER INSERT ON public.purchase_requests
	FOR EACH ROW
	EXECUTE FUNCTION public.notify_purchase_request_created();

CREATE OR REPLACE FUNCTION public.notify_purchase_request_approved()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
	v_approver_name TEXT;
BEGIN
	IF NEW.status = 'approved' AND OLD.status IS DISTINCT FROM 'approved' THEN
		SELECT COALESCE(
			NULLIF(TRIM(CONCAT_WS(' ', up.first_name, up.last_name)), ''),
			NULLIF(u.raw_user_meta_data ->> 'full_name', ''),
			NULLIF(u.email, ''),
			auth.uid()::text
		) INTO v_approver_name
		FROM auth.users u
		LEFT JOIN public.user_profiles up
			ON up.user_uid = auth.uid()
		WHERE u.id = auth.uid();

		INSERT INTO public.user_notifications (
			user_id,
			company_id,
			type,
			title,
			body,
			data,
			priority
		) VALUES (
			NEW.created_by,
			NEW.company_id,
			'purchase_approved',
			'Demande approuvée ! 🎉',
			'Ta demande "' || NEW.name || '" a été approuvée par ' || COALESCE(v_approver_name, 'un admin'),
			jsonb_build_object(
				'request_id', NEW.id,
				'approved_by', auth.uid()
			),
			'normal'
		);
	END IF;

	RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trigger_notify_purchase_request_approved ON public.purchase_requests;
CREATE TRIGGER trigger_notify_purchase_request_approved
	AFTER UPDATE ON public.purchase_requests
	FOR EACH ROW
	EXECUTE FUNCTION public.notify_purchase_request_approved();

CREATE OR REPLACE FUNCTION public.notify_low_stock()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
	v_total_qty INTEGER;
	v_min_stock INTEGER;
	v_item_name TEXT;
	v_current_user UUID := auth.uid();
BEGIN
	SELECT COALESCE(SUM(qty), 0) INTO v_total_qty
	FROM public.stock
	WHERE item_id = NEW.item_id;

	SELECT (meta->>'min_stock')::INTEGER, name
	INTO v_min_stock, v_item_name
	FROM public.items
	WHERE id = NEW.item_id;

	IF v_min_stock IS NOT NULL AND v_total_qty < v_min_stock THEN
		INSERT INTO public.user_notifications (user_id, company_id, type, title, body, data, priority)
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
				'created_by', v_current_user
			),
			'high'
		FROM public.memberships m
		WHERE m.company_id = NEW.company_id
		  AND m.role IN ('admin', 'manager')
		  AND m.user_uid IS DISTINCT FROM v_current_user;
	END IF;

	RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trigger_notify_low_stock ON public.stock;
CREATE TRIGGER trigger_notify_low_stock
	AFTER INSERT OR UPDATE ON public.stock
	FOR EACH ROW
	EXECUTE FUNCTION public.notify_low_stock();

CREATE OR REPLACE FUNCTION public.notify_equipment_assigned()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
	v_equipment_name TEXT;
	v_assigned_to UUID;
	v_assigner UUID := auth.uid();
BEGIN
	SELECT name INTO v_equipment_name
	FROM public.equipment
	WHERE id = NEW.id;

	v_assigned_to := (NEW.meta->>'assigned_to')::UUID;

	IF v_assigned_to IS NOT NULL
	   AND (OLD.meta->>'assigned_to')::UUID IS DISTINCT FROM v_assigned_to
	   AND v_assigned_to IS DISTINCT FROM v_assigner THEN
		PERFORM public.send_notification_to_user(
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

DROP TRIGGER IF EXISTS trigger_notify_equipment_assigned ON public.equipment;
CREATE TRIGGER trigger_notify_equipment_assigned
	AFTER UPDATE ON public.equipment
	FOR EACH ROW
	EXECUTE FUNCTION public.notify_equipment_assigned();

-- =====================================================================
-- 5. Realtime publication (idempotent)
-- =====================================================================
DO $$
BEGIN
	IF NOT EXISTS (
		SELECT 1
		FROM pg_publication_tables
		WHERE pubname = 'supabase_realtime'
		  AND schemaname = 'public'
		  AND tablename = 'user_notifications'
	) THEN
		EXECUTE 'ALTER PUBLICATION supabase_realtime ADD TABLE public.user_notifications';
	END IF;
END;
$$;
