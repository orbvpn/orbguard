/// OrbGuard Lab API Client
/// Main client for communicating with the threat intelligence backend

import 'dart:async';
import 'dart:io';

import 'package:device_info_plus/device_info_plus.dart';
import 'package:dio/dio.dart';

import 'api_config.dart';
import 'api_interceptors.dart';
import '../../models/api/threat_indicator.dart';
import '../../models/api/sms_analysis.dart';
import '../../models/api/url_reputation.dart';
import '../../models/api/campaign.dart';
import '../../models/api/threat_stats.dart';

/// Singleton API client for OrbGuard Lab
class OrbGuardApiClient {
  static OrbGuardApiClient? _instance;
  static OrbGuardApiClient get instance => _instance ??= OrbGuardApiClient._();

  late final Dio _dio;
  late final AuthInterceptor _authInterceptor;
  late final CacheInterceptor _cacheInterceptor;

  bool _initialized = false;

  OrbGuardApiClient._();

  /// Initialize the API client
  Future<void> init({String? baseUrl, bool enableLogging = false}) async {
    if (_initialized) return;

    // Create Dio instance
    _dio = Dio(BaseOptions(
      baseUrl: baseUrl ?? ApiConfig.baseUrl,
      connectTimeout: Duration(milliseconds: ApiConfig.connectTimeout),
      receiveTimeout: Duration(milliseconds: ApiConfig.receiveTimeout),
      sendTimeout: Duration(milliseconds: ApiConfig.sendTimeout),
      headers: {
        'Content-Type': 'application/json',
        'Accept': 'application/json',
      },
    ));

    // Initialize interceptors
    _authInterceptor = AuthInterceptor(_dio);
    await _authInterceptor.init();

    _cacheInterceptor = CacheInterceptor();

    // Add interceptors in order
    if (enableLogging) {
      _dio.interceptors.add(LoggingInterceptor(
        enabled: true,
        logRequestBody: true,
        logResponseBody: true,
      ));
    }

    _dio.interceptors.add(_authInterceptor);
    _dio.interceptors.add(RetryInterceptor(_dio));
    _dio.interceptors.add(_cacheInterceptor);

    // Register device if not already done
    if (_authInterceptor.deviceId == null) {
      await _registerDevice();
    }

    _initialized = true;
  }

  /// Register device with backend
  Future<void> _registerDevice() async {
    try {
      final deviceInfo = DeviceInfoPlugin();
      Map<String, dynamic> deviceData = {};

      if (Platform.isAndroid) {
        final info = await deviceInfo.androidInfo;
        deviceData = {
          'platform': 'android',
          'model': info.model,
          'manufacturer': info.manufacturer,
          'version': info.version.release,
          'sdk_int': info.version.sdkInt,
          'device_id': info.id,
        };
      } else if (Platform.isIOS) {
        final info = await deviceInfo.iosInfo;
        deviceData = {
          'platform': 'ios',
          'model': info.model,
          'name': info.name,
          'version': info.systemVersion,
          'device_id': info.identifierForVendor,
        };
      }

      final response = await _dio.post(
        ApiEndpoints.authDevice,
        data: deviceData,
      );

      if (response.statusCode == 200 || response.statusCode == 201) {
        final data = response.data as Map<String, dynamic>;
        final deviceId = data['device_id'] as String?;
        final token = data['token'] as String?;

        if (deviceId != null) {
          await _authInterceptor.setDeviceId(deviceId);
        }
        if (token != null) {
          await _authInterceptor.saveTokens(accessToken: token);
        }
      }
    } catch (e) {
      // Device registration is optional, continue without it
    }
  }

  /// Update base URL
  void setBaseUrl(String url) {
    _dio.options.baseUrl = url;
    ApiConfig.setBaseUrl(url);
  }

  /// Clear cache
  void clearCache() {
    _cacheInterceptor.clearCache();
  }

  /// Check if authenticated
  bool get isAuthenticated => _authInterceptor.isAuthenticated;

  // ============================================
  // GENERIC HTTP METHODS (for services that need direct access)
  // ============================================

  /// Generic GET request
  Future<T> get<T>(String path, {Map<String, dynamic>? queryParameters}) async {
    final response = await _dio.get(path, queryParameters: queryParameters);
    return response.data as T;
  }

  /// Generic POST request
  Future<T> post<T>(String path, {dynamic data}) async {
    final response = await _dio.post(path, data: data);
    return response.data as T;
  }

  /// Generic PUT request
  Future<T> put<T>(String path, {dynamic data}) async {
    final response = await _dio.put(path, data: data);
    return response.data as T;
  }

  /// Generic DELETE request
  Future<T> delete<T>(String path) async {
    final response = await _dio.delete(path);
    return response.data as T;
  }

  // ============================================
  // DEVICE SECURITY
  // ============================================

  /// Register device with backend
  Future<Map<String, dynamic>> registerDevice(Map<String, dynamic> deviceData) async {
    try {
      final response = await _dio.post(ApiEndpoints.authDevice, data: deviceData);
      return response.data as Map<String, dynamic>? ?? {};
    } on DioException catch (e) {
      throw ApiError.fromDioException(e);
    }
  }

  /// Get device security status
  Future<Map<String, dynamic>> getDeviceSecurityStatus() async {
    try {
      final response = await _dio.get('${ApiEndpoints.devices}/security/status');
      return response.data as Map<String, dynamic>? ?? {};
    } on DioException catch (e) {
      throw ApiError.fromDioException(e);
    }
  }

  /// Get anti-theft settings
  Future<Map<String, dynamic>> getAntiTheftSettings() async {
    try {
      final response = await _dio.get('${ApiEndpoints.devices}/anti-theft/settings');
      return response.data as Map<String, dynamic>? ?? {};
    } on DioException catch (e) {
      throw ApiError.fromDioException(e);
    }
  }

  /// Update anti-theft settings
  Future<bool> updateAntiTheftSettings(Map<String, dynamic> settings) async {
    try {
      await _dio.put('${ApiEndpoints.devices}/anti-theft/settings', data: settings);
      return true;
    } on DioException catch (e) {
      throw ApiError.fromDioException(e);
    }
  }

  /// Locate device
  Future<Map<String, dynamic>> locateDevice() async {
    try {
      final response = await _dio.get('${ApiEndpoints.devices}/locate');
      return response.data as Map<String, dynamic>? ?? {};
    } on DioException catch (e) {
      throw ApiError.fromDioException(e);
    }
  }

  /// Send device command (lock, wipe, alarm, etc.)
  Future<bool> sendDeviceCommand(String command, {Map<String, dynamic>? data}) async {
    try {
      await _dio.post('${ApiEndpoints.devices}/command/$command', data: data);
      return true;
    } on DioException catch (e) {
      throw ApiError.fromDioException(e);
    }
  }

  /// Mark device as lost
  Future<bool> markDeviceLost({String? message}) async {
    try {
      await _dio.post('${ApiEndpoints.devices}/status/lost', data: {'message': message});
      return true;
    } on DioException catch (e) {
      throw ApiError.fromDioException(e);
    }
  }

  /// Mark device as stolen
  Future<bool> markDeviceStolen({String? reportNumber}) async {
    try {
      await _dio.post('${ApiEndpoints.devices}/status/stolen', data: {'report_number': reportNumber});
      return true;
    } on DioException catch (e) {
      throw ApiError.fromDioException(e);
    }
  }

  /// Mark device as recovered
  Future<bool> markDeviceRecovered() async {
    try {
      await _dio.post('${ApiEndpoints.devices}/status/recovered');
      return true;
    } on DioException catch (e) {
      throw ApiError.fromDioException(e);
    }
  }

