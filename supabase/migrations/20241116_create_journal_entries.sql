create table if not exists public.journal_entries (
  id uuid primary key default gen_random_uuid(),
  company_id uuid not null references public.companies(id) on delete cascade,
  scope text not null,
  entity_id text,
  event text not null,
  note text,
  payload jsonb,
  created_at timestamptz not null default now(),
  created_by uuid references auth.users(id)
);

create index if not exists journal_entries_company_scope_idx
  on public.journal_entries (company_id, scope, entity_id);

alter table public.journal_entries enable row level security;

drop policy if exists journal_entries_select on public.journal_entries;
create policy journal_entries_select
on public.journal_entries
for select
using (
  public.has_company_role(company_id, array['owner','admin','employee','viewer'])
);

drop policy if exists journal_entries_insert on public.journal_entries;
create policy journal_entries_insert
on public.journal_entries
for insert
with check (
  public.has_company_role(company_id, array['owner','admin','employee','viewer'])
);
