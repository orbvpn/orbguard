// OrbGuard Lab API Configuration
// Endpoints and configuration for communicating with the threat intelligence backend

class ApiConfig {
  /// Base URL for OrbGuard Lab API
  /// Override via environment or settings for different environments
  static String baseUrl = 'https://guard.orbai.world';

  /// API version prefix
  static const String apiVersion = '/api/v1';

  /// Request timeout in milliseconds. Mutable so the API settings screen's
  /// "Connection Timeout" can override the default before the client inits.
  static int connectTimeout = 30000;
  static int receiveTimeout = 30000;
  static int sendTimeout = 30000;

  /// Apply a user-selected connection timeout (seconds) to all Dio timeouts.
  /// Ignores non-positive values so a missing/invalid setting keeps defaults.
  static void setTimeoutSeconds(int seconds) {
    if (seconds <= 0) return;
    final ms = seconds * 1000;
    connectTimeout = ms;
    receiveTimeout = ms;
    sendTimeout = ms;
  }

  /// Retry configuration
  static const int maxRetries = 3;
  static const int retryDelayMs = 1000;

  /// Cache TTL in seconds
  static const int cacheTtlShort = 300;      // 5 minutes
  static const int cacheTtlMedium = 3600;    // 1 hour
  static const int cacheTtlLong = 86400;     // 24 hours

  /// Update the base URL (e.g., from settings)
  static void setBaseUrl(String url) {
    baseUrl = url;
  }
}

/// API Endpoints
class ApiEndpoints {
  static const String _v1 = ApiConfig.apiVersion;

  // ============================================
  // INDICATORS
  // ============================================

  /// List threat indicators with pagination
  /// GET /api/v1/indicators?page=1&limit=100&type=domain&severity=critical
  static const String indicators = '$_v1/indicators';

  /// Check indicators against threat intelligence
  /// POST /api/v1/indicators/check
  /// Body: { "indicators": [{ "value": "...", "type": "domain" }] }
  static const String indicatorsCheck = '$_v1/indicators/check';

  /// Get single indicator by ID
  /// GET /api/v1/indicators/{id}
  static String indicator(String id) => '$_v1/indicators/$id';

  // ============================================
  // SMS ANALYSIS (Safe SMS)
  // ============================================

  /// Analyze SMS message for threats
  /// POST /api/v1/sms/analyze
  /// Body: { "content": "...", "sender": "...", "timestamp": "..." }
  static const String smsAnalyze = '$_v1/sms/analyze';

  /// Batch SMS analysis
  /// POST /api/v1/sms/analyze/batch
  static const String smsAnalyzeBatch = '$_v1/sms/analyze/batch';

  /// Check URL extracted from SMS
  /// POST /api/v1/sms/check-url
  static const String smsCheckUrl = '$_v1/sms/check-url';

  /// Get phishing patterns
  /// GET /api/v1/sms/patterns
  static const String smsPatterns = '$_v1/sms/patterns';

  /// Get SMS analysis stats
  /// GET /api/v1/sms/stats
  static const String smsStats = '$_v1/sms/stats';

  /// Report SMS false positive
  /// POST /api/v1/sms/report-false-positive
  static const String smsReportFalsePositive = '$_v1/sms/report-false-positive';

  // ============================================
  // SOCIAL MEDIA (username presence enumeration)
  // ============================================

  /// Enumerate public username presence across a curated platform list (OSINT).
  /// POST /api/v1/social/username-scan
  /// Body: { "username": "..." }
  /// Response: { "username", "results": [{ "platform", "url", "status" }],
  ///   "found_count", "not_found_count", "unknown_count", "platform_count",
  ///   "scanned_at" } where status is "found" | "not_found" | "unknown".
  static const String socialUsernameScan = '$_v1/social/username-scan';

  // ============================================
  // URL PROTECTION (Safe Web)
  // ============================================

  /// Check URL reputation
  /// POST /api/v1/url/check
  /// Body: { "url": "https://..." }
  static const String urlCheck = '$_v1/url/check';

  /// Batch URL check
  /// POST /api/v1/url/check/batch
  static const String urlCheckBatch = '$_v1/url/check/batch';

  /// Get domain reputation details
  /// GET /api/v1/url/reputation/{domain}
  static String urlReputation(String domain) => '$_v1/url/reputation/$domain';

