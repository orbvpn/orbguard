'use strict';
/* ---------- helpers ---------- */
const $ = (s, r) => (r || document).querySelector(s);
const $$ = (s, r) => Array.from((r || document).querySelectorAll(s));
const ic = (n, c) => '<svg class="ic' + (c ? ' ' + c : '') + '" aria-hidden="true"><use href="#i-' + n + '"/></svg>';
const reduce = window.matchMedia && matchMedia('(prefers-reduced-motion: reduce)').matches;
const wait = ms => new Promise(r => setTimeout(r, reduce ? Math.min(ms, 60) : ms));
const ease = t => (t < .5 ? 2 * t * t : 1 - Math.pow(-2 * t + 2, 2) / 2);
function tween(ms, step, done) {
  if (reduce) { step(1); if (done) done(); return; }
  const t0 = performance.now();
  (function f(now) {
    const t = Math.min(1, (now - t0) / ms);
    step(ease(t));
    if (t < 1) requestAnimationFrame(f); else if (done) done();
  })(t0);
}
function countTo(el, from, to, ms) {
  if (!el) return;
  /* figures sit proportionally at rest and go tabular only while they count, so nothing jitters */
  el.classList.add('counting');
  tween(ms || 900, t => { el.textContent = Math.round(from + (to - from) * t); }, () => el.classList.remove('counting'));
}

/* ---------- the Orb: geometry in a 200 unit box, the logo's proportions ---------- */
const G = { c: 100, ro: 96, ri: 52 };
G.r = (G.ro + G.ri) / 2;                       // stroke centre line
G.sw = G.ro - G.ri;                            // ring thickness
G.cap = (G.sw / 2) / G.r * 180 / Math.PI;      // degrees a round cap adds to each end
const GAP_OPEN = 15;                           // visible opening of a gap, in degrees
const pt = (deg, r) => {
  const a = (deg - 90) * Math.PI / 180;
  return [(G.c + r * Math.cos(a)).toFixed(2), (G.c + r * Math.sin(a)).toFixed(2)];
};
function arc(a0, a1, r) {
  r = r || G.r;
  const sweep = (((a1 - a0) % 360) + 360) % 360 || 360;
  const p0 = pt(a0, r), p1 = pt(a1, r);
  return 'M' + p0[0] + ' ' + p0[1] + 'A' + r + ' ' + r + ' 0 ' + (sweep > 180 ? 1 : 0) + ' 1 ' + p1[0] + ' ' + p1[1];
}
const FULL = (() => { const t = pt(0, G.r), b = pt(180, G.r); return 'M' + t[0] + ' ' + t[1] + 'A' + G.r + ' ' + G.r + ' 0 1 1 ' + b[0] + ' ' + b[1] + 'A' + G.r + ' ' + G.r + ' 0 1 1 ' + t[0] + ' ' + t[1] + 'Z'; })();
/* gaps: [{at: degrees clockwise from top, half: half-angle on the centre line}] */
function bodyD(gaps) {
  const g = (gaps || []).filter(x => x.half > .4).sort((a, b) => a.at - b.at);
  if (!g.length) return FULL;
  let d = '';
  g.forEach((x, i) => { const n = g[(i + 1) % g.length]; d += arc(x.at + x.half, n.at - n.half + (i === g.length - 1 ? 360 : 0)); });
  return d;
}
const gapOf = at => ({ at, half: GAP_OPEN / 2 + G.cap });