  /// Get location history
  Future<List<Map<String, dynamic>>> getLocationHistory({int days = 7}) async {
    try {
      final response = await _dio.get('${ApiEndpoints.devices}/location/history', queryParameters: {'days': days});
      return (response.data['locations'] as List<dynamic>?)?.cast<Map<String, dynamic>>() ?? [];
    } on DioException catch (e) {
      throw ApiError.fromDioException(e);
    }
  }

  /// Get SIM history
  Future<List<Map<String, dynamic>>> getSIMHistory() async {
    try {
      final response = await _dio.get('${ApiEndpoints.devices}/sim/history');
      return (response.data['sim_history'] as List<dynamic>?)?.cast<Map<String, dynamic>>() ?? [];
    } on DioException catch (e) {
      throw ApiError.fromDioException(e);
    }
  }

  /// Add trusted SIM
  Future<bool> addTrustedSIM(String simId, String name) async {
    try {
      await _dio.post('${ApiEndpoints.devices}/sim/trusted', data: {'sim_id': simId, 'name': name});
      return true;
    } on DioException catch (e) {
      throw ApiError.fromDioException(e);
    }
  }

  /// Audit OS vulnerabilities
  Future<Map<String, dynamic>> auditOSVulnerabilities() async {
    try {
      final response = await _dio.post('${ApiEndpoints.devices}/security/audit-os');
      return response.data as Map<String, dynamic>? ?? {};
    } on DioException catch (e) {
      throw ApiError.fromDioException(e);
    }
  }

  // ============================================
  // FORENSICS
  // ============================================

  /// Get forensic capabilities
  Future<Map<String, dynamic>> getForensicCapabilities() async {
    try {
      final response = await _dio.get('${ApiEndpoints.forensics}/capabilities');
      return response.data as Map<String, dynamic>? ?? {};
    } on DioException catch (e) {
      throw ApiError.fromDioException(e);
    }
  }

  /// Get IOC stats
  Future<Map<String, dynamic>> getIOCStats() async {
    try {
      final response = await _dio.get('${ApiEndpoints.forensics}/ioc/stats');
      return response.data as Map<String, dynamic>? ?? {};
    } on DioException catch (e) {
      throw ApiError.fromDioException(e);
    }
  }

  /// Analyze shutdown log
  Future<Map<String, dynamic>> analyzeShutdownLog(Map<String, dynamic> logData) async {
    try {
      final response = await _dio.post('${ApiEndpoints.forensics}/analyze/shutdown', data: logData);
      return response.data as Map<String, dynamic>? ?? {};
    } on DioException catch (e) {
      throw ApiError.fromDioException(e);
    }
  }

  /// Analyze backup
  Future<Map<String, dynamic>> analyzeBackup(Map<String, dynamic> backupData) async {
    try {
      final response = await _dio.post('${ApiEndpoints.forensics}/analyze/backup', data: backupData);
      return response.data as Map<String, dynamic>? ?? {};
    } on DioException catch (e) {
      throw ApiError.fromDioException(e);
    }
  }

  /// Analyze data usage
  Future<Map<String, dynamic>> analyzeDataUsage(Map<String, dynamic> usageData) async {
    try {
      final response = await _dio.post('${ApiEndpoints.forensics}/analyze/data-usage', data: usageData);
      return response.data as Map<String, dynamic>? ?? {};
    } on DioException catch (e) {
      throw ApiError.fromDioException(e);
    }
  }

  /// Analyze sysdiagnose (iOS)
  Future<Map<String, dynamic>> analyzeSysdiagnose(Map<String, dynamic> sysdiagnoseData) async {
    try {
      final response = await _dio.post('${ApiEndpoints.forensics}/analyze/sysdiagnose', data: sysdiagnoseData);
      return response.data as Map<String, dynamic>? ?? {};
    } on DioException catch (e) {
      throw ApiError.fromDioException(e);
    }
  }

  /// Analyze logcat (Android)
  Future<Map<String, dynamic>> analyzeLogcat(Map<String, dynamic> logcatData) async {
    try {
      final response = await _dio.post('${ApiEndpoints.forensics}/analyze/logcat', data: logcatData);
      return response.data as Map<String, dynamic>? ?? {};
    } on DioException catch (e) {
      throw ApiError.fromDioException(e);
    }
  }

  /// Run full forensic analysis
  Future<Map<String, dynamic>> runFullForensicAnalysis(Map<String, dynamic> data) async {
    try {
      final response = await _dio.post('${ApiEndpoints.forensics}/analyze/full', data: data);
      return response.data as Map<String, dynamic>? ?? {};
    } on DioException catch (e) {
      throw ApiError.fromDioException(e);
    }
  }

  /// Quick forensic check
  Future<Map<String, dynamic>> quickForensicCheck(List<Map<String, dynamic>> indicators) async {
    try {
      final response = await _dio.post('${ApiEndpoints.forensics}/check', data: {'indicators': indicators});
      return response.data as Map<String, dynamic>? ?? {};
    } on DioException catch (e) {
      throw ApiError.fromDioException(e);
    }
  }

  // ============================================
  // PRIVACY
  // ============================================

  /// Audit privacy
  Future<Map<String, dynamic>> auditPrivacy(Map<String, dynamic> appData) async {
    try {
      final response = await _dio.post('${ApiEndpoints.privacy}/audit', data: appData);
      return response.data as Map<String, dynamic>? ?? {};
    } on DioException catch (e) {
      throw ApiError.fromDioException(e);
    }
  }

  /// Record privacy event
  Future<bool> recordPrivacyEvent(Map<String, dynamic> event) async {
    try {
      await _dio.post('${ApiEndpoints.privacy}/events', data: event);
      return true;
    } on DioException catch (e) {
      throw ApiError.fromDioException(e);
    }
  }

  /// Check clipboard content
  Future<Map<String, dynamic>> checkClipboard(String content) async {
    try {
      final response = await _dio.post('${ApiEndpoints.privacy}/check/clipboard', data: {'content': content});
      return response.data as Map<String, dynamic>? ?? {};
    } on DioException catch (e) {
      throw ApiError.fromDioException(e);
    }
  }

  // ============================================
  // SCAM DETECTION
  // ============================================

  /// Analyze potential scam
  Future<Map<String, dynamic>> analyzeScam(Map<String, dynamic> scamData) async {
    try {
      final response = await _dio.post('${ApiEndpoints.scam}/analyze', data: scamData);
      return response.data as Map<String, dynamic>? ?? {};
    } on DioException catch (e) {
      throw ApiError.fromDioException(e);
    }
  }

  /// Get scam patterns
  Future<List<Map<String, dynamic>>> getScamPatterns() async {
    try {
      final response = await _dio.get('${ApiEndpoints.scam}/patterns');
      return (response.data['patterns'] as List<dynamic>?)?.cast<Map<String, dynamic>>() ?? [];
    } on DioException catch (e) {
      throw ApiError.fromDioException(e);
    }
  }

  /// Report scam
  Future<bool> reportScam(Map<String, dynamic> report) async {
    try {
      await _dio.post('${ApiEndpoints.scam}/report', data: report);
      return true;
    } on DioException catch (e) {
      throw ApiError.fromDioException(e);
    }
  }

  /// Get phone reputation
  Future<Map<String, dynamic>> getPhoneReputation(String phoneNumber) async {
    try {
      final response = await _dio.get('${ApiEndpoints.scam}/phone/reputation', queryParameters: {'number': phoneNumber});
      return response.data as Map<String, dynamic>? ?? {};
    } on DioException catch (e) {
      throw ApiError.fromDioException(e);
    }
  }