  /// Get DNS block rules for VPN
  /// GET /api/v1/url/dns-rules
  static const String urlDnsRules = '$_v1/url/dns-rules';

  // ============================================
  // QR CODE SECURITY
  // ============================================

  /// Scan QR code content for threats
  /// POST /api/v1/qr/scan
  /// Body: { "content": "...", "content_type": "url" }
  static const String qrScan = '$_v1/qr/scan';

  /// Report QR scan false positive
  /// POST /api/v1/qr/report-false-positive
  static const String qrReportFalsePositive = '$_v1/qr/report-false-positive';

  /// Batch QR scan
  /// POST /api/v1/qr/scan/batch
  static const String qrScanBatch = '$_v1/qr/scan/batch';

  /// Get QR content preview
  /// POST /api/v1/qr/preview
  static const String qrPreview = '$_v1/qr/preview';

  // ============================================
  // DARK WEB MONITORING
  // ============================================

  /// Check email for breaches
  /// POST /api/v1/darkweb/check/email
  /// Body: { "email": "user@example.com" }
  static const String darkwebCheckEmail = '$_v1/darkweb/check/email';

  /// Check password for breaches (k-anonymity)
  /// POST /api/v1/darkweb/check/password
  /// Body: { "password_hash_prefix": "5BAA6..." } (only first 5 chars of SHA-1)
  static const String darkwebCheckPassword = '$_v1/darkweb/check/password';

  /// Monitor assets for breaches
  /// POST /api/v1/darkweb/monitor
  static const String darkwebMonitor = '$_v1/darkweb/monitor';

  /// Get breach alerts
  /// GET /api/v1/darkweb/alerts
  /// Response: { "unread": [...], "read": [...], "unread_count": N, "total_count": N }
  static const String darkwebAlerts = '$_v1/darkweb/alerts';

  /// Get breach details
  /// GET /api/v1/darkweb/breaches/{id}
  static String darkwebBreach(String id) => '$_v1/darkweb/breaches/$id';

  // ============================================
  // APP SECURITY
  // ============================================

  /// Analyze app permissions and risk
  /// POST /api/v1/apps/analyze
  /// Body: { "package_name": "...", "permissions": [...], "install_source": "..." }
  static const String appsAnalyze = '$_v1/apps/analyze';

  /// Batch app analysis
  /// POST /api/v1/apps/analyze/batch
  static const String appsAnalyzeBatch = '$_v1/apps/analyze/batch';

  /// Get app privacy report
  /// POST /api/v1/apps/privacy-report
  /// Body: { "package_name": "..." }
  static const String appsPrivacyReport = '$_v1/apps/privacy-report';

  /// Get known trackers list
  /// GET /api/v1/apps/trackers
  static const String appsTrackers = '$_v1/apps/trackers';

  // ============================================
  // NETWORK SECURITY
  // ============================================

  /// Audit Wi-Fi network
  /// POST /api/v1/network/wifi/audit
  static const String networkWifiAudit = '$_v1/network/wifi/audit';

  /// Scan for rogue access points
  /// POST /api/v1/network/rogue-ap/scan
  static const String rogueApScan = '$_v1/network/rogue-ap/scan';

  /// Get trusted access points
  /// GET /api/v1/network/rogue-ap/trusted
  static const String rogueApTrusted = '$_v1/network/rogue-ap/trusted';

  /// Add trusted access point
  /// POST /api/v1/network/rogue-ap/trusted
  static const String rogueApTrustedAdd = '$_v1/network/rogue-ap/trusted';

  /// Remove trusted access point
  /// DELETE /api/v1/network/rogue-ap/trusted/{id}
  static String rogueApTrustedRemove(String id) => '$_v1/network/rogue-ap/trusted/$id';

  /// Get detected network threats
  /// GET /api/v1/network/threats
  /// Response: { "threats": [...], "count": N }
  static const String networkThreats = '$_v1/network/threats';

  /// Check DNS configuration
  /// POST /api/v1/network/dns/check
  static const String networkDnsCheck = '$_v1/network/dns/check';

  /// DNS leak-check canary configuration
  /// GET /api/v1/network/dns/leak-config
  /// Response: { "leak_check_available": bool, "canary_zone": "..." }
  static const String networkDnsLeakConfig = '$_v1/network/dns/leak-config';

  /// Get VPN recommendations
  /// POST /api/v1/network/vpn/recommend
  static const String networkVpnRecommend = '$_v1/network/vpn/recommend';

