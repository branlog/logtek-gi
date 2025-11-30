-- Notifications lorsqu'un stock est retiré (delta négatif sur public.stock).
-- Bypass RLS pour garantir la diffusion.

create or replace function public.notify_stock_removed()
returns trigger
language plpgsql
security definer
set search_path = public, pg_temp
set row_security = off
as $$
declare
  v_company_id uuid;
  v_item_id uuid;
  v_warehouse_id uuid;
  v_section_id uuid;
  v_old_qty numeric := coalesce(OLD.qty, 0);
  v_new_qty numeric := coalesce(NEW.qty, 0);
  v_delta numeric;
  v_item_name text;
  v_wh_name text;
  v_removed numeric;
begin
  -- Identify target IDs
  v_company_id := coalesce(NEW.company_id, OLD.company_id);
  v_item_id := coalesce(NEW.item_id, OLD.item_id);
  v_warehouse_id := coalesce(NEW.warehouse_id, OLD.warehouse_id);
  v_section_id := coalesce(NEW.section_id, OLD.section_id);

  -- Compute delta (negative = removal)
  if TG_OP = 'DELETE' then
    v_delta := -v_old_qty;
    v_new_qty := 0;
  else
    v_delta := v_new_qty - v_old_qty;
  end if;

  if v_delta >= 0 then
    return coalesce(NEW, OLD);
  end if;

  v_removed := abs(v_delta);

  select i.name into v_item_name from public.items i where i.id = v_item_id;
  select w.name into v_wh_name from public.warehouses w where w.id = v_warehouse_id;

  perform public.send_notification_to_company(
    v_company_id,
    'stock_removed',
    'Retrait de stock',
    coalesce(v_item_name, 'Pièce') || ' : ' || v_removed::text || ' retiré(s) de ' || coalesce(v_wh_name, 'un entrepôt'),
    jsonb_build_object(
      'item_id', v_item_id,
      'warehouse_id', v_warehouse_id,
      'section_id', v_section_id,
      'removed_qty', v_removed,
      'new_qty', v_new_qty
    ),
    'normal'
  );

  return coalesce(NEW, OLD);
end;
$$;

drop trigger if exists trigger_notify_stock_removed on public.stock;
create trigger trigger_notify_stock_removed
  after insert or update or delete on public.stock
  for each row
  execute function public.notify_stock_removed();
