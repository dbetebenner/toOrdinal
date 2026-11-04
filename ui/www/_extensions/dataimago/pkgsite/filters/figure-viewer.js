// @dataimago/css@0.1.0-alpha.33 dist/quarto/_extensions/dataimago/pkgsite/filters/figure-viewer.js · sha256:650db5390b3cbe889213e02efad264ed6b33042d6f9da1b476ec19f7d5b8e7e4 · generated from tokens; do not edit · restore: npx -p @dataimago/css@0.1.0-alpha.33 dataimago-sync
/**
 * dataimago figure viewer: click (or Enter/Space) an image marked `.di-figure-box` to see it enlarged
 * in a dialog, with its figcaption (math, emphasis and links intact).
 *
 * A classic script with no dependencies and no global API. It binds once, by event delegation, so
 * including it twice is harmless. Presentation lives in figure-modal.scss.
 *
 * Triggers: `img.di-figure-box`, or an `img` inside an element with that class, unless the image sits
 * in a link (an `a[href]` that is not Quarto's `a.lightbox`). Each trigger is made keyboard-operable.
 *
 * Ported from LIwLD's figure-modal.js (SGPc, after #244). Three gaps there are closed here:
 *   1. A caption link to another page, a missing id or a malformed fragment closes the viewer and
 *      then navigates itself, instead of relying on a detached anchor.
 *   2. A ResizeObserver keeps the caption's "scrollable region" semantics current while it is open.
 *   3. openModal takes the trigger and stores it as the opener, not document.activeElement.
 */