  // ============================================
  // YARA SCANNING
  // ============================================

  /// Scan data with YARA rules
  /// POST /api/v1/yara/scan
  /// Body: { "data": "base64...", "filename": "..." }
  static const String yaraScan = '$_v1/yara/scan';

  /// Quick scan with cached rules
  /// POST /api/v1/yara/quick-scan
  static const String yaraQuickScan = '$_v1/yara/quick-scan';

  /// Get available YARA rules
  /// GET /api/v1/yara/rules
  static const String yaraRules = '$_v1/yara/rules';

  // ============================================
  // MITRE ATT&CK
  // ============================================

  /// Get tactics
  /// GET /api/v1/mitre/tactics
  static const String mitreTactics = '$_v1/mitre/tactics';

  /// Get techniques
  /// GET /api/v1/mitre/techniques
  static const String mitreTechniques = '$_v1/mitre/techniques';

  /// Get technique details
  /// GET /api/v1/mitre/techniques/{id}
  static String mitreTechnique(String id) => '$_v1/mitre/techniques/$id';

  /// Export ATT&CK Navigator layer
  /// GET /api/v1/mitre/navigator/export
  static const String mitreNavigatorExport = '$_v1/mitre/navigator/export';

  // ============================================
  // CAMPAIGNS & ACTORS
  // ============================================

  /// List campaigns
  /// GET /api/v1/campaigns
  static const String campaigns = '$_v1/campaigns';

  /// Get campaign details
  /// GET /api/v1/campaigns/{id}
  static String campaign(String id) => '$_v1/campaigns/$id';

  /// List threat actors
  /// GET /api/v1/actors
  static const String actors = '$_v1/actors';

  /// Get actor details
  /// GET /api/v1/actors/{id}
  static String actor(String id) => '$_v1/actors/$id';

  // ============================================
  // ORBNET VPN INTEGRATION
  // ============================================

  /// Check if domain should be blocked
  /// POST /api/v1/orbnet/dns/block
  /// Body: { "domain": "example.com" }
  static const String orbnetDnsBlock = '$_v1/orbnet/dns/block';

  /// Batch DNS block check
  /// POST /api/v1/orbnet/dns/block/batch
  static const String orbnetDnsBlockBatch = '$_v1/orbnet/dns/block/batch';

  /// Get block rules
  /// GET /api/v1/orbnet/rules
  static const String orbnetRules = '$_v1/orbnet/rules';

  /// Sync threat intelligence
  /// POST /api/v1/orbnet/sync
  static const String orbnetSync = '$_v1/orbnet/sync';

  // ============================================
  // STATISTICS & DASHBOARD
  // ============================================

  /// Health check / ping
  /// GET /api/v1/health (backend also serves /health; the /api/v1 alias is
  /// the canonical client path)
  static const String health = '$_v1/health';

  /// Get threat statistics
  /// GET /api/v1/stats
  static const String stats = '$_v1/stats';

  /// Get dashboard summary
  /// GET /api/v1/stats/dashboard
  static const String statsDashboard = '$_v1/stats/dashboard';

  /// Get protection status
  /// GET /api/v1/stats/protection
  static const String statsProtection = '$_v1/stats/protection';

  /// Get alerts list
  /// GET /api/v1/alerts
  static const String alerts = '$_v1/alerts';

  /// Mark alert as read
  /// POST /api/v1/alerts/{id}/read
  static String alertMarkRead(String id) => '$_v1/alerts/$id/read';

  /// Clear all alerts
  /// DELETE /api/v1/alerts
  static const String alertsClear = '$_v1/alerts';

  // ============================================
  // STIX/TAXII
  // ============================================

  /// TAXII discovery
  /// GET /taxii2/
  static const String taxiiDiscovery = '/taxii2/';

  /// TAXII collections
  /// GET /taxii2/collections/
  static const String taxiiCollections = '/taxii2/collections/';

  /// Get TAXII collection objects
  /// GET /taxii2/collections/{id}/objects
  static String taxiiCollectionObjects(String id) => '/taxii2/collections/$id/objects';

  // ============================================
  // CORRELATION & GRAPH
  // ============================================

  /// Get correlated indicators for a single indicator
  /// GET /api/v1/correlation/indicator/{id}
  static String correlation(String id) => '$_v1/correlation/indicator/$id';

  /// List correlation results
  /// GET /api/v1/correlation
  static const String correlations = '$_v1/correlation';

