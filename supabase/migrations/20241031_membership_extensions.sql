-- Membership invitations table
create table if not exists public.membership_invites (
  id uuid primary key default gen_random_uuid(),
  company_id uuid not null references public.companies(id) on delete cascade,
  email text not null,
  role text not null check (role in ('owner','admin','employee','viewer')),
  status text not null default 'pending' check (status in ('pending','accepted','cancelled','failed')),
  invite_token text not null unique,
  user_uid uuid references auth.users(id),
  invited_by uuid references auth.users(id),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  responded_at timestamptz,
  notes text
);

create unique index if not exists membership_invites_unique_email_per_company
  on public.membership_invites (company_id, lower(email))
  where status = 'pending';

create index if not exists membership_invites_company_idx
  on public.membership_invites (company_id);

drop trigger if exists membership_invites_set_updated_at on public.membership_invites;
create trigger membership_invites_set_updated_at
before update on public.membership_invites
for each row execute function public.handle_updated_at();

-- Join codes table
create table if not exists public.company_join_codes (
  id uuid primary key default gen_random_uuid(),
  company_id uuid not null references public.companies(id) on delete cascade,
  code_hash text not null,
  code_hint text,
  label text,
  role text not null check (role in ('owner','admin','employee','viewer')),
  max_uses integer check (max_uses is null or max_uses > 0),
  uses integer not null default 0 check (uses >= 0),
  expires_at timestamptz,
  created_by uuid references auth.users(id),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  revoked_at timestamptz,
  notes text
);

create unique index if not exists company_join_codes_hash_idx
  on public.company_join_codes (code_hash);

create index if not exists company_join_codes_company_idx
  on public.company_join_codes (company_id);

drop trigger if exists company_join_codes_set_updated_at on public.company_join_codes;
create trigger company_join_codes_set_updated_at
before update on public.company_join_codes
for each row execute function public.handle_updated_at();

-- Enable RLS
alter table public.membership_invites enable row level security;
alter table public.company_join_codes enable row level security;

-- Policies: membership_invites
drop policy if exists membership_invites_select on public.membership_invites;
create policy membership_invites_select
on public.membership_invites
for select
using (
  public.has_company_role(company_id, array['owner','admin'])
);

drop policy if exists membership_invites_insert on public.membership_invites;
create policy membership_invites_insert
on public.membership_invites
for insert
with check (
  public.has_company_role(company_id, array['owner','admin'])
);

drop policy if exists membership_invites_update on public.membership_invites;
create policy membership_invites_update
on public.membership_invites
for update
using (
  public.has_company_role(company_id, array['owner','admin'])
)
with check (
  public.has_company_role(company_id, array['owner','admin'])
);

-- Policies: company_join_codes
drop policy if exists company_join_codes_select on public.company_join_codes;
create policy company_join_codes_select
on public.company_join_codes
for select
using (
  public.has_company_role(company_id, array['owner','admin'])
);

drop policy if exists company_join_codes_insert on public.company_join_codes;
create policy company_join_codes_insert
on public.company_join_codes
for insert
with check (
  public.has_company_role(company_id, array['owner','admin'])
);

drop policy if exists company_join_codes_update on public.company_join_codes;
create policy company_join_codes_update
on public.company_join_codes
for update
using (
  public.has_company_role(company_id, array['owner','admin'])
)
with check (
  public.has_company_role(company_id, array['owner','admin'])
);

-- Join company with code
create or replace function public.join_company_with_code(p_code text)
returns table(company_id uuid, role text)
language plpgsql
security definer
set search_path = public
as $$
declare
  v_code text := trim(p_code);
  v_hash text;
  v_entry public.company_join_codes%rowtype;
begin
  if v_code is null or length(v_code) < 4 then
    raise exception 'Code invalide';
  end if;

  v_hash := encode(digest(upper(v_code), 'sha256'), 'hex');

  select *
    into v_entry
  from public.company_join_codes
  where code_hash = v_hash
    and revoked_at is null
    and (expires_at is null or expires_at > now())
    and (max_uses is null or uses < max_uses)
  order by created_at desc
  limit 1
  for update;

  if not found then
    raise exception 'Code invalide ou expiré';
  end if;

  insert into public.memberships (company_id, user_uid, role)
  values (v_entry.company_id, auth.uid(), v_entry.role)
  on conflict (company_id, user_uid)
    do update set role = excluded.role, updated_at = now();

  update public.company_join_codes
     set uses = uses + 1,
         updated_at = now()
   where id = v_entry.id;

  return query
    select v_entry.company_id, v_entry.role;
end;
$$;

grant execute on function public.join_company_with_code(text) to authenticated;
