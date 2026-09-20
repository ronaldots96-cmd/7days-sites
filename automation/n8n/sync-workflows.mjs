import { buildWorkflowDefinitions, WORKFLOW_NAMES } from "./workflows.mjs";

const GATEWAY_ID = "lIjj6ZfGdTWSyjJa";
const PROJECT_ID = "r4ZVjZ0f7KqGnsdB";
const APPLY = process.argv.includes("--apply");

function validateWorkflow(key, workflow) {
  if (!workflow?.name || !Array.isArray(workflow.nodes) || !workflow.connections || !workflow.settings) {
    throw new Error(`${key}: invalid workflow shape`);
  }

  const names = new Set();
  const ids = new Set();
  for (const node of workflow.nodes) {
    if (!node.id || ids.has(node.id)) throw new Error(`${key}: duplicate or missing node id ${node.id || ""}`);
    if (!node.name || names.has(node.name)) throw new Error(`${key}: duplicate or missing node name ${node.name || ""}`);
    ids.add(node.id);
    names.add(node.name);
  }

  for (const [source, groups] of Object.entries(workflow.connections)) {
    if (!names.has(source)) throw new Error(`${key}: unknown connection source ${source}`);
    for (const outputs of Object.values(groups)) {
      for (const branch of outputs) {
        for (const target of branch || []) {
          if (!names.has(target.node)) throw new Error(`${key}: unknown connection target ${target.node}`);
        }
      }
    }
  }

  const serialized = JSON.stringify(workflow);
  if (/eyJ[a-zA-Z0-9_-]{20,}\.[a-zA-Z0-9_-]{20,}\.[a-zA-Z0-9_-]{20,}/.test(serialized)) {
    throw new Error(`${key}: a JWT-like secret was found in the definition`);
  }
  if (/Bearer\s+[A-Za-z0-9_-]{24,}/.test(serialized)) {
    throw new Error(`${key}: a bearer secret was found in the definition`);
  }

  if (key === "gateway") {
    const webhook = workflow.nodes.find((node) => node.type === "n8n-nodes-base.webhook");
    if (!webhook) throw new Error("gateway: webhook node missing");
    if (webhook.id !== "34b1e87b-b56d-4cb8-8785-303be9012b9d") throw new Error("gateway: webhook node id changed");
    if (webhook.webhookId !== "a7e62049-f7ad-4a1a-bf13-684dc2797c48") throw new Error("gateway: webhookId changed");
    if (webhook.parameters?.path !== "7days-leadform") throw new Error("gateway: webhook path changed");
    if (webhook.parameters?.authentication !== "headerAuth") throw new Error("gateway: Header Auth is not enforced");
    if (webhook.credentials) throw new Error("gateway: credential must be attached manually; never embed it here");
  }
}

function apiBody(workflow) {
  return {
    name: workflow.name,
    nodes: workflow.nodes,
    connections: workflow.connections,
    settings: workflow.settings,
  };
}

function projectIdOf(workflow) {
  return workflow.projectId
    || workflow.homeProject?.id
    || workflow.shared?.find((share) => share?.projectId)?.projectId
    || workflow.shared?.find((share) => share?.project?.id)?.project?.id
    || null;
}

function assertSafeToUpdate(workflow, expectedName, allowTransfer = false) {
  if (!workflow) throw new Error(`${expectedName}: workflow not found`);
  if (workflow.active === true) throw new Error(`${expectedName}: workflow is active; refusing to modify a live workflow`);
  if (workflow.isArchived === true) throw new Error(`${expectedName}: workflow is archived`);
  if (workflow.name !== expectedName) throw new Error(`${expectedName}: id/name mismatch (${workflow.name})`);
  const projectId = projectIdOf(workflow);
  if (!allowTransfer && projectId && projectId !== PROJECT_ID) {
    throw new Error(`${expectedName}: workflow belongs to another project (${projectId})`);
  }
}

