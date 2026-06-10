-- +goose Up
-- +goose StatementBegin

SET search_path TO orbguard_lab, public;

CREATE EXTENSION IF NOT EXISTS pgcrypto;

-- Cached supply-chain vulnerability records sourced from OSV.dev.
-- One row per (ecosystem, package, advisory). version_range holds the
-- OSV affected ranges/versions for the package as JSON text so the
-- server can re-run semver matching from cache without calling OSV.
CREATE TABLE IF NOT EXISTS orbguard_lab.supply_chain_vulns (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),

  ecosystem VARCHAR(100) NOT NULL,
  package_name TEXT NOT NULL,

  -- JSON: {"ranges":[{"type":"SEMVER","events":[...]}],"versions":[...]}
  version_range TEXT NOT NULL DEFAULT '',

  -- Best public identifier: CVE alias when available, otherwise the
  -- OSV/GHSA advisory id.
  cve_id VARCHAR(120) NOT NULL,

  -- critical | high | medium | low | unknown
  severity VARCHAR(20) NOT NULL DEFAULT 'unknown',
  cvss_score DOUBLE PRECISION NOT NULL DEFAULT 0,

  summary TEXT NOT NULL DEFAULT '',
  source VARCHAR(50) NOT NULL DEFAULT 'osv.dev',

  published_at TIMESTAMPTZ,
  fetched_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),

  UNIQUE (ecosystem, package_name, cve_id)
);

CREATE INDEX IF NOT EXISTS idx_supply_chain_vulns_package
  ON orbguard_lab.supply_chain_vulns (ecosystem, package_name);

CREATE INDEX IF NOT EXISTS idx_supply_chain_vulns_severity
  ON orbguard_lab.supply_chain_vulns (severity);

CREATE INDEX IF NOT EXISTS idx_supply_chain_vulns_fetched
  ON orbguard_lab.supply_chain_vulns (fetched_at);

-- Freshness tracking for OSV package lookups. A row here means the
-- package was queried successfully at last_checked_at (possibly with
-- zero vulnerabilities found) — used to avoid re-querying OSV on every
-- /supply-chain/check call.
CREATE TABLE IF NOT EXISTS orbguard_lab.supply_chain_package_checks (
  ecosystem VARCHAR(100) NOT NULL,
  package_name TEXT NOT NULL,
  last_checked_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),

  PRIMARY KEY (ecosystem, package_name)
);