  /// Report phone number
  Future<bool> reportPhoneNumber(String phoneNumber, String reason) async {
    try {
      await _dio.post('${ApiEndpoints.scam}/phone/report', data: {'number': phoneNumber, 'reason': reason});
      return true;
    } on DioException catch (e) {
      throw ApiError.fromDioException(e);
    }
  }

  // ============================================
  // NETWORK
  // ============================================

  /// Check if domain should be blocked
  Future<bool> shouldBlockDomain(String domain) async {
    try {
      final response = await _dio.post(ApiEndpoints.networkDnsCheck, data: {'domain': domain});
      return response.data['should_block'] as bool? ?? false;
    } on DioException catch (e) {
      throw ApiError.fromDioException(e);
    }
  }

  // ============================================
  // INDICATORS
  // ============================================

  /// List threat indicators with optional filters
  Future<PaginatedResponse<ThreatIndicator>> listIndicators({
    int page = 1,
    int limit = 100,
    IndicatorType? type,
    SeverityLevel? severity,
    List<String>? tags,
    String? campaign,
  }) async {
    try {
      final queryParams = <String, dynamic>{
        'page': page,
        'limit': limit,
      };

      if (type != null) queryParams['type'] = type.value;
      if (severity != null) queryParams['severity'] = severity.value;
      if (tags != null && tags.isNotEmpty) queryParams['tags'] = tags.join(',');
      if (campaign != null) queryParams['campaign'] = campaign;

      final response = await _dio.get(
        ApiEndpoints.indicators,
        queryParameters: queryParams,
      );

      return PaginatedResponse.fromJson(
        response.data,
        (json) => ThreatIndicator.fromJson(json as Map<String, dynamic>),
      );
    } on DioException catch (e) {
      throw ApiError.fromDioException(e);
    }
  }

  /// Check indicators against threat intelligence
  Future<List<IndicatorCheckResult>> checkIndicators(
    List<IndicatorCheckRequest> indicators,
  ) async {
    try {
      final response = await _dio.post(
        ApiEndpoints.indicatorsCheck,
        data: {
          'indicators': indicators.map((i) => i.toJson()).toList(),
        },
      );

      final results = response.data['results'] as List<dynamic>;
      return results
          .map((r) => IndicatorCheckResult.fromJson(r as Map<String, dynamic>))
          .toList();
    } on DioException catch (e) {
      throw ApiError.fromDioException(e);
    }
  }

  /// Get single indicator by ID
  Future<ThreatIndicator> getIndicator(String id) async {
    try {
      final response = await _dio.get(ApiEndpoints.indicator(id));
      return ThreatIndicator.fromJson(response.data as Map<String, dynamic>);
    } on DioException catch (e) {
      throw ApiError.fromDioException(e);
    }
  }

  // ============================================
  // SMS ANALYSIS
  // ============================================

  /// Analyze SMS message for threats
  Future<SmsAnalysisResult> analyzeSms(SmsAnalysisRequest request) async {
    try {
      final response = await _dio.post(
        ApiEndpoints.smsAnalyze,
        data: request.toJson(),
      );
      return SmsAnalysisResult.fromJson(response.data as Map<String, dynamic>);
    } on DioException catch (e) {
      throw ApiError.fromDioException(e);
    }
  }

  /// Batch SMS analysis
  Future<List<SmsAnalysisResult>> analyzeSmssBatch(
    List<SmsAnalysisRequest> messages,
  ) async {
    try {
      final response = await _dio.post(
        ApiEndpoints.smsAnalyzeBatch,
        data: {
          'messages': messages.map((m) => m.toJson()).toList(),
        },
      );

      final results = response.data['results'] as List<dynamic>;
      return results
          .map((r) => SmsAnalysisResult.fromJson(r as Map<String, dynamic>))
          .toList();
    } on DioException catch (e) {
      throw ApiError.fromDioException(e);
    }
  }

  /// Get phishing patterns
  Future<List<PhishingPattern>> getPhishingPatterns() async {
    try {
      final response = await _dio.get(
        ApiEndpoints.smsPatterns,
        options: Options(extra: {'cacheTtl': ApiConfig.cacheTtlLong}),
      );

      final patterns = response.data['patterns'] as List<dynamic>;
      return patterns
          .map((p) => PhishingPattern.fromJson(p as Map<String, dynamic>))
          .toList();
    } on DioException catch (e) {
      throw ApiError.fromDioException(e);
    }
  }

  // ============================================
  // URL PROTECTION
  // ============================================

  /// Check URL reputation
  Future<UrlReputationResult> checkUrl(String url) async {
    try {
      final response = await _dio.post(
        ApiEndpoints.urlCheck,
        data: {'url': url},
      );
      return UrlReputationResult.fromJson(response.data as Map<String, dynamic>);
    } on DioException catch (e) {
      throw ApiError.fromDioException(e);
    }
  }

  /// Batch URL check
  Future<List<UrlReputationResult>> checkUrlsBatch(List<String> urls) async {
    try {
      final response = await _dio.post(
        ApiEndpoints.urlCheckBatch,
        data: {'urls': urls},
      );

      final results = response.data['results'] as List<dynamic>;
      return results
          .map((r) => UrlReputationResult.fromJson(r as Map<String, dynamic>))
          .toList();
    } on DioException catch (e) {
      throw ApiError.fromDioException(e);
    }
  }

  /// Get domain reputation details
  Future<DomainReputation> getDomainReputation(String domain) async {
    try {
      final response = await _dio.get(ApiEndpoints.urlReputation(domain));
      return DomainReputation.fromJson(response.data as Map<String, dynamic>);
    } on DioException catch (e) {
      throw ApiError.fromDioException(e);
    }
  }

  // ============================================
  // QR CODE SECURITY
  // ============================================

  /// Scan QR code content for threats
  Future<QrScanResult> scanQrCode(QrScanRequest request) async {
    try {
      final response = await _dio.post(
        ApiEndpoints.qrScan,
        data: request.toJson(),
      );
      return QrScanResult.fromJson(response.data as Map<String, dynamic>);
    } on DioException catch (e) {
      throw ApiError.fromDioException(e);
    }
  }

  // ============================================
  // DARK WEB MONITORING
  // ============================================

  /// Check email for breaches
  Future<BreachCheckResult> checkEmailBreaches(String email) async {
    try {
      final response = await _dio.post(
        ApiEndpoints.darkwebCheckEmail,
        data: {'email': email},
      );
      return BreachCheckResult.fromJson(response.data as Map<String, dynamic>);
    } on DioException catch (e) {
      throw ApiError.fromDioException(e);
    }
  }

  /// Check password for breaches (k-anonymity)
  Future<PasswordBreachResult> checkPasswordBreaches(
    String passwordHashPrefix,
  ) async {
    try {
      final response = await _dio.post(
        ApiEndpoints.darkwebCheckPassword,
        data: {'password_hash_prefix': passwordHashPrefix},
      );
      return PasswordBreachResult.fromJson(
        response.data as Map<String, dynamic>,
      );
    } on DioException catch (e) {
      throw ApiError.fromDioException(e);
    }
  }

  /// Get breach alerts for monitored assets
  Future<List<BreachAlert>> getBreachAlerts() async {
    try {
      final response = await _dio.get(ApiEndpoints.darkwebAlerts);

      final alerts = response.data['alerts'] as List<dynamic>;
      return alerts
          .map((a) => BreachAlert.fromJson(a as Map<String, dynamic>))
          .toList();
    } on DioException catch (e) {
      throw ApiError.fromDioException(e);
    }
  }

