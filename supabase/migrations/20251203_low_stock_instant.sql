-- Instant low-stock notifications on stock/item changes (bypass RLS).

create or replace function public.check_low_stock_item(p_item_id uuid)
returns void
language plpgsql
security definer
set search_path = public, pg_temp
set row_security = off
as $$
declare
  v_item record;
begin
  if p_item_id is null then
    return;
  end if;

  select
    i.id as item_id,
    i.company_id,
    i.name as item_name,
    coalesce(sum(s.qty), 0) as total_qty,
    case
      when (i.meta->>'min_stock') ~ '^\d+$' then (i.meta->>'min_stock')::int
      else null
    end as min_stock
  into v_item
  from public.items i
  left join public.stock s on s.item_id = i.id
  where i.id = p_item_id
  group by i.id, i.company_id, i.name, i.meta;

  if v_item.min_stock is null then
    return;
  end if;

  if v_item.total_qty < v_item.min_stock then
    perform public.send_notification_to_company(
      v_item.company_id,
      'low_stock',
      'Stock faible 📦',
      v_item.item_name || ' : ' || v_item.total_qty || ' restant (min: ' || v_item.min_stock || ')',
      jsonb_build_object(
        'item_id', v_item.item_id,
        'current_qty', v_item.total_qty,
        'min_stock', v_item.min_stock,
        'source', 'realtime'
      ),
      'high'
    );
  end if;
end;
$$;

create or replace function public.notify_low_stock_on_stock()
returns trigger
language plpgsql
security definer
set search_path = public, pg_temp
set row_security = off
as $$
begin
  perform public.check_low_stock_item(coalesce(NEW.item_id, OLD.item_id));
  return NEW;
end;
$$;

create or replace function public.notify_low_stock_on_item()
returns trigger
language plpgsql
security definer
set search_path = public, pg_temp
set row_security = off
as $$
begin
  perform public.check_low_stock_item(NEW.id);
  return NEW;
end;
$$;

drop trigger if exists trigger_notify_low_stock_on_stock on public.stock;
create trigger trigger_notify_low_stock_on_stock
after insert or update or delete on public.stock
for each row
execute function public.notify_low_stock_on_stock();

drop trigger if exists trigger_notify_low_stock_on_item on public.items;
create trigger trigger_notify_low_stock_on_item
after update of meta on public.items
for each row
execute function public.notify_low_stock_on_item();
