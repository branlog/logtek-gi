-- Inventory sections let chaque entrepôt organiser son stock par zone
create table if not exists public.inventory_sections (
  id uuid primary key default gen_random_uuid(),
  company_id uuid not null references public.companies(id) on delete cascade,
  warehouse_id uuid not null references public.warehouses(id) on delete cascade,
  name text not null,
  code text,
  description text,
  active boolean not null default true,
  sort_order integer,
  created_by uuid references auth.users(id),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

comment on table public.inventory_sections is
  'Sections d’inventaire physiques à l’intérieur d’un entrepôt.';
comment on column public.inventory_sections.code is
  'Code court optionnel pour la section (affichage étiquettes).';

drop trigger if exists inventory_sections_set_updated_at on public.inventory_sections;
create trigger inventory_sections_set_updated_at
before update on public.inventory_sections
for each row execute function public.handle_updated_at();

create index if not exists inventory_sections_company_idx
  on public.inventory_sections (company_id);
create index if not exists inventory_sections_warehouse_idx
  on public.inventory_sections (warehouse_id);
create unique index if not exists inventory_sections_unique_name_per_warehouse
  on public.inventory_sections (warehouse_id, lower(name));
create unique index if not exists inventory_sections_unique_code_per_company
  on public.inventory_sections (company_id, lower(code))
  where code is not null and length(code) > 0;

alter table public.inventory_sections enable row level security;

drop policy if exists inventory_sections_select on public.inventory_sections;
create policy inventory_sections_select
on public.inventory_sections
for select
using (
  public.has_company_role(company_id, array['owner','admin','employee','viewer'])
);

drop policy if exists inventory_sections_insert on public.inventory_sections;
create policy inventory_sections_insert
on public.inventory_sections
for insert
with check (
  public.has_company_role(company_id, array['owner','admin'])
);

drop policy if exists inventory_sections_update on public.inventory_sections;
create policy inventory_sections_update
on public.inventory_sections
for update
using (
  public.has_company_role(company_id, array['owner','admin'])
)
with check (
  public.has_company_role(company_id, array['owner','admin'])
);

drop policy if exists inventory_sections_delete on public.inventory_sections;
create policy inventory_sections_delete
on public.inventory_sections
for delete
using (
  public.has_company_role(company_id, array['owner','admin'])
);

-- Stock now peut pointer vers une section
alter table if exists public.stock
  add column if not exists section_id uuid references public.inventory_sections(id) on delete set null;

-- Autorise plusieurs lignes stock par entrepôt en fonction de la section
alter table if exists public.stock
  drop constraint if exists stock_company_id_item_id_warehouse_id_key;

drop index if exists public.stock_company_id_item_id_warehouse_id_idx;

create unique index if not exists stock_unique_item_location
  on public.stock (company_id, item_id, warehouse_id, coalesce(section_id, '00000000-0000-0000-0000-000000000000'::uuid));

create index if not exists stock_section_idx
  on public.stock (section_id);

-- Les mouvements suivent aussi la section (si précisée)
alter table if exists public.stock_moves
  add column if not exists section_id uuid references public.inventory_sections(id) on delete set null;

-- Les demandes d’achat peuvent préparer une section cible
alter table if exists public.purchase_requests
  add column if not exists section_id uuid references public.inventory_sections(id) on delete set null;

create index if not exists purchase_requests_section_idx
  on public.purchase_requests (section_id);
