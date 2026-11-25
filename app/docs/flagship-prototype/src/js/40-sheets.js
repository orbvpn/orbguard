/* ---------- SHEETS. Every pop-up in OrbGuard is a sheet (showAppSheet), so every one here is too ---------- */
const shHead = o => '<div class="sh-head">' + (o.icon ? '<span class="d-ic ' + (o.tone || '') + '">' + ic(o.icon) + '</span>' : '')
  + '<h2 class="t-h2">' + o.title + '</h2>' + (o.body ? '<p class="t-body">' + o.body + '</p>' : '') + '</div>';
const money = n => '$' + n.toFixed(2);
const miniOrb = (size, o) => orb(Object.assign({ size: size }, o || {}));

const SHEETS = {
  /* the one thing to fix: plain steps, then the ring closes */
  fix(S) {
    return shHead({ icon: 'user_id', tone: 'amber', title: 'Your email was in a data breach',
      body: PERSON.breach + ' was breached in ' + PERSON.breachYear + '. Your email address and password were in the leak.' })
      + '<ol class="steps"><li><b>Change your ' + PERSON.breach + ' password</b><span>Start there. That is the one that leaked.</span></li>'
      + '<li><b>Change it anywhere you reused it</b><span>A leaked password gets tried on other sites.</span></li>'
      + '<li><b>Turn on two-step sign-in</b><span>Wherever the site offers it.</span></li></ol>'
      + '<button class="btn lime" data-act="fixed">I changed it. Close the gap</button><button class="btn text" data-close>Not now</button>';
  },
  /* the score, shown as the engine really adds it up */
  score(S) {
    const gap = S.moment === 'gap', total = gap ? 900 : 1000, D = DEVICES[S.dev];
    return '<div class="sh-head"><h2 class="t-h2">How your score adds up</h2>'
      + '<div class="score-top"><p class="big-num">' + total + '<small>of 1000</small></p><span class="grow"></span>' + chip('on', band(total), true) + '</div></div>'
      + '<div class="scorebar" role="img" aria-label="' + total + ' of 1000 points">' + RUBRIC.map(r => '<i' + (gap && r.id === 'breach' ? ' class="miss"' : '') + ' style="--w:' + r.pts + '"></i>').join('') + '</div>'
      + '<div class="srows">' + RUBRIC.map(r => {
        const got = gap && r.id === 'breach' ? 0 : r.pts;
        return '<div class="srow' + (got ? '' : ' miss') + '"><span class="grow">' + r.name + '</span><span class="t-mono">' + got + ' of ' + r.pts + '</span></div>';
      }).join('') + '</div>'
      + (S.dev === 'iphone' ? '<p class="t-small note">iPhone cannot audit other apps, so those last 50 points are yours. You are never marked down for something the system forbids.</p>' : '')
      + (gap ? '<button class="btn lime" data-act="fix" style="margin-top:18px">Close the gap, earn 100</button>' : '<button class="btn plain" data-close style="margin-top:18px">Done</button>');
  },
  /* results: only what really ran is counted */
  results(S) {
    const list = deviceChecks(S.dev), ran = list.filter(c => c.run), no = list.filter(c => !c.run), D = DEVICES[S.dev], gap = S.moment === 'gap';
    return '<div class="sh-head center">' + miniOrb(84, gap ? { gaps: [150] } : {})
      + '<h2 class="t-h2">' + (gap ? 'Checks are clean' : 'All clear') + '</h2><p class="t-body">' + ran.length + ' checks ran clean' + (gap ? '. One gap is still open.' : '.') + '</p></div>'
      + '<div class="glass lrows">' + ran.map(c => lrow('check_circle', 'ink-lime', c.name)).join('') + '</div>'
      + (no.length ? '<div class="cant"><p class="t-title">' + no.length + ' checks are not possible on ' + D.os + '</p><p class="t-small">' + no.map(c => c.name).join(', ') + '. iOS does not let any app run these, so they are not counted as passed.</p></div>' : '')
      + (S.plan ? '' : '<button class="credit-line" data-sheet="credits">' + ic('ticket') + '<span class="grow">' + S.credits + (S.credits === 1 ? ' scan credit left' : ' scan credits left') + '</span><b>Go unlimited</b>' + chev() + '</button>')
      + '<div class="btn-row" style="margin-top:16px">' + (gap ? '' : '<button class="btn plain" data-sheet="share">Share</button>') + '<button class="btn lime" data-close>Done</button></div>';
  },
  /* the point of sale: real tiers, real prices */
  plans(S) {
    const yr = S.billing !== 'month', sel = S.planSel || 'plus', D = DEVICES[S.dev];
    return shHead({ title: 'Go unlimited', body: 'One subscription unlocks OrbGuard, OrbVPN &amp; OrbBrowser premium.' })
      + '<div class="seg2" role="tablist"><button data-bill="month"' + (yr ? '' : ' class="on"') + '>Monthly</button><button data-bill="year"' + (yr ? ' class="on"' : '') + '>Yearly</button></div>'
      + '<div class="plans">' + PLANS.map(p => {
        const on = p.id === sel, save = Math.round((1 - p.year / (p.month * 12)) * 100);
        return '<button class="glass plan-card' + (on ? ' sel' : '') + '" data-plan="' + p.id + '" aria-pressed="' + on + '">'
          + '<span class="line"><span class="radio"></span><span class="t-title grow">' + p.name + '</span>' + (p.best ? chip('pink', 'Recommended') : '') + '</span>'
          + '<span class="price"><b>' + money(yr ? p.year : p.month) + '</b><span>' + (yr ? 'a year, save ' + save + '%' : 'a month') + '</span></span>'
          + '<span class="t-small">' + p.tag + '</span>'
          + (on ? '<ul class="gets">' + (p.from ? '<li class="from">Everything in ' + p.from + ', plus</li>' : '') + p.gets.map(g => '<li>' + ic('check_circle') + '<span>' + g + '</span></li>').join('') + '</ul>' : '')
          + '</button>';
      }).join('') + '</div>'
      + (D.noStore
        ? '<button class="btn lime" data-act="toast:Subscribe on your phone, then sign in here">Subscribe on your phone</button><p class="t-small center">' + D.os + ' does not sell plans in the app. Your plan unlocks here when you sign in.</p>'
        : '<button class="btn lime" data-act="buy">Continue with ' + plan(sel).name + '</button><p class="t-small center">Prices come from your app store, in your currency.</p>');
  },
  /* the free path stays honest: one credit per check, earn more or go unlimited */
  credits(S) {
    return '<div class="sh-head center"><span class="d-ic">' + ic('ticket') + '</span><p class="big-num">' + S.credits + '<small>' + (S.credits === 1 ? 'scan credit' : 'scan credits') + '</small></p>'
      + '<p class="t-body">' + (S.credits ? 'Each check you start uses one credit.' : 'You are out of credits. Earn one, or go unlimited.') + '</p></div>'
      + '<button class="btn plain" data-act="ad">' + ic('play') + 'Watch ad to earn a scan</button>'
      + '<button class="btn lime" data-sheet="plans" style="margin-top:10px">Go unlimited with a plan</button>';
  },
  alerts(S) {
    if (S.moment === 'gap') return shHead({ title: 'Alerts' }) + '<div class="glass rows">' + row({ icon: 'user_id', tone: 'amber', title: 'Your email was in a data breach', sub: PERSON.breach + ', found today', end: chev(), attr: 'data-act="fix"' }) + '</div>';
    return '<div class="sh-head center"><span class="d-ic mute">' + ic('bell') + '</span><h2 class="t-h2">No alerts</h2><p class="t-body">OrbGuard only speaks up when something needs you.</p></div><button class="btn plain" data-close>Done</button>';
  },
  lost(S) {
    return shHead({ icon: 'map_point_wave', title: 'Find this phone', body: 'If it goes missing, sign in with your OrbVPN account to reach it.' })
      + '<div class="glass lrows">' + lrow('map_point', 'ink-lime', 'Locate it on a map') + lrow('bell_bing', 'ink-lime', 'Ring it, even on silent') + lrow('camera', 'ink-lime', 'Photograph whoever has it') + '</div>'
      + '<button class="btn plain" data-act="toast:Setup asks for location and camera access" style="margin-top:18px">Set up</button>';
  },
  privacy(S) {
    return shHead({ icon: 'lock_keyhole', title: 'Private by design', body: 'What OrbGuard can and cannot see.' })
      + '<div class="glass lrows">' + lrow('check_circle', 'ink-lime', 'Checks of this ' + DEVICES[S.dev].noun + ' run on the ' + DEVICES[S.dev].noun)
      + lrow('check_circle', 'ink-lime', 'It never reads your inbox. You choose what to check')
      + lrow('check_circle', 'ink-lime', 'Passwords are checked without ever being sent')
      + lrow('check_circle', 'ink-lime', 'It never listens to, records or joins a call') + '</div>'
      + '<button class="btn plain" data-close style="margin-top:18px">Done</button>';
  },
  pro(S) {
    return shHead({ icon: 'tuning_2', tone: 'mute', title: 'Pro tools', body: 'For security people. The everyday app stays calm, and 34 expert tools stay one switch away.' })
      + '<div class="glass lrows">' + lrow('radar_2', 'ink-2', 'Threat intelligence, 9 tools') + lrow('server', 'ink-2', 'Enterprise, 9 tools') + lrow('bug', 'ink-2', 'Forensics and network tools') + '</div>'
      + '<button class="btn plain" data-act="toast:Pro mode is a switch in the real app" style="margin-top:18px">Turn on Pro mode</button>';
  },
  share(S) {
    return shHead({ title: 'Share your result' }) + shareCard() + '<button class="btn lime" data-act="toast:The share sheet opens in the real app" style="margin-top:16px">Share</button>';
  },
  tool(S, id) {
    const t = TOOLS.find(x => x.id === id), gap = S.moment === 'gap' && id === 'email';
    const res = S.toolDone === id ? '<div class="tool-res' + (gap ? ' care' : '') + '">' + ic(gap ? 'danger_triangle' : 'check_circle') + '<span>' + (gap ? t.bad : t.ok) + '</span></div>' : '';
    const btn = S.toolDone === id ? (gap ? '<button class="btn lime" data-act="fix">Close the gap</button>' : '<button class="btn plain" data-close>Done</button>')
      : '<button class="btn ' + (t.toast ? 'plain' : 'lime') + '" data-act="' + (t.toast ? 'toast:' + t.toast : 'tool-run:' + id) + '">' + t.btn + '</button>';
    return shHead({ icon: t.icon, title: t.name, body: t.body }) + res + btn;
  }
};

