-- Adds the “to_place” status to purchase_request_status enum so the app
-- can mark purchases as ready to be placed.
DO $$
BEGIN
  ALTER TYPE purchase_request_status ADD VALUE 'to_place';
EXCEPTION
  WHEN duplicate_object THEN
    NULL;
END $$;
