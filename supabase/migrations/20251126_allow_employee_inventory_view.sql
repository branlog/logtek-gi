-- Broaden read access on inventory tables so employees/viewers can see data.
-- This keeps write access restricted (existing policies remain intact).

-- Warehouses
alter table if exists public.warehouses enable row level security;
drop policy if exists warehouses_select_all_roles on public.warehouses;
create policy warehouses_select_all_roles
on public.warehouses
for select
using (
  public.has_company_role(company_id, array['owner','admin','employee','viewer'])
);

-- Items
alter table if exists public.items enable row level security;
drop policy if exists items_select_all_roles on public.items;
create policy items_select_all_roles
on public.items
for select
using (
  public.has_company_role(company_id, array['owner','admin','employee','viewer'])
);

-- Stock
alter table if exists public.stock enable row level security;
drop policy if exists stock_select_all_roles on public.stock;
create policy stock_select_all_roles
on public.stock
for select
using (
  public.has_company_role(company_id, array['owner','admin','employee','viewer'])
);

-- Equipment
alter table if exists public.equipment enable row level security;
drop policy if exists equipment_select_all_roles on public.equipment;
create policy equipment_select_all_roles
on public.equipment
for select
using (
  public.has_company_role(company_id, array['owner','admin','employee','viewer'])
);
