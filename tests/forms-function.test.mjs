import assert from "node:assert/strict";
import { afterEach, before, test } from "node:test";
import { readFile } from "node:fs/promises";

let onRequestOptions;
let onRequestPost;
let originalFetch;

before(async () => {
  const source = await readFile(new URL("../functions/api/forms.js", import.meta.url), "utf8");
  const moduleUrl = `data:text/javascript;base64,${Buffer.from(source).toString("base64")}`;
  ({ onRequestOptions, onRequestPost } = await import(moduleUrl));
  originalFetch = globalThis.fetch;
});

afterEach(() => {
  globalThis.fetch = originalFetch;
});

const secret = "test-only-secret-with-at-least-32-characters";
const env = {
  N8N_LEAD_WEBHOOK_URL: "https://automation.example.test/webhook/7days-leadform",
  N8N_WEBHOOK_SECRET: secret,
};

function leadPayload(overrides = {}) {
  return {
    schema_version: "3.0",
    event: "lead_intake.submitted",
    submission_id: "submission-12345678",
    contact: { name: "Test lead", email: "lead@example.test" },
    ...overrides,
  };
}

function formRequest(payload, headers = {}) {
  return new Request("https://7days-sites.pages.dev/api/forms", {
    method: "POST",
    headers: {
      Accept: "application/json",
      "Content-Type": "application/json",
      Origin: "https://7days-sites.pages.dev",
      ...headers,
    },
    body: typeof payload === "string" ? payload : JSON.stringify(payload),
  });
}

async function body(response) {
  return response.json();
}

test("OPTIONS advertises only POST and OPTIONS without enabling cross-origin access", async () => {
  const response = await onRequestOptions();
  assert.equal(response.status, 204);
  assert.equal(response.headers.get("Allow"), "POST, OPTIONS");
  assert.equal(response.headers.get("Access-Control-Allow-Origin"), null);
});

test("rejects a cross-origin browser request before calling n8n", async () => {
  let called = false;
  globalThis.fetch = async () => {
    called = true;
    throw new Error("must not be called");
  };

  const response = await onRequestPost({
    request: formRequest(leadPayload(), { Origin: "https://attacker.example" }),
    env,
  });

  assert.equal(response.status, 403);
  assert.equal((await body(response)).error, "origin_not_allowed");
  assert.equal(called, false);
});

test("fails closed when the n8n bearer secret is absent or too short", async () => {
  let called = false;
  globalThis.fetch = async () => {
    called = true;
    throw new Error("must not be called");
  };

  for (const configuredSecret of [undefined, "too-short"]) {
    const response = await onRequestPost({
      request: formRequest(leadPayload()),
      env: { ...env, N8N_WEBHOOK_SECRET: configuredSecret },
    });
    assert.equal(response.status, 503);
    assert.equal((await body(response)).error, "upstream_auth_not_configured");
  }
  assert.equal(called, false);
});

test("forwards the event, idempotency key, bearer credential and unchanged JSON", async () => {
  const payload = leadPayload();
  let forwarded;
  globalThis.fetch = async (url, init) => {
    forwarded = { url, init };
    return new Response(JSON.stringify({
      lead_id: "lead-12345678",
      onboarding_token: "a".repeat(64),
      onboarding_url: "https://7days-sites.pages.dev/briefing?lead_id=lead-12345678&token=opaque",
    }), { status: 200, headers: { "Content-Type": "application/json" } });
  };

  const response = await onRequestPost({ request: formRequest(payload), env });
  const responseBody = await body(response);

  assert.equal(response.status, 200);
  assert.equal(forwarded.url, env.N8N_LEAD_WEBHOOK_URL);
  assert.equal(forwarded.init.headers.Authorization, `Bearer ${secret}`);
  assert.equal(forwarded.init.headers["Idempotency-Key"], payload.submission_id);
  assert.equal(forwarded.init.headers["X-Sevenday-Event"], payload.event);
  assert.deepEqual(JSON.parse(forwarded.init.body), payload);
  assert.equal(responseBody.lead_id, "lead-12345678");
  assert.equal(responseBody.onboarding_token, "a".repeat(64));
  assert.equal(
    responseBody.onboarding_url,
    "/briefing?lead_id=lead-12345678&token=opaque",
  );
  assert.equal(JSON.stringify(responseBody).includes(secret), false);
});

test("rejects a false-positive lead response that has no durable id or onboarding token", async () => {
  globalThis.fetch = async () => new Response(JSON.stringify({ ok: true }), {
    status: 200,
    headers: { "Content-Type": "application/json" },
  });

  const response = await onRequestPost({ request: formRequest(leadPayload()), env });
  assert.equal(response.status, 502);
  assert.equal((await body(response)).error, "upstream_invalid_response");
});

test("does not expose an external onboarding redirect returned by n8n", async () => {
  globalThis.fetch = async () => new Response(JSON.stringify({
    lead_id: "lead-12345678",
    onboarding_token: "b".repeat(64),
    onboarding_url: "https://attacker.example/briefing?token=stolen",
  }), { status: 200, headers: { "Content-Type": "application/json" } });

  const response = await onRequestPost({ request: formRequest(leadPayload()), env });
  assert.equal(response.status, 200);
  assert.equal((await body(response)).onboarding_url, null);
});

test("accepts a successful onboarding acknowledgement without returning lead credentials", async () => {
  globalThis.fetch = async () => new Response(null, { status: 204 });
  const payload = leadPayload({
    event: "client_onboarding.submitted",
    submission_id: "onboarding-12345678",
    parent_lead_id: "lead-12345678",
    onboarding_token: "c".repeat(64),
  });

  const response = await onRequestPost({ request: formRequest(payload), env });
  const responseBody = await body(response);
  assert.equal(response.status, 200);
  assert.equal(responseBody.ok, true);
  assert.equal(responseBody.submission_id, payload.submission_id);
  assert.equal(responseBody.lead_id, null);
  assert.equal(responseBody.onboarding_token, null);
});

test("maps upstream rejection and timeout to stable public errors", async () => {
  globalThis.fetch = async () => new Response("unauthorized", { status: 401 });
  let response = await onRequestPost({ request: formRequest(leadPayload()), env });
  assert.equal(response.status, 502);
  assert.deepEqual(await body(response), {
    ok: false,
    error: "upstream_rejected",
    upstream_status: 401,
  });

  globalThis.fetch = async () => {
    throw new DOMException("timed out", "AbortError");
  };
  response = await onRequestPost({ request: formRequest(leadPayload()), env });
  assert.equal(response.status, 502);
  assert.equal((await body(response)).error, "upstream_timeout");
});
