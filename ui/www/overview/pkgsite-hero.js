// @dataimago/css@0.1.0-alpha.24 dist/quarto/_extensions/dataimago/pkgsite/pkgsite-hero.js · sha256:372b3ff2e24a7f3ce0973f50abc31b491465ba0e973b6cf6f917ea41dd21ea5c · generated from tokens; do not edit · restore: npx -p @dataimago/css@0.1.0-alpha.24 dataimago-sync
/**
 * pkgsite hero loader (spec "Hero inputs"). Loaded only for `hero.kind: js`.
 *
 * The module at `data-hero-src` is imported only when motion is allowed. Its default export is
 * `mount(el, { signal }) -> { pause(), play(), destroy() }`; a result without pause and play is refused
 * (motion-lint cannot see JS, so the contract is enforced here, at runtime). The poster stays visible until a
 * mount succeeds, and on any failure, so the page never breaks. The module and the poster must come from the
 * site's own origin (a data: poster in a raster type is the one exception).
 */

const REDUCED = '(prefers-reduced-motion: reduce)';

const RASTER_DATA = /^data:image\/(png|jpeg|gif|webp)[;,]/i;

export function initHeroes({
  document: doc = globalThis.document,
  window: win = globalThis.window,
  importFn = (href) => import(href),
  console: log = globalThis.console,
} = {}) {
  const none = { destroy() {}, ready: Promise.resolve() };
  if (!doc || !win) return none;
  if (win.matchMedia?.(REDUCED).matches) return none;
  const mounts = [...doc.querySelectorAll('.di-hero-mount')].filter((el) => el.dataset.heroSrc);
  if (mounts.length === 0) return none;

  const ac = new AbortController();
  const box = doc.getElementById('di-hero-pause');
  const live = [];
  let warned = false;
  const warn = (msg, err) => {
    if (warned) return;
    warned = true;
    log.warn(`pkgsite-hero: ${msg}`, err ?? '');
  };
  // Same scheme and origin as the page. blob:https://site/x reports the page's origin, so the scheme is compared
  // too; data: and javascript: have origin "null", and a "null" page origin (file:) matches nothing.
  const sameOrigin = (src) => {
    try {
      const u = new URL(src, doc.baseURI);
      const b = new URL(doc.baseURI);
      return b.origin !== 'null' && u.origin === b.origin && u.protocol === b.protocol;
    } catch { return false; }
  };

  const set = (h, paused) => {
    if (h.paused === paused) return;
    try {
      if (paused) h.api.pause(); else h.api.play();
    } catch (err) {
      return warn(`${h.el.dataset.heroSrc} threw from ${paused ? 'pause' : 'play'}`, err);
    }
    h.paused = paused;
    h.el.dataset.heroState = paused ? 'paused' : 'playing';
  };
  const wanted = () => Boolean(box?.checked) || doc.visibilityState === 'hidden';
  const sync = () => { const p = wanted(); for (const h of live) set(h, p); };
  box?.addEventListener('change', sync, { signal: ac.signal });
  doc.addEventListener('visibilitychange', sync, { signal: ac.signal });

  const ready = Promise.all(mounts.map(async (el) => {
    const src = el.dataset.heroSrc;
    const poster = el.querySelector('img');
    const ps = el.dataset.heroPoster;
    if (poster && ps && !RASTER_DATA.test(ps) && !sameOrigin(ps)) {
      poster.removeAttribute('src');
      warn(`poster ${ps} is not from this site; dropped`);
    }
    if (!sameOrigin(src)) return warn(`${src} is not from this site; keeping the poster`);
    let api;
    try {
      const mod = await importFn(new URL(src, doc.baseURI).href);
      api = await mod.default(el, { signal: ac.signal });
    } catch (err) {
      return warn(`could not load ${src}; keeping the poster`, err);
    }
    if (!api || typeof api.pause !== 'function' || typeof api.play !== 'function') {
      try { api?.destroy?.(); } catch { /* the poster stays either way */ }
      return warn(`${src} must return { pause, play, destroy }; keeping the poster`);
    }
    if (ac.signal.aborted) { try { api.destroy?.(); } catch { /* gone */ } return; }
    const h = { el, api, paused: false };
    el.dataset.heroState = 'playing';
    live.push(h);
    if (poster) poster.hidden = true;
    if (wanted()) set(h, true);
  }));

  return {
    ready,
    destroy() {
      ac.abort();
      for (const h of live) { try { h.api.destroy?.(); } catch { /* already gone */ } }
    },
  };
}

if (typeof document !== 'undefined') initHeroes();
