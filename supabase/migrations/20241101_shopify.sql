-- Shopify shop connections
create table if not exists public.shopify_shops (
  id uuid primary key default gen_random_uuid(),
  company_id uuid not null references public.companies(id) on delete cascade,
  shop_domain text not null unique,
  access_token text not null,
  scope text,
  status text not null default 'active',
  connected_at timestamptz not null default now(),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

drop trigger if exists shopify_shops_set_updated_at on public.shopify_shops;
create trigger shopify_shops_set_updated_at
before update on public.shopify_shops
for each row execute function public.handle_updated_at();

create index if not exists shopify_shops_company_idx
  on public.shopify_shops (company_id);

alter table public.shopify_shops enable row level security;

drop policy if exists shopify_shops_select on public.shopify_shops;
create policy shopify_shops_select
on public.shopify_shops
for select
using (public.is_company_member(company_id));

drop policy if exists shopify_shops_write on public.shopify_shops;
create policy shopify_shops_write
on public.shopify_shops
for all
using (public.has_company_role(company_id, array['owner','admin']))
with check (public.has_company_role(company_id, array['owner','admin']));
