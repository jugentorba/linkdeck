/* LinkDeck cosmetic filtering + popup guard.
 * Injected at document start in every frame. Kept intentionally conservative:
 * it hides empty ad containers and blocks script-driven popups, but never
 * removes page content.
 */
(function () {
  if (window.__linkdeckInstalled) return;
  window.__linkdeckInstalled = true;

  var AD_SELECTORS = [
    'ins.adsbygoogle',
    '[id^="google_ads_iframe"]',
    'iframe[src*="doubleclick.net"]',
    'iframe[src*="googlesyndication.com"]',
    'iframe[src*="adservice"]',
    'iframe[id^="aswift_"]',
    '[class*="ad-slot"]',
    '[class*="adslot"]',
    '[class*="adsbygoogle"]',
    '[id*="div-gpt-ad"]',
    '[data-ad-slot]',
    '[data-ad-client]',
    '[aria-label="Advertisement"]',
    '[aria-label="advertisement"]'
  ];

  function hide(el) {
    if (el && el.style) el.style.setProperty('display', 'none', 'important');
  }

  function report(n) {
    // Native shells may expose a stats bridge; the web build simply ignores it.
    try {
      if (window.LinkDeckStats && typeof window.LinkDeckStats.report === 'function') {
        window.LinkDeckStats.report(n);
      } else if (window.webkit && window.webkit.messageHandlers &&
                 window.webkit.messageHandlers.linkdeckStats) {
        window.webkit.messageHandlers.linkdeckStats.postMessage(n);
      }
    } catch (e) { }
  }

  var removed = 0;
  var adBlockingEnabled = window.__linkdeckBlockAds !== false;

  function sweep() {
    if (!adBlockingEnabled) return;
    for (var i = 0; i < AD_SELECTORS.length; i++) {
      var nodes;
      try { nodes = document.querySelectorAll(AD_SELECTORS[i]); } catch (e) { continue; }
      for (var j = 0; j < nodes.length; j++) {
        if (nodes[j].style.display !== 'none') { hide(nodes[j]); removed++; }
      }
    }
    // Killed trackers leave behind empty 1x1-ish frames; drop them.
    var frames = document.querySelectorAll('iframe');
    for (var k = 0; k < frames.length; k++) {
      var f = frames[k];
      var w = f.getBoundingClientRect().width;
      var h = f.getBoundingClientRect().height;
      if ((w <= 2 && h <= 2) || (f.src === 'about:blank' && w < 8 && h < 8)) {
        if (f.style.display !== 'none') { hide(f); removed++; }
      }
    }
    if (removed) { report(removed); removed = 0; }
  }

  // Popup guard: only allow window.open() triggered by a real user tap.
  // Native shells may allow popups with either flag.
  if (!(window.__linkdeckAllowPopups === true || window.__linkdeckBlockPopups === false)) {
  var lastGesture = 0;
  ['pointerdown', 'mousedown', 'touchstart', 'keydown'].forEach(function (type) {
    window.addEventListener(type, function (e) {
      if (e.isTrusted) lastGesture = Date.now();
    }, true);
  });

  var realOpen = window.open;
  window.open = function () {
    if (Date.now() - lastGesture > 800) { report(1); return null; }
    try { return realOpen.apply(window, arguments); } catch (e) { return null; }
  };

  // Kill the classic "top.location = ad" redirect after a click.
  try {
    var realAssign = window.location.assign.bind(window.location);
    var realReplace = window.location.replace.bind(window.location);
    var isAdHost = function (url) {
      var blocked = window.__linkdeckBlockedHosts || [];
      try {
        var u = new URL(url, location.href);
        if (u.hostname === location.hostname) return false;
        var h = u.hostname;
        for (var i = 0; i < blocked.length; i++) {
          if (h === blocked[i] || h.slice(-blocked[i].length - 1) === '.' + blocked[i]) return true;
        }
      } catch (e) { }
      return false;
    };
    window.location.assign = function (u) {
      if (isAdHost(u) && Date.now() - lastGesture > 800) return;
      return realAssign(u);
    };
    window.location.replace = function (u) {
      if (isAdHost(u) && Date.now() - lastGesture > 800) return;
      return realReplace(u);
    };
  } catch (e) { }
  }

  var pending = null;
  var schedule = function () {
    if (pending) return;
    pending = setTimeout(function () { pending = null; sweep(); }, 250);
  };

  if (document.readyState === 'loading') {
    document.addEventListener('DOMContentLoaded', schedule, { once: true });
  } else {
    schedule();
  }
  window.addEventListener('load', schedule);
  try {
    new MutationObserver(schedule).observe(document.documentElement, { childList: true, subtree: true });
  } catch (e) { }
})();
