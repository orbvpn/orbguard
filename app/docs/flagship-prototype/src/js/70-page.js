/* ---------- the page around the devices: every exhibit is drawn by the same functions as the live app ---------- */
const slot = (name, html) => { const el = $('[data-slot="' + name + '"]'); if (el) el.innerHTML = html; return el; };
const moonChip = (cls, icon) => '<span class="moon ' + cls + '">' + ic(icon) + '</span>';

function buildStates() {
  const st = (o, name, line) => '<div class="p-state">' + orb(Object.assign({ size: 128 }, o)) + '<p class="t-title">' + name + '</p><p class="t-small">' + line + '</p></div>';
  return st({ live: true, hole: '<span class="orb-num">1000</span>' }, 'Whole', 'Covered. Every check that can run came back clean.')
    + st({ live: true, gaps: [150], hole: '<span class="orb-num">900</span>' }, 'A gap', 'One thing to fix. It opens toward the shield that found it.')
    + st({ mode: 'check', segs: ['on', 'on', 'now', 'off', 'off'], hole: '<span class="orb-num">2<small>/5</small></span>' }, 'Segments', 'Checking. One segment for each check this device can run.')
    + st({ mode: 'fresh' }, 'Dotted', 'Not checked yet. Nothing is claimed before the first check.')
    + st({ still: true, hole: '<span class="orb-num">1000</span>' }, 'Still', 'Paused. The ring only moves while something is really running.')
    + '<div class="p-state"><div class="p-moons">' + moonChip('on', 'magnifer_bug') + moonChip('care', 'user_id') + moonChip('off', 'eye_scan') + '</div><p class="t-title">The shields</p><p class="t-small">On, needs you, or not possible here. A shield that cannot run is never green.</p></div>';
}

const WALL = [
  [{ view: onboardView, nav: false, S: { slide: 0 } }, 'First run', 'The ring starts dotted. Nothing is claimed yet.'],
  [{ view: primeView, nav: false }, 'Permissions', 'Asked once, with the reason first.'],
  [{}, 'Home, all clear', 'One verdict, one proof line, one action.'],
  [{ view: scanStill, nav: false }, 'A check, running', 'Five segments, because five checks can run on iPhone.'],
  [{ sheet: 'results' }, 'Results', 'Only what ran is counted. The rest is named.'],
  [{ S: { moment: 'gap' } }, 'Home, one gap', 'The ring opens toward the shield that found it.'],
  [{ S: { moment: 'gap' }, sheet: 'fix' }, 'Closing the gap', 'Plain steps, then the ring joins.'],
  [{ S: { moment: 'gap' }, sheet: 'score' }, 'The score', 'It shows its working, in the engine’s own numbers.'],
  [{ S: { tab: 'protect' } }, 'Protect', 'Six shields, each reporting in a sentence.'],
  [{ S: { tab: 'protect', detail: 'who' } }, 'A shield, honestly', 'What iPhone does not allow is said out loud.'],
  [{ S: { tab: 'check' } }, 'Check', 'One box for links, messages and numbers.'],
  [{ S: { tab: 'check', paste: 'done' } }, 'A scam, caught', 'A verdict, three reasons, one instruction.'],
  [{ S: { tab: 'me' } }, 'Me', 'Account, plan, then the quiet settings.'],
  [{ S: { tab: 'me' }, sheet: 'plans' }, 'The point of sale', 'Real tiers and prices. One plan, three apps.'],
  [{ S: { tab: 'me', credits: 0 }, sheet: 'credits' }, 'Out of credits', 'Earn one or go unlimited. Never a dead end.'],
  [{ S: { theme: 'light' } }, 'Light', 'The cloud theme, from the same kit.']
];
/* each frame fills its column, so four fit across at any desktop width */
const buildWall = () => WALL.map(w => '<figure>' + fit(frame(w[0]), 413, 872, .62, 'data-fit=".72"') + '<figcaption><b>' + w[1] + '</b><span>' + w[2] + '</span></figcaption></figure>').join('');

/* ---------- sell kit ---------- */
const SHOTS = [
  ['Know if you’re<br>being watched.', {}],
  ['One tap.<br>A clear answer.', { view: scanStill, nav: false }],
  ['See the gap.<br>Close it.', { S: { moment: 'gap' } }],
  ['Six shields that<br>report back.', { S: { tab: 'protect' } }],
  ['Honest about<br>its limits.', { sheet: 'results' }]
];
const buildShots = () => SHOTS.map(s => '<figure class="shot os" data-app="dark"><div class="bed"></div><p class="shot-h">' + s[0] + '</p><div class="shot-dev">' + fit(frame(s[1]), 413, 872, .46, 'data-fit="1"') + '</div></figure>').join('');

