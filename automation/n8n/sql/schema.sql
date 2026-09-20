BEGIN;

CREATE EXTENSION IF NOT EXISTS pgcrypto WITH SCHEMA public;

DO $pgcrypto$
BEGIN
  IF NOT EXISTS (
    SELECT 1
    FROM pg_extension AS extensions
    JOIN pg_namespace AS namespaces ON namespaces.oid = extensions.extnamespace
    WHERE extensions.extname = 'pgcrypto'
      AND namespaces.nspname = 'public'
  ) THEN
    RAISE EXCEPTION 'pgcrypto must be installed in the public schema';
  END IF;
END;
$pgcrypto$;

CREATE SCHEMA IF NOT EXISTS sevenday_private;
REVOKE ALL ON SCHEMA sevenday_private FROM PUBLIC;

CREATE TABLE IF NOT EXISTS sevenday_private.token_keys (
  purpose text PRIMARY KEY,
  secret bytea NOT NULL CHECK (octet_length(secret) >= 32),
  created_at timestamptz NOT NULL DEFAULT now()
);

REVOKE ALL ON TABLE sevenday_private.token_keys FROM PUBLIC;

INSERT INTO sevenday_private.token_keys (purpose, secret)
VALUES ('onboarding-v1', public.gen_random_bytes(32))
ON CONFLICT (purpose) DO NOTHING;

CREATE TABLE IF NOT EXISTS public.sevenday_leads (
  id uuid PRIMARY KEY DEFAULT public.gen_random_uuid(),
  initial_submission_id varchar(100) UNIQUE NOT NULL,
  status text NOT NULL DEFAULT 'new',
  schema_version text NOT NULL,
  submitted_at timestamptz NOT NULL,
  form_version text,
  form_duration_ms bigint,
  contact_name text NOT NULL,
  contact_email text NOT NULL,
  contact_phone text,
  preferred_channel text,
  package_interest text,
  visual_directions text[] NOT NULL DEFAULT '{}',
  objectives text[] NOT NULL DEFAULT '{}',
  assets_available text[] NOT NULL DEFAULT '{}',
  business_name_status text,
  business_name text,
  domain_status text,
  domain_or_site_url text,
  source jsonb,
  consent jsonb NOT NULL,
  raw_payload jsonb NOT NULL,
  payload_hash char(64) NOT NULL,
  onboarding_token_hash char(64) NOT NULL,
  onboarding_token_key text NOT NULL DEFAULT 'onboarding-v1',
  onboarding_token_expires_at timestamptz NOT NULL,
  onboarding_token_consumed_at timestamptz,
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now()
);

CREATE TABLE IF NOT EXISTS public.sevenday_submissions (
  event text NOT NULL,
  submission_id varchar(100) NOT NULL,
  lead_id uuid REFERENCES public.sevenday_leads(id) ON DELETE SET NULL,
  schema_version text NOT NULL,
  payload_hash char(64) NOT NULL,
  received_at timestamptz NOT NULL DEFAULT now(),
  submitted_at timestamptz,
  raw_payload jsonb NOT NULL,
  PRIMARY KEY (event, submission_id)
);

CREATE TABLE IF NOT EXISTS public.sevenday_onboardings (
  submission_id varchar(100) PRIMARY KEY,
  lead_id uuid NOT NULL REFERENCES public.sevenday_leads(id) ON DELETE CASCADE,
  parent_submission_id varchar(100),
  schema_version text NOT NULL,
  payload_hash char(64) NOT NULL,
  submitted_at timestamptz NOT NULL,
  form_duration_ms bigint,
  project jsonb NOT NULL,
  business jsonb NOT NULL,
  messaging jsonb NOT NULL,
  scope jsonb NOT NULL,
  brand jsonb NOT NULL,
  assets jsonb NOT NULL,
  launch jsonb NOT NULL,
  contact jsonb NOT NULL,
  source jsonb,
  consent jsonb NOT NULL,
  raw_payload jsonb NOT NULL,
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now()
);

CREATE TABLE IF NOT EXISTS public.sevenday_notification_outbox (
  id uuid PRIMARY KEY DEFAULT public.gen_random_uuid(),
  lead_id uuid NOT NULL REFERENCES public.sevenday_leads(id) ON DELETE CASCADE,
  submission_id varchar(100) NOT NULL,
  channel text NOT NULL,
  recipient text NOT NULL,
  template_version text NOT NULL,
  payload jsonb NOT NULL,
  status text NOT NULL DEFAULT 'pending',
  attempts integer NOT NULL DEFAULT 0,
  next_attempt_at timestamptz NOT NULL DEFAULT now(),
  lease_token uuid,
  locked_at timestamptz,
  locked_by text,
  provider_message_id text,
  last_error text,
  sent_at timestamptz,
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now(),
  UNIQUE (submission_id, channel, template_version)
);

CREATE TABLE IF NOT EXISTS public.sevenday_production_jobs (
  id uuid PRIMARY KEY DEFAULT public.gen_random_uuid(),
  lead_id uuid NOT NULL REFERENCES public.sevenday_leads(id) ON DELETE CASCADE,
  onboarding_submission_id varchar(100) UNIQUE NOT NULL
    REFERENCES public.sevenday_onboardings(submission_id) ON DELETE CASCADE,
  status text NOT NULL DEFAULT 'queued',
  production_context jsonb NOT NULL,
  handoff jsonb,
  attempts integer NOT NULL DEFAULT 0,
  lease_token uuid,
  locked_at timestamptz,
  locked_by text,
  last_error text,
  created_at timestamptz NOT NULL DEFAULT now(),
  started_at timestamptz,
  updated_at timestamptz NOT NULL DEFAULT now(),
  completed_at timestamptz
);

-- Compatibility with the earlier draft if it was applied before this migration.
ALTER TABLE public.sevenday_leads
  ADD COLUMN IF NOT EXISTS payload_hash char(64),
  ADD COLUMN IF NOT EXISTS onboarding_token_key text NOT NULL DEFAULT 'onboarding-v1',
  ADD COLUMN IF NOT EXISTS onboarding_token_consumed_at timestamptz;

ALTER TABLE public.sevenday_leads
  ALTER COLUMN id SET DEFAULT public.gen_random_uuid();

ALTER TABLE public.sevenday_submissions
  ADD COLUMN IF NOT EXISTS payload_hash char(64);

ALTER TABLE public.sevenday_onboardings
  ADD COLUMN IF NOT EXISTS payload_hash char(64);

ALTER TABLE public.sevenday_notification_outbox
  ADD COLUMN IF NOT EXISTS lease_token uuid,
  ADD COLUMN IF NOT EXISTS locked_at timestamptz,
  ADD COLUMN IF NOT EXISTS locked_by text;

