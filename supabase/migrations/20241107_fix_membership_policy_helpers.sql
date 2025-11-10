-- Ensure membership helper functions bypass RLS to avoid recursive policies
create or replace function public.is_company_member(p_company_id uuid)
returns boolean
language plpgsql
security definer
set search_path = public
set row_security = off
as $$
declare
  v_user uuid := auth.uid();
begin
  if p_company_id is null or v_user is null then
    return false;
  end if;

  return exists (
    select 1
      from public.memberships m
     where m.company_id = p_company_id
       and m.user_uid = v_user
  );
end;
$$;

grant execute on function public.is_company_member(uuid) to authenticated;

create or replace function public.has_company_role(
  p_company_id uuid,
  p_roles text[]
)
returns boolean
language plpgsql
security definer
set search_path = public
set row_security = off
as $$
declare
  v_user uuid := auth.uid();
begin
  if p_company_id is null or v_user is null then
    return false;
  end if;

  return exists (
    select 1
      from public.memberships m
     where m.company_id = p_company_id
       and m.user_uid = v_user
       and (
         p_roles is null
         or m.role = any (p_roles)
       )
  );
end;
$$;

grant execute on function public.has_company_role(uuid, text[]) to authenticated;
