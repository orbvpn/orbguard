/* ---------- device shells: where the regions live for each layout ---------- */
let rmUid = 0;
/* the logo mark itself: assets/branding/orbguard_icon.svg, same stops, same proportions */
function ringMark(px) {
  const u = 'rm' + (++rmUid);
  return '<svg class="ringmark" width="' + px + '" height="' + px + '" viewBox="0 0 100 100" aria-hidden="true"><defs><radialGradient id="' + u + '" gradientUnits="userSpaceOnUse" cx="38" cy="38" r="62">'
    + '<stop offset="0" stop-color="#f2fcd0"/><stop offset=".2" stop-color="#e0f4b0"/><stop offset=".4" stop-color="#c4e896"/><stop offset=".6" stop-color="#a0d87c"/><stop offset=".8" stop-color="#84c86c"/><stop offset="1" stop-color="#68b060"/>'
    + '</radialGradient></defs><circle cx="50" cy="50" r="34" fill="none" stroke="url(#' + u + ')" stroke-width="22"/></svg>';
}
function planMini(S) {
  return S.plan
    ? '<div class="plan-mini"><b>' + plan(S.plan).name + ' plan</b><small>Unlimited checks</small></div>'
    : '<div class="plan-mini"><b>Free plan</b><small>' + S.credits + (S.credits === 1 ? ' scan credit' : ' scan credits') + '</small><button data-sheet="plans">Go unlimited' + chev() + '</button></div>';
}
const CAP = '<span class="cap"><svg viewBox="0 0 12 12"><path d="M2 6h8"/></svg><svg viewBox="0 0 12 12"><rect x="2.5" y="2.5" width="7" height="7"/></svg><svg viewBox="0 0 12 12"><path d="M2.5 2.5l7 7M9.5 2.5l-7 7"/></svg></span>';

const SHELL = {
  phone(S) {
    return '<div class="bed"></div>' + statusBar() + '<div class="island"></div><div class="view on" data-main></div>' + navBar(S.tab) + OVERLAY + '<div class="homebar"></div>';
  },
  /* the cover screen of a foldable is simply a narrower phone */
  cover(S) {
    return '<div class="bed"></div>' + statusBar() + '<div class="punch"></div><div class="view on" data-main></div>' + navBar(S.tab) + OVERLAY + '<div class="homebar"></div>';
  },
  /* unfolded: two panes that never put anything under the hinge */
  fold(S) {
    return '<div class="leaf leaf-r"><div class="pane pane-r"><div class="bed"></div><div class="sbar">' + '<span></span>' + SYS + '</div><div class="view on" data-side></div>' + OVERLAY + '</div></div>'
      + '<div class="leaf leaf-l"><div class="face front"><div class="pane pane-l"><div class="bed"></div><div class="sbar"><span>9:41</span></div><div class="view on" data-home></div>' + navBar(S.tab) + '</div></div>'
      + '<div class="face back"><div class="cover os" data-cover data-app="dark"></div></div></div>'
      + '<div class="crease"></div>';
  },
  desk(S) {
    const os = S.os || 'mac', mod = os === 'mac' ? '⌘' : 'Ctrl ';
    const bar = os === 'mac' ? '<span class="tl"><i></i><i></i><i></i></span><span class="grow"></span><span class="win-title">OrbGuard</span><span class="grow"></span><span class="tl ghost"></span>'
      : os === 'win' ? '<span class="win-app">' + ringMark(15) + 'OrbGuard</span><span class="grow"></span>' + CAP
      : '<span class="gx ghost"></span><span class="grow"></span><span class="win-title strong">OrbGuard</span><span class="grow"></span><span class="gx"><svg viewBox="0 0 12 12"><path d="M3 3l6 6M9 3l-6 6"/></svg></span>';
    return '<div class="win-bar" data-os="' + os + '">' + bar + '</div><div class="win-body"><div class="bed"></div>'
      + '<aside class="side-nav"><div class="brandrow">' + ringMark(26) + '<span>OrbGuard</span></div>'
      + '<button class="search" data-act="palette">' + ic('magnifer') + '<span class="grow">Search or run</span><kbd>' + mod + 'K</kbd></button>'
      + '<nav aria-label="Main">' + TABS.map(t => '<button data-tab="' + t[0] + '">' + ic(t[1]) + '<span class="grow">' + t[2] + '</span></button>').join('') + '</nav>'
      + '<span class="grow"></span><div data-plan-mini></div>'
      + '<button class="acct-row" data-tab="me"><span class="circ avatar">' + PERSON.initial + '</span><span class="grow"><b>' + PERSON.name + '</b><small>' + PERSON.email + '</small></span></button></aside>'
      + '<section class="col-home"><div class="view on" data-home></div></section>'
      + '<section class="col-side"><div class="view on" data-side></div></section>'
      + OVERLAY
      + '<div class="palette" hidden><div class="pal-scrim" data-close></div><div class="pal-box"><div class="pal-in">' + ic('magnifer')
      + '<input type="text" placeholder="Type a command" aria-label="Command" autocomplete="off" spellcheck="false"></div><div class="pal-list"></div></div></div>'
      + '</div>';
  }
};

