/// OrbGuard Lab API Configuration
/// Endpoints and configuration for communicating with the threat intelligence backend

class ApiConfig {
  /// Base URL for OrbGuard Lab API
  /// Override via environment or settings for different environments
  static String baseUrl = 'https://guard.orbai.world';

  /// API version prefix
  static const String apiVersion = '/api/v1';

  /// Request timeout in milliseconds
  static const int connectTimeout = 30000;
  static const int receiveTimeout = 30000;
  static const int sendTimeout = 30000;

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
  /// GET /api/v1/apps/privacy-report/{package_name}
  static String appsPrivacyReport(String packageName) => '$_v1/apps/privacy-report/$packageName';

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

  /// Check DNS configuration
  /// POST /api/v1/network/dns/check
  static const String networkDnsCheck = '$_v1/network/dns/check';

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
  /// GET /api/v1/health
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

  /// Get correlated indicators
  /// GET /api/v1/correlation/{id}
  static String correlation(String id) => '$_v1/correlation/$id';

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

  /// Get enterprise security events
  /// GET /api/v1/enterprise/events
  static const String enterpriseEvents = '$_v1/enterprise/events';

  /// Get enterprise device health
  /// GET /api/v1/enterprise/devices
  static const String enterpriseDevices = '$_v1/enterprise/devices';

  /// Get compliance frameworks
  /// GET /api/v1/enterprise/compliance/frameworks
  static const String complianceFrameworks = '$_v1/enterprise/compliance/frameworks';

  /// Get compliance reports
  /// GET /api/v1/enterprise/compliance/reports
  static const String complianceReports = '$_v1/enterprise/compliance/reports';

  /// Get compliance controls
  /// GET /api/v1/enterprise/compliance/controls
  static const String complianceControls = '$_v1/enterprise/compliance/controls';

  /// Generate compliance report
  /// POST /api/v1/enterprise/compliance/reports/generate
  static const String complianceReportGenerate = '$_v1/enterprise/compliance/reports/generate';

  /// Get enterprise policies
  /// GET /api/v1/enterprise/policies
  static const String enterprisePolicies = '$_v1/enterprise/policies';

  /// Assign policy to groups
  /// POST /api/v1/enterprise/policies/{id}/assign-groups
  static String policyAssignGroups(String id) => '$_v1/enterprise/policies/$id/assign-groups';

  /// Assign policy to devices
  /// POST /api/v1/enterprise/policies/{id}/assign-devices
  static String policyAssignDevices(String id) => '$_v1/enterprise/policies/$id/assign-devices';

  /// Remove policy assignment
  /// POST /api/v1/enterprise/policies/{id}/unassign
  static String policyUnassign(String id) => '$_v1/enterprise/policies/$id/unassign';

  /// Evaluate device compliance
  /// POST /api/v1/enterprise/devices/{id}/evaluate-compliance
  static String deviceEvaluateCompliance(String id) => '$_v1/enterprise/devices/$id/evaluate-compliance';

  /// BYOD enrollment
  /// POST /api/v1/enterprise/byod/enroll
  static const String byodEnroll = '$_v1/enterprise/byod/enroll';

  /// Get BYOD enrollment status
  /// GET /api/v1/enterprise/byod/{deviceId}/status
  static String byodStatus(String deviceId) => '$_v1/enterprise/byod/$deviceId/status';

  /// BYOD unenrollment
  /// POST /api/v1/enterprise/byod/{deviceId}/unenroll
  static String byodUnenroll(String deviceId) => '$_v1/enterprise/byod/$deviceId/unenroll';

  /// Detect device ownership
  /// GET /api/v1/enterprise/devices/{id}/ownership
  static String deviceOwnership(String id) => '$_v1/enterprise/devices/$id/ownership';

  /// Set device ownership
  /// POST /api/v1/enterprise/devices/{id}/ownership
  static String deviceOwnershipSet(String id) => '$_v1/enterprise/devices/$id/ownership';

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

  // ============================================
  // INTELLIGENCE SOURCES
  // ============================================

  /// List intelligence sources
  /// GET /api/v1/intel/sources
  static const String intelSources = '$_v1/intel/sources';

  /// Get intelligence source details
  /// GET /api/v1/intel/sources/{id}
  static String intelSource(String id) => '$_v1/intel/sources/$id';

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
  static const String mlModels = '$_v1/ml/models';

  /// Get anomaly detections
  /// GET /api/v1/ml/anomalies
  static const String mlAnomalies = '$_v1/ml/anomalies';

  /// Run ML analysis
  /// POST /api/v1/ml/analyze
  static const String mlAnalyze = '$_v1/ml/analyze';

  /// Get ML insights
  /// GET /api/v1/ml/insights
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

  // ============================================
  // DESKTOP SECURITY
  // ============================================

  /// Get persistence items
  /// GET /api/v1/desktop/persistence
  static const String desktopPersistence = '$_v1/desktop/persistence';

  /// Get signed apps
  /// GET /api/v1/desktop/apps
  static const String desktopApps = '$_v1/desktop/apps';

  /// Get firewall rules
  /// GET /api/v1/desktop/firewall
  static const String desktopFirewall = '$_v1/desktop/firewall';

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
  static const String graphNodes = '$_v1/graph/nodes';

  /// Get graph relations
  /// GET /api/v1/graph/relations
  static const String graphRelations = '$_v1/graph/relations';

  /// Search graph
  /// POST /api/v1/graph/search
  static const String graphSearch = '$_v1/graph/search';

  // ============================================
  // SUPPLY CHAIN SECURITY
  // ============================================

  /// Get known vulnerabilities
  /// GET /api/v1/supply-chain/vulnerabilities
  static const String supplyChainVulnerabilities = '$_v1/supply-chain/vulnerabilities';

  /// Check library vulnerabilities
  /// POST /api/v1/supply-chain/check
  /// Body: { "libraries": [{ "name": "...", "version": "..." }] }
  static const String supplyChainCheck = '$_v1/supply-chain/check';

  /// Get tracker signatures
  /// GET /api/v1/supply-chain/trackers
  static const String supplyChainTrackers = '$_v1/supply-chain/trackers';
}
