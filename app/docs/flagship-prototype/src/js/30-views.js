/* ---------- PROTECT: six shields, each reporting in its own words ---------- */
const sect = t => '<h2 class="t-label sect-label">' + t + '</h2>';
const pagehead = (t, sub) => '<div class="pagehead"><div class="grow"><h1 class="t-h2">' + t + '</h1>' + (sub ? '<p class="t-small">' + sub + '</p>' : '') + '</div></div>';
const toneOf = (S, id) => { const st = shieldState(S, id); return st === 'care' ? 'amber' : st === 'on' ? '' : 'mute'; };
const lrow = (icon, tone, text) => '<div class="lrow">' + ic(icon, tone) + '<span class="grow">' + text + '</span></div>';

function shieldRows(S) {
  return '<div class="glass rows">' + SHIELDS.map(sh => row({
    icon: sh.icon, tone: toneOf(S, sh.id), title: esc(sh.name), sub: shieldLine(S, sh.id),
    end: shieldChip(S, sh.id) + chev(), attr: 'data-shield="' + sh.id + '"'
  })).join('') + '</div>';
}
function protectView(S) {
  const D = DEVICES[S.dev];
  return '<div class="scroll">' + pagehead('Protect', 'Six shields. Each one tells you what it did.')
    + shieldRows(S)
    + (D.desk ? '' : sect('Lost or stolen') + '<div class="glass rows">' + row({
      icon: 'map_point_wave', tone: 'mute', title: 'Find this phone', sub: 'Locate it, ring it, or photograph whoever has it',
      end: chip('mute', 'Set up') + chev(), attr: 'data-sheet="lost"' }) + '</div>')
    + '</div>';
}
/* compact shields for the wide layouts: the same six, as tiles */
function shieldGrid(S) {
  return '<div class="sgrid">' + SHIELDS.map(sh => {
    const st = shieldState(S, sh.id);
    return '<button class="glass stile ' + st + '" data-shield="' + sh.id + '"><span class="line"><span class="tile sm ' + toneOf(S, sh.id) + '">' + ic(sh.icon) + '</span><span class="grow"></span>' + shieldChip(S, sh.id) + '</span>'
      + '<span class="t-title">' + esc(sh.name) + '</span></button>';
  }).join('') + '</div>';
}

/* ---------- SHIELD DETAIL: what it does, and what this device cannot ---------- */
function detailView(S, id) {
  const sh = shield(id), D = DEVICES[S.dev], dt = shieldDetail(S, id), tone = toneOf(S, id);
  let h = '<div class="scroll">'
    + '<div class="pagehead"><button class="circ" data-back aria-label="Back">' + ic('alt_arrow_left') + '</button><span class="grow"></span>' + shieldChip(S, id) + '</div>'
    + '<div class="d-hero"><span class="d-ic ' + tone + '">' + ic(sh.icon) + '</span><h1 class="t-h2">' + esc(sh.name) + '</h1><p class="t-body">' + dt.lead + '</p></div>'
    + '<div class="glass pad d-now"><span class="t-label">Right now</span><p class="t-title">' + shieldLine(S, id) + '</p></div>';
  if (dt.log) h += '<div class="glass pad d-log"><div class="line"><span class="t-label grow">Blocked today</span><span class="t-mono ink-pink">23</span></div>' + dayStrip(D) + '</div>';
  if (dt.covers.length) h += sect('What it checks') + '<div class="glass lrows">' + dt.covers.map(c => lrow('check_circle', 'ink-lime', c)).join('') + '</div>';
  if (dt.cant.length) h += sect('Not possible here') + '<div class="glass lrows dim">' + dt.cant.map(c => lrow('forbidden_circle', 'ink-3', c)).join('') + '</div><p class="t-small note">' + dt.why + '</p>';
  if (dt.note) h += '<p class="t-small note">' + dt.note + '</p>';
  if (dt.act) h += '<div class="d-act"><button class="btn ' + dt.act[2] + '" data-act="' + esc(dt.act[0]) + '">' + dt.act[1] + '</button></div>';
  return h + '</div>';
}

