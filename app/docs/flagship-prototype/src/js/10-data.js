/* ---------- what is real, per device ----------
   Names, counts and limits below mirror the app as it is today:
   six shields (shields_screen.dart), eleven check stages (device_scan_service.dart),
   the score rubric (privacy_score_engine.dart), tiers and prices (pricing page).
   Figures a real device would report (times, counts) are sample data. */
const esc = s => String(s).replace(/[&<>"']/g, c => ({ '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;', "'": '&#39;' }[c]));

const SHIELDS = [
  { id: 'spy',  at: 330, icon: 'magnifer_bug',     name: 'Spyware &\u00A0Pegasus',  what: 'Looks for professional spy software' },
  { id: 'who',  at: 30,  icon: 'eye_scan',         name: 'Who’s watching you', what: 'Trackers, stalkerware and risky permissions' },
  { id: 'scam', at: 90,  icon: 'chat_round_check', name: 'Scam shield',        what: 'Texts, links and QR codes' },
  { id: 'id',   at: 150, icon: 'user_id',          name: 'Identity &\u00A0breach',  what: 'Your accounts in known leaks' },
  { id: 'vpn',  at: 210, icon: 'eye_closed',       name: 'Hidden VPN &\u00A0proxy', what: 'Traffic being secretly rerouted' },
  { id: 'call', at: 270, icon: 'phone_calling',    name: 'Secure call',        what: 'Your device, before a sensitive call' }
];
const shield = id => SHIELDS.find(s => s.id === id);

/* the eleven real stages on a phone, named by what they look for */
const CHECKS = [
  { id: 'net',   sh: 'spy', name: 'Connection interception', doing: 'Looking for interception' },
  { id: 'proc',  sh: 'spy', name: 'Injected code',           doing: 'Checking for injected code' },
  { id: 'files', sh: 'spy', name: 'Spyware traces in files', doing: 'Looking for spyware traces' },
  { id: 'data',  sh: 'spy', name: 'App data tampering',      doing: 'Checking app data for tampering' },
  { id: 'mem',   sh: 'spy', name: 'Memory tampering',        doing: 'Checking memory for tampering' },
  { id: 'cert',  sh: 'spy', name: 'Untrusted certificates',  doing: 'Looking for untrusted certificates' },
  { id: 'perm',  sh: 'who', name: 'Risky app permissions',   doing: 'Auditing app permissions' },
  { id: 'acc',   sh: 'who', name: 'Stalkerware services',    doing: 'Looking for stalkerware services' },
  { id: 'keys',  sh: 'who', name: 'Keyloggers',              doing: 'Checking keyboards for keyloggers' },
  { id: 'loc',   sh: 'who', name: 'Location tracking',       doing: 'Checking who follows your location' },
  { id: 'mal',   sh: 'spy', name: 'App malware',             doing: 'Scanning your apps for malware' }
];
/* a computer is checked in six areas instead (the tabs of the desktop security screen) */
const DESK_CHECKS = [
  { id: 'pers', sh: 'spy', name: 'Startup items', doing: 'Looking at what starts at login' },
  { id: 'sign', sh: 'spy', name: 'Code signing',  doing: 'Checking who signed your apps' },
  { id: 'fw',   sh: 'spy', name: 'Firewall',      doing: 'Checking the system firewall' },
  { id: 'netw', sh: 'vpn', name: 'Network',       doing: 'Checking network settings' },
  { id: 'brow', sh: 'spy', name: 'Browser',       doing: 'Checking your browsers' },
  { id: 'quar', sh: 'spy', name: 'Quarantine',    doing: 'Reviewing quarantined files' }
];

const DEVICES = {
  iphone: {
    os: 'iPhone', noun: 'phone', runs: ['net', 'proc', 'files', 'data', 'mem'], ms: 1050,
    shields: { spy: 'on', who: 'limited', scam: 'on', id: 'on', vpn: 'on', call: 'on' },
    report: {
      spy: 'Daily checkup on. 5\u00A0of\u00A05 checks clean.',
      who: 'iPhone keeps other apps private, even from OrbGuard.',
      scam: 'Ready. Share any text or link to check it.',
      id: '1 email watched. No new breaches.',
      vpn: 'Nothing is rerouting your traffic.',
      call: 'Ready. 7 checks before a sensitive call.'
    },
    brief: { spy: 'Spyware watch: 5\u00A0of\u00A05 clean', scam: 'Scam shield: ready for any link', id: 'Breach watch: no new leaks', vpn: 'Hidden VPN watch: nothing rerouted', call: 'Secure call: ready, 7 checks' },
    feed: [
      { icon: 'magnifer_bug', text: 'Daily checkup ran, 5\u00A0of\u00A05 clean', at: '07:02' },
      { icon: 'user_id', text: 'Email checked against breach records', at: '09:15' },
      { icon: 'eye_closed', text: 'Hidden VPN check, nothing rerouted', at: '13:40' },
      { icon: 'chat_round_check', text: 'Link you shared was checked, safe', at: '18:21' }
    ],
    marks: [7.03, 9.25, 13.66, 18.35, 21.2], blocks: [], today: '5 things checked'
  },
  android: {
    os: 'Android', noun: 'phone', runs: CHECKS.map(c => c.id), ms: 600,
    shields: { spy: 'on', who: 'on', scam: 'on', id: 'on', vpn: 'on', call: 'on' },
    report: {
      spy: 'Daily checkup on. 11\u00A0of\u00A011 checks clean.',
      who: 'Tracker firewall on. 23 trackers blocked today.',
      scam: 'Ready. Share any text or link to check it.',
      id: '1 email watched. No new breaches.',
      vpn: 'Nothing is rerouting your traffic.',
      call: 'Ready. 7 checks before a sensitive call.'
    },
    brief: { spy: 'Spyware watch: 11\u00A0of\u00A011 clean', who: 'Tracker firewall: 23 blocked today', scam: 'Scam shield: ready for any link', id: 'Breach watch: no new leaks', vpn: 'Hidden VPN watch: nothing rerouted', call: 'Secure call: ready, 7 checks' },
    feed: [
      { icon: 'shield_network', text: 'Blocked a tracker, metrics.adsrv.example', at: 'now', pink: 1 },
      { icon: 'virus', text: 'New app scanned, nothing found', at: '16:48' },
      { icon: 'user_id', text: 'Email checked against breach records', at: '09:15' },
      { icon: 'magnifer_bug', text: 'Daily checkup ran, 11\u00A0of\u00A011 clean', at: '07:02' }
    ],
    marks: [7.03, 9.25, 16.8],
    blocks: [.4, 1.1, 6.6, 7.4, 8.2, 8.5, 9.9, 10.3, 11.7, 12.2, 12.4, 13.9, 14.6, 15.1, 16.2, 17.3, 17.9, 18.4, 19.2, 19.8, 20.5, 21.0, 21.4],
    today: '23 trackers blocked, 3 checks'
  },
  mac: {
    os: 'Mac', noun: 'Mac', desk: true, runs: DESK_CHECKS.map(c => c.id), ms: 900, firewall: 'macOS Firewall',
    shields: { spy: 'on', who: 'off', scam: 'on', id: 'on', vpn: 'on', call: 'off' },
    report: {
      spy: 'Daily checkup on. 6\u00A0of\u00A06 areas clean.',
      who: 'Not available on a computer.',
      scam: 'Ready. Paste any text or link to check it.',
      id: '1 email watched. No new breaches.',
      vpn: 'Nothing is rerouting your traffic.',
      call: 'These checks need your phone.'
    },
    brief: { spy: 'Spyware watch: 6\u00A0of\u00A06 areas clean', scam: 'Scam shield: ready for any link', id: 'Breach watch: no new leaks', vpn: 'Hidden VPN watch: nothing rerouted' },
    feed: [
      { icon: 'magnifer_bug', text: 'Daily checkup ran, 6\u00A0of\u00A06 areas clean', at: '08:10' },
      { icon: 'shield_network', text: 'macOS Firewall is on', at: '08:10' },
      { icon: 'user_id', text: 'Email checked against breach records', at: '09:15' },
      { icon: 'eye_closed', text: 'Hidden VPN check, nothing rerouted', at: '15:30' }
    ],
    marks: [8.16, 9.25, 15.5], blocks: [], today: '4 things checked'
  }
};
/* Windows and Linux get the same honest desktop set, with their own words */
['win:Windows:PC:Windows Firewall', 'linux:Linux:computer:System firewall'].forEach(line => {
  const p = line.split(':'), d = JSON.parse(JSON.stringify(DEVICES.mac));
  d.os = p[1]; d.noun = p[2]; d.firewall = p[3]; d.noStore = true;
  d.feed[1].text = p[3] + ' is on';
  DEVICES[p[0]] = d;
});
const SHORT_LIMIT = { limited: 'Limited', off: 'Not here' };

const deviceChecks = dev => {
  const D = DEVICES[dev];
  return (D.desk ? DESK_CHECKS : CHECKS).map(c => Object.assign({ run: D.runs.indexOf(c.id) >= 0 }, c));
};

/* what each shield really covers on this device, and what it honestly cannot */
function shieldDetail(S, id) {
  const dev = S.dev, D = DEVICES[dev], list = deviceChecks(dev);
  const of = sh => list.filter(c => c.sh === sh);
  const names = a => a.map(c => c.name);
  switch (id) {
    case 'spy': {
      const mine = D.desk ? list : of('spy');
      return {
        lead: 'Looks for the traces that professional spyware leaves on a ' + D.noun + '.',
        covers: names(mine.filter(c => c.run)), cant: names(mine.filter(c => !c.run)),
        why: 'iOS does not let any app run these checks. OrbGuard says so and never counts them as passed.',
        act: ['check', 'Check now', 'lime']
      };
    }
    case 'who':
      if (D.desk) return { lead: 'Shows which apps can watch you through trackers, permissions and hidden services.', covers: [], cant: ['Tracker firewall', 'Stalkerware services', 'Risky app permissions', 'Location tracking'], why: 'These checks are built for phones. On a ' + D.noun + ', the Spyware shield covers startup items, code signing and the firewall instead.' };
      if (dev === 'iphone') return {
        lead: 'Shows which apps can watch you through trackers, permissions and hidden services.',
        covers: [], cant: ['Tracker firewall'].concat(names(of('who'))),
        why: 'iPhone keeps every app in its own box, so no app can see what the others do. That same wall is why stalkerware is rare on iPhone. The Spyware shield still checks the phone itself.'
      };
      return {
        lead: 'Shows which apps can watch you through trackers, permissions and hidden services.',
        covers: ['Tracker firewall, blocking as you browse'].concat(names(of('who'))), cant: [],
        log: true, act: ['toast:Tracker firewall paused for 10 minutes', 'Pause firewall for 10 minutes', 'plain']
      };
    case 'scam':
      return {
        lead: 'Tells you if a message, link or code is a trick before you act on it.',
        covers: [D.desk ? 'Texts you paste' : 'Texts you paste or share', 'Links', 'QR codes', 'Phone numbers'], cant: [],
        note: 'OrbGuard never reads your inbox. You pick a message and it checks that one.',
        act: ['tab:check', 'Check a message', 'lime']
      };
    case 'id':
      return {
        lead: 'Watches known data breaches for your accounts.',
        covers: ['Your email addresses in known breaches', 'Passwords, checked without ever sending them'], cant: [],
        act: S.moment === 'gap' ? ['fix', 'Close the gap', 'lime'] : ['tool:email', 'Check an email', 'lime']
      };
    case 'vpn':
      return {
        lead: 'Notices when your traffic is being rerouted without you knowing.',
        covers: ['A VPN tunnel you did not start', 'A system proxy rerouting your traffic'],
        cant: dev === 'iphone' ? ['Naming the app behind a VPN', 'Turning a VPN off for you'] : [],
        why: 'iPhone does not reveal which app set up a VPN. OrbGuard shows that one is active and takes you to Settings to remove it.',
        act: ['toast:Opens VPN settings on the real ' + D.noun, 'Open VPN settings', 'plain']
      };
    default:
      if (D.desk) return { lead: 'Checks a phone before a sensitive call.', covers: [], cant: ['7 device checks before a call'], why: 'Calls happen on your phone, so this shield lives there. Sign in on your phone with the same account to use it.' };
      return {
        lead: 'Checks this phone before a call that matters.',
        covers: ['7 checks of this phone, run in a few seconds'], cant: [],
        note: 'It checks the device you call from. It never listens to, records or joins a call.',
        act: ['tool:call', 'Run secure call check', 'lime']
      };
  }
}

/* on-demand tools on the Check tab; each maps to a screen that exists today */
const TOOLS = [
  { id: 'qr',    icon: 'qr_code',       name: 'Scan a QR code',    sub: 'Before you open it',
    body: 'Point the camera at any code. OrbGuard reads where it leads before you open it.', btn: 'Open camera', toast: 'The camera opens in the real app' },
  { id: 'email', icon: 'letter',        name: 'Check an email',    sub: 'Known data breaches',
    body: 'See if an address shows up in a known data breach.', btn: 'Check maya@example.com', ok: 'No known breaches for this address.', bad: '1 breach found: Northwind Travel, 2025.' },
  { id: 'wifi',  icon: 'wi_fi_router',  name: 'Check this <span class="nb">Wi-Fi</span>',  sub: 'Fake hotspots',
    body: 'Looks for signs of a fake or tampered hotspot on the network you are using.', btn: 'Check this network', ok: 'This network looks normal.' },
  { id: 'call',  icon: 'phone_calling', name: 'Before a call',     sub: '7 device checks', on: ['iphone', 'android'],
    body: 'Checks this phone in 7 ways before a sensitive call. It never listens to the call itself.', btn: 'Run secure call check', ok: '7\u00A0of\u00A07 checks passed.' },
  { id: 'vpn',   icon: 'eye_closed',    name: 'Hidden VPN',        sub: 'Rerouted traffic',
    body: 'Looks for a VPN tunnel or a proxy that you did not set up.', btn: 'Check now', ok: 'Nothing is rerouting your traffic.' },
  { id: 'apk',   icon: 'file_check',    name: 'Check an app file', sub: 'Before you install', on: ['android'],
    body: 'Pick an app file before you install it. OrbGuard scans it for malware.', btn: 'Choose a file', toast: 'The file picker opens in the real app' }
];
const toolsFor = dev => TOOLS.filter(t => !t.on || t.on.indexOf(dev) >= 0);
const SAMPLE_TEXT = 'Your parcel is on hold. Pay the 1.99 fee today or it goes back: parcel-fee-redelivery.example/track';
const SAMPLE_WHY = ['The link is not a real carrier address', 'It pushes you to pay fast', 'A small fee is a common way to steal card details'];

/* the real rubric, in the engine's own numbers */
const RUBRIC = [
  { id: 'base',   pts: 200, name: 'OrbGuard is installed' },
  { id: 'recent', pts: 200, name: 'Checked in the last 7 days' },
  { id: 'clean',  pts: 150, name: 'Last check came back clean' },
  { id: 'guards', pts: 250, name: 'Shields are on' },
  { id: 'breach', pts: 100, name: 'No breached accounts' },
  { id: 'alerts', pts: 50,  name: 'Alerts can reach you' },
  { id: 'audit',  pts: 50,  name: 'No apps with spyware-style access' }
];
const band = n => (n >= 850 ? 'Excellent' : n >= 700 ? 'Good' : n >= 450 ? 'Fair' : 'Needs work');

const PLANS = [
  { id: 'guard', name: 'Guard', month: 3.99, year: 20.99, tag: 'Everyday protection for one person.',
    gets: ['Automatic spyware and stalkerware monitoring', 'Scam link, QR code and permission checks', 'Hidden VPN and proxy detection', 'Secure device checkups', 'OrbVPN and OrbBrowser access included'] },
  { id: 'plus', name: 'Guard+', month: 6.99, year: 49.99, tag: 'Full coverage for you and your devices.', best: true, from: 'Guard',
    gets: ['Full scam shield for texts, links and QR codes', 'Secure call check before sensitive calls', 'Cover more of your devices'] },
  { id: 'ultimate', name: 'Guard Ultimate', month: 11.99, year: 79.99, tag: 'Everything, for you and your family.', from: 'Guard+',
    gets: ['Dark web and identity breach monitoring', 'Cover your whole family'] }
];
const plan = id => PLANS.find(p => p.id === id);

const PERSON = { name: 'Maya', initial: 'M', email: 'maya@example.com', breach: 'Northwind Travel', breachYear: '2025' };
