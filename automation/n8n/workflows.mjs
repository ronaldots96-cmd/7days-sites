import { readFileSync } from "node:fs";
import { dirname, join } from "node:path";
import { fileURLToPath } from "node:url";

const HERE = dirname(fileURLToPath(import.meta.url));
const SQL_DIR = join(HERE, "sql");

const POSTGRES = {
  postgres: { id: "3MreXHC1Ukpf8Wps", name: "Lisboa.Co - Postgres" },
};
const GMAIL = {
  gmailOAuth2: { id: "wbYIDFuikY3gnQ31", name: "Lisboa.Co - Gmail" },
};

const readSql = (name) => readFileSync(join(SQL_DIR, name), "utf8").trim();

// n8n Postgres 2.6 treats queryReplacement as a comma-separated value. Passing
// JSON directly therefore corrupts normal payloads. Each workflow passes one
// Base64 string and the SQL decodes it back to JSONB.
const base64JsonSql = (name) =>
  readSql(name).replaceAll(
    "$1::jsonb",
    "convert_from(decode($1, 'base64'), 'UTF8')::jsonb",
  );

const settings = {
  executionOrder: "v1",
  saveDataErrorExecution: "none",
  saveDataSuccessExecution: "none",
  saveManualExecutions: false,
  saveExecutionProgress: false,
  timezone: "America/Sao_Paulo",
};

const sticky = (id, name, content, position, color = 5, size = [520, 240]) => ({
  id,
  name,
  type: "n8n-nodes-base.stickyNote",
  typeVersion: 1,
  position,
  parameters: { content, height: size[1], width: size[0], color },
});

const postgresNode = (id, name, query, position, extra = {}) => ({
  id,
  name,
  type: "n8n-nodes-base.postgres",
  typeVersion: 2.6,
  position,
  credentials: POSTGRES,
  parameters: {
    operation: "executeQuery",
    query,
    options: extra.options ?? {},
  },
  ...(extra.alwaysOutputData ? { alwaysOutputData: true } : {}),
});

const normalizeRequestCode = String.raw`
const input = $input.first()?.json ?? {};
const payload = input.body && typeof input.body === 'object' && !Array.isArray(input.body)
  ? input.body
  : input;
const sourceHeaders = input.headers && typeof input.headers === 'object' ? input.headers : {};
const headers = Object.fromEntries(
  Object.entries(sourceHeaders).map(([key, value]) => [String(key).toLowerCase(), value]),
);

let validationError = null;
if (!payload || typeof payload !== 'object' || Array.isArray(payload)) {
  validationError = 'invalid_payload';
} else if (!['lead_intake.submitted', 'client_onboarding.submitted'].includes(payload.event)) {
  validationError = 'invalid_event';
} else if (typeof payload.submission_id !== 'string' || payload.submission_id.length < 8 || payload.submission_id.length > 100) {
  validationError = 'invalid_submission_id';
} else if (payload.schema_version !== '3.0') {
  validationError = 'unsupported_schema_version';
} else if (headers['x-sevenday-event'] == null || String(headers['x-sevenday-event']).trim() === '') {
  validationError = 'missing_event_header';
} else if (headers['idempotency-key'] == null || String(headers['idempotency-key']).trim() === '') {
  validationError = 'missing_idempotency_key';
}

const envelope = {
  payload,
  header_event: headers['x-sevenday-event'] == null ? null : String(headers['x-sevenday-event']),
  idempotency_key: headers['idempotency-key'] == null ? null : String(headers['idempotency-key']),
  validation_error: validationError,
};

return [{
  json: {
    payload_base64: Buffer.from(JSON.stringify(envelope), 'utf8').toString('base64'),
  },
}];
`;

const formatGatewayResponseCode = String.raw`
const row = $input.first()?.json ?? {};
const ok = row.ok === true || row.ok === 'true';
let responseStatus = Number(row.http_status);
if (!Number.isInteger(responseStatus) || responseStatus < 200 || responseStatus > 499) {
  responseStatus = ok ? 200 : 500;
}

const body = ok
  ? {
      ok: true,
      status: row.status || 'accepted',
      lead_id: row.lead_id || null,
      submission_id: row.submission_id || null,
      onboarding_token: row.onboarding_token || null,
      onboarding_token_expires_at: row.onboarding_token_expires_at || null,
      production_job_id: row.production_job_id || null,
      production_status: row.production_status || null,
      is_new: row.is_new === true || row.is_new === 'true',
    }
  : {
      ok: false,
      error: row.error_code || row.error || 'request_rejected',
      submission_id: row.submission_id || null,
    };

return [{ json: { response_status: responseStatus, response_body: body } }];
`;