let orbUid = 0;
/* the kit's Spectrum (logo and hero only) as a soft light that patrols the ring */
const GLINT = [['#FFFFFF', .2, 0, 9], ['#FFFFFF', .46, -15, 0], ['#7FE6A8', .46, -31, -15], ['#53D2D8', .4, -47, -31], ['#9FB1E6', .32, -63, -47], ['#C79BD6', .22, -80, -63]];
function orb(o) {
  o = o || {};
  const u = ++orbUid, size = o.size || 224;
  const gaps = (o.gaps || []).map(gapOf);
  const d = bodyD(gaps);
  const stops = [0, .2, .4, .6, .8, 1].map((t, i) => '<stop offset="' + t + '" style="stop-color:var(--orb-' + i + ')"/>').join('');
  const cls = ['orb', o.mode === 'fresh' ? 'fresh' : '', o.mode === 'check' ? 'checking' : '', o.still ? 'still' : '', o.live && !o.still ? 'is-live' : '', gaps.length ? 'care' : ''].filter(Boolean).join(' ');
  let s = '<svg viewBox="0 0 200 200" aria-hidden="true"><defs>'
    + '<radialGradient id="ob' + u + '" gradientUnits="userSpaceOnUse" cx="80" cy="78" r="124">' + stops + '</radialGradient>'
    + '<linearGradient id="ol' + u + '" gradientUnits="userSpaceOnUse" x1="20" y1="20" x2="180" y2="180"><stop offset="0" stop-color="#fff" stop-opacity=".18"/><stop offset=".42" stop-color="#fff" stop-opacity="0"/><stop offset="1" stop-color="#000" stop-opacity=".14"/></linearGradient>'
    + '<filter id="of' + u + '" x="-40%" y="-40%" width="180%" height="180%"><feGaussianBlur stdDeviation="8"/></filter>'
    + '<filter id="od' + u + '" x="-20%" y="-20%" width="140%" height="140%"><feGaussianBlur stdDeviation="3.2"/></filter>'
    + '<filter id="oh' + u + '" x="-20%" y="-20%" width="140%" height="140%"><feGaussianBlur stdDeviation="1.7"/></filter>'
    + '<mask id="om' + u + '" maskUnits="userSpaceOnUse" x="0" y="0" width="200" height="200"><path class="orb-bp" d="' + d + '" stroke="#fff" stroke-width="' + G.sw + '" fill="none" stroke-linecap="round"/></mask>'
    + '</defs>'
    + '<circle class="orb-track" cx="100" cy="100" r="' + G.r + '" stroke-width="' + G.sw + '"/>'
    + '<circle class="orb-dots" cx="100" cy="100" r="' + G.r + '" stroke-width="3.2"/>'
    + '<g class="orb-body"><path class="orb-bp" d="' + d + '" stroke="url(#ob' + u + ')" stroke-width="' + G.sw + '"/>'
    + '<path class="orb-bp" d="' + d + '" stroke="url(#ol' + u + ')" stroke-width="' + G.sw + '"/></g>'
    + '<g class="orb-depth" mask="url(#om' + u + ')">'
    + '<circle cx="100" cy="100" r="' + (G.ri + 1) + '" fill="none" stroke="#12300A" stroke-opacity=".28" stroke-width="8" filter="url(#od' + u + ')"/>'
    + '<circle cx="100" cy="100" r="' + (G.ro - 1) + '" fill="none" stroke="#12300A" stroke-opacity=".2" stroke-width="6" filter="url(#od' + u + ')"/>'
    + '<path d="' + arc(-62, 14, G.ro - 9) + '" fill="none" stroke="#fff" stroke-opacity=".62" stroke-width="3.4" stroke-linecap="round" filter="url(#oh' + u + ')"/>'
    + '</g>'
    + '<g class="orb-glint-wrap" mask="url(#om' + u + ')"><g class="orb-glint" filter="url(#of' + u + ')">'
    + GLINT.map(a => '<path d="' + arc(a[2], a[3]) + '" stroke="' + a[0] + '" stroke-opacity="' + a[1] + '" stroke-width="' + (G.sw + 10) + '"/>').join('')
    + '</g></g>'
    + '<g class="orb-segs"></g>'
    + gaps.map(g => { const p = pt(g.at, G.r); return '<circle class="orb-spark" cx="' + p[0] + '" cy="' + p[1] + '" r="4.6"/>'; }).join('')
    + '</svg>';
  return '<div class="' + cls + '" data-u="' + u + '" data-gaps="' + (o.gaps || []).join(',') + '"' + (o.segs ? ' data-segs="' + o.segs.join(',') + '"' : '') + ' style="--d:' + size + 'px">'
    + (o.tap ? '<button class="orb-tap" data-act="' + o.tap + '" aria-label="' + (o.tapLabel || 'Check now') + '"></button>' : '')
    + s + '<div class="orb-hole">' + (o.hole || '') + '</div></div>';
}
/* close every gap: the ends travel toward each other until the circle is whole */
function orbClose(el, done) {
  if (!el) return;
  const ats = (el.dataset.gaps || '').split(',').filter(Boolean).map(Number);
  const paths = $$('.orb-bp', el), h0 = GAP_OPEN / 2 + G.cap;
  $$('.orb-spark', el).forEach(n => n.remove());
  tween(820, t => {
    const d = bodyD(ats.map(at => ({ at, half: h0 * (1 - t) })));
    paths.forEach(p => p.setAttribute('d', d));
  }, () => {
    el.dataset.gaps = '';
    el.classList.remove('care');
    orbFlash(el);
    if (done) done();
  });
}
function orbFlash(el) { el.classList.remove('flash'); void el.offsetWidth; el.classList.add('flash'); setTimeout(() => el.classList.remove('flash'), 950); }
/* check mode: one segment per check that can really run on this device */
function orbSegs(el, states) {
  const u = el.dataset.u, n = states.length, pad = n > 7 ? 2.2 : 3;
  el.classList.add('checking'); el.classList.remove('fresh');
  $('.orb-segs', el).innerHTML = states.map((st, i) => {
    const a0 = i * 360 / n + pad, a1 = (i + 1) * 360 / n - pad;
    return '<path class="seg ' + st + '" d="' + arc(a0, a1) + '" stroke-width="' + G.sw + '"' + (st === 'on' ? ' style="stroke:url(#ob' + u + ')"' : '') + '/>';
  }).join('');
}
function orbSeg(el, i, st) {
  const p = $$('.seg', el)[i]; if (!p) return;
  p.setAttribute('class', 'seg ' + st);
  p.style.stroke = st === 'on' ? 'url(#ob' + el.dataset.u + ')' : '';
}
/* static frames describe their segments in markup; this turns them into arcs */
function hydrate(scope) {
  $$('.orb[data-segs]', scope).forEach(el => { orbSegs(el, el.dataset.segs.split(',')); el.removeAttribute('data-segs'); });
}
function orbWhole(el) {
  el.classList.remove('checking', 'fresh', 'care');
  $$('.orb-bp', el).forEach(p => p.setAttribute('d', FULL));
  el.dataset.gaps = '';
  orbFlash(el);
}

