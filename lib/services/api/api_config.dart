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

  /// Get threat statistics
  /// GET /api/v1/stats
  static const String stats = '$_v1/stats';

  /// Get dashboard summary
  /// GET /api/v1/stats/dashboard
  static const String statsDashboard = '$_v1/stats/dashboard';

  /// Get protection status
  /// GET /api/v1/stats/protection
  static const String statsProtection = '$_v1/stats/protection';

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
}