  /// Run correlation analysis
  /// POST /api/v1/correlation/run
  static const String correlationRun = '$_v1/correlation/run';

  /// Get related entities from graph
  /// GET /api/v1/graph/related/{id}
  static String graphRelated(String id) => '$_v1/graph/related/$id';

  // ============================================
  // AUTHENTICATION
  // ============================================

  /// Login / get token
  /// POST /api/v1/auth/login
  static const String authLogin = '$_v1/auth/login';

  /// Refresh token
  /// POST /api/v1/auth/refresh
  static const String authRefresh = '$_v1/auth/refresh';

  /// Register device
  /// POST /api/v1/auth/device
  static const String authDevice = '$_v1/auth/device';

  // ============================================
  // ENTERPRISE
  // ============================================

  /// Get enterprise statistics
  /// GET /api/v1/enterprise/stats
  static const String enterpriseStats = '$_v1/enterprise/stats';

  /// Get compliance frameworks
  /// GET /api/v1/enterprise/compliance/frameworks
  static const String complianceFrameworks = '$_v1/enterprise/compliance/frameworks';

  /// Get compliance reports
  /// GET /api/v1/enterprise/compliance/reports
  static const String complianceReports = '$_v1/enterprise/compliance/reports';

  /// Get compliance control catalogs (GDPR / SOC 2 / CIS definitions).
  /// GET /api/v1/enterprise/compliance/controls
  /// Supports ?framework=gdpr|soc2|cis. Controls are returned with
  /// status "unknown" — they are catalog definitions, not assessments.
  static const String complianceControls = '$_v1/enterprise/compliance/controls';

  /// Generate compliance report
  /// POST /api/v1/enterprise/compliance/reports
  /// Body: {framework, start_date, end_date}; framework must be one of
  /// gdpr|soc2|cis (the catalogs the backend can assess against).
  static const String complianceReportGenerate = '$_v1/enterprise/compliance/reports';

  /// List conditional access policies (Zero Trust).
  /// GET /api/v1/enterprise/policies
  /// Client-path alias for /enterprise/zerotrust/policies; returns
  /// {policies: [ConditionalAccessPolicy...], count}.
  static const String enterprisePolicies = '$_v1/enterprise/policies';

  // ============================================
  // SIEM INTEGRATION
  // ============================================

  /// Get SIEM connections
  /// GET /api/v1/siem/connections
  static const String siemConnections = '$_v1/siem/connections';

  /// Get SIEM event forwarders
  /// GET /api/v1/siem/forwarders
  static const String siemForwarders = '$_v1/siem/forwarders';

  /// Get SIEM alerts
  /// GET /api/v1/siem/alerts
  static const String siemAlerts = '$_v1/siem/alerts';

  // ============================================
  // WEBHOOKS
  // ============================================

  /// List webhooks
  /// GET /api/v1/webhooks
  static const String webhooks = '$_v1/webhooks';

  /// Create/update webhook
  /// POST /api/v1/webhooks
  static const String webhooksCreate = '$_v1/webhooks';

  /// Delete webhook
  /// DELETE /api/v1/webhooks/{id}
  static String webhookDelete(String id) => '$_v1/webhooks/$id';

  /// Enable webhook
  /// POST /api/v1/webhooks/{id}/enable
  static String webhookEnable(String id) => '$_v1/webhooks/$id/enable';

  /// Disable webhook
  /// POST /api/v1/webhooks/{id}/disable
  static String webhookDisable(String id) => '$_v1/webhooks/$id/disable';

  /// Send a test delivery for a webhook
  /// POST /api/v1/webhooks/{id}/test
  static String webhookTest(String id) => '$_v1/webhooks/$id/test';

  // ============================================
  // INTELLIGENCE SOURCES
  // ============================================

  /// List intelligence sources
  /// GET /api/v1/intel/sources
  static const String intelSources = '$_v1/intel/sources';

  /// Get intelligence source details
  /// GET /api/v1/intel/sources/{id}
  static String intelSource(String id) => '$_v1/intel/sources/$id';

  /// Create intelligence source
  /// POST /api/v1/sources
  static const String sourcesCreate = '$_v1/sources';

  /// Update intelligence source
  /// PATCH /api/v1/sources/{slug}
  static String sourceUpdate(String slug) => '$_v1/sources/$slug';

  // ============================================
  // INTEGRATIONS
  // ============================================

