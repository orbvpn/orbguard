/* ---------- boot: fill the page, start the three live devices, wire the controls ---------- */
(function () {
  if (!$('[data-slot="phone"]')) return;
  slot('mark', ringMark(28));
  slot('phone', fit('<div class="phone"><div class="os" id="app-phone"></div></div>', 413, 872, 1, 'data-fit="1"'));
  slot('states', buildStates());
  slot('wall', buildWall());
  slot('type-phone', phoneFit({}, .62));
  slot('fold', fit('<div class="fold-stage"><div class="fold-dev os" id="app-fold" data-posture="open" data-app="dark"></div></div>', 708, 848, 1, 'data-fit="1"'));
  slot('tabletop', fit(tabletop(), 848, 588, 1, 'data-fit="1"'));
  slot('desk', fit('<div class="win os" id="app-desk"></div>', 1180, 740, 1, 'data-fit="1" data-min=".62"'));
  slot('tray', trayPopover());
  slot('shots', buildShots());
  slot('ads', buildAds());
  slot('landing', buildLanding());
  slot('widgets', buildWidgets());
  slot('cmp-new', phoneFit({ S: { moment: 'gap' } }, .62));

  const foldDev = $('#app-fold');
  const P = createApp($('#app-phone'), {});
  const F = createApp(foldDev, { layout: 'fold', dev: 'android' });
  const C = createApp($('[data-cover]', foldDev), { layout: 'cover', dev: 'android' });
  const D = createApp($('#app-desk'), { layout: 'desk', dev: 'mac', os: 'mac' });
  C.active = false;
  hydrate(document);

  /* the phone */
  const markMoment = seg('moment', v => P.set({ moment: v }));
  const markLook = seg('look', v => P.set({ theme: v }));
  seg('sound', v => { Sound.set(v === 'on'); });
  P.onChange = () => { markMoment(P.S.moment); markLook(P.S.theme); };

  /* type: the whole page switches between the kit's display recipe as it ships and the wide one */
  const pageEl = $('.page');
  seg('type', v => { if (v === 'kit') pageEl.setAttribute('data-type', 'kit'); else pageEl.removeAttribute('data-type'); });

  /* the foldable: closed, open, tabletop. State carries across the hinge */
  const foldFit = foldDev.closest('.fit'), foldSlot = $('[data-slot="fold"]'), ttSlot = $('[data-slot="tabletop"]');
  let posture = 'open';
  function foldLayout() {
    const tight = posture === 'closed' && foldSlot.clientWidth < 760;
    foldFit.classList.toggle('closed', tight);
    foldFit.dataset.w = tight ? 372 : 708;
    foldFit.style.setProperty('--w', foldFit.dataset.w + 'px');
  }
  function setPosture(p) {
    if (F.busy() || C.busy()) return false;
    const tt = p === 'tabletop';
    if (!tt) {
      const from = posture === 'closed' ? C : F, to = p === 'closed' ? C : F;
      if (from !== to) to.set({ moment: from.S.moment, theme: from.S.theme, credits: from.S.credits, plan: from.S.plan });
      foldDev.dataset.posture = p;
      C.active = p === 'closed'; F.active = p === 'open';
      posture = p;
    }
    ttSlot.hidden = !tt; foldSlot.hidden = tt;
    foldLayout(); fitAll();
  }
  const markPosture = seg('posture', setPosture);

  /* the desktop */
  seg('os', v => D.set({ dev: v, os: v }));
  const palBtn = $('[data-open-palette]');
  if (palBtn) palBtn.addEventListener('click', () => { if (!D.busy()) D.act('palette'); });

  /* pause anything that is off screen; a ring only moves while someone is looking */
  const byRoot = new Map([[P.root, [P]], [foldDev, [F, C]], [D.root, [D]]]);
  let unfolded = reduce;
  if ('IntersectionObserver' in window) {
    const io = new IntersectionObserver(es => es.forEach(e => {
      e.target.classList.toggle('paused', !e.isIntersecting);
      (byRoot.get(e.target) || []).forEach(a => { a.inView = e.isIntersecting; });
      if (e.target === foldDev && e.isIntersecting && !unfolded) {
        unfolded = true;
        setTimeout(() => { if (posture === 'closed' && setPosture('open') !== false) markPosture('open'); }, 700);
      }
    }), { threshold: .2 });
    [P.root, foldDev, D.root].concat($$('.p-panel, [data-ad]')).forEach(n => io.observe(n));
    /* one orchestrated moment: the foldable starts closed and opens when it first comes into view */
    if (!reduce) {
      foldDev.classList.add('no-anim'); setPosture('closed'); markPosture('closed');
      requestAnimationFrame(() => requestAnimationFrame(() => foldDev.classList.remove('no-anim')));
    }
  }

  /* the square ad plays its own pitch: the gap closes, then opens again */
  const ad = $('[data-ad]'); let adOpen = true;
  if (ad && !reduce) setInterval(() => {
    if (ad.classList.contains('paused')) return;
    const host = $('[data-ad-orb]', ad);
    if (adOpen) orbClose($('.orb', host)); else host.innerHTML = orb({ size: 148, gaps: [150], live: true });
    adOpen = !adOpen;
  }, 2800);

  setInterval(() => { const now = performance.now(); APPS.forEach(a => a.tick(now)); }, 500);
  $$('.p-index a').forEach(a => a.addEventListener('click', e => {
    const t = $(a.getAttribute('href')); if (!t) return;
    e.preventDefault(); t.scrollIntoView({ behavior: reduce ? 'auto' : 'smooth', block: 'start' });
  }));
  addEventListener('resize', () => { foldLayout(); fitAll(); });
  fitAll();
  if (document.fonts && document.fonts.ready) document.fonts.ready.then(fitAll);
})();
