WITH next_items AS (
  SELECT outbox.id
  FROM public.sevenday_notification_outbox AS outbox
  WHERE outbox.channel = 'email'
    AND outbox.attempts < 5
    AND (
      (outbox.status = 'pending' AND outbox.next_attempt_at <= now())
      OR (outbox.status = 'dispatching' AND outbox.updated_at < now() - interval '15 minutes')
    )
  ORDER BY outbox.created_at
  FOR UPDATE SKIP LOCKED
  LIMIT 10
),
claimed AS (
  UPDATE public.sevenday_notification_outbox AS outbox
  SET
    status = 'dispatching',
    attempts = outbox.attempts + 1,
    updated_at = now()
  FROM next_items
  WHERE outbox.id = next_items.id
  RETURNING
    outbox.id,
    outbox.lead_id,
    outbox.submission_id,
    outbox.recipient,
    outbox.template_version,
    outbox.payload,
    outbox.attempts
)
SELECT
  claimed.id::text AS outbox_id,
  claimed.lead_id::text AS lead_id,
  claimed.submission_id,
  claimed.recipient,
  claimed.template_version,
  claimed.payload,
  claimed.attempts
FROM claimed;