  /// List integrations
  /// GET /api/v1/integrations
  static const String integrations = '$_v1/integrations';

  /// Update integration status
  /// PATCH /api/v1/integrations/{id}
  static String integration(String id) => '$_v1/integrations/$id';

  // ============================================
  // ML ANALYSIS
  // ============================================

  /// Get ML models
  /// GET /api/v1/ml/models
  /// Response: { "models": [...] }
  static const String mlModels = '$_v1/ml/models';

  /// Get anomaly detections
  /// GET /api/v1/ml/anomalies
  /// Response: { "anomalies": [...], "count": N }
  /// Returns 409 with code "models_not_trained" when models are untrained.
  static const String mlAnomalies = '$_v1/ml/anomalies';

  /// Run anomaly detection over indicators (ID list or filter; {} = recent indicators)
  /// POST /api/v1/ml/anomalies/detect
  /// Response: { "result": { "scores": [...], "anomaly_count": N, ... }, "processed": N }
  static const String mlAnomaliesDetect = '$_v1/ml/anomalies/detect';

  /// Run ML analysis on a raw value
  /// POST /api/v1/ml/analyze
  /// Body: { "value": "...", "type": "domain" } — "value" is REQUIRED (400 otherwise)
  static const String mlAnalyze = '$_v1/ml/analyze';

  /// Get ML insights
  /// GET /api/v1/ml/insights
  /// Response: { "insights": [...], "count": N }
  static const String mlInsights = '$_v1/ml/insights';

  // ============================================
  // PLAYBOOKS
  // ============================================

  /// List playbooks
  /// GET /api/v1/playbooks
  static const String playbooks = '$_v1/playbooks';

  /// Get playbook executions
  /// GET /api/v1/playbooks/executions
  static const String playbookExecutions = '$_v1/playbooks/executions';

  /// Execute playbook
  /// POST /api/v1/playbooks/{id}/execute
  static String playbookExecute(String id) => '$_v1/playbooks/$id/execute';

  /// Enable playbook
  /// POST /api/v1/playbooks/{id}/enable
  static String playbookEnable(String id) => '$_v1/playbooks/$id/enable';

  /// Disable playbook
  /// POST /api/v1/playbooks/{id}/disable
  static String playbookDisable(String id) => '$_v1/playbooks/$id/disable';

  // ============================================
  // DESKTOP SECURITY
  // ============================================

  /// Get persistence items
  /// GET /api/v1/desktop/persistence
  /// Response: { "items": [...], "scanned_at": "..." }
  static const String desktopPersistence = '$_v1/desktop/persistence';

  /// Get signed apps
  /// GET /api/v1/desktop/apps
  /// Response: { "apps": [...], "scanned_at": "..." }
  static const String desktopApps = '$_v1/desktop/apps';

  /// Get firewall rules
  /// GET /api/v1/desktop/firewall
  /// Response: { "rules": [...], ... }
  static const String desktopFirewall = '$_v1/desktop/firewall';

  /// Scan persistence items
  /// POST /api/v1/desktop/persistence/scan
  static const String desktopPersistenceScan = '$_v1/desktop/persistence/scan';

  /// Quick scan persistence
  /// POST /api/v1/desktop/persistence/quick-scan
  static const String desktopPersistenceQuickScan = '$_v1/desktop/persistence/quick-scan';

  /// Verify code signing
  /// POST /api/v1/desktop/codesign/verify
  static const String desktopCodesignVerify = '$_v1/desktop/codesign/verify';

  /// Get network connections
  /// GET /api/v1/desktop/network/connections
  static const String desktopNetworkConnections = '$_v1/desktop/network/connections';

  /// Get listening ports
  /// GET /api/v1/desktop/network/listening
  static const String desktopNetworkListening = '$_v1/desktop/network/listening';

  /// Get outbound connections
  /// GET /api/v1/desktop/network/outbound
  static const String desktopNetworkOutbound = '$_v1/desktop/network/outbound';

  /// Get firewall rules (network monitor)
  /// GET /api/v1/desktop/network/rules
  static const String desktopNetworkRules = '$_v1/desktop/network/rules';

  /// Add firewall rule
  /// POST /api/v1/desktop/network/rules
  static const String desktopNetworkRulesAdd = '$_v1/desktop/network/rules';

  /// Delete firewall rule
  /// DELETE /api/v1/desktop/network/rules/{id}
  static String desktopNetworkRuleDelete(String id) => '$_v1/desktop/network/rules/$id';

