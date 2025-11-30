-- Create a dedicated public bucket for inventory photos.
insert into storage.buckets (id, name, public)
values ('inventory-photos', 'inventory-photos', true)
on conflict (id) do nothing;

drop policy if exists "Public read inventory photos" on storage.objects;
create policy "Public read inventory photos"
on storage.objects
for select
using (bucket_id = 'inventory-photos');

drop policy if exists "Authenticated upload inventory photos" on storage.objects;
create policy "Authenticated upload inventory photos"
on storage.objects
for insert
with check (bucket_id = 'inventory-photos' and auth.role() = 'authenticated');

drop policy if exists "Authenticated update inventory photos" on storage.objects;
create policy "Authenticated update inventory photos"
on storage.objects
for update
using (bucket_id = 'inventory-photos' and auth.role() = 'authenticated')
with check (bucket_id = 'inventory-photos' and auth.role() = 'authenticated');

drop policy if exists "Authenticated delete inventory photos" on storage.objects;
create policy "Authenticated delete inventory photos"
on storage.objects
for delete
using (bucket_id = 'inventory-photos' and auth.role() = 'authenticated');
