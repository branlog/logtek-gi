-- Update list_company_members to drop dependency on user_profiles.full_name
drop function if exists public.list_company_members(uuid);

create or replace function public.list_company_members(p_company_id uuid)
returns table (
  user_uid uuid,
  role text,
  created_at timestamptz,
  first_name text,
  last_name text,
  full_name text,
  email text,
  display_name text
)
language plpgsql
security definer
set search_path = public
set row_security = off
as $$
declare
  v_user uuid := auth.uid();
begin
  if p_company_id is null or v_user is null then
    return;
  end if;

  if not exists (
    select 1
      from public.memberships me
     where me.company_id = p_company_id
       and me.user_uid = v_user
  ) then
    return;
  end if;

  return query
    select
      m.user_uid,
      m.role,
      m.created_at,
      up.first_name,
      up.last_name,
      (u.raw_user_meta_data ->> 'full_name')::text as full_name,
      u.email,
      coalesce(
        nullif(trim(concat_ws(' ', up.first_name, up.last_name)), ''),
        nullif(u.raw_user_meta_data ->> 'full_name', ''),
        nullif(u.email, ''),
        m.user_uid::text
      ) as display_name
    from public.memberships m
    left join public.user_profiles up
      on up.user_uid = m.user_uid
    left join auth.users u
      on u.id = m.user_uid
    where m.company_id = p_company_id
    order by m.created_at;
end;
$$;

grant execute on function public.list_company_members(uuid) to authenticated;