  /// Block IP address
  /// POST /api/v1/desktop/network/block-ip
  static const String desktopBlockIp = '$_v1/desktop/network/block-ip';

  /// Scan browser extensions
  /// POST /api/v1/desktop/browser/extensions/scan
  static const String desktopBrowserScan = '$_v1/desktop/browser/extensions/scan';

  /// VirusTotal hash lookup
  /// GET /api/v1/desktop/virustotal/hash/{hash}
  static String desktopVtHash(String hash) => '$_v1/desktop/virustotal/hash/$hash';

  /// VirusTotal IP lookup
  /// GET /api/v1/desktop/virustotal/ip/{ip}
  static String desktopVtIp(String ip) => '$_v1/desktop/virustotal/ip/$ip';

  /// Full desktop security scan
  /// POST /api/v1/desktop/scan/full
  static const String desktopFullScan = '$_v1/desktop/scan/full';

  // ============================================
  // ANALYTICS & REPORTING
  // ============================================

  /// Get threat analytics
  /// GET /api/v1/analytics/threats
  static const String analyticsThreat = '$_v1/analytics/threats';

  /// Get alert metrics
  /// GET /api/v1/analytics/alerts
  static const String analyticsAlerts = '$_v1/analytics/alerts';

  /// Get detection metrics
  /// GET /api/v1/analytics/detections
  static const String analyticsDetections = '$_v1/analytics/detections';

  /// Get source health
  /// GET /api/v1/analytics/sources
  static const String analyticsSources = '$_v1/analytics/sources';

  /// Get geo distribution
  /// GET /api/v1/analytics/geo
  static const String analyticsGeo = '$_v1/analytics/geo';

  /// Get analytics dashboard
  /// GET /api/v1/analytics/dashboard
  static const String analyticsDashboard = '$_v1/analytics/dashboard';

  /// List reports
  /// GET /api/v1/analytics/reports
  static const String analyticsReports = '$_v1/analytics/reports';

  /// Create report
  /// POST /api/v1/analytics/reports
  static const String analyticsReportCreate = '$_v1/analytics/reports';

  /// Get report by ID
  /// GET /api/v1/analytics/reports/{id}
  static String analyticsReport(String id) => '$_v1/analytics/reports/$id';

  // ============================================
  // VPN SERVERS
  // ============================================

  /// List VPN servers
  /// GET /api/v1/vpn/servers
  static const String vpnServers = '$_v1/vpn/servers';

  /// Get blocked domains for VPN
  /// GET /api/v1/vpn/blocked
  static const String vpnBlocked = '$_v1/vpn/blocked';

  /// Get VPN connection stats
  /// GET /api/v1/vpn/stats
  static const String vpnStats = '$_v1/vpn/stats';

  // ============================================
  // THREAT GRAPH
  // ============================================

  /// Get graph nodes
  /// GET /api/v1/graph/nodes
  /// Response: { "nodes": [...], "count": N }
  static const String graphNodes = '$_v1/graph/nodes';

  /// Get graph relations
  /// GET /api/v1/graph/relations
  /// Response: { "relations": [...], "count": N }
  static const String graphRelations = '$_v1/graph/relations';

  /// Search graph
  /// POST /api/v1/graph/search
  static const String graphSearch = '$_v1/graph/search';

  // ============================================
  // SUPPLY CHAIN SECURITY
  // ============================================

  // NOTE: supplyChainVulnerabilities (GET /supply-chain/vulnerabilities) was
  // removed with its only client consumer; version-aware vulnerability
  // matching uses supplyChainCheck below.

  /// Check package vulnerabilities
  /// POST /api/v1/supply-chain/check
  /// Body: { "packages": [{ "name": "...", "version": "...", "ecosystem": "..."? }] }
  /// Response: { "results": [...] }
  static const String supplyChainCheck = '$_v1/supply-chain/check';

  /// Get tracker signatures
  /// GET /api/v1/supply-chain/trackers
  /// Response: { "trackers": [...], "count": N }
  static const String supplyChainTrackers = '$_v1/supply-chain/trackers';

  // ============================================
  // DEVICE SECURITY
  // ============================================

  /// Device base endpoint
  /// GET/POST /api/v1/device
  static const String devices = '$_v1/device';

  /// Register device
  /// POST /api/v1/device/register
  static const String devicesRegister = '$_v1/device/register';

