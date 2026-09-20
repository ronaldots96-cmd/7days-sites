SELECT result.*, result.error_code AS error
FROM public.sevenday_ingest_onboarding($1::jsonb) AS result;
