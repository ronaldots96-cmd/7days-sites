WITH input AS (
  SELECT $1::jsonb AS data
)
UPDATE public.sevenday_notification_outbox AS outbox
SET
  status = CASE WHEN outbox.attempts >= 5 THEN 'dead_letter' ELSE 'pending' END,
  next_attempt_at = now() + make_interval(mins => LEAST(60, CAST(power(2, GREATEST(outbox.attempts, 1)) AS integer))),
  last_error = left(COALESCE(input.data->>'error', 'unknown provider error'), 1000),
  updated_at = now()
FROM input
WHERE outbox.id = (input.data->>'outbox_id')::uuid
RETURNING outbox.id::text AS outbox_id, outbox.status, outbox.next_attempt_at;