/* ---------- static frames: the same render functions, frozen ---------- */
const BASE_S = { layout: 'phone', dev: 'iphone', theme: 'dark', moment: 'clear', tab: 'home', detail: null, credits: 2, plan: null, planSel: 'plus', billing: 'year', paste: 'empty' };
function frame(o) {
  o = o || {};
  const S = Object.assign({}, BASE_S, o.S), view = o.view || VIEWS[S.tab];
  return '<div class="phone still-all"><div class="os' + (o.sheet ? ' sheet-open' : '') + '" data-app="' + S.theme + '" inert>'
    + '<div class="bed"></div>' + statusBar() + '<div class="island"></div><div class="view on">' + (S.detail ? detailView(S, S.detail) : view(S)) + '</div>'
    + (o.nav === false ? '' : navBar(S.tab))
    + '<div class="scrim"></div><div class="sheet' + (o.sheet ? ' open' : '') + '"><div class="inner">' + (o.sheet ? SHEETS[o.sheet](S, o.arg) : '') + '</div></div>'
    + '<div class="homebar"></div></div></div>';
}
const fit = (html, w, h, s, attrs) => '<div class="fit" data-w="' + w + '" ' + (attrs || '') + ' style="--w:' + w + 'px;--h:' + h + 'px;--s:' + s + '">' + html + '</div>';
const phoneFit = (o, s) => fit(frame(o), 413, 872, s);

/* tabletop posture: the top half stands up and shows the ring, the bottom half lies flat with the list */
function tabletop() {
  const list = deviceChecks('android'), k = 6;
  return '<div class="tt os still-all" data-app="dark" inert>'
    + '<div class="tt-half tt-top"><div class="pane"><div class="bed"></div><div class="tt-row">'
    + orb({ size: 232, mode: 'check', segs: list.map((c, i) => (i < k ? 'on' : i === k ? 'now' : 'off')), hole: '<span class="orb-num">' + k + '<small>/11</small></span><span class="orb-cap">checks</span>' })
    + '<div class="tt-txt"><h1 class="t-display">Checking your phone.</h1><p class="proof"><i class="live"></i><span>' + list[k].doing + '</span></p></div></div></div></div>'
    + '<div class="tt-half tt-bot"><div class="pane"><div class="bed"></div><div class="clist cols">'
    + list.map((c, i) => '<div class="crow ' + (i < k ? 'done' : i === k ? 'now' : '') + '"><i></i><span class="grow">' + c.name + '</span></div>').join('')
    + '</div></div></div></div>';
}

/* the menu bar extra: the ring at 16 pixels still says everything */
function trayPopover() {
  const S = Object.assign({}, BASE_S, { dev: 'mac', layout: 'desk' }), D = DEVICES.mac;
  return '<div class="tray os still-all" data-app="dark" inert><div class="menubar"><span class="grow"></span>' + ringMark(15) + SYS + '<span>Mon 9:41</span></div>'
    + '<div class="pop glass lift"><div class="line" style="gap:14px">' + orb({ size: 76 }) + '<div class="grow"><p class="t-title">No signs you’re being watched.</p><p class="t-small">' + cleanText(S) + '</p></div></div>'
    + '<div class="feed">' + feedRows(D, 2) + '</div><button class="btn lime sm">Check now</button></div></div>';
}