/* ---------- CHECK: ask about one thing, right now ---------- */
function pasteCard(S) {
  const st = S.paste || 'empty';
  let h = '<div class="glass pad paste"><div class="paste-box' + (st === 'empty' ? '' : ' has') + '">'
    + (st === 'empty' ? '<span class="ph">Paste a link, message or number</span>' : esc(SAMPLE_TEXT)) + '</div>';
  if (st === 'busy') h += '<p class="proof" style="text-align:left;margin:14px 2px 2px"><i class="live"></i><span>Checking this message</span></p>';
  if (st === 'done') h += '<div class="verdict-card"><span class="tile amber">' + ic('danger_triangle') + '</span><div class="grow"><p class="t-title">This looks like a scam</p>'
    + '<ul class="why">' + SAMPLE_WHY.map(w => '<li>' + w + '</li>').join('') + '</ul><p class="t-small" style="margin-top:8px;color:var(--text)">Do not open the link. Delete the message.</p></div></div>';
  h += '<div class="btn-row" style="margin-top:14px">'
    + (st === 'done' ? '<button class="btn plain sm" data-act="paste-clear">Check something else</button>'
      : '<button class="btn plain sm" data-act="example">Try an example</button><button class="btn lime sm" data-act="paste-check">Check it</button>')
    + '</div></div>';
  return h;
}
function checkView(S) {
  const D = DEVICES[S.dev], n = D.runs.length, all = toolsFor(S.dev);
  /* tiles fill whole rows only; a tool left over joins the list below, so no tile ever sits alone */
  const cols = S.layout === 'desk' ? 3 : 2, over = all.length % cols;
  const tiles = over ? all.slice(0, -over) : all, rest = over ? all.slice(-over) : [];
  return '<div class="scroll">' + pagehead('Check', 'Not sure about something? Ask.')
    + '<div data-paste>' + pasteCard(S) + '</div>'
    + sect('Quick checks')
    + '<div class="tools">' + tiles.map(t => '<button class="glass tool" data-tool="' + t.id + '"><span class="tile">' + ic(t.icon) + '</span><span class="t-title">' + t.name + '</span><span class="t-small">' + t.sub + '</span></button>').join('') + '</div>'
    + '<div class="glass rows" style="margin-top:12px">'
    + rest.map(t => row({ icon: t.icon, title: t.name, sub: t.sub, end: chev(), attr: 'data-tool="' + t.id + '"' })).join('')
    + row({ icon: 'shield_check', title: 'Full privacy check', sub: 'All ' + n + ' checks this ' + D.noun + ' can run', end: chev(), attr: 'data-act="check"' }) + '</div>'
    + '</div>';
}

/* ---------- ME: account, plan, and the expert tools ---------- */
function planCard(S) {
  if (S.plan) {
    const p = plan(S.plan);
    return '<div class="glass pad plan"><div class="line"><p class="t-head grow">' + p.name + ' plan</p>' + chip('on', 'Unlimited checks', true) + '</div>'
      + '<p class="t-small">Also unlocks OrbVPN and OrbBrowser premium.</p></div>';
  }
  return '<div class="glass pad plan"><div class="line"><p class="t-head grow">Free plan</p>'
    + '<button class="chip ' + (S.credits ? 'mute' : 'care') + '" data-sheet="credits">' + S.credits + (S.credits === 1 ? ' scan credit' : ' scan credits') + '</button></div>'
    + '<p class="t-small">Each check you start uses one credit.</p>'
    + '<div class="btn-row"><button class="btn plain sm" data-sheet="credits">Earn a credit</button><button class="btn lime sm" data-sheet="plans">Go unlimited</button></div></div>';
}
function meView(S) {
  const light = S.theme === 'light';
  return '<div class="scroll">' + pagehead('Me')
    + '<div class="glass pad acct"><div class="line" style="gap:14px"><span class="circ avatar big">' + PERSON.initial + '</span><div class="grow"><p class="t-title">' + PERSON.name + '</p><p class="t-small">' + PERSON.email + '</p></div></div>'
    + '<p class="t-small acct-note">' + ic('verified_check') + '<span>One OrbVPN account for OrbGuard, OrbVPN and OrbBrowser</span></p></div>'
    + '<div data-plan style="margin-top:12px">' + planCard(S) + '</div>'
    + '<div class="glass rows" style="margin-top:12px">'
    + row({ icon: 'bell', title: 'Alerts', sub: 'Only what needs you', end: chip('on', 'On', true) + chev(), attr: 'data-sheet="alerts"' })
    + row({ icon: light ? 'sun_2' : 'moon', title: 'Appearance', sub: 'The same kit as OrbVPN', end: chip('mute', light ? 'Light' : 'Dark') + '<i class="nochev"></i>', attr: 'data-act="theme"' })
    + row({ icon: 'lock_keyhole', title: 'Privacy', sub: 'What OrbGuard can and cannot see', end: chev(), attr: 'data-sheet="privacy"' })
    + row({ icon: 'tuning_2', tone: 'mute', title: 'Pro tools', sub: 'Threat intel, forensics and network tools', end: chip('mute', '34') + chev(), attr: 'data-sheet="pro"' })
    + '</div></div>';
}

/* ---------- the check, as a list that fills in ---------- */
function scanList(S) {
  return '<div class="clist">' + deviceChecks(S.dev).filter(c => c.run).map((c, i) =>
    '<div class="crow" data-ci="' + i + '"><i></i><span class="grow">' + c.name + '</span></div>').join('') + '</div>';
}
function scanPane(S) {
  const D = DEVICES[S.dev];
  return '<div class="scroll">' + pagehead('Checking', 'Only what this ' + D.noun + ' can really run.') + '<div class="glass pad">' + scanList(S) + '</div></div>';
}
/* the second pane on wide screens, when Home is selected */
function todayPane(S) {
  return '<div class="scroll">' + pagehead('Today', S.moment === 'fresh' ? '' : DEVICES[S.dev].today) + todayCard(S, 4, true)
    + sect('Your shields') + shieldGrid(S) + '</div>';
}

const VIEWS = { home: homeView, protect: protectView, check: checkView, me: meView };
function mainHTML(S) { return S.detail ? detailView(S, S.detail) : VIEWS[S.tab](S); }
function sideHTML(S) {
  if (S.scanning) return scanPane(S);
  if (S.detail) return detailView(S, S.detail);
  return S.tab === 'home' ? todayPane(S) : VIEWS[S.tab](S);
}
