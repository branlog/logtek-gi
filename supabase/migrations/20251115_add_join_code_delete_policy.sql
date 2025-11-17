-- Allow owners/admins to delete company join codes
drop policy if exists company_join_codes_delete on public.company_join_codes;
create policy company_join_codes_delete
on public.company_join_codes
for delete
using (
  public.has_company_role(company_id, array['owner','admin'])
);