const prepareEmailClaimCode = String.raw`
const request = { limit: 1, worker_id: 'n8n-7days-email-v1' };
return [{ json: { payload_base64: Buffer.from(JSON.stringify(request), 'utf8').toString('base64') } }];
`;

const prepareEmailCode = String.raw`
return $input.all().map((item) => {
  const row = item.json;
  const tokenOk = row.token_ok === true || row.token_ok === 'true';
  if (!tokenOk || !row.onboarding_token) {
    const failure = {
      outbox_id: row.outbox_id,
      lease_token: row.lease_token,
      error: row.token_error || 'onboarding_token_unavailable',
    };
    return {
      json: {
        route: 'fail',
        payload_base64: Buffer.from(JSON.stringify(failure), 'utf8').toString('base64'),
      },
    };
  }

  const leadId = encodeURIComponent(String(row.lead_id));
  const token = encodeURIComponent(String(row.onboarding_token));
  const onboardingUrl = 'https://7days-sites.pages.dev/briefing?lead_id=' + leadId + '&token=' + token;
  const name = String(row.contact_name || '').trim();
  const greeting = name ? 'Hi ' + name + ',' : 'Hi,';
  const message = [
    greeting,
    '',
    'Welcome to 7days. We received your initial project details.',
    'The next step is to complete your onboarding briefing:',
    onboardingUrl,
    '',
    'This link is personal and expires. If you did not request this, you can ignore this email.',
    '',
    '7days Sites',
  ].join('\n');

  return {
    json: {
      route: 'send',
      outbox_id: row.outbox_id,
      lease_token: row.lease_token,
      send_to: row.recipient,
      subject: 'Welcome to 7days — complete your project briefing',
      message,
    },
  };
});
`;

const markEmailResultCode = String.raw`
const sources = $('Prepare Welcome Email').all();
return $input.all().map((item, index) => {
  const paired = Array.isArray(item.pairedItem) ? item.pairedItem[0] : item.pairedItem;
  const source = sources[paired?.item ?? index]?.json ?? {};
  const provider = item.json ?? {};
  const result = {
    outbox_id: source.outbox_id,
    lease_token: source.lease_token,
    provider_message_id: provider.id || provider.messageId || provider.threadId || null,
  };
  return { json: { payload_base64: Buffer.from(JSON.stringify(result), 'utf8').toString('base64') } };
});
`;

const markEmailFailureCode = String.raw`
const sources = $('Prepare Welcome Email').all();
return $input.all().map((item, index) => {
  const paired = Array.isArray(item.pairedItem) ? item.pairedItem[0] : item.pairedItem;
  const source = sources[paired?.item ?? index]?.json ?? {};
  const provider = item.json ?? {};
  const failure = {
    outbox_id: source.outbox_id,
    lease_token: source.lease_token,
    error: String(provider.error?.message || provider.message || 'gmail_send_failed').slice(0, 1000),
  };
  return { json: { payload_base64: Buffer.from(JSON.stringify(failure), 'utf8').toString('base64') } };
});
`;

const prepareProductionClaimCode = String.raw`
const request = { worker_id: 'n8n-7days-production-handoff-v1' };
return [{ json: { payload_base64: Buffer.from(JSON.stringify(request), 'utf8').toString('base64') } }];
`;

const buildHandoffCode = String.raw`
function sortObject(value) {
  if (Array.isArray(value)) return value.map(sortObject);
  if (!value || typeof value !== 'object') return value;
  return Object.fromEntries(Object.keys(value).sort().map((key) => [key, sortObject(value[key])]));
}

return $input.all().map((item) => {
  const row = item.json;
  const handoff = {
    handoff_version: '1.0',
    state: 'ready_for_builder',
    production_job_id: row.production_job_id,
    lead_id: row.lead_id,
    onboarding_submission_id: row.onboarding_submission_id,
    target: 'v1_site_production',
    production_context: sortObject(row.production_context || {}),
    next_step: 'connect_builder_and_human_approval_gate',
  };
  const request = {
    production_job_id: row.production_job_id,
    lease_token: row.lease_token,
    handoff,
  };
  return [{
    json: {
      payload_base64: Buffer.from(JSON.stringify(request), 'utf8').toString('base64'),
    },
  }][0];
});
`;