  // ============================================
  // APP SECURITY
  // ============================================

  /// Analyze app permissions and risk
  Future<AppAnalysisResult> analyzeApp(AppAnalysisRequest request) async {
    try {
      final response = await _dio.post(
        ApiEndpoints.appsAnalyze,
        data: request.toJson(),
      );
      return AppAnalysisResult.fromJson(response.data as Map<String, dynamic>);
    } on DioException catch (e) {
      throw ApiError.fromDioException(e);
    }
  }

  /// Get known trackers list
  Future<List<TrackerInfo>> getTrackers() async {
    try {
      final response = await _dio.get(
        ApiEndpoints.appsTrackers,
        options: Options(extra: {'cacheTtl': ApiConfig.cacheTtlLong}),
      );

      final trackers = response.data['trackers'] as List<dynamic>;
      return trackers
          .map((t) => TrackerInfo.fromJson(t as Map<String, dynamic>))
          .toList();
    } on DioException catch (e) {
      throw ApiError.fromDioException(e);
    }
  }

  // ============================================
  // NETWORK SECURITY
  // ============================================

  /// Audit Wi-Fi network
  Future<WifiAuditResult> auditWifi(WifiAuditRequest request) async {
    try {
      final response = await _dio.post(
        ApiEndpoints.networkWifiAudit,
        data: request.toJson(),
      );
      return WifiAuditResult.fromJson(response.data as Map<String, dynamic>);
    } on DioException catch (e) {
      throw ApiError.fromDioException(e);
    }
  }

  /// Scan for rogue access points
  Future<Map<String, dynamic>> scanRogueAPs(List<Map<String, dynamic>> nearbyAPs) async {
    try {
      final response = await _dio.post(
        ApiEndpoints.rogueApScan,
        data: {'access_points': nearbyAPs},
      );
      return response.data as Map<String, dynamic>;
    } on DioException catch (e) {
      throw ApiError.fromDioException(e);
    }
  }

  /// Get trusted access points
  Future<List<Map<String, dynamic>>> getTrustedAPs() async {
    try {
      final response = await _dio.get(ApiEndpoints.rogueApTrusted);
      return (response.data['trusted_aps'] as List<dynamic>?)
          ?.cast<Map<String, dynamic>>() ?? [];
    } on DioException catch (e) {
      throw ApiError.fromDioException(e);
    }
  }

  /// Add trusted access point
  Future<Map<String, dynamic>> addTrustedAP(String ssid, String bssid) async {
    try {
      final response = await _dio.post(
        ApiEndpoints.rogueApTrustedAdd,
        data: {'ssid': ssid, 'bssid': bssid},
      );
      return response.data as Map<String, dynamic>;
    } on DioException catch (e) {
      throw ApiError.fromDioException(e);
    }
  }

  /// Remove trusted access point
  Future<void> removeTrustedAP(String id) async {
    try {
      await _dio.delete(ApiEndpoints.rogueApTrustedRemove(id));
    } on DioException catch (e) {
      throw ApiError.fromDioException(e);
    }
  }

  // ============================================
  // YARA SCANNING
  // ============================================

  /// Scan data with YARA rules
  Future<YaraScanResult> scanWithYara(YaraScanRequest request) async {
    try {
      final response = await _dio.post(
        ApiEndpoints.yaraScan,
        data: request.toJson(),
      );
      return YaraScanResult.fromJson(response.data as Map<String, dynamic>);
    } on DioException catch (e) {
      throw ApiError.fromDioException(e);
    }
  }

  // ============================================
  // MITRE ATT&CK
  // ============================================

  /// Get MITRE tactics
  Future<List<MitreTactic>> getMitreTactics() async {
    try {
      final response = await _dio.get(
        ApiEndpoints.mitreTactics,
        options: Options(extra: {'cacheTtl': ApiConfig.cacheTtlLong}),
      );

      final tactics = response.data['tactics'] as List<dynamic>;
      return tactics
          .map((t) => MitreTactic.fromJson(t as Map<String, dynamic>))
          .toList();
    } on DioException catch (e) {
      throw ApiError.fromDioException(e);
    }
  }

  /// Get MITRE techniques
  Future<List<MitreTechnique>> getMitreTechniques({String? tacticId}) async {
    try {
      final queryParams = <String, dynamic>{};
      if (tacticId != null) queryParams['tactic'] = tacticId;

      final response = await _dio.get(
        ApiEndpoints.mitreTechniques,
        queryParameters: queryParams,
        options: Options(extra: {'cacheTtl': ApiConfig.cacheTtlLong}),
      );

      final techniques = response.data['techniques'] as List<dynamic>;
      return techniques
          .map((t) => MitreTechnique.fromJson(t as Map<String, dynamic>))
          .toList();
    } on DioException catch (e) {
      throw ApiError.fromDioException(e);
    }
  }

  // ============================================
  // CAMPAIGNS & ACTORS
  // ============================================

  /// List campaigns
  Future<PaginatedResponse<Campaign>> listCampaigns({
    int page = 1,
    int limit = 50,
    bool? active,
  }) async {
    try {
      final queryParams = <String, dynamic>{
        'page': page,
        'limit': limit,
      };
      if (active != null) queryParams['active'] = active;

      final response = await _dio.get(
        ApiEndpoints.campaigns,
        queryParameters: queryParams,
      );

      return PaginatedResponse.fromJson(
        response.data,
        (json) => Campaign.fromJson(json as Map<String, dynamic>),
      );
    } on DioException catch (e) {
      throw ApiError.fromDioException(e);
    }
  }

  /// Get campaign details
  Future<Campaign> getCampaign(String id) async {
    try {
      final response = await _dio.get(ApiEndpoints.campaign(id));
      return Campaign.fromJson(response.data as Map<String, dynamic>);
    } on DioException catch (e) {
      throw ApiError.fromDioException(e);
    }
  }

  /// List threat actors
  Future<PaginatedResponse<ThreatActor>> listActors({
    int page = 1,
    int limit = 50,
  }) async {
    try {
      final response = await _dio.get(
        ApiEndpoints.actors,
        queryParameters: {'page': page, 'limit': limit},
      );

      return PaginatedResponse.fromJson(
        response.data,
        (json) => ThreatActor.fromJson(json as Map<String, dynamic>),
      );
    } on DioException catch (e) {
      throw ApiError.fromDioException(e);
    }
  }

  /// Get actor details
  Future<ThreatActor> getActor(String id) async {
    try {
      final response = await _dio.get(ApiEndpoints.actor(id));
      return ThreatActor.fromJson(response.data as Map<String, dynamic>);
    } on DioException catch (e) {
      throw ApiError.fromDioException(e);
    }
  }

  // ============================================
  // ORBNET VPN INTEGRATION
  // ============================================

  /// Check if domain should be blocked
  Future<DnsBlockResult> checkDnsBlock(String domain) async {
    try {
      final response = await _dio.post(
        ApiEndpoints.orbnetDnsBlock,
        data: {'domain': domain},
      );
      return DnsBlockResult.fromJson(response.data as Map<String, dynamic>);
    } on DioException catch (e) {
      throw ApiError.fromDioException(e);
    }
  }

  /// Batch DNS block check
  Future<List<DnsBlockResult>> checkDnsBlockBatch(List<String> domains) async {
    try {
      final response = await _dio.post(
        ApiEndpoints.orbnetDnsBlockBatch,
        data: {'domains': domains},
      );

      final results = response.data['results'] as List<dynamic>;
      return results
          .map((r) => DnsBlockResult.fromJson(r as Map<String, dynamic>))
          .toList();
    } on DioException catch (e) {
      throw ApiError.fromDioException(e);
    }
  }

