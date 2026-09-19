WITH input AS (
  SELECT $1::jsonb AS data
),
inserted AS (
  INSERT INTO public.sevenday_leads (
    id,
    initial_submission_id,
    status,
    schema_version,
    submitted_at,
    form_version,
    form_duration_ms,
    contact_name,
    contact_email,
    contact_phone,
    preferred_channel,
    package_interest,
    visual_directions,
    objectives,
    assets_available,
    business_name_status,
    business_name,
    domain_status,
    domain_or_site_url,
    source,
    consent,
    raw_payload,
    onboarding_token_hash,
    onboarding_token_expires_at
  )
  SELECT
    (data->>'lead_id_candidate')::uuid,
    data->>'submission_id',
    'new',
    data#>>'{payload,schema_version}',
    (data#>>'{payload,submitted_at}')::timestamptz,
    data#>>'{payload,form,version}',
    NULLIF(data#>>'{payload,form,duration_ms}', '')::bigint,
    data#>>'{payload,contact,name}',
    lower(data#>>'{payload,contact,email}'),
    NULLIF(data#>>'{payload,contact,phone_whatsapp}', ''),
    NULLIF(data#>>'{payload,contact,preferred_channel}', ''),
    NULLIF(data#>>'{payload,preferences,package_interest}', ''),
    ARRAY(SELECT jsonb_array_elements_text(COALESCE(data#>'{payload,preferences,visual_directions}', '[]'::jsonb))),
    ARRAY(SELECT jsonb_array_elements_text(COALESCE(data#>'{payload,preferences,objectives}', '[]'::jsonb))),
    ARRAY(SELECT jsonb_array_elements_text(COALESCE(data#>'{payload,content,assets_available}', '[]'::jsonb))),
    NULLIF(data#>>'{payload,brand,business_name_status}', ''),
    NULLIF(data#>>'{payload,brand,business_name}', ''),
    NULLIF(data#>>'{payload,brand,domain_status}', ''),
    NULLIF(data#>>'{payload,brand,domain_or_site_url}', ''),
    data#>'{payload,source}',
    data#>'{payload,consent}',
    data->'payload',
    data->>'onboarding_token_hash',
    (data->>'onboarding_token_expires_at')::timestamptz
  FROM input
  ON CONFLICT (initial_submission_id) DO NOTHING
  RETURNING id, true AS is_new
),
target AS (
  SELECT id, is_new FROM inserted
  UNION ALL
  SELECT lead.id, false AS is_new
  FROM public.sevenday_leads AS lead
  CROSS JOIN input
  WHERE lead.initial_submission_id = input.data->>'submission_id'
    AND NOT EXISTS (SELECT 1 FROM inserted)
  LIMIT 1
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
    'lead_intake.submitted',
    input.data->>'submission_id',
    target.id,
    input.data#>>'{payload,schema_version}',
    (input.data#>>'{payload,submitted_at}')::timestamptz,
    input.data->'payload'
  FROM input
  CROSS JOIN target
  ON CONFLICT (event, submission_id) DO NOTHING
  RETURNING submission_id
),
email_outbox AS (
  INSERT INTO public.sevenday_notification_outbox (
    id,
    lead_id,
    submission_id,
    channel,
    recipient,
    template_version,
    payload,
    status
  )
  SELECT
    md5((input.data->>'submission_id') || ':email:welcome-v1')::uuid,
    target.id,
    input.data->>'submission_id',
    'email',
    lower(input.data#>>'{payload,contact,email}'),
    'welcome-v1',
    jsonb_build_object(
      'lead_id', target.id::text,
      'submission_id', input.data->>'submission_id',
      'contact_name', input.data#>>'{payload,contact,name}'
    ),
    'pending'
  FROM input
  CROSS JOIN target
  WHERE target.is_new
  ON CONFLICT (submission_id, channel, template_version) DO NOTHING
  RETURNING id
),
sms_outbox AS (
  INSERT INTO public.sevenday_notification_outbox (
    id,
    lead_id,
    submission_id,
    channel,
    recipient,
    template_version,
    payload,
    status,
    last_error
  )
  SELECT
    md5((input.data->>'submission_id') || ':sms:welcome-v1')::uuid,
    target.id,
    input.data->>'submission_id',
    'sms',
    input.data#>>'{payload,contact,phone_whatsapp}',
    'welcome-v1',
    jsonb_build_object(
      'lead_id', target.id::text,
      'submission_id', input.data->>'submission_id',
      'contact_name', input.data#>>'{payload,contact,name}'
    ),
    'blocked_config',
    'SMS provider and explicit SMS consent are not configured'
  FROM input
  CROSS JOIN target
  WHERE target.is_new
    AND NULLIF(input.data#>>'{payload,contact,phone_whatsapp}', '') IS NOT NULL
  ON CONFLICT (submission_id, channel, template_version) DO NOTHING
  RETURNING id
)
SELECT
  target.id::text AS lead_id,
  target.is_new,
  input.data->>'submission_id' AS submission_id
FROM target
CROSS JOIN input;
