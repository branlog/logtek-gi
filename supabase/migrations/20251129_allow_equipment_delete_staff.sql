-- Allow employees to delete equipment (previously restricted to owner/admin).
alter table if exists public.equipment enable row level security;

drop policy if exists equipment_delete_admin on public.equipment;
create policy equipment_delete_staff
on public.equipment
for delete
using (
  public.has_company_role(company_id, array['owner','admin','employee'])
);
