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
