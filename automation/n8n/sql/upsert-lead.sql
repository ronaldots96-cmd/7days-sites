SELECT result.*, result.error_code AS error
FROM public.sevenday_ingest_lead($1::jsonb) AS result;
