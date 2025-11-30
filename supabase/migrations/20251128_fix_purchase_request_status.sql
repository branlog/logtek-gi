-- Fix notification trigger to use a valid status value.
-- Enum purchase_request_status = ('pending','received','to_place','done'),
-- so checking for 'approved' caused runtime errors on update.

create or replace function public.notify_purchase_request_approved()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  v_approver_name text;
begin
  -- Fire when a request passe en "à placer" (equivalent to approval/achat validé).
  if NEW.status = 'to_place' and OLD.status is distinct from 'to_place' then
    select coalesce(
      nullif(trim(concat_ws(' ', up.first_name, up.last_name)), ''),
      nullif(u.raw_user_meta_data ->> 'full_name', ''),
      nullif(u.email, ''),
      auth.uid()::text
    ) into v_approver_name
    from auth.users u
    left join public.user_profiles up
      on up.user_uid = auth.uid()
    where u.id = auth.uid();

    insert into public.user_notifications (
      user_id,
      company_id,
      type,
      title,
      body,
      data,
      priority
    ) values (
      NEW.created_by,
      NEW.company_id,
      'purchase_approved',
      'Demande approuvée ! 🎉',
      'Ta demande "' || NEW.name || '" a été approuvée par ' || coalesce(v_approver_name, 'un admin'),
      jsonb_build_object(
        'request_id', NEW.id,
        'status', NEW.status,
        'approved_by', auth.uid()
      ),
      'normal'
    );
  end if;

  return NEW;
end;
$$;
