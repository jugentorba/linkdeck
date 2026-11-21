/* LinkDeck — web build
 * Vanilla JS, no build step. Links live in localStorage under `linkdeck.v1`.
 */
(function () {
  'use strict';

  var STORE_KEY = 'linkdeck.v1';
  var TIP_KEY = 'linkdeck.blockingTip.v1';
  var MAX_NAME = 40;
  var PREVIEW_LIMIT = 12;
  var FAVICON_ENDPOINT = 'https://icons.duckduckgo.com/ip3/';

  var byId = function (id) { return document.getElementById(id); };
  var numberFormat = new Intl.NumberFormat('en-US');

  var els = {
    subtitle: byId('deck-subtitle'),
    deck: byId('deck'),
    grid: byId('grid'),
    emptyState: byId('empty-state'),
    emptyAdd: byId('empty-add'),
    addButton: byId('add-button'),
    installButton: byId('install-button'),
    settingsButton: byId('settings-button'),
    blockingInfo: byId('blocking-info'),

    linkDialog: byId('link-dialog'),
    linkForm: byId('link-form'),
    linkDialogTitle: byId('link-dialog-title'),
    linkDialogSubtitle: byId('link-dialog-subtitle'),
    urlField: byId('url-field'),
    urlInput: byId('link-url'),
    urlError: byId('url-error'),
    nameInput: byId('link-name'),
    nameError: byId('name-error'),
    linkSubmit: byId('link-submit'),

    settingsDialog: byId('settings-dialog'),
    blockingSection: byId('blocking-section'),
    blocklistCount: byId('blocklist-count'),
    blocklistSearch: byId('blocklist-search'),
    blocklistPreview: byId('blocklist-preview'),
    blocklistNote: byId('blocklist-note'),
    exportButton: byId('export-button'),
    importButton: byId('import-button'),
    clearButton: byId('clear-button'),
    importInput: byId('import-input'),
    importStatus: byId('import-status'),
    settingsInstall: byId('settings-install'),

    installDialog: byId('install-dialog'),
    installTitle: byId('install-title'),
    installSubtitle: byId('install-subtitle'),
    installSteps: byId('install-steps'),
    installNote: byId('install-note'),

    confirmDialog: byId('confirm-dialog'),
    confirmTitle: byId('confirm-title'),
    confirmBody: byId('confirm-body'),
    confirmAction: byId('confirm-action'),

    contextMenu: byId('context-menu'),
    toasts: byId('toasts'),

    embedView: byId('embed-view'),
    embedBack: byId('embed-back'),
    embedName: byId('embed-name'),
    embedHost: byId('embed-host'),
    embedOpen: byId('embed-open'),
    embedClose: byId('embed-close'),
    embedFrame: byId('embed-frame'),
    embedFallback: byId('embed-fallback'),
    fallbackOpen: byId('fallback-open'),
    fallbackBack: byId('fallback-back'),
    fallbackDismiss: byId('fallback-dismiss'),

    topbar: document.querySelector('.topbar'),
    footnote: document.querySelector('.footnote'),
    skipLink: document.querySelector('.skip-link')
  };

  var links = [];
  var seenIds = new Set();
  var dialogMode = 'add';
  var editingId = null;
  var nameDirty = false;
  var contextLinkId = null;
  var lastFocusedBeforeMenu = null;
  var suppressClickUntil = 0;
  var longPress = null;
  var confirmCallback = null;
  var deferredInstallPrompt = null;
  var blocklist = null;
  var blocklistLoading = false;
  var embedLink = null;
  var embedFallbackTimer = 0;
  var embedDismissTimer = 0;

  /* ---------- Utilities ---------- */

  function formatCount(value) {
    return numberFormat.format(value);
  }

  function linkCountLabel(count) {
    return count + (count === 1 ? ' link' : ' links');
  }

  function makeId() {
    if (window.crypto && typeof window.crypto.randomUUID === 'function') {
      return window.crypto.randomUUID();
    }
    return 'link-' + Date.now().toString(36) + '-' + Math.random().toString(36).slice(2, 10);
  }

  function normalizeUrl(value) {
    var text = String(value || '').trim();
    if (!text) return null;
    if (!/^[a-z][a-z0-9+.-]*:/i.test(text)) text = 'https://' + text;
    var url;
    try { url = new URL(text); } catch (e) { return null; }
    if (url.protocol !== 'http:' && url.protocol !== 'https:') return null;
    if (!url.hostname || url.hostname.indexOf('.') === -1) return null;
    if (url.username || url.password) return null;
    return url.href;
  }

  function hostOf(url) {
    try { return new URL(url).hostname.replace(/^www\./, ''); } catch (e) { return url; }
  }

  function suggestName(url) {
    try {
      var host = new URL(url).hostname.replace(/^www\./, '');
      var label = host.split('.')[0] || host;
      return capitalize(label).slice(0, MAX_NAME);
    } catch (e) { return ''; }
  }

  function capitalize(text) {
    return text ? text.charAt(0).toUpperCase() + text.slice(1) : '';
  }

  function firstLetter(name) {
    var match = String(name || '').match(/[\p{L}\p{N}]/u);
    return match ? match[0].toUpperCase() : '?';
  }

  function hashString(text) {
    var hash = 0;
    for (var i = 0; i < text.length; i++) {
      hash = ((hash << 5) - hash + text.charCodeAt(i)) | 0;
    }
    return Math.abs(hash);
  }

  function gradientFor(host) {
    var hue = hashString(host) % 360;
    return 'linear-gradient(135deg, hsl(' + hue + ' 45% 38%), hsl(' + ((hue + 40) % 360) + ' 52% 26%))';
  }

  function isStandalone() {
    return window.matchMedia('(display-mode: standalone)').matches ||
      window.matchMedia('(display-mode: window-controls-overlay)').matches ||
      window.navigator.standalone === true;
  }

  function isIOS() {
    return /iPhone|iPad|iPod/.test(navigator.userAgent) ||
      (navigator.platform === 'MacIntel' && navigator.maxTouchPoints > 1);
  }

  function isSafari() {
    var ua = navigator.userAgent;
    return /Safari/.test(ua) && !/Chrome|Chromium|CriOS|Edg|OPR|FxiOS|Firefox/.test(ua);
  }

  function saveLinks() {
    try {
      localStorage.setItem(STORE_KEY, JSON.stringify(links));
      return true;
    } catch (e) {
      showToast('Couldn’t save your links. This browser’s storage may be full or blocked.');
      return false;
    }
  }

  function loadLinks() {
    var raw;
    try { raw = localStorage.getItem(STORE_KEY); } catch (e) { return []; }
    if (!raw) return [];
    try {
      var parsed = JSON.parse(raw);
      if (!Array.isArray(parsed)) return [];
      return parsed.map(sanitizeStoredLink).filter(Boolean);
    } catch (e) {
      return [];
    }
  }

  function sanitizeStoredLink(raw) {
    if (!raw || typeof raw !== 'object') return null;
    var url = normalizeUrl(raw.url);
    if (!url) return null;
    var name = typeof raw.name === 'string' ? raw.name.trim().slice(0, MAX_NAME) : '';
    var addedAt = typeof raw.addedAt === 'string' ? raw.addedAt : new Date().toISOString();
    var id = typeof raw.id === 'string' && raw.id.trim() ? raw.id.trim() : makeId();
    // The web build cannot block anything, so counts always start at zero.
    return { id: id, name: name || suggestName(url), url: url, addedAt: addedAt, blocked: 0 };
  }

  /* ---------- Deck rendering ---------- */

  function renderDeck() {
    var blockedTotal = links.reduce(function (sum, link) { return sum + (link.blocked || 0); }, 0);

    if (!links.length) {
      els.subtitle.textContent = 'Your links, as apps';
    } else {
      var subtitle = linkCountLabel(links.length);
      if (blockedTotal > 0) subtitle += ' · ' + formatCount(blockedTotal) + ' blocked';
      els.subtitle.textContent = subtitle;
    }

    els.emptyState.hidden = links.length > 0;
    els.grid.hidden = links.length === 0;

    var fragment = document.createDocumentFragment();
    links.forEach(function (link, index) {
      fragment.appendChild(createTile(link, index));
    });
    els.grid.replaceChildren(fragment);

    updateDataButtons();
  }

  function createTile(link, index) {
    var host = hostOf(link.url);

    var wrap = document.createElement('li');
    wrap.className = 'tile-wrap';
    wrap.dataset.id = link.id;

    var anchor = document.createElement('a');
    anchor.className = 'tile';
    anchor.href = link.url;
    anchor.target = '_blank';
    anchor.rel = 'noopener';
    anchor.dataset.id = link.id;

    if (!seenIds.has(link.id)) {
      seenIds.add(link.id);
      anchor.classList.add('tile-enter');
      anchor.style.setProperty('--tile-index', String(Math.min(index, 8)));
      anchor.addEventListener('animationend', function () {
        anchor.classList.remove('tile-enter');
      }, { once: true });
    }

    var icon = document.createElement('span');
    icon.className = 'tile-icon';
    icon.style.background = gradientFor(host);
    icon.setAttribute('aria-hidden', 'true');

    var letter = document.createElement('span');
    letter.className = 'tile-letter';
    letter.textContent = firstLetter(link.name);
    icon.appendChild(letter);
    addFavicon(icon, host);

    var text = document.createElement('span');
    text.className = 'tile-text';

    var name = document.createElement('span');
    name.className = 'tile-name';
    name.textContent = link.name;

    var meta = document.createElement('span');
    meta.className = 'tile-meta';

    var hostEl = document.createElement('span');
    hostEl.className = 'tile-host';
    hostEl.textContent = host;
    meta.appendChild(hostEl);

    if (link.blocked > 0) meta.appendChild(createShieldPill(link.blocked));

    text.appendChild(name);
    text.appendChild(meta);
    anchor.appendChild(icon);
    anchor.appendChild(text);

    var opens = document.createElement('span');
    opens.className = 'sr-only';
    opens.textContent = '. Opens in a new tab.';
    anchor.appendChild(opens);

    var menuButton = document.createElement('button');
    menuButton.type = 'button';
    menuButton.className = 'tile-menu';
    menuButton.setAttribute('aria-label', 'Actions for ' + link.name);
    menuButton.setAttribute('aria-haspopup', 'menu');
    menuButton.innerHTML = '<svg aria-hidden="true" viewBox="0 0 24 24" fill="currentColor"><circle cx="5" cy="12" r="1.7"></circle><circle cx="12" cy="12" r="1.7"></circle><circle cx="19" cy="12" r="1.7"></circle></svg>';
    menuButton.addEventListener('click', function (event) {
      event.stopPropagation();
      openContextMenu(link.id, menuButton);
    });

    wrap.appendChild(anchor);
    wrap.appendChild(menuButton);
    return wrap;
  }

  function addFavicon(icon, host) {
    var img = document.createElement('img');
    img.className = 'tile-favicon';
    img.alt = '';
    img.width = 44;
    img.height = 44;
    img.loading = 'lazy';
    img.decoding = 'async';
    img.referrerPolicy = 'no-referrer';
    img.addEventListener('load', function () {
      img.classList.add('is-loaded');
    }, { once: true });
    img.addEventListener('error', function () {
      img.remove();
    }, { once: true });
    img.src = FAVICON_ENDPOINT + encodeURIComponent(host) + '.ico';
    icon.appendChild(img);
  }

  function createShieldPill(count) {
    var pill = document.createElement('span');
    pill.className = 'shield-pill';
    var icon = document.createElementNS('http://www.w3.org/2000/svg', 'svg');
    icon.setAttribute('viewBox', '0 0 24 24');
    icon.setAttribute('fill', 'none');
    icon.setAttribute('stroke', 'currentColor');
    icon.setAttribute('stroke-width', '2');
    icon.setAttribute('aria-hidden', 'true');
    var path = document.createElementNS('http://www.w3.org/2000/svg', 'path');
    path.setAttribute('d', 'M12 3l7 3v5c0 4.4-3 8.4-7 10-4-1.6-7-5.6-7-10V6l7-3Z');
    icon.appendChild(path);
    pill.appendChild(icon);
    pill.appendChild(document.createTextNode(formatCount(count)));
    return pill;
  }

  function updateDataButtons() {
    els.exportButton.disabled = links.length === 0;
    els.clearButton.disabled = links.length === 0;
  }

  function focusTile(id) {
    window.requestAnimationFrame(function () {
      var tile = Array.prototype.find.call(
        els.grid.querySelectorAll('a.tile'),
        function (element) { return element.dataset.id === id; }
      );
      if (tile) tile.focus();
      else if (links.length === 0) els.emptyAdd.focus();
    });
  }

  function focusDeck() {
    window.requestAnimationFrame(function () {
      var tile = els.grid.querySelector('a.tile');
      if (tile) tile.focus();
      else els.emptyAdd.focus();
    });
  }

  /* ---------- Opening links ---------- */

  function windowFeatures() {
    var screenWidth = window.screen.availWidth || window.outerWidth || 1200;
    var screenHeight = window.screen.availHeight || window.outerHeight || 800;
    var width = Math.max(360, Math.min(1280, Math.round(screenWidth * 0.9)));
    var height = Math.max(480, Math.min(900, Math.round(screenHeight * 0.9)));
    var left = Math.max(0, Math.round((screenWidth - width) / 2));
    var top = Math.max(0, Math.round((screenHeight - height) / 2));
    return 'popup=yes,width=' + width + ',height=' + height +
      ',left=' + left + ',top=' + top + ',noopener';
  }

  function openLink(link, options) {
    if (!link) return;
    var forceWindow = Boolean(options && options.forceWindow);
    var useWindow = forceWindow || isStandalone();

    // `noopener` is deliberate: the opened site never gets a handle on LinkDeck.
    if (useWindow) window.open(link.url, '_blank', windowFeatures());
    else window.open(link.url, '_blank', 'noopener');

    maybeShowBlockingTip();
  }

  function maybeShowBlockingTip() {
    var seen = null;
    try { seen = localStorage.getItem(TIP_KEY); } catch (e) { }
    if (seen) return;
    try { localStorage.setItem(TIP_KEY, '1'); } catch (e) { }
    showToast('Heads up: a browser tab can’t be ad-blocked by a web page. LinkDeck’s native apps filter ads inside their embedded view.', {
      action: 'Learn more',
      onAction: function () { openSettings('blocking'); },
      duration: 9000
    });
  }

  /* ---------- Add / rename dialog ---------- */

  function openLinkDialog(mode, link) {
    closeMenu(false);
    dialogMode = mode;
    editingId = link ? link.id : null;
    nameDirty = mode === 'rename';

    els.linkDialogTitle.textContent = mode === 'rename' ? 'Rename link' : 'Add a link';
    els.linkDialogSubtitle.textContent = mode === 'rename'
      ? hostOf(link.url)
      : 'Anything with a web address works.';
    els.urlField.hidden = mode === 'rename';
    els.linkSubmit.textContent = mode === 'rename' ? 'Save' : 'Add to deck';

    els.urlInput.value = '';
    els.nameInput.value = mode === 'rename' ? link.name : '';
    clearFieldError(els.urlInput, els.urlError);
    clearFieldError(els.nameInput, els.nameError);

    els.linkDialog.showModal();
    syncDialogLock();

    window.requestAnimationFrame(function () {
      if (mode === 'rename') {
        els.nameInput.focus();
        els.nameInput.select();
      } else {
        els.urlInput.focus();
      }
    });
  }

  function handleUrlInput() {
    clearFieldError(els.urlInput, els.urlError);
    if (nameDirty) return;
    var normalized = normalizeUrl(els.urlInput.value);
    els.nameInput.value = normalized ? suggestName(normalized) : '';
  }

  function handleLinkSubmit(event) {
    event.preventDefault();
    clearFieldError(els.urlInput, els.urlError);
    clearFieldError(els.nameInput, els.nameError);

    if (dialogMode === 'rename') {
      var existing = links.find(function (link) { return link.id === editingId; });
      if (!existing) {
        els.linkDialog.close();
        return;
      }
      var newName = els.nameInput.value.trim();
      if (!newName) {
        setFieldError(els.nameInput, els.nameError, 'Give this link a name.');
        return;
      }
      if (newName === existing.name) {
        els.linkDialog.close();
        return;
      }
      existing.name = newName.slice(0, MAX_NAME);
      saveLinks();
      renderDeck();
      els.linkDialog.close();
      showToast('Renamed to ' + existing.name + '.');
      focusTile(existing.id);
      return;
    }

    var url = normalizeUrl(els.urlInput.value);
    if (!url) {
      setFieldError(els.urlInput, els.urlError, 'Enter a valid web address, like example.com.');
      return;
    }
    var duplicate = links.some(function (link) { return link.url === url; });
    if (duplicate) {
      setFieldError(els.urlInput, els.urlError, 'That link is already on your deck.');
      return;
    }

    var name = els.nameInput.value.trim() || suggestName(url);
    name = name.slice(0, MAX_NAME);
    if (!name) {
      setFieldError(els.nameInput, els.nameError, 'Give this link a name.');
      return;
    }

    var link = {
      id: makeId(),
      name: name,
      url: url,
      addedAt: new Date().toISOString(),
      blocked: 0
    };
    links.push(link);
    saveLinks();
    renderDeck();
    els.linkDialog.close();
    showToast('Added ' + name + '.');
    focusTile(link.id);
  }

  function setFieldError(input, errorEl, message) {
    input.setAttribute('aria-invalid', 'true');
    errorEl.textContent = message;
    errorEl.classList.add('is-shown');
    input.focus();
  }

  function clearFieldError(input, errorEl) {
    input.removeAttribute('aria-invalid');
    errorEl.textContent = '';
    errorEl.classList.remove('is-shown');
  }

  /* ---------- Context menu ---------- */

  function openContextMenu(id, anchor, point) {
    var link = links.find(function (item) { return item.id === id; });
    if (!link) return;

    if (!els.contextMenu.hidden) closeMenu(false);

    contextLinkId = id;
    lastFocusedBeforeMenu = document.activeElement;
    els.contextMenu.hidden = false;
    els.contextMenu.classList.toggle('menu-mobile', window.innerWidth <= 600);

    if (window.innerWidth <= 600) {
      els.contextMenu.style.left = '';
      els.contextMenu.style.top = '';
    } else {
      var rect = anchor.getBoundingClientRect();
      var menuWidth = els.contextMenu.offsetWidth;
      var menuHeight = els.contextMenu.offsetHeight;
      var x = point && typeof point.x === 'number' ? point.x : rect.right - menuWidth;
      var y = point && typeof point.y === 'number' ? point.y : rect.bottom + 6;

      if (point) {
        x = point.x;
        y = point.y;
      } else if (y + menuHeight > window.innerHeight - 8) {
        y = rect.top - menuHeight - 6;
      }

      x = Math.max(8, Math.min(x, window.innerWidth - menuWidth - 8));
      y = Math.max(8, Math.min(y, window.innerHeight - menuHeight - 8));
      els.contextMenu.style.left = x + 'px';
      els.contextMenu.style.top = y + 'px';
    }

    var firstItem = els.contextMenu.querySelector('[role="menuitem"]');
    if (firstItem) firstItem.focus({ preventScroll: true });
  }

  function closeMenu(restoreFocus) {
    if (els.contextMenu.hidden) return;
    els.contextMenu.hidden = true;
    els.contextMenu.classList.remove('menu-mobile');
    els.contextMenu.style.left = '';
    els.contextMenu.style.top = '';
    contextLinkId = null;

    if (restoreFocus !== false && lastFocusedBeforeMenu && document.contains(lastFocusedBeforeMenu)) {
      lastFocusedBeforeMenu.focus({ preventScroll: true });
    }
    lastFocusedBeforeMenu = null;
  }

  function handleMenuAction(action) {
    var link = links.find(function (item) { return item.id === contextLinkId; });
    closeMenu(false);
    if (!link) return;

    if (action === 'open') {
      openLink(link);
    } else if (action === 'window') {
      openLink(link, { forceWindow: true });
    } else if (action === 'rename') {
      openLinkDialog('rename', link);
    } else if (action === 'remove') {
      removeLink(link);
    }
  }

  function onMenuKeydown(event) {
    var items = Array.prototype.slice.call(els.contextMenu.querySelectorAll('[role="menuitem"]'));
    var index = items.indexOf(document.activeElement);

    if (event.key === 'Escape') {
      event.preventDefault();
      closeMenu();
    } else if (event.key === 'Tab') {
      event.preventDefault();
      closeMenu();
    } else if (event.key === 'ArrowDown' || event.key === 'ArrowUp') {
      event.preventDefault();
      var direction = event.key === 'ArrowDown' ? 1 : -1;
      var next = index < 0 ? 0 : (index + direction + items.length) % items.length;
      items[next].focus();
    } else if (event.key === 'Home' || event.key === 'End') {
      event.preventDefault();
      items[event.key === 'Home' ? 0 : items.length - 1].focus();
    }
  }

  function removeLink(link) {
    var index = links.indexOf(link);
    if (index < 0) return;
    links.splice(index, 1);
    saveLinks();
    renderDeck();

    showToast('Removed ' + link.name + '.', {
      action: 'Undo',
      onAction: function () {
        if (links.some(function (item) { return item.id === link.id; })) return;
        links.splice(Math.min(index, links.length), 0, link);
        saveLinks();
        renderDeck();
        focusTile(link.id);
        showToast(link.name + ' restored.');
      }
    });
    focusDeck();
  }

  /* ---------- Settings ---------- */

  function openSettings(section) {
    closeMenu(false);
    if (!els.settingsDialog.open) {
      els.settingsDialog.showModal();
      syncDialogLock();
    }
    updateInstallUI();
    updateDataButtons();

    if (section === 'blocking') {
      window.requestAnimationFrame(function () {
        els.blockingSection.scrollIntoView({ block: 'start' });
      });
    }
    loadBlocklist();
  }

  function loadBlocklist() {
    if (blocklist) {
      renderBlocklistPreview();
      return;
    }
    if (blocklistLoading) return;
    blocklistLoading = true;
    els.blocklistCount.textContent = 'Loading…';

    fetch('blocklist.txt')
      .then(function (response) {
        if (!response.ok) throw new Error('blocklist request failed');
        return response.text();
      })
      .then(function (text) {
        blocklist = text.split('\n')
          .map(function (line) { return line.trim(); })
          .filter(function (line) { return line && line.charAt(0) !== '#'; });
        els.blocklistCount.textContent = formatCount(blocklist.length);
        els.blocklistSearch.disabled = false;
        renderBlocklistPreview();
      })
      .catch(function () {
        els.blocklistCount.textContent = '—';
        els.blocklistNote.textContent = 'Couldn’t load blocklist.txt. Try again when you’re online.';
      })
      .finally(function () {
        blocklistLoading = false;
      });
  }

  function renderBlocklistPreview() {
    if (!blocklist) return;
    var query = els.blocklistSearch.value.trim().toLowerCase();
    var matches = query
      ? blocklist.filter(function (domain) { return domain.indexOf(query) !== -1; })
      : blocklist;
    var shown = Math.min(matches.length, PREVIEW_LIMIT);

    var fragment = document.createDocumentFragment();
    if (!shown) {
      var empty = document.createElement('li');
      empty.className = 'is-empty';
      empty.textContent = 'No matching domains.';
      fragment.appendChild(empty);
    } else {
      matches.slice(0, PREVIEW_LIMIT).forEach(function (domain) {
        var item = document.createElement('li');
        item.textContent = domain;
        fragment.appendChild(item);
      });
    }
    els.blocklistPreview.replaceChildren(fragment);

    if (query) {
      els.blocklistNote.textContent = matches.length
        ? formatCount(matches.length) + (matches.length === 1 ? ' match' : ' matches') + ' · showing ' + shown
        : 'No blocked domains match that search.';
    } else {
      els.blocklistNote.textContent = 'Showing ' + shown + ' of ' + formatCount(blocklist.length) + ' domains.';
    }
  }

  function exportLinks() {
    if (!links.length) return;
    var payload = {
      app: 'LinkDeck',
      version: 1,
      exportedAt: new Date().toISOString(),
      links: links
    };
    var blob = new Blob([JSON.stringify(payload, null, 2)], { type: 'application/json' });
    var url = URL.createObjectURL(blob);
    var anchor = document.createElement('a');
    anchor.href = url;
    anchor.download = 'linkdeck-' + new Date().toISOString().slice(0, 10) + '.json';
    document.body.appendChild(anchor);
    anchor.click();
    anchor.remove();
    window.setTimeout(function () { URL.revokeObjectURL(url); }, 1000);
    showToast('Exported ' + linkCountLabel(links.length) + '.');
  }

  function importLinks(file) {
    if (!file) return;
    els.importStatus.classList.remove('is-error');
    els.importStatus.textContent = 'Reading…';
    els.importInput.value = '';

    if (file.size > 2 * 1024 * 1024) {
      setImportStatus('That file is too large. Choose a LinkDeck JSON export under 2 MB.', true);
      return;
    }

    file.text().then(function (text) {
      var parsed = JSON.parse(text);
      var incoming = Array.isArray(parsed) ? parsed : (parsed && Array.isArray(parsed.links) ? parsed.links : null);
      if (!incoming) throw new Error('no links array');

      var existingUrls = new Set(links.map(function (link) { return link.url; }));
      var existingIds = new Set(links.map(function (link) { return link.id; }));
      var added = 0;
      var duplicates = 0;
      var invalid = 0;
      var next = links.slice();

      incoming.forEach(function (raw) {
        if (!raw || typeof raw !== 'object') { invalid++; return; }
        var url = normalizeUrl(raw.url);
        if (!url) { invalid++; return; }
        if (existingUrls.has(url)) { duplicates++; return; }

        var id = typeof raw.id === 'string' && raw.id.trim() ? raw.id.trim() : makeId();
        if (existingIds.has(id)) id = makeId();
        var name = typeof raw.name === 'string' ? raw.name.trim().slice(0, MAX_NAME) : '';
        var addedAt = typeof raw.addedAt === 'string' ? raw.addedAt : new Date().toISOString();

        existingUrls.add(url);
        existingIds.add(id);
        next.push({
          id: id,
          name: name || suggestName(url),
          url: url,
          addedAt: addedAt,
          blocked: 0
        });
        added++;
      });

      if (!added) {
        var detail = duplicates ? ' Those links are already on your deck.' : '';
        setImportStatus('No new links imported.' + detail, true);
        return;
      }

      links = next;
      saveLinks();
      renderDeck();
      var summary = 'Imported ' + linkCountLabel(added) + '.';
      if (duplicates) summary += ' Skipped ' + duplicates + (duplicates === 1 ? ' duplicate.' : ' duplicates.');
      if (invalid) summary += ' Skipped ' + invalid + ' invalid.';
      setImportStatus(summary, false);
      showToast(summary);
    }).catch(function () {
      setImportStatus('Couldn’t read that file. Choose a LinkDeck JSON export.', true);
    });
  }

  function setImportStatus(message, isError) {
    els.importStatus.textContent = message;
    els.importStatus.classList.toggle('is-error', Boolean(isError));
  }

  function openConfirm(title, body, actionLabel, callback) {
    closeMenu(false);
    els.confirmTitle.textContent = title;
    els.confirmBody.textContent = body;
    els.confirmAction.textContent = actionLabel;
    confirmCallback = callback;
    els.confirmDialog.showModal();
    syncDialogLock();
  }

  /* ---------- Install ---------- */

  function updateInstallUI() {
    var installed = isStandalone();
    els.installButton.hidden = installed;
    els.settingsInstall.disabled = installed;
    els.settingsInstall.textContent = installed
      ? 'Installed on this device'
      : (isIOS() ? 'Add to Home Screen' : 'Install LinkDeck');
  }

  function handleInstallClick() {
    if (isStandalone()) {
      showToast('LinkDeck is already installed.');
      return;
    }
    if (isIOS()) {
      showInstallInstructions();
      return;
    }
    if (deferredInstallPrompt) {
      var promptEvent = deferredInstallPrompt;
      deferredInstallPrompt = null;
      try {
        promptEvent.prompt();
        promptEvent.userChoice.then(function (choice) {
          if (choice && choice.outcome === 'accepted') showToast('Installing LinkDeck…');
          else showToast('Install dismissed. You can install later from Settings.');
          updateInstallUI();
        });
      } catch (e) {
        updateInstallUI();
        showInstallInstructions();
      }
      return;
    }
    showInstallInstructions();
  }

  function showInstallInstructions() {
    var title;
    var subtitle;
    var steps;
    var note;

    if (isIOS()) {
      title = 'Add to Home Screen';
      subtitle = 'One tap from your Home Screen.';
      steps = [
        'Open LinkDeck in Safari.',
        'Tap the Share button in the toolbar.',
        'Tap Add to Home Screen.',
        'Tap Add.'
      ];
      note = 'The Home Screen app opens without Safari’s chrome, but it still can’t block ads in other sites.';
    } else if (isSafari() && /Macintosh/.test(navigator.userAgent)) {
      title = 'Add LinkDeck to the Dock';
      subtitle = 'Safari can keep the deck in your Dock.';
      steps = [
        'Open LinkDeck in Safari.',
        'Choose File → Add to Dock… from the menu bar.',
        'Click Add.'
      ];
      note = 'Add to Dock is available in Safari 17 or later on macOS Sonoma.';
    } else {
      title = 'Install LinkDeck';
      subtitle = 'Keep the deck one tap away.';
      steps = [
        'Open the browser menu.',
        'Choose Install LinkDeck, Install app, or Add to Home screen.',
        'Confirm the install.'
      ];
      note = 'If the option is missing, this browser doesn’t consider the build installable yet. You can still use LinkDeck in a tab.';
    }

    els.installTitle.textContent = title;
    els.installSubtitle.textContent = subtitle;
    els.installSteps.replaceChildren.apply(els.installSteps, steps.map(function (step) {
      var item = document.createElement('li');
      item.textContent = step;
      return item;
    }));
    els.installNote.textContent = note;
    els.installDialog.showModal();
    syncDialogLock();
  }

  /* ---------- Toasts ---------- */

  function showToast(message, options) {
    var settings = options || {};
    var duration = typeof settings.duration === 'number' ? settings.duration : 5200;

    var toast = document.createElement('div');
    toast.className = 'toast';

    var text = document.createElement('p');
    text.textContent = message;
    toast.appendChild(text);

    var remove = function () {
      if (toast.parentNode) toast.remove();
    };

    if (settings.action) {
      var action = document.createElement('button');
      action.type = 'button';
      action.className = 'toast-action';
      action.textContent = settings.action;
      action.addEventListener('click', function () {
        remove();
        if (typeof settings.onAction === 'function') settings.onAction();
      });
      toast.appendChild(action);
    }

    var close = document.createElement('button');
    close.type = 'button';
    close.className = 'toast-close';
    close.setAttribute('aria-label', 'Dismiss notification');
    close.innerHTML = '<svg aria-hidden="true" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round"><path d="M6 6l12 12M18 6 6 18"></path></svg>';
    close.addEventListener('click', remove);
    toast.appendChild(close);

    els.toasts.appendChild(toast);
    while (els.toasts.children.length > 3) {
      els.toasts.firstElementChild.remove();
    }

    if (duration > 0) window.setTimeout(remove, duration);
  }

  /* ---------- Dialogs in general ---------- */

  function syncDialogLock() {
    document.body.classList.toggle('dialog-open', Boolean(document.querySelector('dialog[open]')));
  }

  function focusableIn(dialog) {
    var selector = 'a[href], button:not([disabled]), input:not([disabled]):not([tabindex="-1"]), select:not([disabled]), textarea:not([disabled]), [tabindex]:not([tabindex="-1"])';
    return Array.prototype.filter.call(dialog.querySelectorAll(selector), function (element) {
      return !element.hidden && element.getClientRects().length > 0;
    });
  }

  function onGlobalKeydown(event) {
    if (event.key === 'Tab') {
      var openDialogs = document.querySelectorAll('dialog[open]');
      var dialog = openDialogs[openDialogs.length - 1];
      if (!dialog) return;
      var focusable = focusableIn(dialog);
      if (!focusable.length) {
        event.preventDefault();
        return;
      }
      var first = focusable[0];
      var last = focusable[focusable.length - 1];
      if (event.shiftKey && (document.activeElement === first || !dialog.contains(document.activeElement))) {
        event.preventDefault();
        last.focus();
      } else if (!event.shiftKey && (document.activeElement === last || !dialog.contains(document.activeElement))) {
        event.preventDefault();
        first.focus();
      }
      return;
    }

    if (event.key === 'Escape') {
      if (!els.contextMenu.hidden) {
        event.preventDefault();
        closeMenu();
        return;
      }
      var openDialogs = document.querySelectorAll('dialog[open]');
      if (openDialogs.length) {
        event.preventDefault();
        openDialogs[openDialogs.length - 1].close();
        return;
      }
      if (!els.embedView.hidden) {
        event.preventDefault();
        closeEmbed();
      }
    }
  }

  /* ---------- Embedded view ---------- */

  function setAppInert(inert) {
    [els.skipLink, els.topbar, els.deck, els.footnote].forEach(function (element) {
      if (!element) return;
      if (inert) element.setAttribute('inert', '');
      else element.removeAttribute('inert');
    });
  }

  function showEmbed(link) {
    closeMenu(false);
    embedLink = link;
    var host = hostOf(link.url);

    els.embedView.hidden = false;
    document.body.classList.add('embed-open');
    setAppInert(true);

    els.embedName.textContent = link.name;
    els.embedHost.textContent = host;
    els.embedOpen.href = link.url;
    els.embedFrame.title = link.name + ' — ' + host;
    els.embedFallback.hidden = true;

    window.clearTimeout(embedFallbackTimer);
    window.clearTimeout(embedDismissTimer);
    els.embedFrame.src = link.url;
    document.title = link.name + ' — LinkDeck';

    embedFallbackTimer = window.setTimeout(function () {
      if (!embedLink) return;
      els.embedFallback.hidden = false;
      embedDismissTimer = window.setTimeout(function () {
        els.embedFallback.hidden = true;
      }, 12000);
    }, 4000);

    window.requestAnimationFrame(function () {
      els.embedBack.focus({ preventScroll: true });
    });
  }

  function closeEmbed() {
    if (els.embedView.hidden) return;
    window.clearTimeout(embedFallbackTimer);
    window.clearTimeout(embedDismissTimer);
    els.embedFallback.hidden = true;
    els.embedView.hidden = true;
    els.embedFrame.src = 'about:blank';
    embedLink = null;
    document.body.classList.remove('embed-open');
    setAppInert(false);
    document.title = 'LinkDeck';
    clearLaunchQuery();
    focusDeck();
  }

  function clearLaunchQuery() {
    try {
      var url = new URL(window.location.href);
      url.searchParams.delete('app');
      url.searchParams.delete('embed');
      var search = url.searchParams.toString();
      window.history.replaceState(null, '', url.pathname + (search ? '?' + search : '') + url.hash);
    } catch (e) { }
  }

  function handleLaunchQuery() {
    var params;
    try { params = new URLSearchParams(window.location.search); } catch (e) { return; }
    var id = params.get('app');
    if (!id) return;

    var link = links.find(function (item) { return item.id === id; });
    if (!link) {
      showToast('That app isn’t on your deck.');
      clearLaunchQuery();
      return;
    }
    if (params.get('embed') === '1') {
      showEmbed(link);
      return;
    }

    openLink(link);
    showToast('Opening ' + link.name + '. If nothing happens, allow pop-ups for LinkDeck.', {
      action: 'Open',
      onAction: function () { openLink(link); },
      duration: 7000
    });
  }

  /* ---------- Service worker ---------- */

  function registerServiceWorker() {
    if (!('serviceWorker' in navigator)) return;
    window.addEventListener('load', function () {
      navigator.serviceWorker.register('sw.js').catch(function () {
        // The app still works without offline caching; keep the console clean.
      });
    });
  }

  /* ---------- Events ---------- */

  function bindEvents() {
    els.addButton.addEventListener('click', function () { openLinkDialog('add'); });
    els.emptyAdd.addEventListener('click', function () { openLinkDialog('add'); });
    els.settingsButton.addEventListener('click', function () { openSettings(); });
    els.blockingInfo.addEventListener('click', function () { openSettings('blocking'); });
    els.installButton.addEventListener('click', handleInstallClick);
    els.settingsInstall.addEventListener('click', handleInstallClick);

    document.querySelectorAll('[data-close]').forEach(function (button) {
      button.addEventListener('click', function () {
        var dialog = button.closest('dialog');
        if (dialog) dialog.close();
      });
    });

    document.querySelectorAll('dialog').forEach(function (dialog) {
      dialog.addEventListener('close', syncDialogLock);
      dialog.addEventListener('click', function (event) {
        if (event.target === dialog) dialog.close();
      });
    });

    els.confirmDialog.addEventListener('close', function () {
      confirmCallback = null;
    });

    els.confirmAction.addEventListener('click', function () {
      var callback = confirmCallback;
      confirmCallback = null;
      els.confirmDialog.close();
      if (callback) callback();
    });

    els.linkForm.addEventListener('submit', handleLinkSubmit);
    els.urlInput.addEventListener('input', handleUrlInput);
    els.nameInput.addEventListener('input', function () {
      nameDirty = true;
      clearFieldError(els.nameInput, els.nameError);
    });

    els.linkDialog.addEventListener('close', function () {
      editingId = null;
      clearFieldError(els.urlInput, els.urlError);
      clearFieldError(els.nameInput, els.nameError);
    });

    els.blocklistSearch.addEventListener('input', renderBlocklistPreview);
    els.exportButton.addEventListener('click', exportLinks);
    els.importButton.addEventListener('click', function () { els.importInput.click(); });
    els.importInput.addEventListener('change', function () { importLinks(els.importInput.files[0]); });
    els.clearButton.addEventListener('click', function () {
      openConfirm(
        'Clear deck?',
        'Remove all saved links from this browser? This can’t be undone.',
        'Clear deck',
        function () {
          links = [];
          try { localStorage.removeItem(STORE_KEY); } catch (e) { }
          renderDeck();
          showToast('Deck cleared.');
          if (els.settingsDialog.open) {
            var close = els.settingsDialog.querySelector('[data-close]');
            if (close) close.focus();
          } else {
            focusDeck();
          }
        }
      );
    });

    els.contextMenu.addEventListener('keydown', onMenuKeydown);
    els.contextMenu.addEventListener('click', function (event) {
      var action = event.target.closest('[data-action]');
      if (action) handleMenuAction(action.dataset.action);
    });

    document.addEventListener('pointerdown', function (event) {
      if (!els.contextMenu.hidden && !els.contextMenu.contains(event.target)) closeMenu();
    }, true);

    window.addEventListener('resize', function () { closeMenu(false); });
    window.addEventListener('scroll', function () { closeMenu(false); }, true);
    document.addEventListener('keydown', onGlobalKeydown);

    els.grid.addEventListener('click', function (event) {
      var menuButton = event.target.closest('.tile-menu');
      if (menuButton) return;
      var anchor = event.target.closest('a.tile');
      if (!anchor) return;

      if (Date.now() < suppressClickUntil) {
        event.preventDefault();
        return;
      }
      if (event.metaKey || event.ctrlKey || event.shiftKey || event.altKey) return;

      var link = links.find(function (item) { return item.id === anchor.dataset.id; });
      if (!link) return;
      event.preventDefault();
      openLink(link);
    });

    els.grid.addEventListener('contextmenu', function (event) {
      var wrap = event.target.closest('.tile-wrap');
      if (!wrap) return;
      event.preventDefault();
      var anchor = wrap.querySelector('a.tile');
      if (!anchor) return;
      if (!els.contextMenu.hidden && contextLinkId === wrap.dataset.id) return;
      openContextMenu(wrap.dataset.id, anchor, { x: event.clientX, y: event.clientY });
    });

    els.grid.addEventListener('pointerdown', function (event) {
      if (event.pointerType === 'mouse' && event.button !== 0) return;
      var anchor = event.target.closest('a.tile');
      if (!anchor) return;
      clearLongPress();
      longPress = {
        startX: event.clientX,
        startY: event.clientY,
        id: anchor.dataset.id,
        anchor: anchor,
        timer: window.setTimeout(function () {
          suppressClickUntil = Date.now() + 900;
          var pending = longPress;
          longPress = null;
          if (pending) openContextMenu(pending.id, pending.anchor);
        }, 520)
      };
    });

    els.grid.addEventListener('pointermove', function (event) {
      if (!longPress) return;
      if (Math.abs(event.clientX - longPress.startX) > 10 ||
          Math.abs(event.clientY - longPress.startY) > 10) {
        clearLongPress();
      }
    });

    ['pointerup', 'pointercancel', 'pointerleave'].forEach(function (type) {
      els.grid.addEventListener(type, clearLongPress);
    });

    els.grid.addEventListener('keydown', function (event) {
      var anchor = document.activeElement && document.activeElement.closest
        ? document.activeElement.closest('a.tile')
        : null;

      if (event.key === 'ContextMenu' || (event.shiftKey && event.key === 'F10')) {
        if (!anchor) return;
        event.preventDefault();
        openContextMenu(anchor.dataset.id, anchor);
        return;
      }

      var keys = ['ArrowLeft', 'ArrowRight', 'ArrowUp', 'ArrowDown', 'Home', 'End'];
      if (keys.indexOf(event.key) === -1 || !anchor) return;

      var tiles = Array.prototype.slice.call(els.grid.querySelectorAll('a.tile'));
      var index = tiles.indexOf(anchor);
      if (index < 0) return;

      var columns = window.getComputedStyle(els.grid).gridTemplateColumns.split(' ').length || 1;
      var next = index;
      if (event.key === 'ArrowLeft') next = index - 1;
      else if (event.key === 'ArrowRight') next = index + 1;
      else if (event.key === 'ArrowUp') next = index - columns;
      else if (event.key === 'ArrowDown') next = index + columns;
      else if (event.key === 'Home') next = 0;
      else if (event.key === 'End') next = tiles.length - 1;

      if (next < 0 || next >= tiles.length || next === index) return;
      event.preventDefault();
      tiles[next].focus();
    });

    window.addEventListener('beforeinstallprompt', function (event) {
      event.preventDefault();
      deferredInstallPrompt = event;
      updateInstallUI();
    });
    window.addEventListener('appinstalled', function () {
      deferredInstallPrompt = null;
      updateInstallUI();
      showToast('LinkDeck installed.');
    });

    els.embedBack.addEventListener('click', closeEmbed);
    els.embedClose.addEventListener('click', closeEmbed);
    els.fallbackBack.addEventListener('click', closeEmbed);
    els.fallbackDismiss.addEventListener('click', function () {
      els.embedFallback.hidden = true;
    });
    els.embedOpen.addEventListener('click', function (event) {
      if (!embedLink) return;
      event.preventDefault();
      openLink(embedLink);
    });
    els.fallbackOpen.addEventListener('click', function () {
      if (embedLink) openLink(embedLink);
    });
  }

  function clearLongPress() {
    if (!longPress) return;
    window.clearTimeout(longPress.timer);
    longPress = null;
  }

  function init() {
    links = loadLinks();
    bindEvents();
    renderDeck();
    updateInstallUI();
    registerServiceWorker();
    handleLaunchQuery();
  }

  init();
})();