export function buildWorkflowDefinitions() {
  const gateway = {
    name: "7days",
    settings: { ...settings },
    nodes: [
      {
        id: "34b1e87b-b56d-4cb8-8785-303be9012b9d",
        name: "7days Lead + Onboarding Webhook",
        type: "n8n-nodes-base.webhook",
        typeVersion: 2.1,
        position: [-620, 100],
        webhookId: "a7e62049-f7ad-4a1a-bf13-684dc2797c48",
        parameters: {
          httpMethod: "POST",
          path: "7days-leadform",
          authentication: "headerAuth",
          responseMode: "responseNode",
          options: {},
        },
      },
      {
        id: "b478f45a-bc75-4985-9916-71919f70ea01",
        name: "Normalize Request",
        type: "n8n-nodes-base.code",
        typeVersion: 2,
        position: [-370, 100],
        parameters: { mode: "runOnceForAllItems", jsCode: normalizeRequestCode },
      },
      postgresNode(
        "264f8a37-a21a-4026-b217-acde7c5fb202",
        "Persist Request Atomically",
        base64JsonSql("ingest-request.sql"),
        [-100, 100],
        { options: { queryReplacement: "={{ $json.payload_base64 }}" }, alwaysOutputData: true },
      ),
      {
        id: "047f75e7-1f46-4659-b13f-00fc1aa3f303",
        name: "Format API Response",
        type: "n8n-nodes-base.code",
        typeVersion: 2,
        position: [180, 100],
        parameters: { mode: "runOnceForAllItems", jsCode: formatGatewayResponseCode },
      },
      {
        id: "55f2dfd8-47d8-4986-b65f-bf7c74831404",
        name: "Respond to Website",
        type: "n8n-nodes-base.respondToWebhook",
        typeVersion: 1.5,
        position: [450, 100],
        parameters: {
          respondWith: "json",
          responseBody: "={{ $json.response_body }}",
          options: { responseCode: "={{ $json.response_status }}" },
        },
      },
      sticky(
        "81bf0bec-529d-48b1-8830-a22b90ad1505",
        "BLOCKER — attach Header Auth credential",
        "## Required before publishing\n1. Review and run `7days — Setup PostgreSQL` once.\n2. Create an **HTTP Header Auth** credential named `7days - Webhook Auth` with header `Authorization` and value `Bearer <secret>`, then attach it here.\n3. Configure only the raw `<secret>` (without the `Bearer ` prefix) as the encrypted Cloudflare secret `N8N_WEBHOOK_SECRET`; the Pages Function adds the prefix.\n\nThis draft intentionally contains no auth credential or secret and must remain unpublished until all three steps are complete.",
        [-690, -260],
        4,
        [650, 260],
      ),
    ],
    connections: {
      "7days Lead + Onboarding Webhook": { main: [[{ node: "Normalize Request", type: "main", index: 0 }]] },
      "Normalize Request": { main: [[{ node: "Persist Request Atomically", type: "main", index: 0 }]] },
      "Persist Request Atomically": { main: [[{ node: "Format API Response", type: "main", index: 0 }]] },
      "Format API Response": { main: [[{ node: "Respond to Website", type: "main", index: 0 }]] },
    },
  };

  const setup = {
    name: "7days — Setup PostgreSQL",
    settings: { ...settings },
    nodes: [
      {
        id: "37465a0b-3af4-4c72-bbdb-a230857f2101",
        name: "Run Setup Manually",
        type: "n8n-nodes-base.manualTrigger",
        typeVersion: 1,
        position: [-260, 80],
        parameters: {},
      },
      postgresNode(
        "64f604c7-8ac8-4a61-ab9a-972ef4acc102",
        "Install 7days Schema and Functions",
        readSql("schema.sql"),
        [20, 80],
      ),
      sticky(
        "58869d64-27b1-4cd5-9796-254b7a2e2103",
        "Manual database migration",
        "## Review, then run once manually\nThis node installs/updates the 7days tables, private token key, functions and grants. Run it with the same PostgreSQL credential used by the other workflows. It is never executed by the sync script.",
        [-360, -230],
        5,
        [620, 230],
      ),
    ],
    connections: {
      "Run Setup Manually": { main: [[{ node: "Install 7days Schema and Functions", type: "main", index: 0 }]] },
    },
  };

  const communications = {
    name: "7days — Communications Worker",
    settings: { ...settings },
    nodes: [
      {
        id: "bd73a2bb-ea5b-44ac-9a63-dc321b3f3101",
        name: "Every Minute",
        type: "n8n-nodes-base.scheduleTrigger",
        typeVersion: 1.2,
        position: [-690, 100],
        parameters: { rule: { interval: [{ field: "minutes", minutesInterval: 1 }] } },
      },
      {
        id: "3f3a60ae-4dcb-4283-aa00-0df93adf3102",
        name: "Prepare Email Claim",
        type: "n8n-nodes-base.code",
        typeVersion: 2,
        position: [-470, 100],
        parameters: { mode: "runOnceForAllItems", jsCode: prepareEmailClaimCode },
      },
      postgresNode(
        "fdcc758e-b1b8-4a0e-ac26-077b13e83103",
        "Claim Pending Emails",
        base64JsonSql("claim-email.sql"),
        [-230, 100],
        { options: { queryReplacement: "={{ $json.payload_base64 }}" } },
      ),
      {
        id: "17a1250d-e4b2-4a2d-8e65-2832c72a3104",
        name: "Prepare Welcome Email",
        type: "n8n-nodes-base.code",
        typeVersion: 2,
        position: [20, 100],
        parameters: { mode: "runOnceForAllItems", jsCode: prepareEmailCode },
      },
      {
        id: "4dd43bf0-f2a3-4916-8217-9a896cbb3105",
        name: "Route Email",
        type: "n8n-nodes-base.switch",
        typeVersion: 3.2,
        position: [260, 100],
        parameters: {
          rules: {
            values: [
              {
                conditions: {
                  options: { caseSensitive: true, leftValue: "", typeValidation: "strict", version: 2 },
                  conditions: [{ leftValue: "={{ $json.route }}", rightValue: "send", operator: { type: "string", operation: "equals" } }],
                  combinator: "and",
                },
                renameOutput: true,
                outputKey: "send",
              },
              {
                conditions: {
                  options: { caseSensitive: true, leftValue: "", typeValidation: "strict", version: 2 },
                  conditions: [{ leftValue: "={{ $json.route }}", rightValue: "fail", operator: { type: "string", operation: "equals" } }],
                  combinator: "and",
                },
                renameOutput: true,
                outputKey: "fail",
              },
            ],
          },
          options: {},
        },
      },
      {
        id: "97831a14-8a35-43ea-babc-e49deee33106",
        name: "Send Welcome Email",
        type: "n8n-nodes-base.gmail",
        typeVersion: 2.2,
        position: [520, 20],
        credentials: GMAIL,
        onError: "continueErrorOutput",
        parameters: {
          resource: "message",
          operation: "send",
          sendTo: "={{ $json.send_to }}",
          subject: "={{ $json.subject }}",
          emailType: "text",
          message: "={{ $json.message }}",
          options: { appendAttribution: false },
        },
      },
      {
        id: "46672442-82dc-418d-a627-aae992af3107",
        name: "Prepare Sent Ack",
        type: "n8n-nodes-base.code",
        typeVersion: 2,
        position: [770, -50],
        parameters: { mode: "runOnceForAllItems", jsCode: markEmailResultCode },
      },
      postgresNode(
        "385c445c-63b4-418d-8f0a-85350e5b3108",
        "Mark Email Sent",
        base64JsonSql("mark-outbox-sent.sql"),
        [1020, -50],
        { options: { queryReplacement: "={{ $json.payload_base64 }}" } },
      ),
      {
        id: "48d69a92-5f08-4de1-aec7-0c91e9a93109",
        name: "Prepare Send Failure",
        type: "n8n-nodes-base.code",
        typeVersion: 2,
        position: [770, 120],
        parameters: { mode: "runOnceForAllItems", jsCode: markEmailFailureCode },
      },
      postgresNode(
        "9173095d-8480-42df-882b-1a7684c83110",
        "Retry or Dead Letter Email",
        base64JsonSql("mark-outbox-failed.sql"),
        [1020, 120],
        { options: { queryReplacement: "={{ $json.payload_base64 }}" } },
      ),
      postgresNode(
        "55335c77-fdf8-4999-a586-d08fb2c23111",
        "Release Missing Token",
        base64JsonSql("mark-outbox-failed.sql"),
        [520, 200],
        { options: { queryReplacement: "={{ $json.payload_base64 }}" } },
      ),
      sticky(
        "13309784-17e7-48e1-833d-dfe3955d3112",
        "SMS intentionally blocked",
        "## SMS is not active\nLead ingestion records SMS as `blocked_config`. Do not add a sender until a provider, sender identity, supported countries, explicit SMS consent wording, opt-out handling and a test allowlist are approved. `phone_whatsapp` alone is not SMS consent.",
        [-650, -280],
        4,
        [620, 240],
      ),
    ],
    connections: {
      "Every Minute": { main: [[{ node: "Prepare Email Claim", type: "main", index: 0 }]] },
      "Prepare Email Claim": { main: [[{ node: "Claim Pending Emails", type: "main", index: 0 }]] },
      "Claim Pending Emails": { main: [[{ node: "Prepare Welcome Email", type: "main", index: 0 }]] },
      "Prepare Welcome Email": { main: [[{ node: "Route Email", type: "main", index: 0 }]] },
      "Route Email": {
        main: [
          [{ node: "Send Welcome Email", type: "main", index: 0 }],
          [{ node: "Release Missing Token", type: "main", index: 0 }],
        ],
      },
      "Send Welcome Email": {
        main: [
          [{ node: "Prepare Sent Ack", type: "main", index: 0 }],
          [{ node: "Prepare Send Failure", type: "main", index: 0 }],
        ],
      },
      "Prepare Sent Ack": { main: [[{ node: "Mark Email Sent", type: "main", index: 0 }]] },
      "Prepare Send Failure": { main: [[{ node: "Retry or Dead Letter Email", type: "main", index: 0 }]] },
    },
  };

  const production = {
    name: "7days — V1 Production Handoff",
    settings: { ...settings },
    nodes: [
      {
        id: "e91775d2-7e13-443e-8e4c-580a9d764101",
        name: "Every Minute",
        type: "n8n-nodes-base.scheduleTrigger",
        typeVersion: 1.2,
        position: [-520, 100],
        parameters: { rule: { interval: [{ field: "minutes", minutesInterval: 1 }] } },
      },
      {
        id: "4f40ec46-6cad-484f-a52a-797c3d6d4102",
        name: "Prepare Production Claim",
        type: "n8n-nodes-base.code",
        typeVersion: 2,
        position: [-290, 100],
        parameters: { mode: "runOnceForAllItems", jsCode: prepareProductionClaimCode },
      },
      postgresNode(
        "2c06812b-c06e-454c-827b-c7d0133c4103",
        "Claim Production Job",
        base64JsonSql("claim-production-job.sql"),
        [-40, 100],
        { options: { queryReplacement: "={{ $json.payload_base64 }}" } },
      ),
      {
        id: "960b00e7-518a-4b97-9f3d-181413a84104",
        name: "Build Deterministic Handoff",
        type: "n8n-nodes-base.code",
        typeVersion: 2,
        position: [210, 100],
        parameters: { mode: "runOnceForAllItems", jsCode: buildHandoffCode },
      },
      postgresNode(
        "cb704ff6-f817-4ca0-a671-81a233524105",
        "Store Ready for Builder Handoff",
        base64JsonSql("store-production-handoff.sql"),
        [480, 100],
        { options: { queryReplacement: "={{ $json.payload_base64 }}" } },
      ),
      sticky(
        "8b61cd67-a01d-491c-a8ff-c575a04d4106",
        "Builder connector pending",
        "## Honest boundary\nThis worker creates a deterministic, auditable `ready_for_builder` handoff only. It does **not** claim that a website was generated or deployed. Connect the approved repository/template, build runner, Cloudflare project and human approval gate in a later workflow.",
        [-420, -250],
        5,
        [650, 240],
      ),
    ],
    connections: {
      "Every Minute": { main: [[{ node: "Prepare Production Claim", type: "main", index: 0 }]] },
      "Prepare Production Claim": { main: [[{ node: "Claim Production Job", type: "main", index: 0 }]] },
      "Claim Production Job": { main: [[{ node: "Build Deterministic Handoff", type: "main", index: 0 }]] },
      "Build Deterministic Handoff": { main: [[{ node: "Store Ready for Builder Handoff", type: "main", index: 0 }]] },
    },
  };

  return { gateway, setup, communications, production };
}

export const WORKFLOW_NAMES = Object.freeze({
  gateway: "7days",
  setup: "7days — Setup PostgreSQL",
  communications: "7days — Communications Worker",
  production: "7days — V1 Production Handoff",
});
