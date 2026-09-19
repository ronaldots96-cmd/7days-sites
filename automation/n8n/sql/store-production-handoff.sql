WITH input AS (
  SELECT $1::jsonb AS data
)
UPDATE public.sevenday_production_jobs AS job
SET
  status = 'ready_for_builder',
  handoff = input.data->'handoff',
  updated_at = now(),
  last_error = NULL
FROM input
WHERE job.id = (input.data->>'production_job_id')::uuid
RETURNING job.id::text AS production_job_id, job.lead_id::text AS lead_id, job.status;
