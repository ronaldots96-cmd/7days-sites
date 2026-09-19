WITH input AS (
  SELECT $1::jsonb AS data
),
matched_lead AS (
  SELECT lead.id
  FROM public.sevenday_leads AS lead
  CROSS JOIN input
  WHERE lead.id = (input.data->>'parent_lead_id')::uuid
    AND lead.onboarding_token_hash = input.data->>'onboarding_token_hash'
    AND lead.onboarding_token_expires_at > now()
),
onboarding_write AS (
  INSERT INTO public.sevenday_onboardings (
    submission_id,
    lead_id,
    parent_submission_id,
    schema_version,
    submitted_at,
    form_duration_ms,
    project,
    business,
    messaging,
    scope,
    brand,
    assets,
    launch,
    contact,
    source,
    consent,
    raw_payload
  )
  SELECT
    input.data->>'submission_id',
    matched_lead.id,
    NULLIF(input.data#>>'{payload,parent_submission_id}', ''),
    input.data#>>'{payload,schema_version}',
    (input.data#>>'{payload,submitted_at}')::timestamptz,
    NULLIF(input.data#>>'{payload,form,duration_ms}', '')::bigint,
    input.data#>'{payload,project}',
    input.data#>'{payload,business}',
    input.data#>'{payload,messaging}',
    input.data#>'{payload,scope}',
    input.data#>'{payload,brand}',
    input.data#>'{payload,assets}',
    input.data#>'{payload,launch}',
    input.data#>'{payload,contact}',
    input.data#>'{payload,source}',
    input.data#>'{payload,consent}',
    input.data->'payload'
  FROM input
  CROSS JOIN matched_lead
  ON CONFLICT (submission_id) DO UPDATE SET
    raw_payload = EXCLUDED.raw_payload,
    source = EXCLUDED.source,
    updated_at = now()
  RETURNING lead_id, submission_id
),
submission_write AS (
  INSERT INTO public.sevenday_submissions (
    event,
    submission_id,
    lead_id,
    schema_version,
    submitted_at,
    raw_payload
  )
  SELECT
    'client_onboarding.submitted',
    onboarding_write.submission_id,
    onboarding_write.lead_id,
    input.data#>>'{payload,schema_version}',
    (input.data#>>'{payload,submitted_at}')::timestamptz,
    input.data->'payload'
  FROM input
  CROSS JOIN onboarding_write
  ON CONFLICT (event, submission_id) DO NOTHING
  RETURNING submission_id
),
lead_update AS (
  UPDATE public.sevenday_leads AS lead
  SET status = 'onboarding_complete', updated_at = now()
  FROM onboarding_write
  WHERE lead.id = onboarding_write.lead_id
  RETURNING lead.id
),
job_write AS (
  INSERT INTO public.sevenday_production_jobs (
    id,
    lead_id,
    onboarding_submission_id,
    status,
    production_context
  )
  SELECT
    md5(onboarding_write.submission_id || ':v1-production')::uuid,
    onboarding_write.lead_id,
    onboarding_write.submission_id,
    'queued',
    jsonb_build_object(
      'lead', lead.raw_payload,
      'onboarding', input.data->'payload'
    )
  FROM onboarding_write
  CROSS JOIN input
  JOIN public.sevenday_leads AS lead ON lead.id = onboarding_write.lead_id
  ON CONFLICT (onboarding_submission_id) DO UPDATE SET
    production_context = EXCLUDED.production_context,
    updated_at = now()
  RETURNING id, lead_id, status
)
SELECT
  job_write.lead_id::text AS lead_id,
  job_write.id::text AS production_job_id,
  job_write.status AS production_status,
  input.data->>'submission_id' AS submission_id
FROM job_write
CROSS JOIN input;