(function () {
  'use strict';

  // Imported during server rendering (Next.js) there is no document: do nothing.
  if (typeof document === 'undefined') return;

  var root = document.documentElement;
  if (root.dataset.diFigureViewer === 'bound') return;
  root.dataset.diFigureViewer = 'bound';

  var TRIGGER = 'img.di-figure-box, .di-figure-box img';
  var CAPTION_ID = 'di-figure-modal-caption';
  var CLOSE_GLYPH = '<svg viewBox="0 0 16 16" width="16" height="16" fill="none" stroke="currentColor" ' +
    'stroke-width="1.5" stroke-linecap="round" aria-hidden="true" focusable="false"><path d="M3.5 3.5 12.5 12.5M12.5 3.5 3.5 12.5"/></svg>';

  var modal = null;
  var modalImg = null;
  var modalCaption = null;
  var closeBtn = null;
  var resizeObserver = null;

  var named = typeof WeakSet === 'function' ? new WeakSet() : null; // triggers whose aria-label is ours
  var pendingSpace = null;  // the trigger a Space keydown landed on; opens on its keyup
  var decorateQueued = false;

  var opener = null;        // the trigger that opened the viewer; takes focus back on close
  var scrollPosition = 0;   // where the page was, restored on close
  var scrollLeft = 0;
  var inerted = [];         // page content made inert while open
  var savedBody = null;     // the body's inline styles before the viewer touched them
  var sidebarSaved = null;

  // ── Triggers ───────────────────────────────────────────────────────────────

  /** The trigger image for a node, or null. Images in a link (other than a.lightbox) are left alone. */
  function triggerFor(node) {
    var img = node && node.closest ? node.closest('img') : null;
    if (!img || !img.matches(TRIGGER)) return null;
    var link = img.closest('a[href]');
    if (link && !link.classList.contains('lightbox')) return null;
    return img;
  }

  /** The accessible name for a trigger: its alt text, else its figure's caption, else none. */
  function describe(img) {
    var text = (img.getAttribute('alt') || '').trim();
    if (!text) {
      var figure = img.closest('figure');
      var caption = figure ? figure.querySelector('figcaption') : null;
      text = caption ? caption.textContent.replace(/\s+/g, ' ').trim() : '';
      if (text.length > 120) text = text.slice(0, 120).replace(/\s+$/, '') + '…';
    }
    return text ? 'Enlarge figure: ' + text : 'Enlarge figure';
  }

  /** Make a trigger keyboard-operable and named. An aria-label the author wrote is left alone. */
  function decorate(img) {
    // Quarto's lightbox wrapper (an author forced `lightbox: true`): make the image the only control. The
    // anchor loses its href (kept in data-di-href), so it is no longer a link or a tab stop and nothing nests.
    var wrapper = img.closest('a.lightbox');
    if (wrapper && wrapper.hasAttribute('href')) {
      wrapper.setAttribute('data-di-href', wrapper.getAttribute('href'));
      wrapper.removeAttribute('href');
    }
    if (!img.hasAttribute('tabindex')) img.setAttribute('tabindex', '0');
    if (!img.hasAttribute('role')) img.setAttribute('role', 'button');
    if (img.hasAttribute('aria-label') && !(named && named.has(img))) return;
    img.setAttribute('aria-label', describe(img));
    if (named) named.add(img);
  }

  function decorateAll() {
    document.querySelectorAll(TRIGGER).forEach(function (img) {
      if (triggerFor(img)) decorate(img);
    });
  }

  /** Triggers rendered after load (client navigation, React) get decorated too, once per frame. */
  function observeLateTriggers() {
    if (typeof MutationObserver !== 'function' || !document.body) return;
    new MutationObserver(function (records) {
      var outside = records.some(function (r) { return !(modal && modal.contains(r.target)) && !(r.addedNodes.length === 1 && r.addedNodes[0] === modal); });
      if (!outside || decorateQueued) return;
      decorateQueued = true;
      requestAnimationFrame(function () {
        decorateQueued = false;
        decorateAll();
      });
    }).observe(document.body, { childList: true, subtree: true });
  }

  // ── The dialog ─────────────────────────────────────────────────────────────

  function createModal() {
    modal = document.createElement('div');
    modal.className = 'di-figure-modal';
    modal.hidden = true; // hidden by the module itself, so a page without the stylesheet works
    modal.setAttribute('role', 'dialog');
    modal.setAttribute('aria-modal', 'true');
    modal.setAttribute('aria-label', 'Figure');
    modal.setAttribute('aria-describedby', CAPTION_ID);
    modal.innerHTML =
      '<div class="di-figure-modal-content">' +
        '<div class="di-figure-modal-bar">' +
          '<kbd class="di-figure-modal-esc" aria-hidden="true">Esc</kbd>' +
          '<button class="di-figure-modal-close" type="button" aria-label="Close figure">' + CLOSE_GLYPH + '</button>' +
        '</div>' +
        '<img class="di-figure-modal-image" alt="">' +
        '<div class="di-figure-modal-caption" id="' + CAPTION_ID + '"></div>' +
      '</div>';
    document.body.appendChild(modal);
    modalImg = modal.querySelector('.di-figure-modal-image');
    modalCaption = modal.querySelector('.di-figure-modal-caption');
    closeBtn = modal.querySelector('.di-figure-modal-close');
    modalImg.addEventListener('load', sizeImage);

    closeBtn.addEventListener('click', function (e) {
      e.preventDefault();
      e.stopPropagation();
      closeModal();
    });
    modalCaption.addEventListener('click', onCaptionClick);
    modal.addEventListener('keydown', onModalKeydown);
    // A click on the backdrop itself (not the content) closes.
    modal.addEventListener('click', function (e) {
      if (e.target === modal) closeModal();
    });
  }

  /**
   * A vector source scales to fill the box the CSS caps allow, so it needs its aspect ratio; a raster
   * keeps its natural size (never upscaled). Runs when the enlarged image has loaded.
   */
  function sizeImage() {
    if (!isOpen() || !opener || !modalImg.classList.contains('is-vector-source')) return;
    var w = modalImg.naturalWidth || opener.naturalWidth || opener.clientWidth;
    var h = modalImg.naturalHeight || opener.naturalHeight || opener.clientHeight;
    if (!w || !h) return;
    modalImg.style.setProperty('--di-figure-ratio', String(w / h));
    modalImg.classList.add('di-figure-modal-image--vector');
  }

  function isVectorSource(src) {
    if (/^data:image\/svg\+xml/i.test(src)) return true;
    try {
      return /\.svg$/i.test(new URL(src, location.href).pathname);
    } catch (err) {
      return false;
    }
  }

  function isOpen() {
    return Boolean(modal && modal.classList.contains('is-open'));
  }

  /**
   * A caption taller than its box scrolls, so it becomes a named, focusable region (arrow keys scroll
   * it; a screen reader still reads the text inside). Recomputed whenever the caption is resized.
   */
  function syncCaptionRegion() {
    if (!isOpen() || modalCaption.hidden) return;
    if (modalCaption.scrollHeight > modalCaption.clientHeight) {
      modalCaption.setAttribute('role', 'region');
      modalCaption.setAttribute('tabindex', '0');
      modalCaption.setAttribute('aria-label', 'Figure caption');
    } else {
      clearCaptionRegion();
    }
  }

  function clearCaptionRegion() {
    modalCaption.removeAttribute('role');
    modalCaption.removeAttribute('tabindex');
    modalCaption.removeAttribute('aria-label');
  }

  /** Fill the caption from a copy of the figcaption's HTML (ids stripped); hide the box when empty. */
  function setCaption(figcaption) {
    modalCaption.replaceChildren();
    clearCaptionRegion();
    if (figcaption) {
      var copy = figcaption.cloneNode(true);
      copy.querySelectorAll('[id]').forEach(function (el) { el.removeAttribute('id'); });
      modalCaption.append.apply(modalCaption, copy.childNodes);
    }
    var empty = !modalCaption.textContent.trim() && !modalCaption.querySelector('img, svg, math');
    modalCaption.hidden = empty;
    if (empty) modal.removeAttribute('aria-describedby');
    else modal.setAttribute('aria-describedby', CAPTION_ID);
  }

  /** @param {HTMLImageElement} trigger the image that was clicked or keyboard-activated */
  function openModal(trigger) {
    if (!modal) createModal();
    if (isOpen()) return;
    opener = trigger;
    scrollPosition = window.pageYOffset || document.documentElement.scrollTop;
    scrollLeft = window.pageXOffset || document.documentElement.scrollLeft || 0;

    var source = trigger.currentSrc || trigger.src;
    modalImg.classList.remove('di-figure-modal-image--vector');
    modalImg.style.removeProperty('--di-figure-ratio');
    modalImg.classList.toggle('is-vector-source', isVectorSource(source));
    modalImg.src = source;
    modalImg.alt = trigger.getAttribute('alt') || '';
    var figure = trigger.closest('figure');
    setCaption(figure ? figure.querySelector('figcaption') : null);
    modal.hidden = false;
    modal.classList.add('is-open');

    // Pin the body where it is. Its own inline styles are remembered and put back on close; the
    // scrollbar's width is added as padding so the page doesn't shift sideways when it goes.
    var body = document.body;
    var scrollbar = window.innerWidth - document.documentElement.clientWidth;
    var padding = parseFloat(getComputedStyle(body).paddingRight) || 0;
    savedBody = {};
    ['overflow', 'position', 'top', 'left', 'right', 'paddingRight'].forEach(function (p) { savedBody[p] = body.style[p]; });
    body.style.overflow = 'hidden';
    body.style.position = 'fixed';
    body.style.top = '-' + scrollPosition + 'px';
    body.style.left = '0';
    body.style.right = '0';
    if (scrollbar > 0) body.style.paddingRight = (padding + scrollbar) + 'px';

    // Quarto's TOC sidebar sits outside the pinned flow: keep it where it is.
    var sidebar = document.querySelector('#quarto-sidebar-toc-left');
    if (sidebar) {
      sidebarSaved = { position: sidebar.style.position, top: sidebar.style.top };
      sidebar.style.position = 'fixed';
      sidebar.style.top = '0';
    }

    // Everything outside the dialog is inert while it is open.
    inerted = Array.prototype.filter.call(body.children, function (el) { return el !== modal && !el.inert; });
    inerted.forEach(function (el) { el.inert = true; });

    syncCaptionRegion();
    if (typeof ResizeObserver === 'function') {
      resizeObserver = new ResizeObserver(syncCaptionRegion);
      resizeObserver.observe(modalCaption);
    }
    closeBtn.focus();
  }

  /**
   * Run a scroll without animation. `behavior: 'instant'` is not portable (older WebKit throws or treats it
   * as `auto`), and the page may set `scroll-behavior: smooth` on html or body (Bootstrap does), so both are
   * set to `auto` for the call and put back after.
   */
  function scrollInstantly(fn) {
    var targets = [document.documentElement, document.body];
    var saved = targets.map(function (el) { return el.style.scrollBehavior; });
    targets.forEach(function (el) { el.style.scrollBehavior = 'auto'; });
    try {
      fn();
    } finally {
      targets.forEach(function (el, i) { el.style.scrollBehavior = saved[i]; });
    }
  }

  /**
   * @param {{returnFocus?: boolean}} [options] returnFocus false (a caption link to this page) keeps
   *   the caption and leaves focus for the caller to move to the link's target.
   */
  function closeModal(options) {
    if (!isOpen()) return;
    var returnFocus = !options || options.returnFocus !== false;
    modal.classList.remove('is-open');
    modal.hidden = true;
    if (resizeObserver) {
      resizeObserver.disconnect();
      resizeObserver = null;
    }
    clearCaptionRegion();
    inerted.forEach(function (el) { el.inert = false; });
    inerted = [];

    var body = document.body;
    Object.keys(savedBody).forEach(function (p) { body.style[p] = savedBody[p]; });
    savedBody = null;
    var sidebar = document.querySelector('#quarto-sidebar-toc-left');
    if (sidebar && sidebarSaved) {
      sidebar.style.position = sidebarSaved.position;
      sidebar.style.top = sidebarSaved.top;
    }
    sidebarSaved = null;

    // Back to the reading position in the same frame the body is unpinned, without animation. A scroll
    // that fails must not stop the cleanup below.
    try {
      scrollInstantly(function () { window.scrollTo(scrollLeft, scrollPosition); });
    } catch (err) { /* the page keeps its own position */ }

    modalImg.removeAttribute('src');
    var back = opener;
    opener = null;
    if (!returnFocus) return;
    modalCaption.replaceChildren();
    if (back && document.contains(back)) back.focus({ preventScroll: true });
  }

  // ── Caption links ──────────────────────────────────────────────────────────

  function onCaptionClick(e) {
    var link = e.target.closest('a[href]');
    if (!link) return;
    var target = link.getAttribute('target');
    // A modified click or a link with its own target keeps the browser default; the viewer stays open.
    if (e.button !== 0 || e.metaKey || e.ctrlKey || e.shiftKey || e.altKey || (target && target !== '_self')) return;

    // Resolve an in-page target before acting on the click; a malformed fragment cannot resolve.
    var dest = null;
    var samePage = link.origin === location.origin && link.pathname === location.pathname &&
      link.search === location.search && link.hash;
    if (samePage) {
      try {
        dest = document.getElementById(decodeURIComponent(link.hash.slice(1)));
      } catch (err) {
        dest = null;
      }
    }
    e.preventDefault();
    if (!dest) {
      // Another page, a missing id or a malformed fragment: close at the figure, then navigate.
      var href = link.href;
      closeModal();
      location.href = href;
      return;
    }

    // In-page: back at the reading position first. After two frames, once that offset is the page's
    // own, write the history entry there (Back returns to the figure), then go to the target.
    var hash = link.hash;
    var href2 = link.href;
    closeModal({ returnFocus: false });
    requestAnimationFrame(function () {
      requestAnimationFrame(function () {
        if (location.hash !== hash) {
          try {
            history.pushState(null, '', hash);
          } catch (err) {
            modalCaption.replaceChildren();
            window.location.href = href2;
            return;
          }
        }
        try {
          scrollInstantly(function () { dest.scrollIntoView({ block: 'start' }); });
        } catch (err) { /* focus below still moves to the target */ }
        if (!dest.matches('a[href], button, input, select, textarea, [tabindex]')) dest.setAttribute('tabindex', '-1');
        dest.focus({ preventScroll: true });
        modalCaption.replaceChildren();
      });
    });
  }

  // ── Keyboard ───────────────────────────────────────────────────────────────

  /** Focusable elements in the dialog, in order: close button, the caption region, caption links. */
  function dialogFocusables() {
    var region = modalCaption.hasAttribute('tabindex') ? [modalCaption] : [];
    return [closeBtn].concat(region, Array.prototype.slice.call(modalCaption.querySelectorAll('a[href]')));
  }

  /** Tab and Shift+Tab wrap inside the dialog (the page behind it is inert). */
  function onModalKeydown(e) {
    if (e.key !== 'Tab' || !isOpen()) return;
    var items = dialogFocusables();
    var first = items[0];
    var last = items[items.length - 1];
    if (e.shiftKey && document.activeElement === first) {
      e.preventDefault();
      last.focus();
    } else if (!e.shiftKey && document.activeElement === last) {
      e.preventDefault();
      first.focus();
    }
  }

  // ── Delegated events ───────────────────────────────────────────────────────

  // Capture phase, so Quarto's lightbox (GLightbox, bound to the a.lightbox wrapper) never sees the
  // click when an author forced `lightbox: true`: one click, one viewer.
  document.addEventListener('click', function (e) {
    if (e.button !== 0 || isOpen()) return;
    var img = triggerFor(e.target);
    if (!img) {
      var forced = e.target.closest ? e.target.closest('a.lightbox') : null;
      var inner = forced && forced.querySelector(TRIGGER);
      img = inner ? triggerFor(inner) : null;
      if (!img) return;
    }
    e.preventDefault();
    e.stopPropagation();
    decorate(img);
    openModal(img);
  }, true);

  document.addEventListener('keydown', function (e) {
    if (isOpen()) {
      if (e.key === 'Escape') closeModal();
      return;
    }
    if (e.key !== 'Enter' && e.key !== ' ') return;
    var img = triggerFor(e.target);
    if (!img || e.target !== img) return;
    e.preventDefault();
    // Enter opens on keydown. Space opens on keyup, on the same trigger: opening on keydown moves focus
    // to the close button, and Firefox then fires a click on that button at the Space keyup.
    if (e.key === ' ') pendingSpace = e.repeat ? pendingSpace : img;
    else openModal(img);
  });

  document.addEventListener('keyup', function (e) {
    if (e.key !== ' ') return;
    var img = pendingSpace;
    pendingSpace = null;
    if (!img || isOpen() || e.target !== img) return;
    e.preventDefault();
    openModal(img);
  });

  function start() {
    decorateAll();
    observeLateTriggers();
  }
  if (document.readyState === 'loading') document.addEventListener('DOMContentLoaded', start);
  else start();
})();