  /// Sync threat intelligence for VPN
  Future<SyncResult> syncThreatIntelligence() async {
    try {
      final response = await _dio.post(ApiEndpoints.orbnetSync);
      return SyncResult.fromJson(response.data as Map<String, dynamic>);
    } on DioException catch (e) {
      throw ApiError.fromDioException(e);
    }
  }

  // ============================================
  // STATISTICS & DASHBOARD
  // ============================================

  /// Test API connection / health check
  Future<bool> testConnection() async {
    try {
      final response = await _dio.get(
        ApiEndpoints.health,
        options: Options(
          sendTimeout: const Duration(seconds: 5),
          receiveTimeout: const Duration(seconds: 5),
        ),
      );
      return response.statusCode == 200;
    } catch (e) {
      return false;
    }
  }

  /// Get threat statistics
  Future<ThreatStats> getStats() async {
    try {
      final response = await _dio.get(
        ApiEndpoints.stats,
        options: Options(extra: {'cacheTtl': ApiConfig.cacheTtlShort}),
      );
      return ThreatStats.fromJson(response.data as Map<String, dynamic>);
    } on DioException catch (e) {
      throw ApiError.fromDioException(e);
    }
  }

  /// Get dashboard summary
  Future<DashboardSummary> getDashboardSummary() async {
    try {
      final response = await _dio.get(
        ApiEndpoints.statsDashboard,
        options: Options(extra: {'cacheTtl': ApiConfig.cacheTtlShort}),
      );
      return DashboardSummary.fromJson(response.data as Map<String, dynamic>);
    } on DioException catch (e) {
      throw ApiError.fromDioException(e);
    }
  }

  /// Get protection status
  Future<ProtectionStatus> getProtectionStatus() async {
    try {
      final response = await _dio.get(
        ApiEndpoints.statsProtection,
        options: Options(extra: {'cacheTtl': ApiConfig.cacheTtlShort}),
      );
      return ProtectionStatus.fromJson(response.data as Map<String, dynamic>);
    } on DioException catch (e) {
      throw ApiError.fromDioException(e);
    }
  }

  /// Mark alert as read
  Future<void> markAlertAsRead(String alertId) async {
    try {
      await _dio.post(ApiEndpoints.alertMarkRead(alertId));
    } on DioException catch (e) {
      throw ApiError.fromDioException(e);
    }
  }

  /// Clear all alerts
  Future<void> clearAllAlerts() async {
    try {
      await _dio.delete(ApiEndpoints.alertsClear);
    } on DioException catch (e) {
      throw ApiError.fromDioException(e);
    }
  }

  /// Report SMS false positive
  Future<void> reportSmsFalsePositive(String messageId, String content) async {
    try {
      await _dio.post(
        ApiEndpoints.smsReportFalsePositive,
        data: {
          'message_id': messageId,
          'content': content,
        },
      );
    } on DioException catch (e) {
      throw ApiError.fromDioException(e);
    }
  }

  // ============================================
  // CORRELATION & GRAPH
  // ============================================

  /// Get correlated indicators
  Future<CorrelationResult> getCorrelation(String indicatorId) async {
    try {
      final response = await _dio.get(ApiEndpoints.correlation(indicatorId));
      return CorrelationResult.fromJson(response.data as Map<String, dynamic>);
    } on DioException catch (e) {
      throw ApiError.fromDioException(e);
    }
  }

  /// Get related entities from graph
  Future<GraphRelatedResult> getRelatedEntities(String entityId) async {
    try {
      final response = await _dio.get(ApiEndpoints.graphRelated(entityId));
      return GraphRelatedResult.fromJson(response.data as Map<String, dynamic>);
    } on DioException catch (e) {
      throw ApiError.fromDioException(e);
    }
  }

  // ============================================
  // DIGITAL FOOTPRINT
  // ============================================

  /// Get data brokers list
  Future<List<dynamic>> getDataBrokers() async {
    try {
      final response = await _dio.get('/api/footprint/brokers');
      return response.data['brokers'] as List<dynamic>? ?? [];
    } on DioException catch (e) {
      throw ApiError.fromDioException(e);
    }
  }

  /// Scan digital footprint
  Future<Map<String, dynamic>> scanDigitalFootprint(Map<String, dynamic> params) async {
    try {
      final response = await _dio.post(
        '/api/footprint/scan',
        data: params,
      );
      return response.data as Map<String, dynamic>;
    } on DioException catch (e) {
      throw ApiError.fromDioException(e);
    }
  }

  /// Request data removal from broker
  Future<Map<String, dynamic>> requestDataRemoval(String brokerId) async {
    try {
      final response = await _dio.post(
        '/api/footprint/removal',
        data: {'broker_id': brokerId},
      );
      return response.data as Map<String, dynamic>;
    } on DioException catch (e) {
      throw ApiError.fromDioException(e);
    }
  }

  /// Get removal request status
  Future<Map<String, dynamic>> getRemovalStatus(String requestId) async {
    try {
      final response = await _dio.get('/api/footprint/removal/$requestId');
      return response.data as Map<String, dynamic>;
    } on DioException catch (e) {
      throw ApiError.fromDioException(e);
    }
  }

  // ============================================
  // ENTERPRISE
  // ============================================

  /// Get enterprise statistics
  Future<Map<String, dynamic>> getEnterpriseStats() async {
    try {
      final response = await _dio.get(
        ApiEndpoints.enterpriseStats,
        options: Options(extra: {'cacheTtl': ApiConfig.cacheTtlShort}),
      );
      return response.data as Map<String, dynamic>;
    } on DioException catch (e) {
      throw ApiError.fromDioException(e);
    }
  }

  /// Get enterprise security events
  Future<List<Map<String, dynamic>>> getEnterpriseEvents({int limit = 50}) async {
    try {
      final response = await _dio.get(
        ApiEndpoints.enterpriseEvents,
        queryParameters: {'limit': limit},
      );
      return (response.data['events'] as List<dynamic>?)
          ?.cast<Map<String, dynamic>>() ?? [];
    } on DioException catch (e) {
      throw ApiError.fromDioException(e);
    }
  }

  /// Get enterprise device health
  Future<List<Map<String, dynamic>>> getEnterpriseDevices() async {
    try {
      final response = await _dio.get(ApiEndpoints.enterpriseDevices);
      return (response.data['devices'] as List<dynamic>?)
          ?.cast<Map<String, dynamic>>() ?? [];
    } on DioException catch (e) {
      throw ApiError.fromDioException(e);
    }
  }

  /// Get compliance frameworks
  Future<List<Map<String, dynamic>>> getComplianceFrameworks() async {
    try {
      final response = await _dio.get(
        ApiEndpoints.complianceFrameworks,
        options: Options(extra: {'cacheTtl': ApiConfig.cacheTtlMedium}),
      );
      return (response.data['frameworks'] as List<dynamic>?)
          ?.cast<Map<String, dynamic>>() ?? [];
    } on DioException catch (e) {
      throw ApiError.fromDioException(e);
    }
  }

  /// Get compliance reports
  Future<List<Map<String, dynamic>>> getComplianceReports() async {
    try {
      final response = await _dio.get(ApiEndpoints.complianceReports);
      return (response.data['reports'] as List<dynamic>?)
          ?.cast<Map<String, dynamic>>() ?? [];
    } on DioException catch (e) {
      throw ApiError.fromDioException(e);
    }
  }