-- Curated tracker SDK signatures (Exodus Privacy documented signatures).
CREATE TABLE IF NOT EXISTS orbguard_lab.known_trackers (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  name VARCHAR(200) NOT NULL,
  code_signature VARCHAR(255) NOT NULL UNIQUE,
  category VARCHAR(100) NOT NULL,
  website VARCHAR(255) NOT NULL DEFAULT '',
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_known_trackers_category
  ON orbguard_lab.known_trackers (category);

INSERT INTO orbguard_lab.known_trackers (name, code_signature, category, website) VALUES
  ('Google Firebase Analytics',            'com.google.firebase.analytics',       'Analytics',                 'https://firebase.google.com/'),
  ('Google Analytics',                     'com.google.android.gms.analytics',    'Analytics',                 'https://analytics.google.com/'),
  ('Google AdMob',                         'com.google.android.gms.ads',          'Advertisement',             'https://admob.google.com/'),
  ('Google Tag Manager',                   'com.google.android.gms.tagmanager',   'Analytics',                 'https://marketingplatform.google.com/about/tag-manager/'),
  ('Google CrashLytics',                   'com.google.firebase.crashlytics',     'Crash reporting',           'https://firebase.google.com/products/crashlytics'),
  ('Facebook Analytics',                   'com.facebook.appevents',              'Analytics',                 'https://www.facebook.com/'),
  ('Facebook Ads',                         'com.facebook.ads',                    'Advertisement',             'https://www.facebook.com/business/ads'),
  ('Facebook Login',                       'com.facebook.login',                  'Identification',            'https://developers.facebook.com/docs/facebook-login/'),
  ('AppsFlyer',                            'com.appsflyer',                       'Analytics',                 'https://www.appsflyer.com/'),
  ('Adjust',                               'com.adjust.sdk',                      'Analytics',                 'https://www.adjust.com/'),
  ('Branch',                               'io.branch',                           'Analytics',                 'https://branch.io/'),
  ('Mixpanel',                             'com.mixpanel',                        'Analytics',                 'https://mixpanel.com/'),
  ('Amplitude',                            'com.amplitude',                       'Analytics',                 'https://amplitude.com/'),
  ('Segment',                              'com.segment.analytics',               'Analytics',                 'https://segment.com/'),
  ('OneSignal',                            'com.onesignal',                       'Advertisement',             'https://onesignal.com/'),
  ('Braze (formerly Appboy)',              'com.appboy',                          'Analytics',                 'https://www.braze.com/'),
  ('Braze',                                'com.braze',                           'Analytics',                 'https://www.braze.com/'),
  ('Flurry',                               'com.flurry',                          'Analytics',                 'https://www.flurry.com/'),
  ('ironSource',                           'com.ironsource',                      'Advertisement',             'https://www.is.com/'),
  ('AppLovin',                             'com.applovin',                        'Advertisement',             'https://www.applovin.com/'),
  ('Unity3d Ads',                          'com.unity3d.ads',                     'Advertisement',             'https://unity.com/solutions/unity-ads'),
  ('Vungle',                               'com.vungle',                          'Advertisement',             'https://vungle.com/'),
  ('Chartboost',                           'com.chartboost.sdk',                  'Advertisement',             'https://www.chartboost.com/'),
  ('InMobi',                               'com.inmobi',                          'Advertisement',             'https://www.inmobi.com/'),
  ('Tapjoy',                               'com.tapjoy',                          'Advertisement',             'https://www.tapjoy.com/'),
  ('MoPub',                                'com.mopub',                           'Advertisement',             'https://www.mopub.com/'),
  ('Bugsnag',                              'com.bugsnag',                         'Crash reporting',           'https://www.bugsnag.com/'),
  ('Sentry',                               'io.sentry',                           'Crash reporting',           'https://sentry.io/'),
  ('New Relic',                            'com.newrelic.agent.android',          'Analytics',                 'https://newrelic.com/'),
  ('Microsoft App Center Analytics',       'com.microsoft.appcenter.analytics',   'Analytics',                 'https://appcenter.ms/'),
  ('Microsoft App Center Crashes',         'com.microsoft.appcenter.crashes',     'Crash reporting',           'https://appcenter.ms/'),
  ('HockeyApp',                            'net.hockeyapp.android',               'Crash reporting',           'https://hockeyapp.net/'),
  ('Yandex AppMetrica',                    'com.yandex.metrica',                  'Analytics',                 'https://appmetrica.yandex.com/'),
  ('Baidu Mobile Ads',                     'com.baidu.mobads',                    'Advertisement',             'https://union.baidu.com/'),
  ('Umeng Analytics',                      'com.umeng.analytics',                 'Analytics',                 'https://www.umeng.com/'),
  ('Tencent Bugly',                        'com.tencent.bugly',                   'Crash reporting',           'https://bugly.qq.com/'),
  ('Kochava',                              'com.kochava',                         'Analytics',                 'https://www.kochava.com/'),
  ('Singular',                             'com.singular.sdk',                    'Analytics',                 'https://www.singular.net/'),
  ('CleverTap',                            'com.clevertap.android',               'Analytics',                 'https://clevertap.com/'),
  ('Localytics',                           'com.localytics.android',              'Analytics',                 'https://uplandsoftware.com/localytics/'),
  ('Criteo',                               'com.criteo',                          'Advertisement',             'https://www.criteo.com/'),
  ('Smaato',                               'com.smaato',                          'Advertisement',             'https://www.smaato.com/'),
  ('PubMatic',                             'com.pubmatic',                        'Advertisement',             'https://pubmatic.com/'),
  ('Pangle (ByteDance)',                   'com.bytedance.sdk.openadsdk',         'Advertisement',             'https://www.pangleglobal.com/'),
  ('Airship (Urban Airship)',              'com.urbanairship',                    'Analytics',                 'https://www.airship.com/'),
  ('Pushwoosh',                            'com.pushwoosh',                       'Analytics',                 'https://www.pushwoosh.com/'),
  ('comScore',                             'com.comscore',                        'Analytics',                 'https://www.comscore.com/'),
  ('Nielsen',                              'com.nielsen.app.sdk',                 'Analytics',                 'https://www.nielsen.com/'),
  ('Adobe Experience Cloud',               'com.adobe.marketing.mobile',          'Analytics',                 'https://business.adobe.com/'),
  ('Moat (Oracle)',                        'com.moat.analytics',                  'Advertisement',             'https://www.oracle.com/cx/advertising/measure-ad-performance/'),
  ('Salesforce Marketing Cloud',           'com.salesforce.marketingcloud',       'Analytics',                 'https://www.salesforce.com/products/marketing-cloud/')
ON CONFLICT (code_signature) DO NOTHING;

-- +goose StatementEnd


-- +goose Down
-- +goose StatementBegin

SET search_path TO orbguard_lab, public;

DROP TABLE IF EXISTS orbguard_lab.known_trackers;
DROP TABLE IF EXISTS orbguard_lab.supply_chain_package_checks;
DROP TABLE IF EXISTS orbguard_lab.supply_chain_vulns;

-- +goose StatementEnd
