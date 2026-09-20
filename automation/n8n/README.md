# 7days n8n automation

This directory contains versioned SQL and four n8n workflow drafts:

- `7days`: authenticated ingestion gateway for lead intake and onboarding;
- `7days — Setup PostgreSQL`: manual database migration;
- `7days — Communications Worker`: durable welcome-email outbox worker;
- `7days — V1 Production Handoff`: deterministic handoff marked `ready_for_builder`.

Drafts provisioned in project `r4ZVjZ0f7KqGnsdB` on 2026-09-19:

- gateway: `lIjj6ZfGdTWSyjJa`;
- database setup: `Bgr5CfmCROGUe0xK`;
- communications: `SzOsyIr9OMq2u727`;
- production handoff: `spZQpCRNni9V3lPs`.

All four were verified as inactive after synchronization. The onboarding endpoint
is intentionally link-only: a direct `/briefing` submission without a valid
`lead_id` and token is rejected by PostgreSQL.

## Validate locally

```powershell
node automation/n8n/sync-workflows.mjs
```

Validation is local and performs no network calls. Remote writes only happen with
the explicit `--apply` flag.

## Sync as unpublished drafts

Set the temporary API key only in the current process environment; never put it
in this repository or command history. Then run:

```powershell
node automation/n8n/sync-workflows.mjs --apply
```

The synchronizer updates workflow `lIjj6ZfGdTWSyjJa`, preserving its webhook
node ID, webhook ID and `7days-leadform` path. It upserts the other workflows by
exact name and transfers them to project `r4ZVjZ0f7KqGnsdB` only when needed.
It refuses to modify an active or archived workflow and never publishes or
executes anything.

## Required manual steps

1. Review and manually run `7days — Setup PostgreSQL` once with the same
   PostgreSQL credential used by the workers.
2. Create an n8n HTTP Header Auth credential named `7days - Webhook Auth`:
   header `Authorization`, value `Bearer <strong random secret>`.
3. Attach it to the gateway Webhook node. Configure only the raw secret (without
   the `Bearer ` prefix) as encrypted Cloudflare `N8N_WEBHOOK_SECRET`; the Pages
   Function adds the prefix. Never commit it.
4. Confirm the Gmail sender/from identity and test only with an approved address.
5. Publish the gateway first. Activate the email worker only after a controlled
   end-to-end test.

SMS is deliberately not implemented. It remains `blocked_config` until the
provider, sender identity, supported countries, explicit SMS consent and opt-out
handling are defined. The production worker creates a handoff only; a builder,
repository, deployment destination and human approval gate are still required.

All arbitrary JSON parameters are Base64-encoded before entering the n8n
Postgres 2.6 node because its query-replacement field is comma-separated. SQL
decodes the single value back to JSONB. Workflow execution payload retention is
disabled to reduce PII/token exposure.
