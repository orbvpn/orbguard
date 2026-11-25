/* ---------- THE LIVE APP: one controller, the same screens, three layouts ----------
   phone / cover : one column with a floating tab bar
   fold          : two panes either side of the hinge; the ring never leaves the left one
   desk          : sidebar, ring column, detail column                                   */
const APPS = [];
const OVERLAY = '<div class="scrim" data-close></div><div class="sheet" role="dialog" aria-modal="true" aria-label="Details"><div class="inner" data-sheet-body></div></div><div class="toast" role="status"></div>';

function createApp(root, init) {
  const S = Object.assign({ layout: 'phone', dev: 'iphone', theme: 'dark', moment: 'clear', tab: 'home', detail: null,
    credits: 2, plan: null, planSel: 'plus', billing: 'year', paste: 'empty', scanning: false }, init);
  const mine = n => n.closest('[data-app-root]') === root;
  const qq = s => $$(s, root).filter(mine);
  const q = s => qq(s)[0];
  const two = () => S.layout === 'fold' || S.layout === 'desk';
  let busy = false, sheetName = null, sheetArg = null, toastT = 0, patrolAt = 0, patrolI = 0;
  const app = { root, S };

  root.setAttribute('data-app-root', '');
  root.innerHTML = SHELL[S.layout](S);

  function navState() {
    qq('.nav [data-tab], .side-nav [data-tab]').forEach(b => {
      const on = b.dataset.tab === S.tab;
      b.classList.toggle('on', on);
      if (on) b.setAttribute('aria-current', 'page'); else b.removeAttribute('aria-current');
    });
    qq('.moon').forEach(m => m.classList.toggle('sel', two() && m.dataset.shield === S.detail));
  }
  function paintSide() { const el = q('[data-side]'); if (el) { el.innerHTML = sideHTML(S); el.firstElementChild.classList.add('view-in'); } }
  function paint() {
    root.dataset.app = S.theme;
    if (two()) { q('[data-home]').innerHTML = homeView(S); paintSide(); }
    else { const m = q('[data-main]'); m.innerHTML = mainHTML(S); m.firstElementChild.classList.add('view-in'); }
    const mini = q('[data-plan-mini]'); if (mini) mini.innerHTML = planMini(S);
    navState(); patrolAt = performance.now(); patrolI = 0;
  }
  function refreshPlan() { const p = q('[data-plan]'); if (p) p.innerHTML = planCard(S); const mini = q('[data-plan-mini]'); if (mini) mini.innerHTML = planMini(S); }

  function go(tab) {
    S.tab = tab; S.detail = null;
    if (two()) { paintSide(); navState(); } else paint();
  }
  function openShield(id) {
    S.detail = id;
    if (two()) { paintSide(); navState(); } else { S.tab = 'protect'; paint(); }
  }
  function back() { S.detail = null; if (two()) { paintSide(); navState(); } else paint(); }

  function sheet(name, arg) {
    sheetName = name; sheetArg = arg;
    const body = q('[data-sheet-body]');
    body.innerHTML = SHEETS[name](S, arg); body.scrollTop = 0;
    root.classList.add('sheet-open'); q('.sheet').classList.add('open');
  }
  function closeSheet() {
    if (!sheetName) return;
    sheetName = null; S.toolDone = null;
    root.classList.remove('sheet-open'); q('.sheet').classList.remove('open');
  }
  function resheet() { if (sheetName) q('[data-sheet-body]').innerHTML = SHEETS[sheetName](S, sheetArg); }
  function toast(t, icon) {
    const el = q('.toast');
    el.innerHTML = ic(icon || 'check_circle') + '<span>' + esc(t) + '</span>';
    el.classList.add('show'); clearTimeout(toastT);
    toastT = setTimeout(() => el.classList.remove('show'), 2600);
  }
  function keepInView(el) {
    const sc = el.closest('.scroll'); if (!sc) return;
    const r = el.getBoundingClientRect(), c = sc.getBoundingClientRect(), k = c.height / sc.offsetHeight || 1;
    const over = (r.bottom - c.bottom) / k + 20;
    if (over > 0) sc.scrollTop += over;
  }

  /* the check: each segment is one real check, lit when it finishes */
  async function runCheck() {
    if (busy) return;
    if (!S.plan && S.credits <= 0) return sheet('credits');
    closeSheet();
    if (S.tab !== 'home' || S.detail) { S.tab = 'home'; S.detail = null; paint(); await wait(240); }
    busy = true; S.scanning = true; root.classList.add('scanning');
    const D = DEVICES[S.dev], list = deviceChecks(S.dev).filter(c => c.run), n = list.length, was = S.moment;
    const orbEl = q('.orb'), sc = orbEl.closest('.scroll');
    if (sc) sc.scrollTop = 0;
    q('[data-verdict]').textContent = 'Checking your ' + D.noun + '.';
    q('[data-home-act]').innerHTML = '<p class="proof"><i class="live"></i><span data-doing>Getting ready</span></p>' + (two() ? '' : '<div class="home-act">' + scanList(S) + '</div>');
    if (two()) q('[data-side]').innerHTML = scanPane(S);
    qq('.moon').forEach(m => m.classList.remove('sel', 'rep'));
    orbSegs(orbEl, list.map(() => 'off'));
    $('.orb-hole', orbEl).innerHTML = '<span class="orb-num"><b data-done>0</b><small>/' + n + '</small></span><span class="orb-cap">checks</span>';
    await wait(420);
    for (let i = 0; i < n; i++) {
      const c = list[i], rowEl = q('.crow[data-ci="' + i + '"]'), moon = q('.moon[data-shield="' + c.sh + '"]');
      orbSeg(orbEl, i, 'now');
      q('[data-doing]').textContent = c.doing;
      if (rowEl) { rowEl.classList.add('now'); keepInView(rowEl); }
      if (moon) { moon.classList.remove('ping'); void moon.offsetWidth; moon.classList.add('ping'); }
      await wait(D.ms);
      orbSeg(orbEl, i, 'on');
      if (rowEl) { rowEl.classList.remove('now'); rowEl.classList.add('done'); }
      q('[data-done]').textContent = i + 1;
      Sound.tick(i);
    }
    await wait(420);
    if (!S.plan) S.credits--;
    S.moment = was === 'gap' ? 'gap' : 'clear'; S.scanning = false;
    root.classList.remove('scanning');
    paint();
    const o2 = q('.orb'); orbFlash(o2);
    if (was === 'gap') Sound.care(); else Sound.whole();
    if (was === 'fresh') countTo($('[data-score]', o2), 0, 1000, 1100);
    if (app.onChange) app.onChange();
    await wait(was === 'fresh' ? 1500 : 950);
    busy = false;
    sheet('results');
  }

  /* closing the gap: the two ends of the ring travel until they meet */
  async function fixed() {
    closeSheet();
    if (S.tab !== 'home' || S.detail) { S.tab = 'home'; S.detail = null; paint(); }
    busy = true;
    await wait(460);
    const orbEl = q('.orb'), sc = orbEl.closest('.scroll'); if (sc) sc.scrollTop = 0;
    orbClose(orbEl, () => {
      Sound.whole(); S.moment = 'clear';
      countTo($('[data-score]', orbEl), 900, 1000, 900);
      q('[data-verdict]').textContent = verdictText(S);
      q('[data-home-act]').innerHTML = homeActions(S);
      qq('.moon.care').forEach(m => { m.classList.remove('care'); m.classList.add('on'); });
      const bd = q('.badge'); if (bd) bd.remove();
      const today = q('.today'); if (today) today.outerHTML = todayCard(S);
      if (two()) paintSide();
      toast('Gap closed. Your score is 1000');
      busy = false; patrolAt = performance.now();
      if (app.onChange) app.onChange();
    });
  }

  async function act(a) {
    if (a.indexOf('toast:') === 0) return toast(a.slice(6), 'info_circle');
    if (a.indexOf('tab:') === 0) { closeSheet(); return go(a.slice(4)); }
    if (a.indexOf('tool:') === 0) return sheet('tool', a.slice(5));
    if (a.indexOf('tool-run:') === 0) {
      const btn = q('[data-act="' + a + '"]'); if (btn) { btn.disabled = true; btn.innerHTML = '<i class="live"></i>Checking'; }
      await wait(1100); S.toolDone = a.slice(9); return resheet();
    }
    switch (a) {
      case 'check': return runCheck();
      case 'score': return sheet('score');
      case 'fix': return sheet('fix');
      case 'fixed': return fixed();
      case 'example': S.paste = 'filled'; q('[data-paste]').innerHTML = pasteCard(S); return;
      case 'paste-clear': S.paste = 'empty'; q('[data-paste]').innerHTML = pasteCard(S); return;
      case 'paste-check':
        S.paste = 'busy'; q('[data-paste]').innerHTML = pasteCard(S);
        await wait(1200);
        S.paste = 'done'; { const p = q('[data-paste]'); if (p) { p.innerHTML = pasteCard(S); Sound.care(); } }
        return;
      case 'ad': {
        const btn = q('[data-act="ad"]'); btn.disabled = true; btn.innerHTML = '<i class="live"></i>Ad playing';
        await wait(1600); S.credits++; resheet(); refreshPlan(); toast('1 scan credit earned'); return;
      }
      case 'buy': S.plan = S.planSel; closeSheet(); refreshPlan(); toast(plan(S.plan).name + ' is on. Checks are unlimited'); return;
      case 'theme': S.theme = S.theme === 'dark' ? 'light' : 'dark'; paint(); if (app.onChange) app.onChange(); return;
      case 'palette': return openPalette();
    }
  }

  root.addEventListener('click', e => {
    const t = e.target.closest('[data-tab],[data-act],[data-shield],[data-sheet],[data-close],[data-back],[data-tool],[data-plan],[data-bill],[data-cmd]');
    if (!t || !mine(t)) return;
    const d = t.dataset;
    if (busy && !('close' in d)) return;
    Sound.tap();
    if ('close' in d) { closePalette(); return closeSheet(); }
    if ('back' in d) return back();
    if (d.cmd) return runCmd(+d.cmd);
    if (d.bill) { S.billing = d.bill; return resheet(); }
    if (d.plan) { S.planSel = d.plan; return resheet(); }
    if (d.tool) return sheet('tool', d.tool);
    if (d.sheet) return sheet(d.sheet);
    if (d.shield) return openShield(d.shield);
    if (d.tab) { closeSheet(); return go(d.tab); }
    if (d.act) return act(d.act);
  });

  /* desktop only: a command palette, because a desktop app should answer the keyboard */
  const CMDS = [
    ['shield_check', 'Check now', () => runCheck()],
    ['chat_round_check', 'Check a link or message', () => go('check')],
    ['shield', 'Open Protect', () => go('protect')],
    ['pulse', 'How my score adds up', () => { if (S.moment !== 'fresh') sheet('score'); }],
    ['crown', 'Go unlimited', () => sheet('plans')],
    ['moon', 'Switch appearance', () => act('theme')]
  ];
  let palSel = 0, palList = CMDS;
  function drawPalette() {
    const box = q('.pal-list'); if (!box) return;
    box.innerHTML = palList.length ? palList.map((c, i) => '<button data-cmd="' + CMDS.indexOf(c) + '"' + (i === palSel ? ' class="on"' : '') + '>' + ic(c[0]) + '<span class="grow">' + c[1] + '</span>' + (i === palSel ? '<kbd>Enter</kbd>' : '') + '</button>').join('')
      : '<p class="t-small" style="padding:14px 16px">Nothing matches. Try “check”.</p>';
  }
  function openPalette() {
    const p = q('.palette'); if (!p) return;
    palSel = 0; palList = CMDS; p.hidden = false;
    const inp = $('input', p); inp.value = ''; drawPalette();
    try { inp.focus({ preventScroll: true }); } catch (e) { /* focus is a nicety */ }
  }
  function closePalette() { const p = q('.palette'); if (p) p.hidden = true; }
  function runCmd(i) { closePalette(); closeSheet(); CMDS[i][2](); }
  if (S.layout === 'desk') {
    root.addEventListener('input', e => {
      if (!e.target.closest('.palette')) return;
      const v = e.target.value.trim().toLowerCase();
      palList = CMDS.filter(c => c[1].toLowerCase().indexOf(v) >= 0); palSel = 0; drawPalette();
    });
    root.addEventListener('keydown', e => {
      const p = q('.palette');
      if ((e.metaKey || e.ctrlKey) && e.key.toLowerCase() === 'k') { e.preventDefault(); return p.hidden ? openPalette() : closePalette(); }
      if (!p || p.hidden) return;
      if (e.key === 'Escape') return closePalette();
      if (e.key === 'ArrowDown' || e.key === 'ArrowUp') { e.preventDefault(); palSel = (palSel + (e.key === 'ArrowDown' ? 1 : palList.length - 1)) % Math.max(1, palList.length); return drawPalette(); }
      if (e.key === 'Enter' && palList[palSel]) { e.preventDefault(); runCmd(CMDS.indexOf(palList[palSel])); }
    });
  }

  /* patrol: while all is clear, the proof line reads out each shield's last real report in turn */
  app.tick = now => {
    if (app.inView === false || app.active === false || busy || sheetName || S.moment !== 'clear' || now - patrolAt < 3600) return;
    const span = q('[data-report]'); if (!span) return;
    patrolAt = now;
    const D = DEVICES[S.dev], ids = SHIELDS.map(s => s.id).filter(id => D.brief[id] && D.shields[id] === 'on');
    patrolI = (patrolI + 1) % (ids.length + 1);
    const id = ids[patrolI - 1];
    qq('.moon').forEach(m => m.classList.toggle('rep', m.dataset.shield === id));
    span.classList.add('swap');
    setTimeout(() => { span.textContent = id ? D.brief[id] : cleanText(S); span.classList.remove('swap'); }, 260);
  };

  app.paint = paint; app.act = act; app.sheet = sheet; app.closeSheet = closeSheet; app.runCheck = runCheck; app.go = go;
  app.busy = () => busy;
  app.set = patch => {
    if (busy) return false;
    Object.assign(S, patch);
    if ('moment' in patch || 'dev' in patch) { S.tab = 'home'; S.detail = null; S.paste = 'empty'; closeSheet(); }
    if ('dev' in patch || 'os' in patch) root.innerHTML = SHELL[S.layout](S);
    paint(); return true;
  };
  paint();
  APPS.push(app);
  return app;
}