/* the card people post: the ring, whole, and one line */
function shareCard() {
  return '<div class="share-card"><div class="bed"></div>' + miniOrb(104) + '<p class="t-head">No signs I am being watched.</p><p class="t-small">Checked today with OrbGuard</p><p class="sc-q">Is your circle closed?</p></div>';
}

/* ---------- first run: the same ring, teaching itself in three slides ---------- */
const SLIDES = [
  { head: 'Know if you’re<br>being watched.', sub: 'OrbGuard looks for spyware, stalkerware and trackers on this phone.', orb: { mode: 'fresh' } },
  { head: 'One tap.<br>A clear answer.', sub: 'Tap once. See every check that ran and what it found.', orb: { mode: 'check', segs: ['on', 'on', 'on', 'now', 'off'], hole: '<span class="orb-num">3<small>/5</small></span><span class="orb-cap">checks</span>' } },
  { head: 'Private by design.', sub: 'You choose what gets checked. OrbGuard never reads your inbox or listens to calls.', orb: { live: true } }
];
function onboardView(S) {
  const sl = SLIDES[S.slide || 0];
  return '<div class="scroll onb"><div class="topbar"><span class="grow"></span><button class="btn text" style="width:auto">Skip</button></div>'
    + '<div class="onb-orb">' + orb(Object.assign({ size: 248 }, sl.orb)) + '</div>'
    + '<h1 class="t-display">' + sl.head + '</h1><p class="t-body">' + sl.sub + '</p>'
    + '<div class="dots">' + SLIDES.map((x, i) => '<i' + (i === (S.slide || 0) ? ' class="on"' : '') + '></i>').join('') + '</div>'
    + '<button class="btn lime">' + ((S.slide || 0) === 2 ? 'Get started' : 'Continue') + '</button></div>';
}
function primeView(S) {
  const rows = [['bell', 'Notifications', 'So an alert can reach you'], ['map_point', 'Location', 'For network checks and finding this phone']];
  if (S.dev === 'android') rows.push(['widget_5', 'Usage access', 'To see which apps are active']);
  return '<div class="scroll onb prime"><div class="topbar"></div><span class="grow" style="flex-grow:2"></span><h1 class="t-display" style="text-align:left">Turn on your protection.</h1><p class="t-body" style="text-align:left">Each one is asked once, with the reason first.</p>'
    + '<div class="glass rows" style="margin-top:22px">' + rows.map(r => row({ icon: r[0], title: r[1], sub: r[2], end: '<span class="sw on"></span>' })).join('') + '</div>'
    + '<span class="grow" style="flex-grow:3"></span><button class="btn lime">Turn on</button><button class="btn text">Not now</button></div>';
}
/* the check, frozen mid-run, for the screen wall */
function scanStill(S) {
  const D = DEVICES[S.dev], list = deviceChecks(S.dev).filter(c => c.run), k = S.done || 2;
  return '<div class="scroll home"><div class="topbar"><span class="trust">' + ic('lock_keyhole') + 'Private by design</span></div>'
    + '<div class="hero" style="--orbit:150px"><div class="orbit"></div>' + moons(S, 150)
    + orb({ size: 224, mode: 'check', segs: list.map((c, i) => (i < k ? 'on' : i === k ? 'now' : 'off')), hole: '<span class="orb-num">' + k + '<small>/' + list.length + '</small></span><span class="orb-cap">checks</span>' }) + '</div>'
    + '<h1 class="t-display verdict">Checking your ' + D.noun + '.</h1><p class="proof"><i class="live"></i><span>' + list[k].doing + '</span></p>'
    + '<div class="home-act"><div class="clist">' + list.map((c, i) => '<div class="crow ' + (i < k ? 'done' : i === k ? 'now' : '') + '"><i></i><span class="grow">' + c.name + '</span></div>').join('') + '</div></div></div>';
}
