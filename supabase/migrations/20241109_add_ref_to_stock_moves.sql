-- Ajoute une référence optionnelle sur les mouvements de stock pour relier
-- un mouvement à une demande d’achat ou une note métier (ex: « purchase-<id> »).
alter table if exists public.stock_moves
  add column if not exists ref text;

comment on column public.stock_moves.ref is
  'Référence libre liée à un document externe (demande d’achat, bon, etc.)';