  /// Get compliance controls
  Future<List<Map<String, dynamic>>> getComplianceControls() async {
    try {
      final response = await _dio.get(ApiEndpoints.complianceControls);
      return (response.data['controls'] as List<dynamic>?)
          ?.cast<Map<String, dynamic>>() ?? [];
    } on DioException catch (e) {
      throw ApiError.fromDioException(e);
    }
  }

  /// Generate compliance report
  Future<Map<String, dynamic>> generateComplianceReport({
    required List<String> frameworks,
    required String format,
  }) async {
    try {
      final response = await _dio.post(
        ApiEndpoints.complianceReportGenerate,
        data: {
          'frameworks': frameworks,
          'format': format,
        },
      );
      return response.data as Map<String, dynamic>? ?? {};
    } on DioException catch (e) {
      throw ApiError.fromDioException(e);
    }
  }

  /// Assign policy to groups
  Future<bool> assignPolicyToGroups(String policyId, List<String> groupIds) async {
    try {
      await _dio.post(
        ApiEndpoints.policyAssignGroups(policyId),
        data: {'group_ids': groupIds},
      );
      return true;
    } on DioException catch (e) {
      throw ApiError.fromDioException(e);
    }
  }

  /// Assign policy to devices
  Future<bool> assignPolicyToDevices(String policyId, List<String> deviceIds) async {
    try {
      await _dio.post(
        ApiEndpoints.policyAssignDevices(policyId),
        data: {'device_ids': deviceIds},
      );
      return true;
    } on DioException catch (e) {
      throw ApiError.fromDioException(e);
    }
  }

  /// Remove policy assignment
  Future<bool> removePolicyAssignment(String policyId, {List<String>? groupIds, List<String>? deviceIds}) async {
    try {
      await _dio.post(
        ApiEndpoints.policyUnassign(policyId),
        data: {
          if (groupIds != null) 'group_ids': groupIds,
          if (deviceIds != null) 'device_ids': deviceIds,
        },
      );
      return true;
    } on DioException catch (e) {
      throw ApiError.fromDioException(e);
    }
  }

  /// Evaluate device compliance
  Future<Map<String, dynamic>> evaluateDeviceCompliance(String deviceId) async {
    try {
      final response = await _dio.post(ApiEndpoints.deviceEvaluateCompliance(deviceId));
      return response.data as Map<String, dynamic>;
    } on DioException catch (e) {
      throw ApiError.fromDioException(e);
    }
  }

  /// Enroll BYOD device
  Future<Map<String, dynamic>> enrollBYODDevice(Map<String, dynamic> request) async {
    try {
      final response = await _dio.post(
        ApiEndpoints.byodEnroll,
        data: request,
      );
      return response.data as Map<String, dynamic>;
    } on DioException catch (e) {
      throw ApiError.fromDioException(e);
    }
  }

  /// Get BYOD enrollment status
  Future<Map<String, dynamic>> getBYODEnrollmentStatus(String deviceId) async {
    try {
      final response = await _dio.get(ApiEndpoints.byodStatus(deviceId));
      return response.data as Map<String, dynamic>;
    } on DioException catch (e) {
      throw ApiError.fromDioException(e);
    }
  }

  /// Unenroll BYOD device
  Future<bool> unenrollBYODDevice(String deviceId, {bool wipeWorkData = true}) async {
    try {
      await _dio.post(
        ApiEndpoints.byodUnenroll(deviceId),
        data: {'wipe_work_data': wipeWorkData},
      );
      return true;
    } on DioException catch (e) {
      throw ApiError.fromDioException(e);
    }
  }

  /// Detect device ownership
  Future<String> detectDeviceOwnership(String deviceId) async {
    try {
      final response = await _dio.get(ApiEndpoints.deviceOwnership(deviceId));
      return response.data['ownership_type'] as String? ?? 'unknown';
    } on DioException catch (e) {
      throw ApiError.fromDioException(e);
    }
  }

  /// Set device ownership
  Future<bool> setDeviceOwnership(String deviceId, String ownershipType) async {
    try {
      await _dio.post(
        ApiEndpoints.deviceOwnershipSet(deviceId),
        data: {'ownership_type': ownershipType},
      );
      return true;
    } on DioException catch (e) {
      throw ApiError.fromDioException(e);
    }
  }

  // ============================================
  // SIEM INTEGRATION
  // ============================================

  /// Get SIEM connections
  Future<List<Map<String, dynamic>>> getSiemConnections() async {
    try {
      final response = await _dio.get(ApiEndpoints.siemConnections);
      return (response.data['connections'] as List<dynamic>?)
          ?.cast<Map<String, dynamic>>() ?? [];
    } on DioException catch (e) {
      throw ApiError.fromDioException(e);
    }
  }

  /// Get SIEM event forwarders
  Future<List<Map<String, dynamic>>> getSiemForwarders() async {
    try {
      final response = await _dio.get(ApiEndpoints.siemForwarders);
      return (response.data['forwarders'] as List<dynamic>?)
          ?.cast<Map<String, dynamic>>() ?? [];
    } on DioException catch (e) {
      throw ApiError.fromDioException(e);
    }
  }

  /// Get SIEM alerts
  Future<List<Map<String, dynamic>>> getSiemAlerts() async {
    try {
      final response = await _dio.get(ApiEndpoints.siemAlerts);
      return (response.data['alerts'] as List<dynamic>?)
          ?.cast<Map<String, dynamic>>() ?? [];
    } on DioException catch (e) {
      throw ApiError.fromDioException(e);
    }
  }

  // ============================================
  // WEBHOOKS
  // ============================================

  /// Get webhooks
  Future<List<Map<String, dynamic>>> getWebhooks() async {
    try {
      final response = await _dio.get(ApiEndpoints.webhooks);
      return (response.data['webhooks'] as List<dynamic>?)
          ?.cast<Map<String, dynamic>>() ?? [];
    } on DioException catch (e) {
      throw ApiError.fromDioException(e);
    }
  }

  /// Create webhook
  Future<Map<String, dynamic>> createWebhook(Map<String, dynamic> data) async {
    try {
      final response = await _dio.post(ApiEndpoints.webhooksCreate, data: data);
      return response.data as Map<String, dynamic>;
    } on DioException catch (e) {
      throw ApiError.fromDioException(e);
    }
  }

  /// Delete webhook
  Future<void> deleteWebhook(String id) async {
    try {
      await _dio.delete(ApiEndpoints.webhookDelete(id));
    } on DioException catch (e) {
      throw ApiError.fromDioException(e);
    }
  }

  // ============================================
  // INTELLIGENCE SOURCES
  // ============================================

  /// Get intelligence sources
  Future<List<Map<String, dynamic>>> getIntelSources() async {
    try {
      final response = await _dio.get(
        ApiEndpoints.intelSources,
        options: Options(extra: {'cacheTtl': ApiConfig.cacheTtlMedium}),
      );
      return (response.data['sources'] as List<dynamic>?)
          ?.cast<Map<String, dynamic>>() ?? [];
    } on DioException catch (e) {
      throw ApiError.fromDioException(e);
    }
  }

  // ============================================
  // INTEGRATIONS
  // ============================================

  /// Get integrations
  Future<List<Map<String, dynamic>>> getIntegrations() async {
    try {
      final response = await _dio.get(ApiEndpoints.integrations);
      return (response.data['integrations'] as List<dynamic>?)
          ?.cast<Map<String, dynamic>>() ?? [];
    } on DioException catch (e) {
      throw ApiError.fromDioException(e);
    }
  }

  /// Update integration
  Future<Map<String, dynamic>> updateIntegration(String id, Map<String, dynamic> data) async {
    try {
      final response = await _dio.patch(ApiEndpoints.integration(id), data: data);
      return response.data as Map<String, dynamic>;
    } on DioException catch (e) {
      throw ApiError.fromDioException(e);
    }
  }

