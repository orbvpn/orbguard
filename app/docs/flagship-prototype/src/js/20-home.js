/* ---------- shared screen parts ---------- */
const SYS = '<span class="sys">'
  + '<svg width="18" height="12" viewBox="0 0 18 12"><rect x="0" y="8" width="3" height="4" rx=".8"/><rect x="5" y="5.5" width="3" height="6.5" rx=".8"/><rect x="10" y="3" width="3" height="9" rx=".8"/><rect x="15" y="0" width="3" height="12" rx=".8"/></svg>'
  + '<svg width="17" height="12" viewBox="0 0 17 12"><path d="M8.5 2.6c2.3 0 4.4.9 6 2.4l1.1-1.2A10.3 10.3 0 0 0 8.5 1 10.3 10.3 0 0 0 1.4 3.8L2.5 5a8.6 8.6 0 0 1 6-2.4Zm0 3.5c1.4 0 2.6.5 3.6 1.4l1.1-1.2a7 7 0 0 0-9.4 0l1.1 1.2c1-.9 2.2-1.4 3.6-1.4Zm0 3.4c-.7 0-1.3.3-1.8.7l1.8 1.8 1.8-1.8c-.5-.4-1.1-.7-1.8-.7Z"/></svg>'
  + '<svg width="27" height="13" viewBox="0 0 27 13"><rect x=".5" y=".5" width="23" height="12" rx="3.6" fill="none" stroke="currentColor" opacity=".4"/><rect x="2" y="2" width="20" height="9" rx="2.2"/><rect x="25" y="4.2" width="1.6" height="4.6" rx=".8" opacity=".45"/></svg>'
  + '</span>';
const statusBar = t => '<div class="sbar"><span>' + (t || '9:41') + '</span>' + SYS + '</div>';

const TABS = [['home', 'home_smile', 'Home'], ['protect', 'shield_check', 'Protect'], ['check', 'magnifer', 'Check'], ['me', 'user_rounded', 'Me']];
const navBar = on => '<nav class="nav" aria-label="Main">' + TABS.map(t =>
  '<button data-tab="' + t[0] + '"' + (t[0] === on ? ' class="on" aria-current="page"' : '') + '>' + ic(t[1]) + t[2] + '</button>').join('') + '</nav>';

const chev = () => ic('alt_arrow_right');
const chip = (kind, text, dot) => '<span class="chip ' + kind + '">' + (dot ? '<i></i>' : '') + text + '</span>';
function row(o) {
  const tag = o.attr ? 'button' : 'div';
  return '<' + tag + ' class="row' + (o.cls ? ' ' + o.cls : '') + '"' + (o.attr ? ' ' + o.attr : '') + '>'
    + (o.icon ? '<span class="tile' + (o.tone ? ' ' + o.tone : '') + '">' + ic(o.icon) + '</span>' : '')
    + '<span class="grow"><span class="t-title">' + o.title + '</span>' + (o.sub ? '<span class="sub">' + o.sub + '</span>' : '') + '</span>'
    + (o.end ? '<span class="end">' + o.end + '</span>' : '') + '</' + tag + '>';
}
/* a shield's state on this device, at this moment */
function shieldState(S, id) {
  const D = DEVICES[S.dev];
  if (S.moment === 'fresh') return D.shields[id] === 'off' ? 'off' : 'idle';
  if (S.moment === 'gap' && id === 'id') return 'care';
  return D.shields[id];
}
function shieldChip(S, id) {
  const st = shieldState(S, id);
  if (st === 'on') return chip('on', 'On', true);
  if (st === 'care') return chip('care', '1 gap', true);
  if (st === 'idle') return chip('mute', 'Not yet');
  return chip('mute', SHORT_LIMIT[st]);
}
function shieldLine(S, id) {
  const st = shieldState(S, id);
  if (st === 'care') return 'Your email was in a data breach';
  if (st === 'idle') return shield(id).what;
  return DEVICES[S.dev].report[id];
}

/* the six shields stationed around the Orb; a gap always opens toward its shield */
function moons(S, R) {
  return SHIELDS.map(sh => {
    const a = (sh.at - 90) * Math.PI / 180, st = shieldState(S, sh.id);
    const cls = st === 'on' ? 'on' : st === 'care' ? 'care' : st === 'limited' ? 'limited' : 'off';
    return '<button class="moon ' + cls + '" data-shield="' + sh.id + '" aria-label="' + esc(sh.name) + '" style="--x:'
      + (R * Math.cos(a)).toFixed(1) + 'px;--y:' + (R * Math.sin(a)).toFixed(1) + 'px">' + ic(sh.icon) + '</button>';
  }).join('');
}

