WITH next_job AS (
  SELECT job.id
  FROM public.sevenday_production_jobs AS job
  WHERE
    job.status = 'queued'
    OR (job.status = 'processing' AND job.updated_at < now() - interval '30 minutes')
  ORDER BY job.created_at
  FOR UPDATE SKIP LOCKED
  LIMIT 1
),
claimed AS (
  UPDATE public.sevenday_production_jobs AS job
  SET
    status = 'processing',
    attempts = job.attempts + 1,
    started_at = COALESCE(job.started_at, now()),
    updated_at = now()
  FROM next_job
  WHERE job.id = next_job.id
  RETURNING job.id, job.lead_id, job.onboarding_submission_id, job.production_context, job.attempts
)
SELECT
  claimed.id::text AS production_job_id,
  claimed.lead_id::text AS lead_id,
  claimed.onboarding_submission_id,
  claimed.production_context,
  claimed.attempts
FROM claimed;