  // ============================================
  // ML ANALYSIS
  // ============================================

  /// Get ML models
  Future<List<Map<String, dynamic>>> getMLModels() async {
    try {
      final response = await _dio.get(
        ApiEndpoints.mlModels,
        options: Options(extra: {'cacheTtl': ApiConfig.cacheTtlMedium}),
      );
      return (response.data['models'] as List<dynamic>?)
          ?.cast<Map<String, dynamic>>() ?? [];
    } on DioException catch (e) {
      throw ApiError.fromDioException(e);
    }
  }

  /// Get anomaly detections
  Future<List<Map<String, dynamic>>> getAnomalies() async {
    try {
      final response = await _dio.get(ApiEndpoints.mlAnomalies);
      return (response.data['anomalies'] as List<dynamic>?)
          ?.cast<Map<String, dynamic>>() ?? [];
    } on DioException catch (e) {
      throw ApiError.fromDioException(e);
    }
  }

  /// Get ML insights
  Future<List<Map<String, dynamic>>> getMLInsights() async {
    try {
      final response = await _dio.get(ApiEndpoints.mlInsights);
      return (response.data['insights'] as List<dynamic>?)
          ?.cast<Map<String, dynamic>>() ?? [];
    } on DioException catch (e) {
      throw ApiError.fromDioException(e);
    }
  }

  // ============================================
  // PLAYBOOKS
  // ============================================

  /// Get playbooks
  Future<List<Map<String, dynamic>>> getPlaybooks() async {
    try {
      final response = await _dio.get(ApiEndpoints.playbooks);
      return (response.data['playbooks'] as List<dynamic>?)
          ?.cast<Map<String, dynamic>>() ?? [];
    } on DioException catch (e) {
      throw ApiError.fromDioException(e);
    }
  }

  /// Get playbook executions
  Future<List<Map<String, dynamic>>> getPlaybookExecutions() async {
    try {
      final response = await _dio.get(ApiEndpoints.playbookExecutions);
      return (response.data['executions'] as List<dynamic>?)
          ?.cast<Map<String, dynamic>>() ?? [];
    } on DioException catch (e) {
      throw ApiError.fromDioException(e);
    }
  }

  /// Execute playbook
  Future<Map<String, dynamic>> executePlaybook(String id) async {
    try {
      final response = await _dio.post(ApiEndpoints.playbookExecute(id));
      return response.data as Map<String, dynamic>;
    } on DioException catch (e) {
      throw ApiError.fromDioException(e);
    }
  }

  // ============================================
  // DESKTOP SECURITY
  // ============================================

  /// Get persistence items
  Future<List<Map<String, dynamic>>> getPersistenceItems() async {
    try {
      final response = await _dio.get(ApiEndpoints.desktopPersistence);
      return (response.data['items'] as List<dynamic>?)
          ?.cast<Map<String, dynamic>>() ?? [];
    } on DioException catch (e) {
      throw ApiError.fromDioException(e);
    }
  }

  /// Get signed apps
  Future<List<Map<String, dynamic>>> getSignedApps() async {
    try {
      final response = await _dio.get(ApiEndpoints.desktopApps);
      return (response.data['apps'] as List<dynamic>?)
          ?.cast<Map<String, dynamic>>() ?? [];
    } on DioException catch (e) {
      throw ApiError.fromDioException(e);
    }
  }

  /// Get firewall rules
  Future<List<Map<String, dynamic>>> getDesktopFirewallRules() async {
    try {
      final response = await _dio.get(ApiEndpoints.desktopFirewall);
      return (response.data['rules'] as List<dynamic>?)
          ?.cast<Map<String, dynamic>>() ?? [];
    } on DioException catch (e) {
      throw ApiError.fromDioException(e);
    }
  }

  // ============================================
  // VPN SERVERS
  // ============================================

  /// Get VPN servers
  Future<List<Map<String, dynamic>>> getVpnServers() async {
    try {
      final response = await _dio.get(
        ApiEndpoints.vpnServers,
        options: Options(extra: {'cacheTtl': ApiConfig.cacheTtlMedium}),
      );
      return (response.data['servers'] as List<dynamic>?)
          ?.cast<Map<String, dynamic>>() ?? [];
    } on DioException catch (e) {
      throw ApiError.fromDioException(e);
    }
  }

  /// Get blocked domains for VPN
  Future<List<Map<String, dynamic>>> getVpnBlockedDomains() async {
    try {
      final response = await _dio.get(ApiEndpoints.vpnBlocked);
      return (response.data['domains'] as List<dynamic>?)
          ?.cast<Map<String, dynamic>>() ?? [];
    } on DioException catch (e) {
      throw ApiError.fromDioException(e);
    }
  }

  /// Get VPN connection statistics
  Future<Map<String, dynamic>> getVpnStats() async {
    try {
      final response = await _dio.get(ApiEndpoints.vpnStats);
      return response.data as Map<String, dynamic>? ?? {};
    } on DioException catch (e) {
      throw ApiError.fromDioException(e);
    }
  }

  // ============================================
  // THREAT GRAPH
  // ============================================

  /// Get graph nodes
  Future<List<Map<String, dynamic>>> getGraphNodes({String? query}) async {
    try {
      final response = await _dio.get(
        ApiEndpoints.graphNodes,
        queryParameters: query != null ? {'query': query} : null,
      );
      return (response.data['nodes'] as List<dynamic>?)
          ?.cast<Map<String, dynamic>>() ?? [];
    } on DioException catch (e) {
      throw ApiError.fromDioException(e);
    }
  }

  /// Get graph relations
  Future<List<Map<String, dynamic>>> getGraphRelations({String? nodeId}) async {
    try {
      final response = await _dio.get(
        ApiEndpoints.graphRelations,
        queryParameters: nodeId != null ? {'node_id': nodeId} : null,
      );
      return (response.data['relations'] as List<dynamic>?)
          ?.cast<Map<String, dynamic>>() ?? [];
    } on DioException catch (e) {
      throw ApiError.fromDioException(e);
    }
  }

  // ============================================
  // YARA RULES
  // ============================================

  /// Get YARA rules
  Future<List<Map<String, dynamic>>> getYaraRules() async {
    try {
      final response = await _dio.get(
        ApiEndpoints.yaraRules,
        options: Options(extra: {'cacheTtl': ApiConfig.cacheTtlMedium}),
      );
      return (response.data['rules'] as List<dynamic>?)
          ?.cast<Map<String, dynamic>>() ?? [];
    } on DioException catch (e) {
      throw ApiError.fromDioException(e);
    }
  }

  // ============================================
  // STIX/TAXII
  // ============================================

  /// Get TAXII servers (discovery)
  Future<List<Map<String, dynamic>>> getTaxiiServers() async {
    try {
      final response = await _dio.get(ApiEndpoints.taxiiDiscovery);
      return (response.data['servers'] as List<dynamic>?)
          ?.cast<Map<String, dynamic>>() ?? [];
    } on DioException catch (e) {
      throw ApiError.fromDioException(e);
    }
  }

  /// Get TAXII collections
  Future<List<Map<String, dynamic>>> getTaxiiCollections() async {
    try {
      final response = await _dio.get(ApiEndpoints.taxiiCollections);
      return (response.data['collections'] as List<dynamic>?)
          ?.cast<Map<String, dynamic>>() ?? [];
    } on DioException catch (e) {
      throw ApiError.fromDioException(e);
    }
  }

