/* LinkDeck service worker — app shell and offline fallback. */
'use strict';

var CACHE_VERSION = 'linkdeck-shell-v1.0.2';
var SHELL_PATHS = [
  './',
  './index.html',
  './styles.css',
  './app.js',
  './manifest.webmanifest',
  './404.html',
  './blocklist.txt',
  './icons/favicon.png',
  './icons/icon-192.png',
  './icons/icon-512.png',
  './icons/maskable-512.png',
  './icons/apple-touch-icon.png'
];

var SCOPE = self.registration.scope;
var SHELL_URLS = SHELL_PATHS.map(function (path) { return new URL(path, SCOPE).href; });
var SHELL_SET = new Set(SHELL_URLS);
var APP_SHELL = new URL('index.html', SCOPE).href;
var NOT_FOUND = new URL('404.html', SCOPE).href;
var FAVICON_HOST = 'icons.duckduckgo.com';

self.addEventListener('install', function (event) {
  event.waitUntil(
    caches.open(CACHE_VERSION).then(function (cache) {
      return Promise.all(SHELL_URLS.map(function (url) {
        // Cache files individually so one failure can't discard the whole shell.
        return cache.add(new Request(url, { cache: 'reload' })).catch(function () { });
      }));
    }).then(function () {
      return self.skipWaiting();
    })
  );
});

self.addEventListener('activate', function (event) {
  event.waitUntil(
    caches.keys().then(function (keys) {
      return Promise.all(keys.map(function (key) {
        if (key !== CACHE_VERSION && key.indexOf('linkdeck-') === 0) {
          return caches.delete(key);
        }
        return null;
      }));
    }).then(function () {
      return self.clients.claim();
    })
  );
});

self.addEventListener('fetch', function (event) {
  var request = event.request;
  if (request.method !== 'GET') return;

  var url = new URL(request.url);

  if (request.mode === 'navigate') {
    event.respondWith(navigationResponse(request));
    return;
  }

  if (url.origin === self.location.origin && SHELL_SET.has(url.href)) {
    event.respondWith(shellResponse(request));
    return;
  }

  if (url.hostname === FAVICON_HOST) {
    event.respondWith(faviconResponse(request));
  }
});

async function navigationResponse(request) {
  try {
    var response = await fetch(request);
    if (response && response.ok) {
      var cache = await caches.open(CACHE_VERSION);
      cache.put(request, response.clone());
      return response;
    }
    if (response && response.status === 404) {
      var notFound = await caches.match(NOT_FOUND);
      if (notFound) return asNotFound(notFound);
    }
    return response;
  } catch (error) {
    var direct = await caches.match(request, { ignoreSearch: true });
    if (direct) return direct;

    var shell = await caches.match(APP_SHELL);
    if (shell) return shell;

    var offlinePage = await caches.match(NOT_FOUND);
    if (offlinePage) return offlinePage;

    return new Response('Offline', {
      status: 503,
      statusText: 'Offline',
      headers: { 'Content-Type': 'text/plain; charset=utf-8' }
    });
  }
}

async function shellResponse(request) {
  var cached = await caches.match(request);
  if (cached) return cached;

  try {
    var response = await fetch(request);
    if (response && response.ok) {
      var cache = await caches.open(CACHE_VERSION);
      cache.put(request, response.clone());
    }
    return response;
  } catch (error) {
    return new Response('Offline', {
      status: 503,
      statusText: 'Offline',
      headers: { 'Content-Type': 'text/plain; charset=utf-8' }
    });
  }
}

async function faviconResponse(request) {
  var cached = await caches.match(request);
  if (cached) return cached;

  try {
    var response = await fetch(request);
    if (response && (response.ok || response.type === 'opaque')) {
      var cache = await caches.open(CACHE_VERSION);
      cache.put(request, response.clone());
    }
    return response;
  } catch (error) {
    // The tile keeps its letter fallback; a 204 avoids a broken-image icon.
    return new Response(null, { status: 204, statusText: 'No Content' });
  }
}

async function asNotFound(response) {
  var body = await response.blob();
  return new Response(body, {
    status: 404,
    statusText: 'Not Found',
    headers: response.headers
  });
}