async function main() {
  const definitions = buildWorkflowDefinitions();
  for (const [key, workflow] of Object.entries(definitions)) validateWorkflow(key, workflow);

  if (!APPLY) {
    process.stdout.write(`${JSON.stringify({
      ok: true,
      mode: "validate-only",
      workflows: Object.values(definitions).map((workflow) => ({
        name: workflow.name,
        nodes: workflow.nodes.length,
      })),
      next: "Set N8N_API_KEY in the process environment and run with --apply to sync drafts.",
    }, null, 2)}\n`);
    return;
  }

  const apiKey = String(process.env.N8N_API_KEY || "").trim();
  if (!apiKey) throw new Error("N8N_API_KEY is required with --apply");
  const baseUrl = String(process.env.N8N_BASE_URL || "https://n8n.v4lisboatech.com.br/api/v1")
    .trim()
    .replace(/\/+$/, "");
  if (!baseUrl.startsWith("https://")) throw new Error("N8N_BASE_URL must use HTTPS");

  async function request(path, options = {}) {
    const controller = new AbortController();
    const timeout = setTimeout(() => controller.abort(), 20_000);
    try {
      const response = await fetch(`${baseUrl}${path}`, {
        ...options,
        signal: controller.signal,
        headers: {
          Accept: "application/json",
          "Content-Type": "application/json",
          "X-N8N-API-KEY": apiKey,
          ...(options.headers || {}),
        },
      });
      const text = await response.text();
      let data = null;
      if (text) {
        try { data = JSON.parse(text); } catch { data = { message: text.slice(0, 600) }; }
      }
      if (!response.ok) {
        const message = data?.message || data?.error || `HTTP ${response.status}`;
        throw new Error(`${options.method || "GET"} ${path}: ${message}`);
      }
      return data;
    } finally {
      clearTimeout(timeout);
    }
  }

  async function listAllWorkflows() {
    const rows = [];
    let cursor = null;
    do {
      const query = new URLSearchParams({ limit: "100" });
      if (cursor) query.set("cursor", cursor);
      const page = await request(`/workflows?${query}`);
      rows.push(...(page?.data || []));
      cursor = page?.nextCursor || null;
    } while (cursor);
    return rows;
  }

  const results = [];

  const currentGateway = await request(`/workflows/${GATEWAY_ID}`);
  assertSafeToUpdate(currentGateway, WORKFLOW_NAMES.gateway);
  await request(`/workflows/${GATEWAY_ID}`, {
    method: "PUT",
    body: JSON.stringify(apiBody(definitions.gateway)),
  });
  const verifiedGateway = await request(`/workflows/${GATEWAY_ID}`);
  if (verifiedGateway.active === true) throw new Error("gateway unexpectedly active after update");
  results.push({ key: "gateway", id: GATEWAY_ID, name: verifiedGateway.name, active: Boolean(verifiedGateway.active), action: "updated" });

  const existing = await listAllWorkflows();
  for (const key of ["setup", "communications", "production"]) {
    const definition = definitions[key];
    const matches = existing.filter((workflow) => workflow.name === definition.name);
    if (matches.length > 1) throw new Error(`${definition.name}: multiple workflows have this exact name`);

    let saved;
    let action;
    if (matches.length === 1) {
      const current = await request(`/workflows/${matches[0].id}`);
      assertSafeToUpdate(current, definition.name, true);
      const currentProjectId = projectIdOf(current);
      if (currentProjectId && currentProjectId !== PROJECT_ID) {
        await request(`/workflows/${current.id}/transfer`, {
          method: "PUT",
          body: JSON.stringify({ destinationProjectId: PROJECT_ID }),
        });
      }
      saved = await request(`/workflows/${current.id}`, {
        method: "PUT",
        body: JSON.stringify(apiBody(definition)),
      });
      action = "updated";
    } else {
      saved = await request("/workflows", {
        method: "POST",
        body: JSON.stringify(apiBody(definition)),
      });
      const created = await request(`/workflows/${saved.id}`);
      const createdProjectId = projectIdOf(created);
      if (createdProjectId && createdProjectId !== PROJECT_ID) {
        await request(`/workflows/${saved.id}/transfer`, {
          method: "PUT",
          body: JSON.stringify({ destinationProjectId: PROJECT_ID }),
        });
      }
      action = "created";
    }

    const verified = await request(`/workflows/${saved.id}`);
    if (verified.active === true) throw new Error(`${definition.name}: unexpectedly active after sync`);
    const verifiedProjectId = projectIdOf(verified);
    if (verifiedProjectId && verifiedProjectId !== PROJECT_ID) {
      throw new Error(`${definition.name}: saved in unexpected project ${verifiedProjectId}`);
    }
    results.push({ key, id: verified.id, name: verified.name, active: Boolean(verified.active), action });
  }

  process.stdout.write(`${JSON.stringify({ ok: true, mode: "applied-as-drafts", project_id: PROJECT_ID, workflows: results }, null, 2)}\n`);
}

main().catch((error) => {
  process.stderr.write(`Workflow sync failed: ${error.message}\n`);
  process.exitCode = 1;
});