  /// Get device security status
  /// GET /api/v1/device/{id}/security-status
  static String deviceSecurity(String id) => '$_v1/device/$id/security-status';

  /// Get anti-theft settings
  /// GET /api/v1/device/{id}/settings
  static String deviceAntiTheft(String id) => '$_v1/device/$id/settings';

  /// Locate device
  /// POST /api/v1/device/{id}/locate
  static String deviceLocate(String id) => '$_v1/device/$id/locate';

  /// Send device command
  /// POST /api/v1/device/{id}/command
  /// Body: models.RemoteCommand — { "type": "...", "payload": "(json string)" }
  static String deviceCommand(String id) => '$_v1/device/$id/command';

  /// Lock device
  /// POST /api/v1/device/{id}/lock
  /// Body (optional): { "pin", "message", "phone" }
  static String deviceLock(String id) => '$_v1/device/$id/lock';

  /// Wipe device
  /// POST /api/v1/device/{id}/wipe
  /// Body: { "confirmation_id" (REQUIRED), "factory_reset", "wipe_sd_card", "wipe_esim" }
  static String deviceWipe(String id) => '$_v1/device/$id/wipe';

  /// Ring device
  /// POST /api/v1/device/{id}/ring
  static String deviceRing(String id) => '$_v1/device/$id/ring';

  /// Mark device as lost
  /// POST /api/v1/device/{id}/mark-lost
  static String deviceLost(String id) => '$_v1/device/$id/mark-lost';

  /// Mark device as stolen
  /// POST /api/v1/device/{id}/mark-stolen
  static String deviceStolen(String id) => '$_v1/device/$id/mark-stolen';

  /// Mark device as recovered
  /// POST /api/v1/device/{id}/mark-recovered
  static String deviceRecovered(String id) => '$_v1/device/$id/mark-recovered';

  /// Get device location history
  /// GET /api/v1/device/{id}/location/history
  static String deviceLocationHistory(String id) => '$_v1/device/$id/location/history';

  /// Get SIM history
  /// GET /api/v1/device/{id}/sim/history
  static String deviceSimHistory(String id) => '$_v1/device/$id/sim/history';

  /// Add trusted SIM
  /// POST /api/v1/device/{id}/sim/trusted
  static String deviceTrustedSim(String id) => '$_v1/device/$id/sim/trusted';

  /// Audit OS vulnerabilities (no device segment — global audit route)
  /// POST /api/v1/device/vulnerabilities/audit
  /// Body: { "device_id", "platform", "os_version", "security_patch", "api_level" }
  /// "platform" and "os_version" are REQUIRED (400 otherwise)
  static const String deviceVulnerabilitiesAudit = '$_v1/device/vulnerabilities/audit';

  /// Register a push (FCM/APNs) token for a device so the backend can wake the
  /// device-agent with a high-priority data push instead of waiting for the
  /// next HTTP poll.
  /// POST /api/v1/device/{device_id}/push-token
  /// Body: { "token": "`<fcm/apns token>`", "platform": "android"|"ios" }
  ///
  /// ACTIVATION: the backend handler + migration 022 (device push_token column
  /// already exists; 022 adds the route wiring + FCM sender config) ship with
  /// the FCM rollout — see docs/FCM_SETUP.md. Until Firebase provides a token
  /// on-device this endpoint is never called, so it is inert in current builds.
  static String devicePushToken(String id) => '$_v1/device/$id/push-token';

  // ============================================
  // FORENSICS
  // ============================================

  /// Forensics base endpoint
  /// GET /api/v1/forensics
  static const String forensics = '$_v1/forensics';

  /// Get forensic capabilities
  /// GET /api/v1/forensics/capabilities
  static const String forensicsCapabilities = '$_v1/forensics/capabilities';

  /// Get IOC stats
  /// GET /api/v1/forensics/iocs/stats
  static const String forensicsIocStats = '$_v1/forensics/iocs/stats';

  /// Analyze shutdown log
  /// POST /api/v1/forensics/analyze/shutdown-log
  static const String forensicsAnalyzeShutdownLog = '$_v1/forensics/analyze/shutdown-log';

  /// Analyze backup
  /// POST /api/v1/forensics/analyze/backup
  static const String forensicsAnalyzeBackup = '$_v1/forensics/analyze/backup';