/* ---------- tiny sound layer: soft tones, off until asked for ---------- */
const Sound = (() => {
  let ctx = null, on = false;
  function tone(f, dur, type, vol, delay) {
    if (!on) return;
    try {
      ctx = ctx || new (window.AudioContext || window.webkitAudioContext)();
      if (ctx.state === 'suspended') ctx.resume();
      const t = ctx.currentTime + (delay || 0), o = ctx.createOscillator(), g = ctx.createGain();
      o.type = type || 'sine'; o.frequency.setValueAtTime(f, t); o.connect(g); g.connect(ctx.destination);
      g.gain.setValueAtTime(0, t); g.gain.linearRampToValueAtTime(vol || .05, t + .012); g.gain.exponentialRampToValueAtTime(.0001, t + dur);
      o.start(t); o.stop(t + dur + .03);
    } catch (e) { on = false; }
  }
  return {
    set(v) { on = v; if (v) tone(620, .12, 'sine', .04); },
    tap() { tone(540, .09, 'sine', .035); },
    tick(i) { tone(520 + (i || 0) * 34, .08, 'sine', .03); },
    whole() { tone(523, .16, 'sine', .045); tone(659, .18, 'sine', .045, .09); tone(784, .34, 'sine', .05, .19); },
    care() { tone(440, .2, 'triangle', .04); tone(392, .28, 'triangle', .035, .14); }
  };
})();
