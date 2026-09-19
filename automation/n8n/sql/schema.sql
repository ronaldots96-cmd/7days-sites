CREATE TABLE IF NOT EXISTS public.sevenday_leads (
  id uuid PRIMARY KEY,
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
  onboarding_token_hash char(64) NOT NULL,
  onboarding_token_expires_at timestamptz NOT NULL,
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS sevenday_leads_email_idx
  ON public.sevenday_leads (lower(contact_email));
CREATE INDEX IF NOT EXISTS sevenday_leads_status_idx
  ON public.sevenday_leads (status, created_at);

CREATE TABLE IF NOT EXISTS public.sevenday_submissions (
  event text NOT NULL,
  submission_id varchar(100) NOT NULL,
  lead_id uuid REFERENCES public.sevenday_leads(id) ON DELETE SET NULL,
  schema_version text NOT NULL,
  received_at timestamptz NOT NULL DEFAULT now(),
  submitted_at timestamptz,
  raw_payload jsonb NOT NULL,
  PRIMARY KEY (event, submission_id)
);

CREATE INDEX IF NOT EXISTS sevenday_submissions_lead_idx
  ON public.sevenday_submissions (lead_id, received_at DESC);

CREATE TABLE IF NOT EXISTS public.sevenday_onboardings (
  submission_id varchar(100) PRIMARY KEY,
  lead_id uuid NOT NULL REFERENCES public.sevenday_leads(id) ON DELETE CASCADE,
  parent_submission_id varchar(100),
  schema_version text NOT NULL,
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

CREATE INDEX IF NOT EXISTS sevenday_onboardings_lead_idx
  ON public.sevenday_onboardings (lead_id, created_at DESC);

CREATE TABLE IF NOT EXISTS public.sevenday_notification_outbox (
  id uuid PRIMARY KEY,
  lead_id uuid NOT NULL REFERENCES public.sevenday_leads(id) ON DELETE CASCADE,
  submission_id varchar(100) NOT NULL,
  channel text NOT NULL,
  recipient text NOT NULL,
  template_version text NOT NULL,
  payload jsonb NOT NULL,
  status text NOT NULL DEFAULT 'pending',
  attempts integer NOT NULL DEFAULT 0,
  next_attempt_at timestamptz NOT NULL DEFAULT now(),
  provider_message_id text,
  last_error text,
  sent_at timestamptz,
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now(),
  UNIQUE (submission_id, channel, template_version)
);

CREATE INDEX IF NOT EXISTS sevenday_outbox_dispatch_idx
  ON public.sevenday_notification_outbox (status, channel, next_attempt_at);

CREATE TABLE IF NOT EXISTS public.sevenday_production_jobs (
  id uuid PRIMARY KEY,
  lead_id uuid NOT NULL REFERENCES public.sevenday_leads(id) ON DELETE CASCADE,
  onboarding_submission_id varchar(100) UNIQUE NOT NULL
    REFERENCES public.sevenday_onboardings(submission_id) ON DELETE CASCADE,
  status text NOT NULL DEFAULT 'queued',
  production_context jsonb NOT NULL,
  handoff jsonb,
  attempts integer NOT NULL DEFAULT 0,
  last_error text,
  created_at timestamptz NOT NULL DEFAULT now(),
  started_at timestamptz,
  updated_at timestamptz NOT NULL DEFAULT now(),
  completed_at timestamptz
);

CREATE INDEX IF NOT EXISTS sevenday_production_jobs_queue_idx
  ON public.sevenday_production_jobs (status, created_at);