  /// Analyze data usage
  /// POST /api/v1/forensics/analyze/data-usage
  static const String forensicsAnalyzeDataUsage = '$_v1/forensics/analyze/data-usage';

  /// Analyze sysdiagnose
  /// POST /api/v1/forensics/analyze/sysdiagnose
  static const String forensicsAnalyzeSysdiagnose = '$_v1/forensics/analyze/sysdiagnose';

  /// Analyze logcat
  /// POST /api/v1/forensics/analyze/logcat
  static const String forensicsAnalyzeLogcat = '$_v1/forensics/analyze/logcat';

  /// Run full forensic analysis
  /// POST /api/v1/forensics/full-analysis
  static const String forensicsFullAnalysis = '$_v1/forensics/full-analysis';

  /// Quick forensic check
  /// POST /api/v1/forensics/quick-check
  static const String forensicsQuickCheck = '$_v1/forensics/quick-check';

  /// Upload iOS backup for analysis (multipart: file + device_id)
  /// POST /api/v1/forensics/ios/backup/upload
  static const String forensicsIosBackupUpload = '$_v1/forensics/ios/backup/upload';

  /// Upload iOS sysdiagnose archive for analysis (multipart: file + device_id)
  /// POST /api/v1/forensics/ios/sysdiagnose/upload
  static const String forensicsIosSysdiagnoseUpload = '$_v1/forensics/ios/sysdiagnose/upload';

  /// Upload Android bugreport for analysis (multipart: file + device_id)
  /// POST /api/v1/forensics/android/bugreport/upload
  static const String forensicsAndroidBugreportUpload = '$_v1/forensics/android/bugreport/upload';

  // ============================================
  // DIGITAL FOOTPRINT
  // ============================================

  /// Get data brokers list (response is a bare JSON array of brokers)
  /// GET /api/v1/footprint/brokers
  static const String footprintBrokers = '$_v1/footprint/brokers';

  /// Scan digital footprint
  /// POST /api/v1/footprint/scan
  /// Body: { "email": "...", ... } — "email" is REQUIRED
  static const String footprintScan = '$_v1/footprint/scan';

  /// Quick footprint scan
  /// POST /api/v1/footprint/quick-scan
  static const String footprintQuickScan = '$_v1/footprint/quick-scan';

  /// Request data removal from a broker
  /// POST /api/v1/footprint/removal
  /// Body: { "broker_id": "(uuid)", "email": "...", "user_id": "..." }
  static const String footprintRemoval = '$_v1/footprint/removal';

  /// Get removal request status
  /// GET /api/v1/footprint/removal/{id}
  static String footprintRemovalStatus(String id) => '$_v1/footprint/removal/$id';

  // ============================================
  // PRIVACY
  // ============================================

  /// Privacy base endpoint
  /// GET /api/v1/privacy
  static const String privacy = '$_v1/privacy';

  /// Audit privacy
  /// POST /api/v1/privacy/audit
  static const String privacyAudit = '$_v1/privacy/audit';

  /// Record privacy event
  /// POST /api/v1/privacy/events
  static const String privacyEvents = '$_v1/privacy/events';

  /// Check clipboard
  /// POST /api/v1/privacy/clipboard/check
  static const String privacyClipboardCheck = '$_v1/privacy/clipboard/check';

  /// Check whether a domain is a tracker that should be blocked
  /// POST /api/v1/privacy/trackers/should-block
  /// Body: { "domain": "...", "settings"?: {...} }
  /// Response: { "domain", "should_block", "tracker" }
  static const String privacyTrackersShouldBlock =
      '$_v1/privacy/trackers/should-block';

  // ============================================
  // SCAM DETECTION
  // ============================================

  /// Scam base endpoint
  /// GET /api/v1/scam
  static const String scam = '$_v1/scam';

  /// Analyze scam
  /// POST /api/v1/scam/analyze
  static const String scamAnalyze = '$_v1/scam/analyze';

  /// Get scam patterns
  /// GET /api/v1/scam/patterns
  static const String scamPatterns = '$_v1/scam/patterns';

  /// Report scam
  /// POST /api/v1/scam/report
  static const String scamReport = '$_v1/scam/report';

  /// Get phone reputation
  /// GET /api/v1/scam/phone/{number}
  static String scamPhoneReputation(String number) => '$_v1/scam/phone/$number';

  /// Report phone number
  /// POST /api/v1/scam/phone/report
  static const String scamPhoneReport = '$_v1/scam/phone/report';
}