function buildAds() {
  const lock = px => '<span class="ad-lock">' + ringMark(px) + 'OrbGuard</span>';
  const fig = (html, cap, cls) => '<figure class="ad-fig' + (cls ? ' ' + cls : '') + '">' + html + '<figcaption>' + cap + '</figcaption></figure>';
  return fig('<div class="ad ad-sq os" data-app="dark" data-ad><div class="bed"></div><div class="ad-orb" data-ad-orb>' + orb({ size: 148, gaps: [150], live: true }) + '</div>'
    + '<p class="ad-h">Is your circle closed?</p><p class="ad-s">One tap. A clear answer.</p><div class="ad-foot">' + lock(18) + '<span class="ad-cta">Check yours</span></div></div>', 'Square post, 1080 by 1080. The gap closes on a loop.')
    + fig('<div class="ad ad-st os still-all" data-app="dark"><div class="bed"></div>' + orb({ size: 112 }) + '<p class="ad-h">Know if you’re being watched.</p><span class="ad-cta">Get OrbGuard</span>' + lock(16) + '</div>', 'Story, 9 by 16', 'ad-fig-st')
    + '<div class="ad-col">'
    + fig(fit('<div class="ad ad-bn os still-all" data-app="dark"><div class="bed"></div>' + orb({ size: 58, gaps: [150] }) + '<p class="ad-h">Is your circle closed?</p>' + lock(17) + '<span class="ad-cta">Check yours</span></div>', 728, 90, .5, 'data-fit="1"'), 'Leaderboard, 728 by 90')
    + '<div class="ad-row">'
    + fig('<div class="ad ad-list os still-all" data-app="dark"><div class="bed"></div><span class="ad-icon">' + ringMark(38) + '</span><span class="grow"><b>OrbGuard</b><small>Know if you’re being watched</small></span><span class="ad-cta">Get</span></div>', 'Store search result')
    + fig('<div class="ad ad-mb os still-all" data-app="light"><div class="bed"></div>' + orb({ size: 34 }) + '<p class="ad-h">Know if you’re being watched.</p><span class="ad-cta">Get it</span></div>', 'Mobile banner, 320 by 50, light')
    + '</div>'
    + fig('<div class="ad-search"><small><b>Sponsored</b> guard.orbai.world</small><b>Is your phone being watched? Check it in one tap</b>'
      + '<p>OrbGuard checks for spyware, stalkerware and trackers, then tells you plainly what it found. Free to start.</p></div>', 'Search ad')
    + '</div>';
}
function buildLanding() {
  return '<div class="web os" data-app="dark"><div class="web-bar"><i></i><i></i><i></i><span>guard.orbai.world</span></div><div class="web-body"><div class="bed"></div>'
    + '<div class="web-copy"><span class="ad-lock">' + ringMark(22) + 'OrbGuard</span><h3>Is your circle closed?</h3>'
    + '<p>OrbGuard checks your phone for spyware, stalkerware and trackers, then tells you plainly what it found.</p>'
    + '<div class="web-btns"><span class="btn lime sm">Get OrbGuard</span><span class="btn plain sm">See plans</span></div><small>iPhone, Android, Mac, Windows and Linux</small></div>'
    + '<div class="web-dev">' + fit(frame({}), 413, 872, .56, 'data-fit=".62"') + '</div></div></div>';
}
function buildWidgets() {
  const mono = '<svg width="34" height="34" viewBox="0 0 100 100" aria-hidden="true"><circle cx="50" cy="50" r="34" fill="none" stroke="currentColor" stroke-width="22"/></svg>';
  return '<div class="paper os still-all" data-app="dark"><div class="bed"></div>'
    + '<div class="wg wg-s">' + orb({ size: 92, hole: '<span class="orb-num">1000</span>' }) + '<div><b>All clear</b></div></div>'
    + '<div class="wg wg-m">' + orb({ size: 92, gaps: [150], hole: '<span class="orb-num">900</span>' }) + '<div><b>One gap to close</b><small>Your email was in a data breach</small>' + chip('care', 'Open OrbGuard') + '</div></div>'
    + '<div class="wg-lock"><span class="wg-c" style="color:var(--text)">' + mono + '</span><span class="wg-r"><b>OrbGuard</b><small>All clear, checked 2 min ago</small></span></div></div>'
    + '<div class="p-share os still-all" data-app="dark">' + shareCard() + '</div>';
}

/* ---------- controls ---------- */
function seg(name, pick) {
  const box = $('[data-seg="' + name + '"]'); if (!box) return () => {};
  const mark = v => $$('button', box).forEach(b => b.setAttribute('aria-pressed', String(b.dataset.v === v)));
  box.addEventListener('click', e => { const b = e.target.closest('button'); if (b && pick(b.dataset.v) !== false) mark(b.dataset.v); });
  return mark;
}
function fitAll() {
  $$('.fit[data-fit]').forEach(f => {
    const host = f.parentElement, cs = getComputedStyle(host);
    const avail = host.clientWidth - parseFloat(cs.paddingLeft) - parseFloat(cs.paddingRight);
    if (!(avail > 0)) return;
    const s = Math.max(+f.dataset.min || 0, Math.min(+f.dataset.fit || 1, avail / +f.dataset.w));
    f.style.setProperty('--s', s.toFixed(4));
  });
}
