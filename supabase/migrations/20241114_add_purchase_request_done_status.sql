-- Adds the “done” status to purchase_request_status enum so we can mark
-- requests as fully placed.
DO $$
BEGIN
  ALTER TYPE purchase_request_status ADD VALUE 'done';
EXCEPTION
  WHEN duplicate_object THEN
    NULL;
END $$;
