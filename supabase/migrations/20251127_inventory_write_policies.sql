-- Complement read-only policies by allowing writes for appropriate roles.

-- Warehouses: owners/admins manage structure.
alter table if exists public.warehouses enable row level security;
drop policy if exists warehouses_insert_admin on public.warehouses;
drop policy if exists warehouses_update_admin on public.warehouses;
drop policy if exists warehouses_delete_admin on public.warehouses;
create policy warehouses_insert_admin
on public.warehouses
for insert
with check (public.has_company_role(company_id, array['owner','admin']));
create policy warehouses_update_admin
on public.warehouses
for update
using (public.has_company_role(company_id, array['owner','admin']))
with check (public.has_company_role(company_id, array['owner','admin']));
create policy warehouses_delete_admin
on public.warehouses
for delete
using (public.has_company_role(company_id, array['owner','admin']));

-- Items: allow employees to add/update items; restrict delete to owner/admin.
alter table if exists public.items enable row level security;
drop policy if exists items_insert_staff on public.items;
drop policy if exists items_update_staff on public.items;
drop policy if exists items_delete_admin on public.items;
create policy items_insert_staff
on public.items
for insert
with check (
  public.has_company_role(company_id, array['owner','admin','employee'])
);
create policy items_update_staff
on public.items
for update
using (
  public.has_company_role(company_id, array['owner','admin','employee'])
)
with check (
  public.has_company_role(company_id, array['owner','admin','employee'])
);
create policy items_delete_admin
on public.items
for delete
using (public.has_company_role(company_id, array['owner','admin']));

-- Stock: employees can adjust stock (insert/update rows); delete reserved to owner/admin.
alter table if exists public.stock enable row level security;
drop policy if exists stock_insert_staff on public.stock;
drop policy if exists stock_update_staff on public.stock;
drop policy if exists stock_delete_admin on public.stock;
create policy stock_insert_staff
on public.stock
for insert
with check (
  public.has_company_role(company_id, array['owner','admin','employee'])
);
create policy stock_update_staff
on public.stock
for update
using (
  public.has_company_role(company_id, array['owner','admin','employee'])
)
with check (
  public.has_company_role(company_id, array['owner','admin','employee'])
);
create policy stock_delete_admin
on public.stock
for delete
using (public.has_company_role(company_id, array['owner','admin']));

-- Equipment: employees can create/update; delete restricted to owner/admin.
alter table if exists public.equipment enable row level security;
drop policy if exists equipment_insert_staff on public.equipment;
drop policy if exists equipment_update_staff on public.equipment;
drop policy if exists equipment_delete_admin on public.equipment;
create policy equipment_insert_staff
on public.equipment
for insert
with check (
  public.has_company_role(company_id, array['owner','admin','employee'])
);
create policy equipment_update_staff
on public.equipment
for update
using (
  public.has_company_role(company_id, array['owner','admin','employee'])
)
with check (
  public.has_company_role(company_id, array['owner','admin','employee'])
);
create policy equipment_delete_admin
on public.equipment
for delete
using (public.has_company_role(company_id, array['owner','admin']));
