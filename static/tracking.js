(function () {
  "use strict";

  var ATTRIBUTION_KEY = "sevenday_attribution_v1";
  var ATTRIBUTION_TTL = 90 * 24 * 60 * 60 * 1000;
  var TRACKED_PARAMS = [
    "utm_source",
    "utm_medium",
    "utm_campaign",
    "utm_content",
    "utm_term",
    "utm_id",
    "ref",
    "gclid",
    "dclid",
    "gbraid",
    "wbraid",
    "gad_source",
    "gad_campaignid",
    "srsltid",
    "fbclid",
    "msclkid",
    "ttclid",
    "twclid",
    "li_fat_id"
  ];

  window.dataLayer = window.dataLayer || [];

  function safeJSON(value, fallback) {
    try {
      return JSON.parse(value);
    } catch (error) {
      return fallback;
    }
  }

  function compact(object) {
    return Object.keys(object).reduce(function (result, key) {
      var value = object[key];
      if (value !== null && value !== undefined && value !== "") result[key] = value;
      return result;
    }, {});
  }

  function currentTouch() {
    var params = new URLSearchParams(window.location.search);
    var campaign = {};
    TRACKED_PARAMS.forEach(function (name) {
      campaign[name] = params.get(name);
    });

    return {
      captured_at: new Date().toISOString(),
      landing_page: safePageUrl(),
      path: window.location.pathname,
      referrer: safeReferrer(),
      campaign: compact(campaign)
    };
  }

  function safePageUrl() {
    var url = new URL(window.location.href);
    var safeParams = new URLSearchParams();
    TRACKED_PARAMS.forEach(function (name) {
      var value = url.searchParams.get(name);
      if (value) safeParams.set(name, value);
    });
    var query = safeParams.toString();
    return url.origin + url.pathname + (query ? "?" + query : "");
  }

  function safeReferrer() {
    if (!document.referrer) return null;
    try {
      var url = new URL(document.referrer);
      return url.origin + url.pathname;
    } catch (error) {
      return null;
    }
  }

  function readAttribution() {
    var saved = null;
    try {
      saved = safeJSON(localStorage.getItem(ATTRIBUTION_KEY) || "null", null);
    } catch (error) {
      return null;
    }
    if (!saved || !saved.saved_at || Date.now() - saved.saved_at > ATTRIBUTION_TTL) return null;
    return saved;
  }

  function captureAttribution() {
    var touch = currentTouch();
    var saved = readAttribution();
    var hasCampaign = Object.keys(touch.campaign).length > 0;
    var attribution = saved || {
      saved_at: Date.now(),
      first_touch: touch,
      latest_touch: touch
    };

    if (!saved || hasCampaign) {
      attribution.latest_touch = touch;
      attribution.saved_at = Date.now();
    }

    try {
      localStorage.setItem(ATTRIBUTION_KEY, JSON.stringify(attribution));
    } catch (error) {
      // Tracking must never block the experience when storage is unavailable.
    }
    return attribution;
  }

  window.sevendayGetAttribution = function () {
    return readAttribution() || captureAttribution();
  };

  window.sevendayTrack = function (eventName, payload) {
    var eventPayload = Object.assign({
      event: eventName,
      event_id: window.crypto && crypto.randomUUID ? crypto.randomUUID() : "event-" + Date.now(),
      page_name: document.documentElement.dataset.pageName || document.title,
      page_path: window.location.pathname,
      page_location: safePageUrl()
    }, payload || {});
    window.dataLayer.push(eventPayload);
    return eventPayload;
  };

  var attribution = captureAttribution();
  // GTM owns the actual page-view tag. This event only exposes page context so
  // a container can consume it without creating a duplicate automatic pageview.
  window.sevendayTrack("page_context_ready", {
    traffic_source: attribution,
    document_title: document.title
  });

  function safeDestination(value) {
    if (!value) return null;
    if (value.charAt(0) === "#") return value;
    if (/^(mailto|tel):/i.test(value)) return value.split(":", 1)[0].toLowerCase();
    try {
      var url = new URL(value, window.location.href);
      return url.origin + url.pathname;
    } catch (error) {
      return null;
    }
  }

  document.addEventListener("click", function (event) {
    var trigger = event.target.closest("[data-track-cta]");
    if (!trigger) return;
    window.sevendayTrack("cta_click", {
      cta_name: trigger.dataset.trackCta,
      cta_location: trigger.dataset.trackLocation || null,
      destination: safeDestination(trigger.getAttribute("href"))
    });
  });
})();
