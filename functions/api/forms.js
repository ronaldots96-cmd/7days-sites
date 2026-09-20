const MAX_BODY_BYTES = 64 * 1024;
const ALLOWED_EVENTS = new Set([
  "lead_intake.submitted",
  "client_onboarding.submitted",
]);

function jsonResponse(body, status = 200, extraHeaders = {}) {
  return new Response(JSON.stringify(body), {
    status,
    headers: {
      "Content-Type": "application/json; charset=utf-8",
      "Cache-Control": "no-store",
      "X-Content-Type-Options": "nosniff",
      ...extraHeaders,
    },
  });
}

function isSameOrigin(request) {
  const origin = request.headers.get("Origin");
  if (!origin) return true;
  try {
    return new URL(origin).origin === new URL(request.url).origin;
  } catch {
    return false;
  }
}

function isBoundedString(value, minLength, maxLength) {
  return (
    typeof value === "string" &&
    value.length >= minLength &&
    value.length <= maxLength
  );
}

function safeOnboardingUrl(value, requestUrl) {
  if (typeof value !== "string" || !value.trim()) return null;
  try {
    const requestOrigin = new URL(requestUrl).origin;
    const target = new URL(value.trim(), requestOrigin);
    if (target.origin !== requestOrigin) return null;
    if (target.pathname !== "/briefing" && target.pathname !== "/briefing/") return null;
    return `${target.pathname}${target.search}${target.hash}`;
  } catch {
    return null;
  }
}

export async function onRequestOptions() {
  return new Response(null, {
    status: 204,
    headers: {
      Allow: "POST, OPTIONS",
      "Cache-Control": "no-store",
    },
  });
}

export async function onRequestPost({ request, env }) {
  if (!isSameOrigin(request)) {
    return jsonResponse({ ok: false, error: "origin_not_allowed" }, 403);
  }

  const contentType = request.headers.get("Content-Type") || "";
  if (!contentType.toLowerCase().startsWith("application/json")) {
    return jsonResponse({ ok: false, error: "json_required" }, 415);
  }

  const declaredLength = Number(request.headers.get("Content-Length") || 0);
  if (declaredLength > MAX_BODY_BYTES) {
    return jsonResponse({ ok: false, error: "payload_too_large" }, 413);
  }

  const rawBody = await request.text();
  if (!rawBody || new TextEncoder().encode(rawBody).byteLength > MAX_BODY_BYTES) {
    return jsonResponse({ ok: false, error: "payload_too_large" }, 413);
  }

  let payload;
  try {
    payload = JSON.parse(rawBody);
  } catch {
    return jsonResponse({ ok: false, error: "invalid_json" }, 400);
  }

  if (
    !payload ||
    !ALLOWED_EVENTS.has(payload.event) ||
    typeof payload.submission_id !== "string" ||
    payload.submission_id.length < 8 ||
    payload.submission_id.length > 100
  ) {
    return jsonResponse({ ok: false, error: "invalid_payload" }, 422);
  }

  const upstreamUrl = String(env.N8N_LEAD_WEBHOOK_URL || "").trim();
  if (!upstreamUrl.startsWith("https://")) {
    return jsonResponse({ ok: false, error: "upstream_not_configured" }, 503);
  }

  const upstreamSecret = String(env.N8N_WEBHOOK_SECRET || "").trim();
  if (upstreamSecret.length < 32) {
    return jsonResponse({ ok: false, error: "upstream_auth_not_configured" }, 503);
  }

  const controller = new AbortController();
  const timeout = setTimeout(() => controller.abort(), 15000);
  let upstreamResponse;
  try {
    upstreamResponse = await fetch(upstreamUrl, {
      method: "POST",
      headers: {
        Accept: "application/json",
        Authorization: `Bearer ${upstreamSecret}`,
        "Content-Type": "application/json",
        "Idempotency-Key": payload.submission_id,
        "X-Sevenday-Event": payload.event,
      },
      body: JSON.stringify(payload),
      signal: controller.signal,
    });
  } catch (error) {
    return jsonResponse(
      { ok: false, error: error.name === "AbortError" ? "upstream_timeout" : "upstream_unavailable" },
      502,
    );
  } finally {
    clearTimeout(timeout);
  }

  if (!upstreamResponse.ok) {
    return jsonResponse(
      { ok: false, error: "upstream_rejected", upstream_status: upstreamResponse.status },
      502,
    );
  }

  let upstreamData = {};
  try {
    upstreamData = await upstreamResponse.json();
  } catch {
    upstreamData = {};
  }
  if (!upstreamData || typeof upstreamData !== "object" || Array.isArray(upstreamData)) {
    upstreamData = {};
  }

  if (
    payload.event === "lead_intake.submitted" &&
    (!isBoundedString(upstreamData.lead_id, 8, 100) ||
      !isBoundedString(upstreamData.onboarding_token, 32, 2048))
  ) {
    return jsonResponse({ ok: false, error: "upstream_invalid_response" }, 502);
  }

  return jsonResponse({
    ok: true,
    submission_id: payload.submission_id,
    lead_id: upstreamData.lead_id || null,
    onboarding_token: upstreamData.onboarding_token || null,
    onboarding_url: safeOnboardingUrl(upstreamData.onboarding_url, request.url),
  });
}
