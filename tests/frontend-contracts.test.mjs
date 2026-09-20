import assert from "node:assert/strict";
import { test } from "node:test";
import { readFile } from "node:fs/promises";
import vm from "node:vm";

const root = new URL("../", import.meta.url);

test("briefing removes the onboarding token before GTM and tracking load", async () => {
  const template = await readFile(new URL("templates/briefing.html", root), "utf8");
  const tokenCapture = template.indexOf("const tokenFromUrl = url.searchParams.get('token')");
  const tokenRemoval = template.indexOf("url.searchParams.delete('token')");
  const replaceState = template.indexOf("history.replaceState", tokenRemoval);
  const gtm = template.indexOf("<!-- Google Tag Manager -->");
  const tracking = template.indexOf("tracking.js");

  assert.ok(tokenCapture > -1);
  assert.ok(tokenRemoval > tokenCapture);
  assert.ok(replaceState > tokenRemoval);
  assert.ok(gtm > replaceState);
  assert.ok(tracking > replaceState);
  assert.match(template, /<meta name="referrer" content="no-referrer">/);
});

test("the early briefing script preserves the token in-session and scrubs only it from the URL", async () => {
  const template = await readFile(new URL("templates/briefing.html", root), "utf8");
  const firstScript = template.match(/<script>\s*([\s\S]*?)\s*<\/script>/)?.[1];
  assert.ok(firstScript, "early token script was not found");

  const stored = new Map();
  let replacedWith = null;
  const window = {
    location: {
      href: "https://7days-sites.pages.dev/briefing?lead_id=lead-12345678&token=opaque-secret&utm_source=test#step",
    },
  };
  const context = {
    URL,
    window,
    sessionStorage: {
      getItem: key => stored.get(key) ?? null,
      setItem: (key, value) => stored.set(key, String(value)),
    },
    history: {
      replaceState: (_state, _title, value) => {
        replacedWith = value;
      },
    },
  };

  vm.runInNewContext(firstScript, context);

  assert.equal(window.__sevendayOnboardingToken, "opaque-secret");
  assert.equal(stored.get("sevenday_onboarding_token_v1:lead-12345678"), "opaque-secret");
  assert.equal(replacedWith, "/briefing?lead_id=lead-12345678&utm_source=test#step");
  assert.equal(replacedWith.includes("opaque-secret"), false);
});

test("tracking allowlists campaign parameters and never places lead/token query values in dataLayer", async () => {
  const source = await readFile(new URL("static/tracking.js", root), "utf8");
  const saved = new Map();
  const window = {
    location: {
      href: "https://7days-sites.pages.dev/briefing?lead_id=lead-12345678&token=opaque-secret&utm_source=qa&utm_campaign=contract",
      pathname: "/briefing",
    },
    dataLayer: [],
    crypto: { randomUUID: () => "event-test" },
  };
  const document = {
    referrer: "https://example.test/path?token=referrer-secret",
    title: "Project Onboarding",
    documentElement: { dataset: { pageName: "project_onboarding" } },
    addEventListener: () => {},
  };
  const localStorage = {
    getItem: key => saved.get(key) ?? null,
    setItem: (key, value) => saved.set(key, String(value)),
  };

  vm.runInNewContext(source, {
    window,
    document,
    localStorage,
    URL,
    URLSearchParams,
    Date,
    crypto: window.crypto,
  });

  assert.equal(window.dataLayer.length, 1);
  const serialized = JSON.stringify(window.dataLayer[0]);
  assert.equal(serialized.includes("opaque-secret"), false);
  assert.equal(serialized.includes("lead-12345678"), false);
  assert.equal(serialized.includes("referrer-secret"), false);
  assert.match(window.dataLayer[0].page_location, /utm_source=qa/);
  assert.match(window.dataLayer[0].page_location, /utm_campaign=contract/);
});

test("both browser forms use the same-origin endpoint contract and expected event names", async () => {
  const [home, briefing] = await Promise.all([
    readFile(new URL("templates/index.html", root), "utf8"),
    readFile(new URL("templates/briefing.html", root), "utf8"),
  ]);

  assert.match(home, /event:\s*'lead_intake\.submitted'/);
  assert.match(briefing, /event:'client_onboarding\.submitted'/);
  assert.match(home, /credentials:\s*'omit'/);
  assert.match(briefing, /credentials:'omit'/);
  assert.match(home, /document\.documentElement\.dataset\.webhookUrl/);
  assert.match(briefing, /document\.documentElement\.dataset\.webhookUrl/);
});
