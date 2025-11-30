-- Update notification trigger for purchase request creation
-- Include actual roles ('owner','admin','employee','viewer') instead of non-existent 'manager'.

create or replace function public.notify_purchase_request_created()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  v_creator_name text;
begin
  select coalesce(
    nullif(trim(concat_ws(' ', up.first_name, up.last_name)), ''),
    nullif(u.raw_user_meta_data ->> 'full_name', ''),
    nullif(u.email, ''),
    NEW.created_by::text
  ) into v_creator_name
  from auth.users u
  left join public.user_profiles up
    on up.user_uid = NEW.created_by
  where u.id = NEW.created_by;

  insert into public.user_notifications (
    user_id,
    company_id,
    type,
    title,
    body,
    data,
    priority
  )
  select
    m.user_uid,
    NEW.company_id,
    'purchase_created',
    'Nouvelle demande d''achat',
    coalesce(v_creator_name, 'Un membre') || ' a créé une demande: ' || NEW.name,
    jsonb_build_object(
      'request_id', NEW.id,
      'created_by', NEW.created_by
    ),
    'normal'
  from public.memberships m
  where m.company_id = NEW.company_id
    and m.role in ('owner','admin','employee','viewer')
    and m.user_uid is not distinct from m.user_uid
    and m.user_uid is distinct from NEW.created_by;

  return NEW;
end;
$$;

drop trigger if exists trigger_notify_purchase_request_created on public.purchase_requests;
create trigger trigger_notify_purchase_request_created
  after insert on public.purchase_requests
  for each row
  execute function public.notify_purchase_request_created();
