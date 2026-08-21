(function () {
  window.dataLayer = window.dataLayer || [];

  window.firebullTrack = window.firebullTrack || function (eventName, payload) {
    window.dataLayer.push(Object.assign({ event: eventName }, payload || {}));
  };

  window.firebullTrack("page_view", {
    page_name: "firebull_eventos",
    path: window.location.pathname
  });
})();
