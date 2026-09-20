WITH claimed AS (
  SELECT *
  FROM public.sevenday_claim_email($1::jsonb)
)
SELECT
  claimed.*,
  token.ok AS token_ok,
  token.error_code AS token_error,
  token.contact_name,
  token.onboarding_token,
  token.onboarding_token_expires_at,
  token.onboarding_path
FROM claimed
LEFT JOIN LATERAL public.sevenday_get_onboarding_token(
  jsonb_build_object(
    'outbox_id', claimed.outbox_id,
    'lease_token', claimed.lease_token
  )
) AS token ON true;