  /// Get STIX objects from collection
  Future<List<Map<String, dynamic>>> getStixObjects(String collectionId) async {
    try {
      final response = await _dio.get(ApiEndpoints.taxiiCollectionObjects(collectionId));
      return (response.data['objects'] as List<dynamic>?)
          ?.cast<Map<String, dynamic>>() ?? [];
    } on DioException catch (e) {
      throw ApiError.fromDioException(e);
    }
  }

  // ============================================
  // CORRELATION
  // ============================================

  /// Get correlation results
  Future<List<Map<String, dynamic>>> getCorrelationResults({String? query}) async {
    try {
      final response = await _dio.get(
        '${ApiConfig.apiVersion}/correlation',
        queryParameters: query != null ? {'query': query} : null,
      );
      return (response.data['results'] as List<dynamic>?)
          ?.cast<Map<String, dynamic>>() ?? [];
    } on DioException catch (e) {
      throw ApiError.fromDioException(e);
    }
  }

  /// Run correlation analysis
  Future<Map<String, dynamic>> runCorrelation() async {
    try {
      final response = await _dio.post('${ApiConfig.apiVersion}/correlation/run');
      return response.data as Map<String, dynamic>? ?? {};
    } on DioException catch (e) {
      throw ApiError.fromDioException(e);
    }
  }

  // ============================================
  // ML ANALYSIS
  // ============================================

  /// Run ML analysis
  Future<Map<String, dynamic>> runMLAnalysis() async {
    try {
      final response = await _dio.post('${ApiConfig.apiVersion}/ml/analyze');
      return response.data as Map<String, dynamic>? ?? {};
    } on DioException catch (e) {
      throw ApiError.fromDioException(e);
    }
  }

  // ============================================
  // DESKTOP SECURITY
  // ============================================

  /// Scan for persistence mechanisms
  Future<Map<String, dynamic>> scanPersistence() async {
    try {
      final response = await _dio.post('${ApiConfig.apiVersion}/desktop/persistence/scan');
      return response.data as Map<String, dynamic>? ?? {};
    } on DioException catch (e) {
      throw ApiError.fromDioException(e);
    }
  }

  // ============================================
  // APP SECURITY
  // ============================================

  /// Get installed apps (from device registry)
  Future<List<Map<String, dynamic>>> getInstalledApps() async {
    try {
      final response = await _dio.get('${ApiConfig.apiVersion}/apps/installed');
      return (response.data['apps'] as List<dynamic>?)
          ?.cast<Map<String, dynamic>>() ?? [];
    } on DioException catch (e) {
      throw ApiError.fromDioException(e);
    }
  }

  // ============================================
  // NETWORK / VPN / DNS
  // ============================================

  /// Get network threats
  Future<List<Map<String, dynamic>>> getNetworkThreats() async {
    try {
      final response = await _dio.get('${ApiConfig.apiVersion}/network/threats');
      return (response.data['threats'] as List<dynamic>?)
          ?.cast<Map<String, dynamic>>() ?? [];
    } on DioException catch (e) {
      throw ApiError.fromDioException(e);
    }
  }

  /// Get VPN status
  Future<Map<String, dynamic>> getVpnStatus() async {
    try {
      final response = await _dio.get('${ApiConfig.apiVersion}/vpn/status');
      return response.data as Map<String, dynamic>? ?? {};
    } on DioException catch (e) {
      throw ApiError.fromDioException(e);
    }
  }

  /// Connect to VPN
  Future<Map<String, dynamic>> connectVpn(String server) async {
    try {
      final response = await _dio.post(
        '${ApiConfig.apiVersion}/vpn/connect',
        data: {'server': server},
      );
      return response.data as Map<String, dynamic>? ?? {};
    } on DioException catch (e) {
      throw ApiError.fromDioException(e);
    }
  }

  /// Disconnect from VPN
  Future<void> disconnectVpn() async {
    try {
      await _dio.post('${ApiConfig.apiVersion}/vpn/disconnect');
    } on DioException catch (e) {
      throw ApiError.fromDioException(e);
    }
  }

  /// Get DNS status
  Future<Map<String, dynamic>> getDnsStatus() async {
    try {
      final response = await _dio.get('${ApiConfig.apiVersion}/dns/status');
      return response.data as Map<String, dynamic>? ?? {};
    } on DioException catch (e) {
      throw ApiError.fromDioException(e);
    }
  }

  /// Enable DNS protection
  Future<Map<String, dynamic>> enableDnsProtection({
    bool malwareBlocking = true,
    bool adBlocking = false,
    bool trackingBlocking = true,
  }) async {
    try {
      final response = await _dio.post(
        '${ApiConfig.apiVersion}/dns/enable',
        data: {
          'malware_blocking': malwareBlocking,
          'ad_blocking': adBlocking,
          'tracking_blocking': trackingBlocking,
        },
      );
      return response.data as Map<String, dynamic>? ?? {};
    } on DioException catch (e) {
      throw ApiError.fromDioException(e);
    }
  }

  /// Disable DNS protection
  Future<void> disableDnsProtection() async {
    try {
      await _dio.post('${ApiConfig.apiVersion}/dns/disable');
    } on DioException catch (e) {
      throw ApiError.fromDioException(e);
    }
  }

  // ============================================
  // SUPPLY CHAIN SECURITY
  // ============================================

  /// Get known vulnerabilities database
  Future<List<Map<String, dynamic>>> getSupplyChainVulnerabilities() async {
    try {
      final response = await _dio.get(
        ApiEndpoints.supplyChainVulnerabilities,
        options: Options(extra: {'cacheTtl': ApiConfig.cacheTtlMedium}),
      );
      return (response.data['vulnerabilities'] as List<dynamic>?)
          ?.cast<Map<String, dynamic>>() ?? [];
    } on DioException catch (e) {
      throw ApiError.fromDioException(e);
    }
  }

  /// Check libraries for vulnerabilities
  Future<Map<String, dynamic>> checkSupplyChainLibraries(
    List<Map<String, String>> libraries,
  ) async {
    try {
      final response = await _dio.post(
        ApiEndpoints.supplyChainCheck,
        data: {'libraries': libraries},
      );
      return response.data as Map<String, dynamic>? ?? {};
    } on DioException catch (e) {
      throw ApiError.fromDioException(e);
    }
  }

  /// Get tracker signatures
  Future<List<String>> getTrackerSignatures() async {
    try {
      final response = await _dio.get(
        ApiEndpoints.supplyChainTrackers,
        options: Options(extra: {'cacheTtl': ApiConfig.cacheTtlLong}),
      );
      return (response.data['trackers'] as List<dynamic>?)
          ?.cast<String>() ?? [];
    } on DioException catch (e) {
      throw ApiError.fromDioException(e);
    }
  }
}

/// Generic paginated response
class PaginatedResponse<T> {
  final List<T> items;
  final int page;
  final int limit;
  final int total;
  final int totalPages;
  final bool hasMore;

  PaginatedResponse({
    required this.items,
    required this.page,
    required this.limit,
    required this.total,
    required this.totalPages,
    required this.hasMore,
  });

  factory PaginatedResponse.fromJson(
    Map<String, dynamic> json,
    T Function(dynamic) fromJson,
  ) {
    final itemsList = json['items'] as List<dynamic>? ?? [];
    final total = json['total'] as int? ?? 0;
    final limit = json['limit'] as int? ?? 100;

    return PaginatedResponse(
      items: itemsList.map(fromJson).toList(),
      page: json['page'] as int? ?? 1,
      limit: limit,
      total: total,
      totalPages: (total / limit).ceil(),
      hasMore: json['has_more'] as bool? ?? false,
    );
  }
}