/* the day as a strip: every mark is something the guard really did */
function dayStrip(D) {
  const x = h => (h / 24 * 100).toFixed(2) + '%';
  return '<div class="day"><div class="day-line"></div>'
    + D.blocks.map(h => '<i class="blk" style="left:' + x(h) + '"></i>').join('')
    + D.marks.map(h => '<i class="chk" style="left:' + x(h) + '"></i>').join('')
    + '<i class="nowm" style="left:' + x(21.7) + '"></i>'
    + '<div class="day-ax"><span>00</span><span>06</span><span>12</span><span>18</span><span>24</span></div></div>';
}
const feedRows = (D, n) => D.feed.slice(0, n || 3).map(f =>
  '<div class="frow">' + ic(f.icon) + '<span class="grow">' + esc(f.text) + '</span><span class="t-mono">' + f.at + '</span></div>').join('');
/* bare: for a pane whose own title already says Today, so the word is never printed twice */
function todayCard(S, n, bare) {
  const D = DEVICES[S.dev], open = '<div class="glass pad today' + (bare ? ' flush' : '') + '">';
  if (S.moment === 'fresh') return open + (bare ? '' : '<span class="t-label">Today</span>')
    + '<p class="t-body"' + (bare ? '' : ' style="margin-top:10px"') + '>Nothing yet. Your first check starts the record.</p></div>';
  return open + (bare ? '' : '<div class="line"><span class="t-label grow">Today</span><span class="t-small">' + D.today + '</span></div>')
    + dayStrip(D) + '<div class="feed">' + feedRows(D, n || 3) + '</div></div>';
}

/* ---------- HOME ---------- */
const HOME = {
  clear: { score: 1000, head: 'No signs you’re being watched.', gaps: [] },
  gap:   { score: 900,  head: 'One gap to close.', gaps: [150] },
  fresh: { score: null, head: 'Let’s check your phone.', gaps: [] }
};
const cleanText = S => 'All ' + DEVICES[S.dev].runs.length + ' checks clean, 2 min ago';
const cleanLine = S => '<i class="live"></i><span data-report>' + cleanText(S) + '</span>';
const HERO_SIZE = { phone: [224, 150], cover: [204, 136], fold: [216, 144], desk: [264, 176] };
function heroBlock(S) {
  const H = HOME[S.moment], hs = HERO_SIZE[S.layout || 'phone'], size = hs[0], R = hs[1];
  const hole = S.moment === 'fresh'
    ? '<span class="orb-cap">Not checked yet</span>'
    : '<span class="orb-num" data-score>' + H.score + '</span><span class="orb-cap">privacy score</span>';
  return '<div class="hero" style="--orbit:' + R + 'px"><div class="orbit"></div>' + moons(S, R)
    + orb({ size, live: S.moment !== 'fresh', mode: S.moment === 'fresh' ? 'fresh' : '', gaps: H.gaps, hole,
      tap: S.moment === 'fresh' ? 'check' : 'score', tapLabel: S.moment === 'fresh' ? 'Run my first check' : 'How your score adds up' })
    + '</div>';
}
function careCard(S) {
  return '<div class="glass amber pad care-card">'
    + '<div class="line" style="gap:13px;align-items:flex-start"><span class="tile amber">' + ic('user_id') + '</span><div class="grow">'
    + '<p class="t-title">Your email was in a data breach</p>'
    + '<p class="t-small" style="margin-top:3px">' + PERSON.email + ' and its password leaked from ' + PERSON.breach + '.</p></div></div>'
    + '<button class="btn lime sm" data-act="fix" style="margin-top:16px">Close the gap</button>'
    + '<p class="t-small gain">Closing it adds 100 to your score</p></div>';
}
function homeActions(S) {
  const noun = DEVICES[S.dev].noun;
  if (S.moment === 'clear') return '<p class="proof">' + cleanLine(S) + '</p><div class="home-act"><button class="btn lime" data-act="check">Check now</button></div>';
  if (S.moment === 'gap') return '<p class="proof"><i class="live amber"></i><span>Everything else is clean</span></p><div class="home-act">' + careCard(S) + '</div>';
  return '<p class="proof"><span>One tap. About 20 seconds on this ' + noun + '.</span></p><div class="home-act"><button class="btn lime" data-act="check">Run my first check</button></div>';
}
const verdictText = S => HOME[S.moment].head.replace('phone', DEVICES[S.dev].noun);
function homeView(S) {
  const two = S.layout === 'fold' || S.layout === 'desk';
  return '<div class="scroll home">'
    + (S.layout === 'desk' ? '' : '<div class="topbar"><span class="trust">' + ic('lock_keyhole') + 'Private by design</span><span class="grow"></span>'
      + '<button class="circ" data-sheet="alerts" aria-label="Alerts">' + ic('bell') + (S.moment === 'gap' ? '<i class="badge"></i>' : '') + '</button>'
      + '<button class="circ avatar" data-tab="me" aria-label="Account">' + PERSON.initial + '</button></div>')
    + heroBlock(S)
    + '<h1 class="t-display verdict" data-verdict>' + verdictText(S) + '</h1>'
    + '<div data-home-act>' + homeActions(S) + '</div>'
    + (two ? '' : todayCard(S))
    + '</div>';
}