ALTER TABLE public.sevenday_notification_outbox
  ALTER COLUMN id SET DEFAULT public.gen_random_uuid();

ALTER TABLE public.sevenday_production_jobs
  ADD COLUMN IF NOT EXISTS lease_token uuid,
  ADD COLUMN IF NOT EXISTS locked_at timestamptz,
  ADD COLUMN IF NOT EXISTS locked_by text;

ALTER TABLE public.sevenday_production_jobs
  ALTER COLUMN id SET DEFAULT public.gen_random_uuid();

CREATE OR REPLACE FUNCTION public.sevenday_try_timestamptz(p_value text)
RETURNS timestamptz
LANGUAGE plpgsql
STABLE
STRICT
AS $$
BEGIN
  RETURN p_value::timestamptz;
EXCEPTION WHEN invalid_datetime_format OR datetime_field_overflow THEN
  RETURN NULL;
END;
$$;

CREATE OR REPLACE FUNCTION public.sevenday_try_uuid(p_value text)
RETURNS uuid
LANGUAGE plpgsql
IMMUTABLE
STRICT
AS $$
BEGIN
  RETURN p_value::uuid;
EXCEPTION WHEN invalid_text_representation THEN
  RETURN NULL;
END;
$$;

CREATE OR REPLACE FUNCTION public.sevenday_jsonb_text_array(p_value jsonb)
RETURNS text[]
LANGUAGE sql
IMMUTABLE
AS $$
  SELECT CASE
    WHEN jsonb_typeof(p_value) = 'array'
      THEN ARRAY(SELECT jsonb_array_elements_text(p_value))
    ELSE ARRAY[]::text[]
  END;
$$;

