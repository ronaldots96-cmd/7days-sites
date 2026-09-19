WITH input AS (
  SELECT $1::jsonb AS data
)
UPDATE public.sevenday_notification_outbox AS outbox
SET
  status = 'sent',
  provider_message_id = NULLIF(input.data->>'provider_message_id', ''),
  sent_at = now(),
  updated_at = now(),
  last_error = NULL
FROM input
WHERE outbox.id = (input.data->>'outbox_id')::uuid
RETURNING outbox.id::text AS outbox_id, outbox.status;
