alter table equipment
  add column if not exists last_oil_change_hours numeric,
  add column if not exists oil_change_interval_hours numeric default 250;

create table if not exists maintenance_events (
  id uuid primary key default gen_random_uuid(),
  equipment_id uuid references equipment(id) on delete cascade,
  type text not null,
  hours numeric,
  date timestamp without time zone default now(),
  notes text,
  created_by uuid references profiles(id)
);

create index if not exists maintenance_events_equipment_id_idx
  on maintenance_events(equipment_id);