CREATE OR REPLACE FUNCTION public.sevenday_payload_hash(p_payload jsonb)
RETURNS char(64)
LANGUAGE sql
IMMUTABLE
STRICT
AS $$
  SELECT encode(
    public.digest(
      convert_to(
        ((((p_payload - 'submitted_at') - 'source') - 'onboarding_token') #- '{form,duration_ms}')::text,
        'UTF8'
      ),
      'sha256'
    ),
    'hex'
  )::char(64);
$$;

-- Remove a token left by an earlier draft before computing/backfilling hashes.
-- Existing draft rows used non-recoverable random tokens. Mark them explicitly
-- so the new HMAC generator never pretends it can reproduce those links.
UPDATE public.sevenday_leads
SET onboarding_token_key = 'legacy-random-v0'
WHERE payload_hash IS NULL;

UPDATE public.sevenday_onboardings
SET raw_payload = raw_payload - 'onboarding_token'
WHERE raw_payload ? 'onboarding_token';

UPDATE public.sevenday_submissions
SET raw_payload = raw_payload - 'onboarding_token'
WHERE event = 'client_onboarding.submitted'
  AND raw_payload ? 'onboarding_token';

UPDATE public.sevenday_production_jobs
SET production_context = production_context #- '{onboarding,onboarding_token}'
WHERE (production_context #> '{onboarding}') ? 'onboarding_token';

WITH completed AS (
  SELECT onboardings.lead_id, min(onboardings.created_at) AS completed_at
  FROM public.sevenday_onboardings AS onboardings
  GROUP BY onboardings.lead_id
)
UPDATE public.sevenday_leads AS leads
SET onboarding_token_consumed_at = completed.completed_at,
    status = 'onboarding_complete',
    updated_at = GREATEST(leads.updated_at, completed.completed_at)
FROM completed
WHERE leads.id = completed.lead_id
  AND leads.onboarding_token_consumed_at IS NULL;

UPDATE public.sevenday_leads
SET payload_hash = public.sevenday_payload_hash(raw_payload)
WHERE payload_hash IS NULL;

UPDATE public.sevenday_submissions
SET payload_hash = public.sevenday_payload_hash(raw_payload)
WHERE payload_hash IS NULL;

UPDATE public.sevenday_onboardings
SET payload_hash = public.sevenday_payload_hash(raw_payload)
WHERE payload_hash IS NULL;

ALTER TABLE public.sevenday_leads ALTER COLUMN payload_hash SET NOT NULL;
ALTER TABLE public.sevenday_submissions ALTER COLUMN payload_hash SET NOT NULL;
ALTER TABLE public.sevenday_onboardings ALTER COLUMN payload_hash SET NOT NULL;

CREATE INDEX IF NOT EXISTS sevenday_leads_email_idx
  ON public.sevenday_leads (lower(contact_email));
CREATE INDEX IF NOT EXISTS sevenday_leads_status_idx
  ON public.sevenday_leads (status, created_at);
CREATE INDEX IF NOT EXISTS sevenday_submissions_lead_idx
  ON public.sevenday_submissions (lead_id, received_at DESC);
CREATE INDEX IF NOT EXISTS sevenday_onboardings_lead_idx
  ON public.sevenday_onboardings (lead_id, created_at DESC);
CREATE INDEX IF NOT EXISTS sevenday_outbox_claim_idx
  ON public.sevenday_notification_outbox (channel, status, next_attempt_at, created_at);
CREATE INDEX IF NOT EXISTS sevenday_production_jobs_queue_idx
  ON public.sevenday_production_jobs (status, created_at);

CREATE OR REPLACE FUNCTION sevenday_private.make_onboarding_token(
  p_lead_id uuid,
  p_submission_id text,
  p_key_purpose text DEFAULT 'onboarding-v1'
)
RETURNS text
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = pg_catalog, sevenday_private, public
AS $$
DECLARE
  v_secret bytea;
  v_signature bytea;
BEGIN
  SELECT token_keys.secret
  INTO v_secret
  FROM sevenday_private.token_keys
  WHERE token_keys.purpose = p_key_purpose;

  IF v_secret IS NULL THEN
    RAISE EXCEPTION 'Missing onboarding token key: %', p_key_purpose;
  END IF;

  v_signature := public.hmac(
    convert_to('sevenday:onboarding:v1:' || p_lead_id::text || ':' || p_submission_id, 'UTF8'),
    v_secret,
    'sha256'
  );

  RETURN rtrim(translate(encode(v_signature, 'base64'), '+/', '-_'), '=');
END;
$$;

REVOKE ALL ON FUNCTION sevenday_private.make_onboarding_token(uuid, text, text) FROM PUBLIC;

CREATE OR REPLACE FUNCTION public.sevenday_ingest_lead(p_payload jsonb)
RETURNS TABLE (
  ok boolean,
  http_status integer,
  status text,
  error_code text,
  lead_id text,
  submission_id text,
  onboarding_token text,
  onboarding_token_expires_at timestamptz,
  is_new boolean
)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = pg_catalog, public, sevenday_private
AS $$
DECLARE
  v_submission_id text;
  v_payload_hash char(64);
  v_submitted_at timestamptz;
  v_email text;
  v_name text;
  v_phone text;
  v_lead public.sevenday_leads%ROWTYPE;
  v_existing_hash char(64);
  v_token text;
BEGIN
  ok := false;
  http_status := 422;
  status := 'rejected';
  error_code := NULL;
  lead_id := NULL;
  submission_id := NULL;
  onboarding_token := NULL;
  onboarding_token_expires_at := NULL;
  is_new := false;

  IF jsonb_typeof(p_payload) IS DISTINCT FROM 'object' THEN
    error_code := 'invalid_payload'; RETURN NEXT; RETURN;
  END IF;

  v_submission_id := btrim(COALESCE(p_payload->>'submission_id', ''));
  submission_id := NULLIF(v_submission_id, '');
  v_email := lower(btrim(COALESCE(p_payload#>>'{contact,email}', '')));
  v_name := btrim(COALESCE(p_payload#>>'{contact,name}', ''));
  v_phone := NULLIF(btrim(COALESCE(p_payload#>>'{contact,phone_whatsapp}', '')), '');
  v_submitted_at := public.sevenday_try_timestamptz(p_payload->>'submitted_at');

  IF p_payload->>'event' IS DISTINCT FROM 'lead_intake.submitted' THEN
    error_code := 'invalid_event'; RETURN NEXT; RETURN;
  ELSIF p_payload->>'schema_version' IS DISTINCT FROM '3.0' THEN
    error_code := 'unsupported_schema_version'; RETURN NEXT; RETURN;
  ELSIF length(v_submission_id) < 8 OR length(v_submission_id) > 100 THEN
    error_code := 'invalid_submission_id'; RETURN NEXT; RETURN;
  ELSIF v_submitted_at IS NULL THEN
    error_code := 'invalid_submitted_at'; RETURN NEXT; RETURN;
  ELSIF length(v_name) < 2 OR length(v_name) > 200 THEN
    error_code := 'invalid_contact_name'; RETURN NEXT; RETURN;
  ELSIF length(v_email) > 320 OR v_email !~* '^[^[:space:]@]+@[^[:space:]@]+\.[^[:space:]@]+$' THEN
    error_code := 'invalid_contact_email'; RETURN NEXT; RETURN;
  ELSIF p_payload#>>'{consent,project_contact}' IS DISTINCT FROM 'true' THEN
    error_code := 'contact_consent_required'; RETURN NEXT; RETURN;
  ELSIF jsonb_typeof(p_payload->'preferences') IS DISTINCT FROM 'object'
     OR jsonb_typeof(p_payload->'content') IS DISTINCT FROM 'object'
     OR jsonb_typeof(p_payload->'brand') IS DISTINCT FROM 'object'
     OR jsonb_typeof(p_payload->'contact') IS DISTINCT FROM 'object'
     OR jsonb_typeof(p_payload->'consent') IS DISTINCT FROM 'object' THEN
    error_code := 'invalid_payload_sections'; RETURN NEXT; RETURN;
  END IF;

  v_payload_hash := public.sevenday_payload_hash(p_payload);
  PERFORM pg_advisory_xact_lock(hashtextextended('sevenday:lead:' || v_submission_id, 0));

  SELECT submissions.lead_id, submissions.payload_hash
  INTO v_lead.id, v_existing_hash
  FROM public.sevenday_submissions AS submissions
  WHERE submissions.event = 'lead_intake.submitted'
    AND submissions.submission_id = v_submission_id;

  IF FOUND THEN
    IF v_existing_hash IS DISTINCT FROM v_payload_hash THEN
      http_status := 409;
      status := 'conflict';
      error_code := 'idempotency_conflict';
      RETURN NEXT; RETURN;
    END IF;

    SELECT leads.* INTO v_lead
    FROM public.sevenday_leads AS leads
    WHERE leads.id = v_lead.id;

    IF NOT FOUND THEN
      http_status := 500;
      status := 'error';
      error_code := 'lead_record_missing';
      RETURN NEXT; RETURN;
    END IF;

    IF v_lead.onboarding_token_consumed_at IS NOT NULL THEN
      http_status := 409;
      status := 'conflict';
      error_code := 'onboarding_already_complete';
      RETURN NEXT; RETURN;
    ELSIF v_lead.onboarding_token_expires_at <= now() THEN
      http_status := 410;
      status := 'expired';
      error_code := 'onboarding_token_expired';
      RETURN NEXT; RETURN;
    ELSIF NOT EXISTS (
      SELECT 1
      FROM sevenday_private.token_keys AS token_keys
      WHERE token_keys.purpose = v_lead.onboarding_token_key
    ) THEN
      http_status := 409;
      status := 'conflict';
      error_code := 'onboarding_token_reissue_required';
      RETURN NEXT; RETURN;
    END IF;

    v_token := sevenday_private.make_onboarding_token(
      v_lead.id,
      v_lead.initial_submission_id,
      v_lead.onboarding_token_key
    );
    IF encode(public.digest(convert_to(v_token, 'UTF8'), 'sha256'), 'hex')
       IS DISTINCT FROM v_lead.onboarding_token_hash::text THEN
      http_status := 500;
      status := 'error';
      error_code := 'token_key_mismatch';
      RETURN NEXT; RETURN;
    END IF;

    ok := true;
    http_status := 200;
    status := 'duplicate';
    error_code := NULL;
    lead_id := v_lead.id::text;
    onboarding_token := v_token;
    onboarding_token_expires_at := v_lead.onboarding_token_expires_at;
    is_new := false;
    RETURN NEXT; RETURN;
  END IF;

  v_lead.id := public.gen_random_uuid();
  v_token := sevenday_private.make_onboarding_token(v_lead.id, v_submission_id, 'onboarding-v1');

  INSERT INTO public.sevenday_leads (
    id, initial_submission_id, status, schema_version, submitted_at,
    form_version, form_duration_ms, contact_name, contact_email, contact_phone,
    preferred_channel, package_interest, visual_directions, objectives,
    assets_available, business_name_status, business_name, domain_status,
    domain_or_site_url, source, consent, raw_payload, payload_hash,
    onboarding_token_hash, onboarding_token_key, onboarding_token_expires_at
  ) VALUES (
    v_lead.id,
    v_submission_id,
    'new',
    p_payload->>'schema_version',
    v_submitted_at,
    NULLIF(p_payload#>>'{form,version}', ''),
    CASE WHEN COALESCE(p_payload#>>'{form,duration_ms}', '') ~ '^[0-9]{1,15}$'
      THEN (p_payload#>>'{form,duration_ms}')::bigint END,
    v_name,
    v_email,
    v_phone,
    NULLIF(p_payload#>>'{contact,preferred_channel}', ''),
    NULLIF(p_payload#>>'{preferences,package_interest}', ''),
    public.sevenday_jsonb_text_array(p_payload#>'{preferences,visual_directions}'),
    public.sevenday_jsonb_text_array(p_payload#>'{preferences,objectives}'),
    public.sevenday_jsonb_text_array(p_payload#>'{content,assets_available}'),
    NULLIF(p_payload#>>'{brand,business_name_status}', ''),
    NULLIF(p_payload#>>'{brand,business_name}', ''),
    NULLIF(p_payload#>>'{brand,domain_status}', ''),
    NULLIF(p_payload#>>'{brand,domain_or_site_url}', ''),
    p_payload->'source',
    p_payload->'consent',
    p_payload,
    v_payload_hash,
    encode(public.digest(convert_to(v_token, 'UTF8'), 'sha256'), 'hex'),
    'onboarding-v1',
    now() + interval '14 days'
  )
  RETURNING * INTO v_lead;

  INSERT INTO public.sevenday_submissions (
    event, submission_id, lead_id, schema_version, payload_hash, submitted_at, raw_payload
  ) VALUES (
    'lead_intake.submitted', v_submission_id, v_lead.id,
    p_payload->>'schema_version', v_payload_hash, v_submitted_at, p_payload
  );

  INSERT INTO public.sevenday_notification_outbox (
    lead_id, submission_id, channel, recipient, template_version, payload, status
  ) VALUES (
    v_lead.id,
    v_submission_id,
    'email',
    v_email,
    'welcome-v1',
    jsonb_build_object(
      'lead_id', v_lead.id::text,
      'submission_id', v_submission_id,
      'contact_name', v_name
    ),
    'pending'
  ) ON CONFLICT DO NOTHING;

  IF v_phone IS NOT NULL THEN
    INSERT INTO public.sevenday_notification_outbox (
      lead_id, submission_id, channel, recipient, template_version,
      payload, status, last_error
    ) VALUES (
      v_lead.id,
      v_submission_id,
      'sms',
      v_phone,
      'welcome-v1',
      jsonb_build_object(
        'lead_id', v_lead.id::text,
        'submission_id', v_submission_id,
        'contact_name', v_name
      ),
      'blocked_config',
      'SMS provider and explicit SMS consent are not configured'
    ) ON CONFLICT DO NOTHING;
  END IF;

  ok := true;
  http_status := 201;
  status := 'created';
  error_code := NULL;
  lead_id := v_lead.id::text;
  onboarding_token := v_token;
  onboarding_token_expires_at := v_lead.onboarding_token_expires_at;
  is_new := true;
  RETURN NEXT;
END;
$$;

CREATE OR REPLACE FUNCTION public.sevenday_ingest_onboarding(p_payload jsonb)
RETURNS TABLE (
  ok boolean,
  http_status integer,
  status text,
  error_code text,
  lead_id text,
  submission_id text,
  production_job_id text,
  production_status text,
  is_new boolean
)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = pg_catalog, public, sevenday_private
AS $$
DECLARE
  v_submission_id text;
  v_parent_lead_id uuid;
  v_parent_submission_id text;
  v_token text;
  v_token_hash char(64);
  v_payload_hash char(64);
  v_existing_hash char(64);
  v_existing_lead_id uuid;
  v_submitted_at timestamptz;
  v_sanitized jsonb;
  v_lead public.sevenday_leads%ROWTYPE;
  v_job public.sevenday_production_jobs%ROWTYPE;
  v_lead_found boolean;
BEGIN
  ok := false;
  http_status := 422;
  status := 'rejected';
  error_code := NULL;
  lead_id := NULL;
  submission_id := NULL;
  production_job_id := NULL;
  production_status := NULL;
  is_new := false;

  IF jsonb_typeof(p_payload) IS DISTINCT FROM 'object' THEN
    error_code := 'invalid_payload'; RETURN NEXT; RETURN;
  END IF;

  v_submission_id := btrim(COALESCE(p_payload->>'submission_id', ''));
  submission_id := NULLIF(v_submission_id, '');
  v_parent_lead_id := public.sevenday_try_uuid(p_payload->>'parent_lead_id');
  v_parent_submission_id := NULLIF(btrim(COALESCE(p_payload->>'parent_submission_id', '')), '');
  v_token := btrim(COALESCE(p_payload->>'onboarding_token', ''));
  v_submitted_at := public.sevenday_try_timestamptz(p_payload->>'submitted_at');

  IF p_payload->>'event' IS DISTINCT FROM 'client_onboarding.submitted' THEN
    error_code := 'invalid_event'; RETURN NEXT; RETURN;
  ELSIF p_payload->>'schema_version' IS DISTINCT FROM '3.0' THEN
    error_code := 'unsupported_schema_version'; RETURN NEXT; RETURN;
  ELSIF length(v_submission_id) < 8 OR length(v_submission_id) > 100 THEN
    error_code := 'invalid_submission_id'; RETURN NEXT; RETURN;
  ELSIF v_parent_lead_id IS NULL THEN
    error_code := 'invalid_parent_lead_id'; RETURN NEXT; RETURN;
  ELSIF v_token !~ '^[A-Za-z0-9_-]{43}$' THEN
    error_code := 'invalid_onboarding_token'; RETURN NEXT; RETURN;
  ELSIF v_submitted_at IS NULL THEN
    error_code := 'invalid_submitted_at'; RETURN NEXT; RETURN;
  ELSIF p_payload#>>'{consent,project_contact}' IS DISTINCT FROM 'true' THEN
    error_code := 'contact_consent_required'; RETURN NEXT; RETURN;
  ELSIF jsonb_typeof(p_payload->'project') IS DISTINCT FROM 'object'
     OR jsonb_typeof(p_payload->'business') IS DISTINCT FROM 'object'
     OR jsonb_typeof(p_payload->'messaging') IS DISTINCT FROM 'object'
     OR jsonb_typeof(p_payload->'scope') IS DISTINCT FROM 'object'
     OR jsonb_typeof(p_payload->'brand') IS DISTINCT FROM 'object'
     OR jsonb_typeof(p_payload->'assets') IS DISTINCT FROM 'object'
     OR jsonb_typeof(p_payload->'launch') IS DISTINCT FROM 'object'
     OR jsonb_typeof(p_payload->'contact') IS DISTINCT FROM 'object'
     OR jsonb_typeof(p_payload->'consent') IS DISTINCT FROM 'object' THEN
    error_code := 'invalid_payload_sections'; RETURN NEXT; RETURN;
  END IF;

  v_sanitized := p_payload - 'onboarding_token';
  v_payload_hash := public.sevenday_payload_hash(v_sanitized);
  v_token_hash := encode(public.digest(convert_to(v_token, 'UTF8'), 'sha256'), 'hex');

  PERFORM pg_advisory_xact_lock(hashtextextended('sevenday:onboarding:' || v_submission_id, 0));

  SELECT submissions.lead_id, submissions.payload_hash
  INTO v_existing_lead_id, v_existing_hash
  FROM public.sevenday_submissions AS submissions
  WHERE submissions.event = 'client_onboarding.submitted'
    AND submissions.submission_id = v_submission_id;

  IF FOUND THEN
    SELECT leads.* INTO v_lead
    FROM public.sevenday_leads AS leads
    WHERE leads.id = v_existing_lead_id;
    v_lead_found := FOUND;

    IF v_existing_lead_id IS DISTINCT FROM v_parent_lead_id
       OR v_existing_hash IS DISTINCT FROM v_payload_hash THEN
      http_status := 409;
      status := 'conflict';
      error_code := 'idempotency_conflict';
      RETURN NEXT; RETURN;
    ELSIF NOT v_lead_found OR v_lead.onboarding_token_hash IS DISTINCT FROM v_token_hash THEN
      http_status := 403;
      status := 'forbidden';
      error_code := 'invalid_onboarding_token';
      RETURN NEXT; RETURN;
    END IF;

    SELECT jobs.* INTO v_job
    FROM public.sevenday_production_jobs AS jobs
    WHERE jobs.onboarding_submission_id = v_submission_id;

    IF NOT FOUND THEN
      INSERT INTO public.sevenday_production_jobs (
        lead_id, onboarding_submission_id, status, production_context
      )
      SELECT
        v_existing_lead_id,
        onboardings.submission_id,
        'queued',
        jsonb_build_object(
          'context_version', '1.0',
          'lead_id', v_existing_lead_id::text,
          'lead', v_lead.raw_payload,
          'onboarding', onboardings.raw_payload
        )
      FROM public.sevenday_onboardings AS onboardings
      WHERE onboardings.submission_id = v_submission_id
      RETURNING * INTO v_job;

      IF NOT FOUND THEN
        http_status := 500;
        status := 'error';
        error_code := 'production_job_missing';
        RETURN NEXT; RETURN;
      END IF;
    END IF;

    ok := true;
    http_status := 200;
    status := 'duplicate';
    error_code := NULL;
    lead_id := v_existing_lead_id::text;
    production_job_id := CASE WHEN v_job.id IS NULL THEN NULL ELSE v_job.id::text END;
    production_status := v_job.status;
    is_new := false;
    RETURN NEXT; RETURN;
  END IF;

  PERFORM pg_advisory_xact_lock(hashtextextended('sevenday:onboarding-lead:' || v_parent_lead_id::text, 0));

  SELECT leads.* INTO v_lead
  FROM public.sevenday_leads AS leads
  WHERE leads.id = v_parent_lead_id;

  IF NOT FOUND THEN
    http_status := 404;
    status := 'not_found';
    error_code := 'lead_not_found';
    RETURN NEXT; RETURN;
  ELSIF v_parent_submission_id IS NOT NULL
     AND v_parent_submission_id IS DISTINCT FROM v_lead.initial_submission_id THEN
    http_status := 409;
    status := 'conflict';
    error_code := 'parent_submission_mismatch';
    RETURN NEXT; RETURN;
  ELSIF v_lead.onboarding_token_hash IS DISTINCT FROM v_token_hash THEN
    http_status := 403;
    status := 'forbidden';
    error_code := 'invalid_onboarding_token';
    RETURN NEXT; RETURN;
  ELSIF v_lead.onboarding_token_consumed_at IS NOT NULL THEN
    http_status := 409;
    status := 'conflict';
    error_code := 'onboarding_token_consumed';
    RETURN NEXT; RETURN;
  ELSIF v_lead.onboarding_token_expires_at <= now() THEN
    http_status := 410;
    status := 'expired';
    error_code := 'onboarding_token_expired';
    RETURN NEXT; RETURN;
  END IF;

  INSERT INTO public.sevenday_onboardings (
    submission_id, lead_id, parent_submission_id, schema_version, payload_hash,
    submitted_at, form_duration_ms, project, business, messaging, scope, brand,
    assets, launch, contact, source, consent, raw_payload
  ) VALUES (
    v_submission_id,
    v_lead.id,
    v_parent_submission_id,
    p_payload->>'schema_version',
    v_payload_hash,
    v_submitted_at,
    CASE WHEN COALESCE(p_payload#>>'{form,duration_ms}', '') ~ '^[0-9]{1,15}$'
      THEN (p_payload#>>'{form,duration_ms}')::bigint END,
    p_payload->'project',
    p_payload->'business',
    p_payload->'messaging',
    p_payload->'scope',
    p_payload->'brand',
    p_payload->'assets',
    p_payload->'launch',
    p_payload->'contact',
    p_payload->'source',
    p_payload->'consent',
    v_sanitized
  );

  INSERT INTO public.sevenday_submissions (
    event, submission_id, lead_id, schema_version, payload_hash, submitted_at, raw_payload
  ) VALUES (
    'client_onboarding.submitted', v_submission_id, v_lead.id,
    p_payload->>'schema_version', v_payload_hash, v_submitted_at, v_sanitized
  );

  UPDATE public.sevenday_leads AS leads
  SET status = 'onboarding_complete',
      onboarding_token_consumed_at = now(),
      updated_at = now()
  WHERE leads.id = v_lead.id;

  INSERT INTO public.sevenday_production_jobs (
    lead_id, onboarding_submission_id, status, production_context
  ) VALUES (
    v_lead.id,
    v_submission_id,
    'queued',
    jsonb_build_object(
      'context_version', '1.0',
      'lead_id', v_lead.id::text,
      'lead', v_lead.raw_payload,
      'onboarding', v_sanitized
    )
  )
  RETURNING * INTO v_job;

  ok := true;
  http_status := 202;
  status := 'queued';
  error_code := NULL;
  lead_id := v_lead.id::text;
  production_job_id := v_job.id::text;
  production_status := v_job.status;
  is_new := true;
  RETURN NEXT;
END;
$$;

CREATE OR REPLACE FUNCTION public.sevenday_ingest_request(p_request jsonb)
RETURNS TABLE (
  ok boolean,
  http_status integer,
  status text,
  error text,
  error_code text,
  lead_id text,
  submission_id text,
  onboarding_token text,
  onboarding_token_expires_at timestamptz,
  production_job_id text,
  production_status text,
  is_new boolean
)
LANGUAGE plpgsql
AS $$
DECLARE
  v_payload jsonb;
  v_header_event text;
  v_idempotency_key text;
  v_validation_error text;
  v_lead record;
  v_onboarding record;
BEGIN
  v_payload := CASE
    WHEN jsonb_typeof(p_request->'payload') = 'object' THEN p_request->'payload'
    ELSE p_request
  END;
  v_header_event := NULLIF(btrim(COALESCE(p_request->>'header_event', '')), '');
  v_idempotency_key := NULLIF(btrim(COALESCE(p_request->>'idempotency_key', '')), '');
  v_validation_error := NULLIF(btrim(COALESCE(p_request->>'validation_error', '')), '');

  IF v_validation_error IS NOT NULL THEN
    RETURN QUERY SELECT
      false, 422, 'rejected'::text, v_validation_error, v_validation_error,
      NULL::text, v_payload->>'submission_id', NULL::text, NULL::timestamptz,
      NULL::text, NULL::text, false;
    RETURN;
  ELSIF v_header_event IS NOT NULL
     AND v_header_event IS DISTINCT FROM v_payload->>'event' THEN
    RETURN QUERY SELECT
      false, 400, 'rejected'::text, 'header_event_mismatch'::text, 'header_event_mismatch'::text,
      NULL::text, v_payload->>'submission_id', NULL::text, NULL::timestamptz,
      NULL::text, NULL::text, false;
    RETURN;
  ELSIF v_idempotency_key IS NOT NULL
     AND v_idempotency_key IS DISTINCT FROM v_payload->>'submission_id' THEN
    RETURN QUERY SELECT
      false, 409, 'conflict'::text, 'idempotency_key_mismatch'::text, 'idempotency_key_mismatch'::text,
      NULL::text, v_payload->>'submission_id', NULL::text, NULL::timestamptz,
      NULL::text, NULL::text, false;
    RETURN;
  END IF;

  IF v_payload->>'event' = 'lead_intake.submitted' THEN
    SELECT result.* INTO v_lead
    FROM public.sevenday_ingest_lead(v_payload) AS result;

    RETURN QUERY SELECT
      v_lead.ok,
      v_lead.http_status,
      v_lead.status,
      v_lead.error_code,
      v_lead.error_code,
      v_lead.lead_id,
      v_lead.submission_id,
      v_lead.onboarding_token,
      v_lead.onboarding_token_expires_at,
      NULL::text,
      NULL::text,
      v_lead.is_new;
    RETURN;
  ELSIF v_payload->>'event' = 'client_onboarding.submitted' THEN
    SELECT result.* INTO v_onboarding
    FROM public.sevenday_ingest_onboarding(v_payload) AS result;

    RETURN QUERY SELECT
      v_onboarding.ok,
      v_onboarding.http_status,
      v_onboarding.status,
      v_onboarding.error_code,
      v_onboarding.error_code,
      v_onboarding.lead_id,
      v_onboarding.submission_id,
      NULL::text,
      NULL::timestamptz,
      v_onboarding.production_job_id,
      v_onboarding.production_status,
      v_onboarding.is_new;
    RETURN;
  END IF;

  RETURN QUERY SELECT
    false, 422, 'rejected'::text, 'invalid_event'::text, 'invalid_event'::text,
    NULL::text, v_payload->>'submission_id', NULL::text, NULL::timestamptz,
    NULL::text, NULL::text, false;
END;
$$;

CREATE OR REPLACE FUNCTION public.sevenday_claim_email(p_request jsonb DEFAULT '{}'::jsonb)
RETURNS TABLE (
  outbox_id text,
  lease_token text,
  lead_id text,
  submission_id text,
  recipient text,
  template_version text,
  payload jsonb,
  attempts integer,
  lease_expires_at timestamptz
)
LANGUAGE plpgsql
AS $$
DECLARE
  v_limit integer := 10;
  v_worker_id text := left(COALESCE(NULLIF(p_request->>'worker_id', ''), 'n8n-email-worker'), 100);
BEGIN
  IF COALESCE(p_request->>'limit', '') ~ '^[0-9]{1,2}$' THEN
    v_limit := LEAST(25, GREATEST(1, (p_request->>'limit')::integer));
  END IF;

  UPDATE public.sevenday_notification_outbox AS outbox
  SET status = 'dead_letter',
      lease_token = NULL,
      locked_at = NULL,
      locked_by = NULL,
      last_error = COALESCE(outbox.last_error, 'Dispatch lease expired after maximum attempts'),
      updated_at = now()
  WHERE outbox.channel = 'email'
    AND outbox.attempts >= 5
    AND (
      outbox.status = 'pending'
      OR (
        outbox.status = 'dispatching'
        AND COALESCE(outbox.locked_at, outbox.updated_at) < now() - interval '15 minutes'
      )
    );

  RETURN QUERY
  WITH candidates AS (
    SELECT candidate.id
    FROM public.sevenday_notification_outbox AS candidate
    WHERE candidate.channel = 'email'
      AND candidate.attempts < 5
      AND (
        (candidate.status = 'pending' AND candidate.next_attempt_at <= now())
        OR (
          candidate.status = 'dispatching'
          AND COALESCE(candidate.locked_at, candidate.updated_at) < now() - interval '15 minutes'
        )
      )
    ORDER BY candidate.created_at, candidate.id
    FOR UPDATE SKIP LOCKED
    LIMIT v_limit
  )
  UPDATE public.sevenday_notification_outbox AS claimed
  SET status = 'dispatching',
      attempts = claimed.attempts + 1,
      lease_token = public.gen_random_uuid(),
      locked_at = now(),
      locked_by = v_worker_id,
      updated_at = now()
  FROM candidates
  WHERE claimed.id = candidates.id
  RETURNING
    claimed.id::text,
    claimed.lease_token::text,
    claimed.lead_id::text,
    claimed.submission_id::text,
    claimed.recipient,
    claimed.template_version,
    claimed.payload,
    claimed.attempts,
    claimed.locked_at + interval '15 minutes';
END;
$$;

CREATE OR REPLACE FUNCTION public.sevenday_get_onboarding_token(p_request jsonb)
RETURNS TABLE (
  ok boolean,
  error_code text,
  outbox_id text,
  lead_id text,
  recipient text,
  contact_name text,
  onboarding_token text,
  onboarding_token_expires_at timestamptz,
  onboarding_path text
)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = pg_catalog, public, sevenday_private
AS $$
DECLARE
  v_outbox_id uuid := public.sevenday_try_uuid(p_request->>'outbox_id');
  v_lease_token uuid := public.sevenday_try_uuid(p_request->>'lease_token');
  v_outbox public.sevenday_notification_outbox%ROWTYPE;
  v_lead public.sevenday_leads%ROWTYPE;
  v_token text;
BEGIN
  ok := false;
  error_code := 'invalid_claim';
  outbox_id := p_request->>'outbox_id';
  lead_id := NULL;
  recipient := NULL;
  contact_name := NULL;
  onboarding_token := NULL;
  onboarding_token_expires_at := NULL;
  onboarding_path := NULL;

  IF v_outbox_id IS NULL OR v_lease_token IS NULL THEN
    RETURN NEXT; RETURN;
  END IF;

  SELECT outbox.* INTO v_outbox
  FROM public.sevenday_notification_outbox AS outbox
  WHERE outbox.id = v_outbox_id
    AND outbox.lease_token = v_lease_token
    AND outbox.status = 'dispatching'
    AND outbox.channel = 'email'
    AND outbox.template_version = 'welcome-v1'
    AND COALESCE(outbox.locked_at, outbox.updated_at) >= now() - interval '15 minutes';

  IF NOT FOUND THEN
    error_code := 'lease_mismatch'; RETURN NEXT; RETURN;
  END IF;

  SELECT leads.* INTO v_lead
  FROM public.sevenday_leads AS leads
  WHERE leads.id = v_outbox.lead_id;

  IF NOT FOUND THEN
    error_code := 'lead_not_found'; RETURN NEXT; RETURN;
  ELSIF v_lead.onboarding_token_consumed_at IS NOT NULL THEN
    error_code := 'onboarding_already_complete'; RETURN NEXT; RETURN;
  ELSIF v_lead.onboarding_token_expires_at <= now() THEN
    error_code := 'onboarding_token_expired'; RETURN NEXT; RETURN;
  ELSIF NOT EXISTS (
    SELECT 1
    FROM sevenday_private.token_keys AS token_keys
    WHERE token_keys.purpose = v_lead.onboarding_token_key
  ) THEN
    error_code := 'onboarding_token_reissue_required'; RETURN NEXT; RETURN;
  END IF;

  v_token := sevenday_private.make_onboarding_token(
    v_lead.id,
    v_lead.initial_submission_id,
    v_lead.onboarding_token_key
  );

  IF encode(public.digest(convert_to(v_token, 'UTF8'), 'sha256'), 'hex')
     IS DISTINCT FROM v_lead.onboarding_token_hash::text THEN
    error_code := 'token_key_mismatch'; RETURN NEXT; RETURN;
  END IF;

  ok := true;
  error_code := NULL;
  lead_id := v_lead.id::text;
  recipient := v_outbox.recipient;
  contact_name := v_lead.contact_name;
  onboarding_token := v_token;
  onboarding_token_expires_at := v_lead.onboarding_token_expires_at;
  onboarding_path := '/briefing?lead_id=' || v_lead.id::text || '&token=' || v_token;
  RETURN NEXT;
END;
$$;

CREATE OR REPLACE FUNCTION public.sevenday_mark_outbox_sent(p_request jsonb)
RETURNS TABLE (ok boolean, error_code text, outbox_id text, status text)
LANGUAGE plpgsql
AS $$
DECLARE
  v_outbox_id uuid := public.sevenday_try_uuid(p_request->>'outbox_id');
  v_lease_token uuid := public.sevenday_try_uuid(p_request->>'lease_token');
BEGIN
  ok := false;
  error_code := 'invalid_claim';
  outbox_id := p_request->>'outbox_id';
  status := NULL;

  IF v_outbox_id IS NULL OR v_lease_token IS NULL THEN RETURN NEXT; RETURN; END IF;

  UPDATE public.sevenday_notification_outbox AS outbox
  SET status = 'sent',
      provider_message_id = NULLIF(left(COALESCE(p_request->>'provider_message_id', ''), 500), ''),
      sent_at = now(),
      lease_token = NULL,
      locked_at = NULL,
      locked_by = NULL,
      last_error = NULL,
      updated_at = now()
  WHERE outbox.id = v_outbox_id
    AND outbox.lease_token = v_lease_token
    AND outbox.status = 'dispatching'
  RETURNING true, NULL::text, outbox.id::text, outbox.status
  INTO ok, error_code, outbox_id, status;

  IF NOT FOUND THEN
    error_code := 'lease_mismatch';
  END IF;
  RETURN NEXT;
END;
$$;

CREATE OR REPLACE FUNCTION public.sevenday_mark_outbox_failed(p_request jsonb)
RETURNS TABLE (
  ok boolean,
  error_code text,
  outbox_id text,
  status text,
  next_attempt_at timestamptz
)
LANGUAGE plpgsql
AS $$
DECLARE
  v_outbox_id uuid := public.sevenday_try_uuid(p_request->>'outbox_id');
  v_lease_token uuid := public.sevenday_try_uuid(p_request->>'lease_token');
BEGIN
  ok := false;
  error_code := 'invalid_claim';
  outbox_id := p_request->>'outbox_id';
  status := NULL;
  next_attempt_at := NULL;

  IF v_outbox_id IS NULL OR v_lease_token IS NULL THEN RETURN NEXT; RETURN; END IF;

  UPDATE public.sevenday_notification_outbox AS outbox
  SET status = CASE WHEN outbox.attempts >= 5 THEN 'dead_letter' ELSE 'pending' END,
      next_attempt_at = CASE
        WHEN outbox.attempts >= 5 THEN outbox.next_attempt_at
        ELSE now() + make_interval(mins => LEAST(60, CAST(power(2, GREATEST(outbox.attempts, 1)) AS integer)))
      END,
      lease_token = NULL,
      locked_at = NULL,
      locked_by = NULL,
      last_error = left(COALESCE(NULLIF(p_request->>'error', ''), 'unknown provider error'), 1000),
      updated_at = now()
  WHERE outbox.id = v_outbox_id
    AND outbox.lease_token = v_lease_token
    AND outbox.status = 'dispatching'
  RETURNING true, NULL::text, outbox.id::text, outbox.status, outbox.next_attempt_at
  INTO ok, error_code, outbox_id, status, next_attempt_at;

  IF NOT FOUND THEN error_code := 'lease_mismatch'; END IF;
  RETURN NEXT;
END;
$$;

CREATE OR REPLACE FUNCTION public.sevenday_claim_production_job(p_request jsonb DEFAULT '{}'::jsonb)
RETURNS TABLE (
  production_job_id text,
  lease_token text,
  lead_id text,
  onboarding_submission_id text,
  production_context jsonb,
  attempts integer,
  lease_expires_at timestamptz
)
LANGUAGE plpgsql
AS $$
DECLARE
  v_worker_id text := left(COALESCE(NULLIF(p_request->>'worker_id', ''), 'n8n-production-worker'), 100);
BEGIN
  UPDATE public.sevenday_production_jobs AS jobs
  SET status = 'dead_letter',
      lease_token = NULL,
      locked_at = NULL,
      locked_by = NULL,
      last_error = COALESCE(jobs.last_error, 'Production lease expired after maximum attempts'),
      updated_at = now()
  WHERE jobs.attempts >= 5
    AND (
      jobs.status = 'queued'
      OR (
        jobs.status = 'processing'
        AND COALESCE(jobs.locked_at, jobs.updated_at) < now() - interval '30 minutes'
      )
    );

  RETURN QUERY
  WITH candidate AS (
    SELECT pending.id
    FROM public.sevenday_production_jobs AS pending
    WHERE pending.attempts < 5
      AND (
        pending.status = 'queued'
        OR (
          pending.status = 'processing'
          AND COALESCE(pending.locked_at, pending.updated_at) < now() - interval '30 minutes'
        )
      )
    ORDER BY pending.created_at, pending.id
    FOR UPDATE SKIP LOCKED
    LIMIT 1
  )
  UPDATE public.sevenday_production_jobs AS claimed
  SET status = 'processing',
      attempts = claimed.attempts + 1,
      lease_token = public.gen_random_uuid(),
      locked_at = now(),
      locked_by = v_worker_id,
      started_at = COALESCE(claimed.started_at, now()),
      updated_at = now()
  FROM candidate
  WHERE claimed.id = candidate.id
  RETURNING
    claimed.id::text,
    claimed.lease_token::text,
    claimed.lead_id::text,
    claimed.onboarding_submission_id::text,
    claimed.production_context,
    claimed.attempts,
    claimed.locked_at + interval '30 minutes';
END;
$$;

CREATE OR REPLACE FUNCTION public.sevenday_store_production_handoff(p_request jsonb)
RETURNS TABLE (ok boolean, error_code text, production_job_id text, lead_id text, status text)
LANGUAGE plpgsql
AS $$
DECLARE
  v_job_id uuid := public.sevenday_try_uuid(p_request->>'production_job_id');
  v_lease_token uuid := public.sevenday_try_uuid(p_request->>'lease_token');
BEGIN
  ok := false;
  error_code := 'invalid_claim';
  production_job_id := p_request->>'production_job_id';
  lead_id := NULL;
  status := NULL;

  IF v_job_id IS NULL OR v_lease_token IS NULL
     OR jsonb_typeof(p_request->'handoff') IS DISTINCT FROM 'object' THEN
    RETURN NEXT; RETURN;
  END IF;

  UPDATE public.sevenday_production_jobs AS jobs
  SET status = 'ready_for_builder',
      handoff = p_request->'handoff',
      lease_token = NULL,
      locked_at = NULL,
      locked_by = NULL,
      last_error = NULL,
      updated_at = now()
  WHERE jobs.id = v_job_id
    AND jobs.lease_token = v_lease_token
    AND jobs.status = 'processing'
  RETURNING true, NULL::text, jobs.id::text, jobs.lead_id::text, jobs.status
  INTO ok, error_code, production_job_id, lead_id, status;

  IF NOT FOUND THEN error_code := 'lease_mismatch'; END IF;
  RETURN NEXT;
END;
$$;

CREATE OR REPLACE FUNCTION public.sevenday_mark_production_failed(p_request jsonb)
RETURNS TABLE (
  ok boolean,
  error_code text,
  production_job_id text,
  status text
)
LANGUAGE plpgsql
AS $$
DECLARE
  v_job_id uuid := public.sevenday_try_uuid(p_request->>'production_job_id');
  v_lease_token uuid := public.sevenday_try_uuid(p_request->>'lease_token');
BEGIN
  ok := false;
  error_code := 'invalid_claim';
  production_job_id := p_request->>'production_job_id';
  status := NULL;

  IF v_job_id IS NULL OR v_lease_token IS NULL THEN RETURN NEXT; RETURN; END IF;

  UPDATE public.sevenday_production_jobs AS jobs
  SET status = CASE WHEN jobs.attempts >= 5 THEN 'dead_letter' ELSE 'queued' END,
      lease_token = NULL,
      locked_at = NULL,
      locked_by = NULL,
      last_error = left(COALESCE(NULLIF(p_request->>'error', ''), 'unknown production error'), 1000),
      updated_at = now()
  WHERE jobs.id = v_job_id
    AND jobs.lease_token = v_lease_token
    AND jobs.status = 'processing'
  RETURNING true, NULL::text, jobs.id::text, jobs.status
  INTO ok, error_code, production_job_id, status;

  IF NOT FOUND THEN error_code := 'lease_mismatch'; END IF;
  RETURN NEXT;
END;
$$;

COMMENT ON TABLE sevenday_private.token_keys IS
  'Private HMAC keys. Never expose this table or its values to n8n execution output.';
COMMENT ON COLUMN public.sevenday_leads.onboarding_token_hash IS
  'SHA-256 of the deterministic opaque onboarding token; the raw token is never persisted.';
COMMENT ON TABLE public.sevenday_notification_outbox IS
  'Durable at-least-once delivery queue. Use outbox id as provider idempotency key when supported.';
COMMENT ON TABLE public.sevenday_production_jobs IS
  'Durable V1 production queue; ready_for_builder means handoff prepared, not site deployed.';

-- PostgreSQL grants EXECUTE on new functions to PUBLIC by default. Keep these
-- functions callable only by the role that installs this migration (the same
-- role the n8n Postgres credential must use).
DO $acl$
DECLARE
  v_function record;
BEGIN
  FOR v_function IN
    SELECT procedures.oid::regprocedure AS signature
    FROM pg_proc AS procedures
    JOIN pg_namespace AS namespaces ON namespaces.oid = procedures.pronamespace
    WHERE (
      namespaces.nspname = 'public'
      AND strpos(procedures.proname, 'sevenday_') = 1
    ) OR (
      namespaces.nspname = 'sevenday_private'
      AND procedures.proname = 'make_onboarding_token'
    )
  LOOP
    EXECUTE format('REVOKE ALL ON FUNCTION %s FROM PUBLIC', v_function.signature);
    EXECUTE format('GRANT EXECUTE ON FUNCTION %s TO %I', v_function.signature, current_user);
  END LOOP;
END;
$acl$;

COMMIT;
