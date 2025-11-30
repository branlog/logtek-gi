-- Notifications pour l'ajout de tâches inventaire et mécaniques.
-- Envoie à tous les membres de l'entreprise. Bypass RLS sur memberships.

create or replace function public.notify_inventory_task_added()
returns trigger
language plpgsql
security definer
set search_path = public, pg_temp
set row_security = off
as $$
declare
  v_creator text;
  r record;
begin
  select coalesce(
    nullif(trim(concat_ws(' ', up.first_name, up.last_name)), ''),
    nullif(u.raw_user_meta_data ->> 'full_name', ''),
    nullif(u.email, ''),
    auth.uid()::text,
    'Un membre'
  ) into v_creator
  from auth.users u
  left join public.user_profiles up
    on up.user_uid = auth.uid()
  where u.id = auth.uid();

  for r in
    select n.elem as task
    from jsonb_array_elements(coalesce(NEW.meta->'tasks', '[]'::jsonb)) as n(elem)
    left join jsonb_array_elements(coalesce(OLD.meta->'tasks', '[]'::jsonb)) as o(elem)
      on (n.elem->>'id') = (o.elem->>'id')
    where o.elem is null -- nouvelles tâches seulement
      and (n.elem->>'title') is not null
  loop
    perform public.send_notification_to_company(
      NEW.company_id,
      'inventory_task_added',
      'Nouvelle tâche inventaire',
      v_creator || ' a ajouté une tâche: ' || coalesce(NEW.name, 'pièce'),
      jsonb_build_object(
        'item_id', NEW.id,
        'item_name', NEW.name,
        'task_id', r.task->>'id',
        'task_title', r.task->>'title'
      ),
      'normal'
    );
  end loop;

  return NEW;
end;
$$;

drop trigger if exists trigger_notify_inventory_task_added on public.items;
create trigger trigger_notify_inventory_task_added
  after update of meta on public.items
  for each row
  execute function public.notify_inventory_task_added();


create or replace function public.notify_mechanic_task_added()
returns trigger
language plpgsql
security definer
set search_path = public, pg_temp
set row_security = off
as $$
declare
  v_creator text;
  r record;
begin
  select coalesce(
    nullif(trim(concat_ws(' ', up.first_name, up.last_name)), ''),
    nullif(u.raw_user_meta_data ->> 'full_name', ''),
    nullif(u.email, ''),
    auth.uid()::text,
    'Un membre'
  ) into v_creator
  from auth.users u
  left join public.user_profiles up
    on up.user_uid = auth.uid()
  where u.id = auth.uid();

  for r in
    select n.elem as task
    from jsonb_array_elements(coalesce(NEW.meta->'mechanic_tasks', '[]'::jsonb)) as n(elem)
    left join jsonb_array_elements(coalesce(OLD.meta->'mechanic_tasks', '[]'::jsonb)) as o(elem)
      on (n.elem->>'id') = (o.elem->>'id')
    where o.elem is null
      and (n.elem->>'title') is not null
  loop
    perform public.send_notification_to_company(
      NEW.company_id,
      'mechanic_task_added',
      'Nouvelle tâche mécanique',
      v_creator || ' a ajouté une tâche sur ' || coalesce(NEW.name, 'un équipement'),
      jsonb_build_object(
        'equipment_id', NEW.id,
        'equipment_name', NEW.name,
        'task_id', r.task->>'id',
        'task_title', r.task->>'title'
      ),
      'normal'
    );
  end loop;

  return NEW;
end;
$$;

drop trigger if exists trigger_notify_mechanic_task_added on public.equipment;
create trigger trigger_notify_mechanic_task_added
  after update of meta on public.equipment
  for each row
  execute function public.notify_mechanic_task_added();
