-- Reset memberships RLS policies to use helper functions (security definer) only
alter table public.memberships enable row level security;

drop policy if exists memberships_select_self on public.memberships;
drop policy if exists memberships_select_admin on public.memberships;
drop policy if exists memberships_insert_admin on public.memberships;
drop policy if exists memberships_update_admin on public.memberships;
drop policy if exists memberships_delete_admin on public.memberships;

create policy memberships_select_self
on public.memberships
for select
using (
  auth.uid() = user_uid
);

create policy memberships_select_admin
on public.memberships
for select
using (
  public.has_company_role(company_id, array['owner','admin'])
);

create policy memberships_insert_admin
on public.memberships
for insert
with check (
  public.has_company_role(company_id, array['owner','admin'])
);

create policy memberships_update_admin
on public.memberships
for update
using (
  public.has_company_role(company_id, array['owner','admin'])
)
with check (
  public.has_company_role(company_id, array['owner','admin'])
);

create policy memberships_delete_admin
on public.memberships
for delete
using (
  public.has_company_role(company_id, array['owner','admin'])
);
