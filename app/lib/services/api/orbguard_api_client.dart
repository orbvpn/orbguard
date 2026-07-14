// OrbGuard Lab API Client
// Main client for communicating with the threat intelligence backend

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:device_info_plus/device_info_plus.dart';
import 'package:dio/dio.dart';
import 'package:package_info_plus/package_info_plus.dart';

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

  /// Collect device metadata in the exact shape the backend's
  /// POST /api/v1/auth/device handler decodes:
  /// {device_id, device_name, platform, os_version, app_version, model, manufacturer}
  Future<Map<String, dynamic>> _collectDeviceData() async {
    final deviceInfo = DeviceInfoPlugin();

    String appVersion = '';
    try {
      final packageInfo = await PackageInfo.fromPlatform();
      appVersion = packageInfo.version;
    } catch (_) {
      // App version is optional metadata; registration proceeds without it.
    }

    if (Platform.isAndroid) {
      final info = await deviceInfo.androidInfo;
      return {
        'device_id': info.id,
        'device_name': '${info.manufacturer} ${info.model}',
        'platform': 'android',
        'os_version': info.version.release,
        'app_version': appVersion,
        'model': info.model,
        'manufacturer': info.manufacturer,
      };
    } else if (Platform.isIOS) {
      final info = await deviceInfo.iosInfo;
      return {
        'device_id': info.identifierForVendor ?? '',
        'device_name': info.name,
        'platform': 'ios',
        'os_version': info.systemVersion,
        'app_version': appVersion,
        'model': info.model,
        'manufacturer': 'Apple',
      };
    } else if (Platform.isMacOS) {
      final info = await deviceInfo.macOsInfo;
      return {
        'device_id': info.systemGUID ?? '',
        'device_name': info.computerName,
        'platform': 'macos',
        'os_version': info.osRelease,
        'app_version': appVersion,
        'model': info.model,
        'manufacturer': 'Apple',
      };
    } else if (Platform.isWindows) {
      final info = await deviceInfo.windowsInfo;
      return {
        'device_id': info.deviceId,
        'device_name': info.computerName,
        'platform': 'windows',
        'os_version': info.displayVersion,
        'app_version': appVersion,
        'model': info.productName,
        'manufacturer': '',
      };
    } else if (Platform.isLinux) {
      final info = await deviceInfo.linuxInfo;
      return {
        'device_id': info.machineId ?? '',
        'device_name': info.prettyName,
        'platform': 'linux',
        'os_version': info.versionId ?? '',
        'app_version': appVersion,
        'model': info.name,
        'manufacturer': '',
      };
    }

    return {
      'device_id': '',
      'device_name': Platform.localHostname,
      'platform': Platform.operatingSystem,
      'os_version': Platform.operatingSystemVersion,
      'app_version': appVersion,
      'model': '',
      'manufacturer': '',
    };
  }

  /// Persist the credentials returned by POST /api/v1/auth/device:
  /// {device_id, api_key, expires_at, token, refresh_token, expires_in, token_type}
  /// The long-lived api_key is used as the bearer credential; the refresh
  /// token enables session rotation via POST /api/v1/auth/refresh.
  Future<void> _storeRegistrationCredentials(Map<String, dynamic> data) async {
    final deviceId = data['device_id'] as String?;
    final apiKey = data['api_key'] as String?;
    final refreshToken = data['refresh_token'] as String?;

    if (deviceId != null && deviceId.isNotEmpty) {
      await _authInterceptor.setDeviceId(deviceId);
    }
    if (apiKey != null && apiKey.isNotEmpty) {
      await _authInterceptor.saveTokens(
        accessToken: apiKey,
        refreshToken: refreshToken,
      );
    }
  }

  /// Register device with backend
  Future<void> _registerDevice() async {
    try {
      final deviceData = await _collectDeviceData();
      if ((deviceData['device_id'] as String).isEmpty) {
        // Backend rejects registrations without a device_id; nothing to send.
        return;
      }

      final response = await _dio.post(
        ApiEndpoints.authDevice,
        data: deviceData,
      );

      if (response.statusCode == 200 || response.statusCode == 201) {
        await _storeRegistrationCredentials(
          response.data as Map<String, dynamic>,
        );
      }
    } catch (e) {
      // Device registration is optional at startup; authenticated calls will
      // surface 401s if it never succeeds.
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

  /// The registered device ID, required by all /device/{device_id}/... routes.
  /// Throws instead of building a broken path when registration never happened.
  String get _requiredDeviceId {
    final id = _authInterceptor.deviceId;
    if (id == null || id.isEmpty) {
      throw ApiError(
        message: 'Device is not registered with the backend; '
            'device-scoped endpoints are unavailable.',
        code: 'NO_DEVICE_ID',
      );
    }
    return id;
  }

  /// Register device with backend (POST /api/v1/auth/device).
  /// Missing required fields are filled from the local device metadata; the
  /// returned api_key/refresh_token are persisted for subsequent calls.
  Future<Map<String, dynamic>> registerDevice(Map<String, dynamic> deviceData) async {
    try {
      final payload = await _collectDeviceData();
      payload.addAll(deviceData);

      final response = await _dio.post(ApiEndpoints.authDevice, data: payload);
      final data = response.data as Map<String, dynamic>? ?? {};
      await _storeRegistrationCredentials(data);
      return data;
    } on DioException catch (e) {
      throw ApiError.fromDioException(e);
    }
  }

  /// Get device security status
  /// GET /api/v1/device/{device_id}/security-status
  Future<Map<String, dynamic>> getDeviceSecurityStatus() async {
    try {
      final response =
          await _dio.get(ApiEndpoints.deviceSecurity(_requiredDeviceId));
      return response.data as Map<String, dynamic>? ?? {};
    } on DioException catch (e) {
      throw ApiError.fromDioException(e);
    }
  }

  /// Get anti-theft settings
  /// GET /api/v1/device/{device_id}/settings
  Future<Map<String, dynamic>> getAntiTheftSettings() async {
    try {
      final response =
          await _dio.get(ApiEndpoints.deviceAntiTheft(_requiredDeviceId));
      return response.data as Map<String, dynamic>? ?? {};
    } on DioException catch (e) {
      throw ApiError.fromDioException(e);
    }
  }

  /// Update anti-theft settings
  /// PUT /api/v1/device/{device_id}/settings
  ///
  /// The backend decodes models.AntiTheftSettings (enable_remote_locate,
  /// enable_remote_lock, enable_remote_wipe, enable_thief_selfie,
  /// enable_sim_alert, selfie_after_attempts, ...). Legacy client keys are
  /// translated to those field names; backend-shaped keys pass through.
  Future<bool> updateAntiTheftSettings(Map<String, dynamic> settings) async {
    const legacyKeyMap = {
      'locate_enabled': 'enable_remote_locate',
      'lock_enabled': 'enable_remote_lock',
      'wipe_enabled': 'enable_remote_wipe',
      'thief_selfie_enabled': 'enable_thief_selfie',
      'sim_monitoring_enabled': 'enable_sim_alert',
      'max_unlock_attempts': 'selfie_after_attempts',
    };

    final deviceId = _requiredDeviceId;
    final payload = <String, dynamic>{'device_id': deviceId};
    settings.forEach((key, value) {
      payload[legacyKeyMap[key] ?? key] = value;
    });

    try {
      await _dio.put(ApiEndpoints.deviceAntiTheft(deviceId), data: payload);
      return true;
    } on DioException catch (e) {
      throw ApiError.fromDioException(e);
    }
  }

  /// Locate device (issues a remote locate command)
  /// POST /api/v1/device/{device_id}/locate
  /// Response: { "status": "locate_requested", "command_id": "..." }
  Future<Map<String, dynamic>> locateDevice() async {
    try {
      final response =
          await _dio.post(ApiEndpoints.deviceLocate(_requiredDeviceId));
      return response.data as Map<String, dynamic>? ?? {};
    } on DioException catch (e) {
      throw ApiError.fromDioException(e);
    }
  }

  /// Send device command (lock, wipe, ring, etc.)
  /// POST /api/v1/device/{device_id}/command
  /// Body: models.RemoteCommand — { "type": "...", "payload": "`<json string>`" }
  Future<bool> sendDeviceCommand(String command, {Map<String, dynamic>? data}) async {
    try {
      await _dio.post(
        ApiEndpoints.deviceCommand(_requiredDeviceId),
        data: {
          'type': command,
          if (data != null && data.isNotEmpty) 'payload': jsonEncode(data),
        },
      );
      return true;
    } on DioException catch (e) {
      throw ApiError.fromDioException(e);
    }
  }

  /// Lock device (issues a remote lock command)
  /// POST /api/v1/device/{device_id}/lock
  /// Body: models.LockCommandPayload — { "pin", "message", "phone" } (all optional)
  Future<Map<String, dynamic>> lockDevice({
    String? pin,
    String? message,
    String? phone,
  }) async {
    try {
      final response = await _dio.post(
        ApiEndpoints.deviceLock(_requiredDeviceId),
        data: {
          if (pin != null && pin.isNotEmpty) 'pin': pin,
          if (message != null && message.isNotEmpty) 'message': message,
          if (phone != null && phone.isNotEmpty) 'phone': phone,
        },
      );
      return response.data as Map<String, dynamic>? ?? {};
    } on DioException catch (e) {
      throw ApiError.fromDioException(e);
    }
  }

  /// Wipe device (issues a remote wipe command)
  /// POST /api/v1/device/{device_id}/wipe
  /// Body: models.WipeCommandPayload — "confirmation_id" is REQUIRED by the
  /// backend as a safety check (400 without it).
  Future<Map<String, dynamic>> wipeDevice({
    required String confirmationId,
    bool factoryReset = true,
    bool wipeSdCard = false,
    bool wipeEsim = false,
  }) async {
    if (confirmationId.isEmpty) {
      throw ApiError(
        message: 'confirmation_id is required for the wipe command',
        code: 'INVALID_ARGUMENT',
      );
    }
    try {
      final response = await _dio.post(
        ApiEndpoints.deviceWipe(_requiredDeviceId),
        data: {
          'confirmation_id': confirmationId,
          'factory_reset': factoryReset,
          'wipe_sd_card': wipeSdCard,
          'wipe_esim': wipeEsim,
        },
      );
      return response.data as Map<String, dynamic>? ?? {};
    } on DioException catch (e) {
      throw ApiError.fromDioException(e);
    }
  }

  /// Ring device (issues a remote ring command)
  /// POST /api/v1/device/{device_id}/ring
  Future<Map<String, dynamic>> ringDevice() async {
    try {
      final response =
          await _dio.post(ApiEndpoints.deviceRing(_requiredDeviceId));
      return response.data as Map<String, dynamic>? ?? {};
    } on DioException catch (e) {
      throw ApiError.fromDioException(e);
    }
  }

  /// Mark device as lost
  /// POST /api/v1/device/{device_id}/mark-lost (no request body)
  Future<bool> markDeviceLost({String? message}) async {
    try {
      await _dio.post(ApiEndpoints.deviceLost(_requiredDeviceId));
      return true;
    } on DioException catch (e) {
      throw ApiError.fromDioException(e);
    }
  }

  /// Mark device as stolen
  /// POST /api/v1/device/{device_id}/mark-stolen (no request body)
  Future<bool> markDeviceStolen({String? reportNumber}) async {
    try {
      await _dio.post(ApiEndpoints.deviceStolen(_requiredDeviceId));
      return true;
    } on DioException catch (e) {
      throw ApiError.fromDioException(e);
    }
  }

  /// Mark device as recovered
  /// POST /api/v1/device/{device_id}/mark-recovered
  Future<bool> markDeviceRecovered() async {
    try {
      await _dio.post(ApiEndpoints.deviceRecovered(_requiredDeviceId));
      return true;
    } on DioException catch (e) {
      throw ApiError.fromDioException(e);
    }
  }

  /// Get location history
  /// GET /api/v1/device/{device_id}/location/history
  /// Response: { "device_id", "locations": [...], "count" }
  Future<List<Map<String, dynamic>>> getLocationHistory({int days = 7}) async {
    try {
      final response = await _dio
          .get(ApiEndpoints.deviceLocationHistory(_requiredDeviceId));
      final locations = response.data['locations'];
      if (locations is! List) {
        throw ApiError(
          message: 'Unexpected location history response: missing "locations" list',
          code: 'BAD_RESPONSE',
        );
      }
      return locations.cast<Map<String, dynamic>>();
    } on DioException catch (e) {
      throw ApiError.fromDioException(e);
    }
  }

  /// Get SIM history
  /// GET /api/v1/device/{device_id}/sim/history
  /// Response: { "device_id", "events": [...], "count" }
  Future<List<Map<String, dynamic>>> getSIMHistory() async {
    try {
      final response =
          await _dio.get(ApiEndpoints.deviceSimHistory(_requiredDeviceId));
      final events = response.data['events'];
      if (events is! List) {
        throw ApiError(
          message: 'Unexpected SIM history response: missing "events" list',
          code: 'BAD_RESPONSE',
        );
      }
      return events.cast<Map<String, dynamic>>();
    } on DioException catch (e) {
      throw ApiError.fromDioException(e);
    }
  }

  /// Add trusted SIM
  /// POST /api/v1/device/{device_id}/sim/trusted — Body: { "iccid": "..." }
  Future<bool> addTrustedSIM(String iccid, String name) async {
    try {
      await _dio.post(
        ApiEndpoints.deviceTrustedSim(_requiredDeviceId),
        data: {'iccid': iccid},
      );
      return true;
    } on DioException catch (e) {
      throw ApiError.fromDioException(e);
    }
  }

  /// Audit OS vulnerabilities
  /// POST /api/v1/device/vulnerabilities/audit
  /// Body: { device_id, platform, os_version, security_patch, api_level }
  /// (platform and os_version are required by the backend)
  Future<Map<String, dynamic>> auditOSVulnerabilities() async {
    try {
      final deviceInfo = DeviceInfoPlugin();
      final payload = <String, dynamic>{
        'device_id': _authInterceptor.deviceId ?? '',
      };

      if (Platform.isAndroid) {
        final info = await deviceInfo.androidInfo;
        payload['platform'] = 'android';
        payload['os_version'] = info.version.release;
        payload['security_patch'] = info.version.securityPatch ?? '';
        payload['api_level'] = info.version.sdkInt;
      } else if (Platform.isIOS) {
        final info = await deviceInfo.iosInfo;
        payload['platform'] = 'ios';
        payload['os_version'] = info.systemVersion;
      } else {
        throw ApiError(
          message: 'OS vulnerability audit is only supported on Android and iOS',
          code: 'UNSUPPORTED_PLATFORM',
        );
      }

      final response = await _dio.post(
        ApiEndpoints.deviceVulnerabilitiesAudit,
        data: payload,
      );
      return response.data as Map<String, dynamic>? ?? {};
    } on DioException catch (e) {
      throw ApiError.fromDioException(e);
    }
  }

  /// Register a push (FCM/APNs) token for the registered device so the backend
  /// can wake the device-agent with a high-priority data push.
  /// POST /api/v1/device/{device_id}/push-token
  /// Body: { "token", "platform" }
  ///
  /// [platform] defaults to the current OS ("android"/"ios"). Invoked by
  /// DevicePushService once Firebase Cloud Messaging hands the app a token
  /// (on init and on every token refresh).
  Future<bool> registerPushToken(String token, {String? platform}) async {
    if (token.isEmpty) {
      throw ApiError(
        message: 'A non-empty push token is required',
        code: 'INVALID_ARGUMENT',
      );
    }
    try {
      await _dio.post(
        ApiEndpoints.devicePushToken(_requiredDeviceId),
        data: {
          'token': token,
          'platform': platform ?? Platform.operatingSystem,
        },
      );
      return true;
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
  /// GET /api/v1/forensics/iocs/stats
  Future<Map<String, dynamic>> getIOCStats() async {
    try {
      final response = await _dio.get(ApiEndpoints.forensicsIocStats);
      return response.data as Map<String, dynamic>? ?? {};
    } on DioException catch (e) {
      throw ApiError.fromDioException(e);
    }
  }

  /// Analyze shutdown log
  /// POST /api/v1/forensics/analyze/shutdown-log
  Future<Map<String, dynamic>> analyzeShutdownLog(Map<String, dynamic> logData) async {
    try {
      final response = await _dio.post(ApiEndpoints.forensicsAnalyzeShutdownLog, data: logData);
      return response.data as Map<String, dynamic>? ?? {};
    } on DioException catch (e) {
      throw ApiError.fromDioException(e);
    }
  }

  // NOTE: analyzeBackup / analyzeDataUsage / analyzeSysdiagnose were removed:
  // those backend paths are service-only (server-side file paths), archive
  // artifacts go through the dedicated multipart upload endpoints
  // (uploadSysdiagnose / uploadAndroidBugreport), and the methods had zero
  // call sites.

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
  /// POST /api/v1/forensics/full-analysis
  Future<Map<String, dynamic>> runFullForensicAnalysis(Map<String, dynamic> data) async {
    try {
      final response = await _dio.post(ApiEndpoints.forensicsFullAnalysis, data: data);
      return response.data as Map<String, dynamic>? ?? {};
    } on DioException catch (e) {
      throw ApiError.fromDioException(e);
    }
  }

  /// Quick forensic check
  /// POST /api/v1/forensics/quick-check
  /// Body: { "platform": "ios"|"android", "log_data": "..." }
  Future<Map<String, dynamic>> quickForensicCheck(Map<String, dynamic> payload) async {
    if ((payload['log_data'] as String?)?.isEmpty ?? true) {
      throw ApiError(
        message: 'log_data is required for a quick forensic check',
        code: 'INVALID_ARGUMENT',
      );
    }
    try {
      final response =
          await _dio.post(ApiEndpoints.forensicsQuickCheck, data: payload);
      return response.data as Map<String, dynamic>? ?? {};
    } on DioException catch (e) {
      throw ApiError.fromDioException(e);
    }
  }

  /// Shared multipart upload helper for forensic artifact uploads.
  /// Sends FormData: { "file": (multipart file), "device_id": "..." }.
  /// [onSendProgress] reports real bytes-sent progress from dio.
  Future<Map<String, dynamic>> _uploadForensicArtifact(
    String endpoint,
    String filePath, {
    String? deviceId,
    void Function(int sent, int total)? onSendProgress,
  }) async {
    final id = deviceId ?? _requiredDeviceId;
    final file = File(filePath);
    if (!file.existsSync()) {
      throw ApiError(
        message: 'File not found for forensic upload: $filePath',
        code: 'FILE_NOT_FOUND',
      );
    }
    try {
      final formData = FormData.fromMap({
        'file': await MultipartFile.fromFile(
          filePath,
          filename: filePath.split(Platform.pathSeparator).last,
        ),
        'device_id': id,
      });
      final response = await _dio.post(
        endpoint,
        data: formData,
        onSendProgress: onSendProgress,
      );
      return response.data as Map<String, dynamic>? ?? {};
    } on DioException catch (e) {
      throw ApiError.fromDioException(e);
    }
  }

  /// Upload an iOS backup for forensic analysis
  /// POST /api/v1/forensics/ios/backup/upload (multipart: file + device_id)
  /// The file must be a ZIP of the backup directory (.zip only).
  Future<Map<String, dynamic>> uploadIosBackup(
    String filePath, {
    String? deviceId,
    void Function(int sent, int total)? onSendProgress,
  }) =>
      _uploadForensicArtifact(
        ApiEndpoints.forensicsIosBackupUpload,
        filePath,
        deviceId: deviceId,
        onSendProgress: onSendProgress,
      );

  /// Upload an iOS sysdiagnose archive for forensic analysis
  /// POST /api/v1/forensics/ios/sysdiagnose/upload (multipart: file + device_id)
  /// Accepted archive types: .tar.gz, .tgz, .zip.
  Future<Map<String, dynamic>> uploadSysdiagnose(
    String filePath, {
    String? deviceId,
    void Function(int sent, int total)? onSendProgress,
  }) =>
      _uploadForensicArtifact(
        ApiEndpoints.forensicsIosSysdiagnoseUpload,
        filePath,
        deviceId: deviceId,
        onSendProgress: onSendProgress,
      );

  /// Upload an Android bugreport for forensic analysis
  /// POST /api/v1/forensics/android/bugreport/upload (multipart: file + device_id)
  /// Accepted file types: .zip (bugreport archive) or .txt (raw bugreport).
  Future<Map<String, dynamic>> uploadAndroidBugreport(
    String filePath, {
    String? deviceId,
    void Function(int sent, int total)? onSendProgress,
  }) =>
      _uploadForensicArtifact(
        ApiEndpoints.forensicsAndroidBugreportUpload,
        filePath,
        deviceId: deviceId,
        onSendProgress: onSendProgress,
      );

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
  /// POST /api/v1/privacy/events — backend decodes models.PrivacyEvent and
  /// requires "device_id" (400 without it); the legacy "type" key is mapped
  /// to the model's "event_type".
  Future<bool> recordPrivacyEvent(Map<String, dynamic> event) async {
    final payload = Map<String, dynamic>.from(event);

    // Legacy callers send 'type'; the Go model field is 'event_type'.
    if (payload.containsKey('type') && !payload.containsKey('event_type')) {
      payload['event_type'] = payload.remove('type');
    }

    final deviceId = payload['device_id'] as String? ?? _authInterceptor.deviceId;
    if (deviceId == null || deviceId.isEmpty) {
      throw ApiError(
        message: 'device_id is required to record a privacy event '
            '(device not registered)',
        code: 'NO_DEVICE_ID',
      );
    }
    payload['device_id'] = deviceId;

    try {
      await _dio.post(ApiEndpoints.privacyEvents, data: payload);
      return true;
    } on DioException catch (e) {
      throw ApiError.fromDioException(e);
    }
  }

  /// Check clipboard content
  /// POST /api/v1/privacy/clipboard/check — Body: { "content", "source_app" }
  Future<Map<String, dynamic>> checkClipboard(String content) async {
    try {
      final response = await _dio.post(
        ApiEndpoints.privacyClipboardCheck,
        data: {'content': content},
      );
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
  /// GET /api/v1/scam/patterns
  /// Response: { "version", "last_updated", "scam_types": [...], "risk_indicators": [...] }
  Future<List<Map<String, dynamic>>> getScamPatterns() async {
    try {
      final response = await _dio.get(ApiEndpoints.scamPatterns);
      final scamTypes = response.data['scam_types'];
      if (scamTypes is! List) {
        throw ApiError(
          message: 'Unexpected scam patterns response: missing "scam_types" list',
          code: 'BAD_RESPONSE',
        );
      }
      return scamTypes.cast<Map<String, dynamic>>();
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
  /// GET /api/v1/scam/phone/{number}
  Future<Map<String, dynamic>> getPhoneReputation(String phoneNumber) async {
    try {
      final response = await _dio.get(
        ApiEndpoints.scamPhoneReputation(Uri.encodeComponent(phoneNumber)),
      );
      return response.data as Map<String, dynamic>? ?? {};
    } on DioException catch (e) {
      throw ApiError.fromDioException(e);
    }
  }

  /// Report phone number
  /// POST /api/v1/scam/phone/report
  /// Body: { "phone_number" (required), "scam_type", "description" }
  Future<bool> reportPhoneNumber(String phoneNumber, String reason) async {
    try {
      await _dio.post(
        ApiEndpoints.scamPhoneReport,
        data: {'phone_number': phoneNumber, 'description': reason},
      );
      return true;
    } on DioException catch (e) {
      throw ApiError.fromDioException(e);
    }
  }

  // ============================================
  // NETWORK
  // ============================================

  /// Check if a domain is a tracker that should be blocked.
  /// POST /api/v1/privacy/trackers/should-block {domain}
  /// -> { "domain", "should_block", "tracker" }
  /// (Previously pointed at the DNS-check endpoint, which never returned a
  /// should_block verdict; this is the purpose-built backend route.)
  Future<bool> shouldBlockDomain(String domain) async {
    try {
      final response = await _dio.post(
        ApiEndpoints.privacyTrackersShouldBlock,
        data: {'domain': domain},
      );
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

      final results = _asList(response.data, 'results');
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

      final results = _asList(response.data, 'results');
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

      final patterns = _asList(response.data, 'patterns');
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

      final results = _asList(response.data, 'results');
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

  /// Report a QR scan false positive
  /// POST /api/v1/qr/report-false-positive
  /// Body: { "content": "...", "reason"?: "..." }
  Future<void> reportQrFalsePositive(String content, {String? reason}) async {
    try {
      await _dio.post(
        ApiEndpoints.qrReportFalsePositive,
        data: {
          'content': content,
          if (reason != null && reason.isNotEmpty) 'reason': reason,
        },
      );
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
  /// GET /api/v1/darkweb/alerts
  /// Response: { "unread": [...], "read": [...], "unread_count", "total_count" }
  /// Unread alerts are returned first.
  Future<List<BreachAlert>> getBreachAlerts() async {
    try {
      final response = await _dio.get(ApiEndpoints.darkwebAlerts);

      final data = response.data;
      final unread = data is Map<String, dynamic> ? data['unread'] : null;
      final read = data is Map<String, dynamic> ? data['read'] : null;
      if (unread is! List || read is! List) {
        throw ApiError(
          message: 'Unexpected dark web alerts response: '
              'missing "unread"/"read" lists',
          code: 'BAD_RESPONSE',
        );
      }

      return [...unread, ...read]
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

      final trackers = _asList(response.data, 'trackers');
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
      return _asList(response.data, 'trusted_aps').cast<Map<String, dynamic>>();
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

      final tactics = _asList(response.data, 'tactics');
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

      final techniques = _asList(response.data, 'techniques');
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

      final results = _asList(response.data, 'results');
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

  /// Get correlated indicators for a single indicator
  /// GET /api/v1/correlation/indicator/{id}
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
  /// GET /api/v1/footprint/brokers — response is a bare JSON array
  Future<List<dynamic>> getDataBrokers() async {
    try {
      final response = await _dio.get(ApiEndpoints.footprintBrokers);
      final data = response.data;
      if (data is! List) {
        throw ApiError(
          message: 'Unexpected brokers response: expected a JSON array',
          code: 'BAD_RESPONSE',
        );
      }
      return data;
    } on DioException catch (e) {
      throw ApiError.fromDioException(e);
    }
  }

  /// Scan digital footprint
  /// POST /api/v1/footprint/scan — Body must include "email"
  Future<Map<String, dynamic>> scanDigitalFootprint(Map<String, dynamic> params) async {
    try {
      final response = await _dio.post(
        ApiEndpoints.footprintScan,
        data: params,
      );
      return response.data as Map<String, dynamic>;
    } on DioException catch (e) {
      throw ApiError.fromDioException(e);
    }
  }

  /// Request data removal from broker
  /// POST /api/v1/footprint/removal — Body: { "broker_id", "email"? }
  Future<Map<String, dynamic>> requestDataRemoval(String brokerId, {String? email}) async {
    try {
      final response = await _dio.post(
        ApiEndpoints.footprintRemoval,
        data: {
          'broker_id': brokerId,
          if (email != null && email.isNotEmpty) 'email': email,
        },
      );
      return response.data as Map<String, dynamic>;
    } on DioException catch (e) {
      throw ApiError.fromDioException(e);
    }
  }

  /// Get removal request status
  /// GET /api/v1/footprint/removal/{id}
  Future<Map<String, dynamic>> getRemovalStatus(String requestId) async {
    try {
      final response =
          await _dio.get(ApiEndpoints.footprintRemovalStatus(requestId));
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

  /// List conditional access policies (Zero Trust).
  /// Returns the raw policy objects from {policies: [...], count}.
  Future<List<Map<String, dynamic>>> getEnterprisePolicies() async {
    try {
      final response = await _dio.get(ApiEndpoints.enterprisePolicies);
      final data = response.data;
      if (data is Map<String, dynamic>) {
        return (data['policies'] as List<dynamic>?)
                ?.whereType<Map<String, dynamic>>()
                .toList() ??
            [];
      }
      return [];
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
      return _asList(response.data, 'frameworks').cast<Map<String, dynamic>>();
    } on DioException catch (e) {
      throw ApiError.fromDioException(e);
    }
  }

  /// Get compliance reports
  Future<List<Map<String, dynamic>>> getComplianceReports() async {
    try {
      final response = await _dio.get(ApiEndpoints.complianceReports);
      return _asList(response.data, 'reports').cast<Map<String, dynamic>>();
    } on DioException catch (e) {
      throw ApiError.fromDioException(e);
    }
  }

  /// Get compliance control catalog (GDPR / SOC 2 / CIS definitions).
  /// [framework] optionally filters server-side (gdpr|soc2|cis).
  /// Controls come back with status "unknown" — definitions, not assessments.
  Future<List<Map<String, dynamic>>> getComplianceControls({String? framework}) async {
    try {
      final response = await _dio.get(
        ApiEndpoints.complianceControls,
        queryParameters: {
          if (framework != null && framework.isNotEmpty) 'framework': framework,
        },
      );
      final data = response.data;
      if (data is Map<String, dynamic>) {
        return (data['controls'] as List<dynamic>?)
                ?.whereType<Map<String, dynamic>>()
                .toList() ??
            [];
      }
      return [];
    } on DioException catch (e) {
      throw ApiError.fromDioException(e);
    }
  }

  /// Generate a compliance report for a single framework (gdpr|soc2|cis).
  /// Dates are sent as yyyy-MM-dd; the backend defaults missing dates to the
  /// last month. Returns the generated report object.
  Future<Map<String, dynamic>> generateComplianceReport({
    required String framework,
    DateTime? startDate,
    DateTime? endDate,
  }) async {
    String fmt(DateTime d) =>
        '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
    try {
      final response = await _dio.post(
        ApiEndpoints.complianceReportGenerate,
        data: {
          'framework': framework,
          if (startDate != null) 'start_date': fmt(startDate),
          if (endDate != null) 'end_date': fmt(endDate),
        },
      );
      return response.data as Map<String, dynamic>? ?? {};
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
      return _asList(response.data, 'connections').cast<Map<String, dynamic>>();
    } on DioException catch (e) {
      throw ApiError.fromDioException(e);
    }
  }

  /// Get SIEM event forwarders
  Future<List<Map<String, dynamic>>> getSiemForwarders() async {
    try {
      final response = await _dio.get(ApiEndpoints.siemForwarders);
      return _asList(response.data, 'forwarders').cast<Map<String, dynamic>>();
    } on DioException catch (e) {
      throw ApiError.fromDioException(e);
    }
  }

  /// Get the persisted SIEM alert feed.
  ///
  /// The server returns `{alerts: [{id, integration_id, severity, title,
  /// description, source, created_at, forwarded, forward_error}], count}`.
  /// Supports optional [limit] (server default 100, max 500) and [severity]
  /// filters.
  Future<List<Map<String, dynamic>>> getSiemAlerts({
    int? limit,
    String? severity,
  }) async {
    try {
      final response = await _dio.get(
        ApiEndpoints.siemAlerts,
        queryParameters: {
          if (limit != null) 'limit': limit,
          if (severity != null && severity.isNotEmpty) 'severity': severity,
        },
      );
      return _asList(response.data, 'alerts').cast<Map<String, dynamic>>();
    } on DioException catch (e) {
      throw ApiError.fromDioException(e);
    }
  }

  // ============================================
  // WEBHOOKS
  // ============================================

  /// Get webhooks
  /// Extracts a list from a response body that may be a bare JSON array or an
  /// envelope like {"key": [...]}. Returns const [] when absent or wrong-shaped
  /// — never throws "String is not a subtype of int of index" on a bare array.
  static List<dynamic> _asList(dynamic data, String key) {
    if (data is List) return data;
    if (data is Map && data[key] is List) return data[key] as List<dynamic>;
    return const [];
  }

  Future<List<Map<String, dynamic>>> getWebhooks() async {
    try {
      final response = await _dio.get(ApiEndpoints.webhooks);
      return _asList(response.data, 'webhooks').cast<Map<String, dynamic>>();
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

  /// Enable or disable a webhook
  /// POST /api/v1/webhooks/{id}/enable | /disable
  Future<void> setWebhookEnabled(String id, bool enabled) async {
    try {
      await _dio.post(
        enabled ? ApiEndpoints.webhookEnable(id) : ApiEndpoints.webhookDisable(id),
      );
    } on DioException catch (e) {
      throw ApiError.fromDioException(e);
    }
  }

  /// Send a test delivery for a webhook
  /// POST /api/v1/webhooks/{id}/test — returns the backend's delivery result
  Future<Map<String, dynamic>> testWebhook(String id) async {
    try {
      final response = await _dio.post(ApiEndpoints.webhookTest(id));
      return response.data as Map<String, dynamic>? ?? {};
    } on DioException catch (e) {
      throw ApiError.fromDioException(e);
    }
  }

  // ============================================
  // INTELLIGENCE SOURCES
  // ============================================

  /// Get intelligence sources
  /// GET /api/v1/intel/sources — Response: { "data": [...], "total": N }
  Future<List<Map<String, dynamic>>> getIntelSources() async {
    try {
      final response = await _dio.get(
        ApiEndpoints.intelSources,
        options: Options(extra: {'cacheTtl': ApiConfig.cacheTtlMedium}),
      );
      final sources = response.data['data'];
      if (sources is! List) {
        throw ApiError(
          message: 'Unexpected sources response: missing "data" list',
          code: 'BAD_RESPONSE',
        );
      }
      return sources.cast<Map<String, dynamic>>();
    } on DioException catch (e) {
      throw ApiError.fromDioException(e);
    }
  }

  /// Create intelligence source
  /// POST /api/v1/sources
  Future<Map<String, dynamic>> createSource(Map<String, dynamic> source) async {
    try {
      final response = await _dio.post(ApiEndpoints.sourcesCreate, data: source);
      return response.data as Map<String, dynamic>? ?? {};
    } on DioException catch (e) {
      throw ApiError.fromDioException(e);
    }
  }

  /// Update intelligence source
  /// PATCH /api/v1/sources/{slug}
  Future<Map<String, dynamic>> updateSource(
    String slug,
    Map<String, dynamic> updates,
  ) async {
    try {
      final response =
          await _dio.patch(ApiEndpoints.sourceUpdate(slug), data: updates);
      return response.data as Map<String, dynamic>? ?? {};
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
      return _asList(response.data, 'integrations').cast<Map<String, dynamic>>();
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
  /// GET /api/v1/ml/models — Response: MLServiceStats with "models": [...]
  Future<List<Map<String, dynamic>>> getMLModels() async {
    try {
      final response = await _dio.get(
        ApiEndpoints.mlModels,
        options: Options(extra: {'cacheTtl': ApiConfig.cacheTtlMedium}),
      );
      final models = response.data['models'];
      if (models is! List) {
        throw ApiError(
          message: 'Unexpected ML models response: missing "models" list',
          code: 'BAD_RESPONSE',
        );
      }
      return models.cast<Map<String, dynamic>>();
    } on DioException catch (e) {
      throw ApiError.fromDioException(e);
    }
  }

  /// Get anomaly detections
  /// GET /api/v1/ml/anomalies — Response: { "anomalies": [...], "count": N }
  /// Throws [MlModelsNotTrainedError] when the backend answers 409 with
  /// code "models_not_trained" (anomaly models not trained yet).
  Future<List<Map<String, dynamic>>> getAnomalies() async {
    try {
      final response = await _dio.get(ApiEndpoints.mlAnomalies);
      final anomalies = response.data['anomalies'];
      if (anomalies is! List) {
        throw ApiError(
          message: 'Unexpected anomalies response: missing "anomalies" list',
          code: 'BAD_RESPONSE',
        );
      }
      return anomalies.cast<Map<String, dynamic>>();
    } on DioException catch (e) {
      final error = ApiError.fromDioException(e);
      if (e.response?.statusCode == 409) {
        throw MlModelsNotTrainedError(
          message: error.message,
          details: error.details,
        );
      }
      throw error;
    }
  }

  /// Get ML insights
  /// GET /api/v1/ml/insights — Response: { "insights": [...], "count": N }
  Future<List<Map<String, dynamic>>> getMLInsights() async {
    try {
      final response = await _dio.get(ApiEndpoints.mlInsights);
      final insights = response.data['insights'];
      if (insights is! List) {
        throw ApiError(
          statusCode: response.statusCode,
          message: 'Unexpected ML insights response: missing "insights" list',
          code: 'BAD_RESPONSE',
        );
      }
      return insights.cast<Map<String, dynamic>>();
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
      return _asList(response.data, 'playbooks').cast<Map<String, dynamic>>();
    } on DioException catch (e) {
      throw ApiError.fromDioException(e);
    }
  }

  /// Get playbook executions
  Future<List<Map<String, dynamic>>> getPlaybookExecutions() async {
    try {
      final response = await _dio.get(ApiEndpoints.playbookExecutions);
      return _asList(response.data, 'executions').cast<Map<String, dynamic>>();
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

  /// Enable or disable a playbook
  /// POST /api/v1/playbooks/{id}/enable | /disable
  Future<void> setPlaybookEnabled(String id, bool enabled) async {
    try {
      await _dio.post(
        enabled ? ApiEndpoints.playbookEnable(id) : ApiEndpoints.playbookDisable(id),
      );
    } on DioException catch (e) {
      throw ApiError.fromDioException(e);
    }
  }

  // ============================================
  // DESKTOP SECURITY
  // ============================================

  /// Get persistence items
  /// GET /api/v1/desktop/persistence
  /// Response: { "items": [...], "scanned_at": "..." }
  Future<List<Map<String, dynamic>>> getPersistenceItems() async {
    try {
      final response = await _dio.get(ApiEndpoints.desktopPersistence);
      final items = response.data['items'];
      if (items is! List) {
        throw ApiError(
          message: 'Unexpected persistence response: missing "items" list',
          code: 'BAD_RESPONSE',
        );
      }
      return items.cast<Map<String, dynamic>>();
    } on DioException catch (e) {
      throw ApiError.fromDioException(e);
    }
  }

  /// Get signed apps
  /// GET /api/v1/desktop/apps
  /// Response: { "apps": [...], "scanned_at": "..." }
  Future<List<Map<String, dynamic>>> getSignedApps() async {
    try {
      final response = await _dio.get(ApiEndpoints.desktopApps);
      final apps = response.data['apps'];
      if (apps is! List) {
        throw ApiError(
          message: 'Unexpected desktop apps response: missing "apps" list',
          code: 'BAD_RESPONSE',
        );
      }
      return apps.cast<Map<String, dynamic>>();
    } on DioException catch (e) {
      throw ApiError.fromDioException(e);
    }
  }

  /// Get firewall rules
  /// GET /api/v1/desktop/firewall — Response: { "rules": [...], ... }
  Future<List<Map<String, dynamic>>> getDesktopFirewallRules() async {
    try {
      final response = await _dio.get(ApiEndpoints.desktopFirewall);
      final rules = response.data['rules'];
      if (rules is! List) {
        throw ApiError(
          message: 'Unexpected firewall rules response: missing "rules" list',
          code: 'BAD_RESPONSE',
        );
      }
      return rules.cast<Map<String, dynamic>>();
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
      return _asList(response.data, 'servers').cast<Map<String, dynamic>>();
    } on DioException catch (e) {
      throw ApiError.fromDioException(e);
    }
  }

  /// Get blocked domains for VPN
  /// GET /api/v1/vpn/blocked (alias of /orbnet/rules)
  /// Response: { "rules": [...], "count": N }
  Future<List<Map<String, dynamic>>> getVpnBlockedDomains() async {
    try {
      final response = await _dio.get(ApiEndpoints.vpnBlocked);
      final rules = response.data['rules'];
      if (rules is! List) {
        throw ApiError(
          message: 'Unexpected VPN block rules response: missing "rules" list',
          code: 'BAD_RESPONSE',
        );
      }
      return rules.cast<Map<String, dynamic>>();
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
  /// GET /api/v1/graph/nodes — Response: { "nodes": [...], "count": N }
  Future<List<Map<String, dynamic>>> getGraphNodes({String? query}) async {
    try {
      final response = await _dio.get(
        ApiEndpoints.graphNodes,
        queryParameters: query != null ? {'query': query} : null,
      );
      final nodes = response.data['nodes'];
      if (nodes is! List) {
        throw ApiError(
          message: 'Unexpected graph nodes response: missing "nodes" list',
          code: 'BAD_RESPONSE',
        );
      }
      return nodes.cast<Map<String, dynamic>>();
    } on DioException catch (e) {
      throw ApiError.fromDioException(e);
    }
  }

  /// Get graph relations
  /// GET /api/v1/graph/relations — Response: { "relations": [...], "count": N }
  Future<List<Map<String, dynamic>>> getGraphRelations({String? nodeId}) async {
    try {
      final response = await _dio.get(
        ApiEndpoints.graphRelations,
        queryParameters: nodeId != null ? {'node_id': nodeId} : null,
      );
      final relations = response.data['relations'];
      if (relations is! List) {
        throw ApiError(
          message:
              'Unexpected graph relations response: missing "relations" list',
          code: 'BAD_RESPONSE',
        );
      }
      return relations.cast<Map<String, dynamic>>();
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
      return _asList(response.data, 'rules').cast<Map<String, dynamic>>();
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
      return _asList(response.data, 'servers').cast<Map<String, dynamic>>();
    } on DioException catch (e) {
      throw ApiError.fromDioException(e);
    }
  }

  /// Get TAXII collections
  Future<List<Map<String, dynamic>>> getTaxiiCollections() async {
    try {
      final response = await _dio.get(ApiEndpoints.taxiiCollections);
      return _asList(response.data, 'collections').cast<Map<String, dynamic>>();
    } on DioException catch (e) {
      throw ApiError.fromDioException(e);
    }
  }

  /// Get STIX objects from collection
  Future<List<Map<String, dynamic>>> getStixObjects(String collectionId) async {
    try {
      final response = await _dio.get(ApiEndpoints.taxiiCollectionObjects(collectionId));
      return _asList(response.data, 'objects').cast<Map<String, dynamic>>();
    } on DioException catch (e) {
      throw ApiError.fromDioException(e);
    }
  }

  // ============================================
  // CORRELATION
  // ============================================

  /// List correlation results
  /// GET /api/v1/correlation
  Future<List<Map<String, dynamic>>> getCorrelations({String? query}) async {
    try {
      final response = await _dio.get(
        ApiEndpoints.correlations,
        queryParameters: query != null ? {'query': query} : null,
      );
      final data = response.data;
      final results = data is Map<String, dynamic>
          ? (data['correlations'] ?? data['results'])
          : null;
      if (results is! List) {
        throw ApiError(
          message: 'Unexpected correlation list response: '
              'missing "correlations" list',
          code: 'BAD_RESPONSE',
        );
      }
      return results.cast<Map<String, dynamic>>();
    } on DioException catch (e) {
      throw ApiError.fromDioException(e);
    }
  }

  /// Legacy name kept for existing call sites.
  Future<List<Map<String, dynamic>>> getCorrelationResults({String? query}) =>
      getCorrelations(query: query);

  /// Run correlation analysis
  /// POST /api/v1/correlation/run
  Future<Map<String, dynamic>> runCorrelation() async {
    try {
      final response = await _dio.post(ApiEndpoints.correlationRun);
      return response.data as Map<String, dynamic>? ?? {};
    } on DioException catch (e) {
      throw ApiError.fromDioException(e);
    }
  }

  // ============================================
  // ML ANALYSIS
  // ============================================

  /// Run ML analysis on a raw indicator value
  /// POST /api/v1/ml/analyze — Body: { "value": "...", "type": "domain"|... }
  /// The backend requires "value" (400 otherwise), so it is validated here.
  Future<Map<String, dynamic>> runMLAnalysis({String? value, String? type}) async {
    if (value == null || value.isEmpty) {
      throw ApiError(
        message: 'ML analysis requires a "value" to analyze '
            '(e.g. a domain, URL, IP, or hash)',
        code: 'INVALID_ARGUMENT',
      );
    }
    try {
      final response = await _dio.post(
        ApiEndpoints.mlAnalyze,
        data: {
          'value': value,
          if (type != null && type.isNotEmpty) 'type': type,
        },
      );
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
  // NETWORK THREATS
  // ============================================
  // NOTE: device VPN control (/vpn/status|connect|disconnect) and device DNS
  // control (/dns/status|enable|disable) were removed: the backend never
  // exposed them, VPN protection is provided by the separate OrbVPN app, and
  // DNS protection is configured at the OS level (Private DNS / profiles).

  /// Get network threats
  /// GET /api/v1/network/threats — Response: { "threats": [...], "count": N }
  Future<List<Map<String, dynamic>>> getNetworkThreats() async {
    try {
      final response = await _dio.get(ApiEndpoints.networkThreats);
      final threats = response.data['threats'];
      if (threats is! List) {
        throw ApiError(
          message: 'Unexpected network threats response: '
              'missing "threats" list',
          code: 'BAD_RESPONSE',
        );
      }
      return threats.cast<Map<String, dynamic>>();
    } on DioException catch (e) {
      throw ApiError.fromDioException(e);
    }
  }

  // ============================================
  // SUPPLY CHAIN SECURITY
  // ============================================

  // NOTE: getSupplyChainVulnerabilities (GET /supply-chain/vulnerabilities)
  // was removed: its only consumer was the client-side advisory-prefix
  // matcher in SupplyChainMonitorService, which fabricated matches by
  // ignoring version ranges. Version-aware matching now goes through
  // checkSupplyChainPackages (POST /supply-chain/check) below; the backend
  // route remains for other consumers.

  /// Check packages for vulnerabilities
  /// POST /api/v1/supply-chain/check
  /// Body: { "packages": [{ "name", "version", "ecosystem"? }] }
  /// Response: { "results": [...] }
  Future<List<Map<String, dynamic>>> checkSupplyChainPackages(
    List<Map<String, dynamic>> packages,
  ) async {
    try {
      final response = await _dio.post(
        ApiEndpoints.supplyChainCheck,
        data: {'packages': packages},
      );
      final results = response.data['results'];
      if (results is! List) {
        throw ApiError(
          message: 'Unexpected supply-chain check response: '
              'missing "results" list',
          code: 'BAD_RESPONSE',
        );
      }
      return results.cast<Map<String, dynamic>>();
    } on DioException catch (e) {
      throw ApiError.fromDioException(e);
    }
  }

  /// Get tracker signatures
  /// GET /api/v1/supply-chain/trackers
  /// Response: { "trackers": [...], "count": N } — elements may be plain
  /// signature strings or objects carrying a signature/package prefix.
  Future<List<String>> getTrackerSignatures() async {
    try {
      final response = await _dio.get(
        ApiEndpoints.supplyChainTrackers,
        options: Options(extra: {'cacheTtl': ApiConfig.cacheTtlLong}),
      );
      final trackers = response.data['trackers'];
      if (trackers is! List) {
        throw ApiError(
          message: 'Unexpected supply-chain trackers response: '
              'missing "trackers" list',
          code: 'BAD_RESPONSE',
        );
      }
      return trackers
          .map((t) {
            if (t is String) return t;
            if (t is Map) {
              final sig = t['signature'] ?? t['package_prefix'] ?? t['name'];
              if (sig is String) return sig;
            }
            return null;
          })
          .whereType<String>()
          .toList();
    } on DioException catch (e) {
      throw ApiError.fromDioException(e);
    }
  }

  // ============================================
  // ANALYTICS & REPORTING
  // ============================================

  /// Get threat analytics
  Future<Map<String, dynamic>> getThreatAnalytics({String period = '7d'}) async {
    try {
      final response = await _dio.get(
        ApiEndpoints.analyticsThreat,
        queryParameters: {'period': period},
      );
      return response.data as Map<String, dynamic>? ?? {};
    } on DioException catch (e) {
      throw ApiError.fromDioException(e);
    }
  }

  /// Get alert metrics
  Future<Map<String, dynamic>> getAlertMetrics({String period = '7d'}) async {
    try {
      final response = await _dio.get(
        ApiEndpoints.analyticsAlerts,
        queryParameters: {'period': period},
      );
      return response.data as Map<String, dynamic>? ?? {};
    } on DioException catch (e) {
      throw ApiError.fromDioException(e);
    }
  }

  /// Get detection metrics
  Future<Map<String, dynamic>> getDetectionMetrics({String period = '7d'}) async {
    try {
      final response = await _dio.get(
        ApiEndpoints.analyticsDetections,
        queryParameters: {'period': period},
      );
      return response.data as Map<String, dynamic>? ?? {};
    } on DioException catch (e) {
      throw ApiError.fromDioException(e);
    }
  }

  /// Get source health report
  Future<Map<String, dynamic>> getSourceHealth() async {
    try {
      final response = await _dio.get(ApiEndpoints.analyticsSources);
      return response.data as Map<String, dynamic>? ?? {};
    } on DioException catch (e) {
      throw ApiError.fromDioException(e);
    }
  }

  /// Get geo distribution
  Future<Map<String, dynamic>> getGeoDistribution({String period = '7d'}) async {
    try {
      final response = await _dio.get(
        ApiEndpoints.analyticsGeo,
        queryParameters: {'period': period},
      );
      return response.data as Map<String, dynamic>? ?? {};
    } on DioException catch (e) {
      throw ApiError.fromDioException(e);
    }
  }

  /// Get analytics dashboard config
  Future<Map<String, dynamic>> getAnalyticsDashboard() async {
    try {
      final response = await _dio.get(ApiEndpoints.analyticsDashboard);
      return response.data as Map<String, dynamic>? ?? {};
    } on DioException catch (e) {
      throw ApiError.fromDioException(e);
    }
  }

  /// List analytics reports
  Future<List<Map<String, dynamic>>> getAnalyticsReports({int limit = 20}) async {
    try {
      final response = await _dio.get(
        ApiEndpoints.analyticsReports,
        queryParameters: {'limit': limit},
      );
      return (response.data as List<dynamic>?)
          ?.cast<Map<String, dynamic>>() ?? [];
    } on DioException catch (e) {
      throw ApiError.fromDioException(e);
    }
  }

  /// Create analytics report
  Future<Map<String, dynamic>> createAnalyticsReport({
    required String reportType,
    String format = 'json',
    String period = '7d',
  }) async {
    try {
      final response = await _dio.post(
        ApiEndpoints.analyticsReportCreate,
        data: {
          'report_type': reportType,
          'format': format,
          'period': period,
        },
      );
      return response.data as Map<String, dynamic>? ?? {};
    } on DioException catch (e) {
      throw ApiError.fromDioException(e);
    }
  }

  /// Get analytics report by ID
  Future<Map<String, dynamic>> getAnalyticsReport(String id) async {
    try {
      final response = await _dio.get(ApiEndpoints.analyticsReport(id));
      return response.data as Map<String, dynamic>? ?? {};
    } on DioException catch (e) {
      throw ApiError.fromDioException(e);
    }
  }

  // ============================================
  // DESKTOP SECURITY (Extended)
  // ============================================

  /// Quick scan persistence
  Future<Map<String, dynamic>> quickScanPersistence() async {
    try {
      final response = await _dio.post(ApiEndpoints.desktopPersistenceQuickScan);
      return response.data as Map<String, dynamic>? ?? {};
    } on DioException catch (e) {
      throw ApiError.fromDioException(e);
    }
  }

  /// Verify code signing
  Future<Map<String, dynamic>> verifyCodeSigning(String path) async {
    try {
      final response = await _dio.post(
        ApiEndpoints.desktopCodesignVerify,
        data: {'path': path},
      );
      return response.data as Map<String, dynamic>? ?? {};
    } on DioException catch (e) {
      throw ApiError.fromDioException(e);
    }
  }

  /// Get network connections
  Future<List<Map<String, dynamic>>> getNetworkConnections() async {
    try {
      final response = await _dio.get(ApiEndpoints.desktopNetworkConnections);
      return (response.data as List<dynamic>?)
          ?.cast<Map<String, dynamic>>() ?? [];
    } on DioException catch (e) {
      throw ApiError.fromDioException(e);
    }
  }

  /// Get listening ports
  Future<List<Map<String, dynamic>>> getListeningPorts() async {
    try {
      final response = await _dio.get(ApiEndpoints.desktopNetworkListening);
      return (response.data as List<dynamic>?)
          ?.cast<Map<String, dynamic>>() ?? [];
    } on DioException catch (e) {
      throw ApiError.fromDioException(e);
    }
  }

  /// Get outbound connections
  Future<List<Map<String, dynamic>>> getOutboundConnections() async {
    try {
      final response = await _dio.get(ApiEndpoints.desktopNetworkOutbound);
      return (response.data as List<dynamic>?)
          ?.cast<Map<String, dynamic>>() ?? [];
    } on DioException catch (e) {
      throw ApiError.fromDioException(e);
    }
  }

  /// Get network firewall rules
  Future<List<Map<String, dynamic>>> getNetworkFirewallRules() async {
    try {
      final response = await _dio.get(ApiEndpoints.desktopNetworkRules);
      return (response.data as List<dynamic>?)
          ?.cast<Map<String, dynamic>>() ?? [];
    } on DioException catch (e) {
      throw ApiError.fromDioException(e);
    }
  }

  /// Add firewall rule
  Future<void> addFirewallRule(Map<String, dynamic> rule) async {
    try {
      await _dio.post(ApiEndpoints.desktopNetworkRulesAdd, data: rule);
    } on DioException catch (e) {
      throw ApiError.fromDioException(e);
    }
  }

  /// Delete firewall rule
  Future<void> deleteFirewallRule(String id) async {
    try {
      await _dio.delete(ApiEndpoints.desktopNetworkRuleDelete(id));
    } on DioException catch (e) {
      throw ApiError.fromDioException(e);
    }
  }

  /// Block IP address
  Future<void> blockIpAddress(String ip, {String reason = ''}) async {
    try {
      await _dio.post(ApiEndpoints.desktopBlockIp, data: {'ip': ip, 'reason': reason});
    } on DioException catch (e) {
      throw ApiError.fromDioException(e);
    }
  }

  /// Scan browser extensions
  Future<Map<String, dynamic>> scanBrowserExtensions() async {
    try {
      final response = await _dio.post(ApiEndpoints.desktopBrowserScan);
      return response.data as Map<String, dynamic>? ?? {};
    } on DioException catch (e) {
      throw ApiError.fromDioException(e);
    }
  }

  /// VirusTotal hash lookup
  Future<Map<String, dynamic>> vtLookupHash(String hash) async {
    try {
      final response = await _dio.get(ApiEndpoints.desktopVtHash(hash));
      return response.data as Map<String, dynamic>? ?? {};
    } on DioException catch (e) {
      throw ApiError.fromDioException(e);
    }
  }

  /// VirusTotal IP lookup
  Future<Map<String, dynamic>> vtLookupIp(String ip) async {
    try {
      final response = await _dio.get(ApiEndpoints.desktopVtIp(ip));
      return response.data as Map<String, dynamic>? ?? {};
    } on DioException catch (e) {
      throw ApiError.fromDioException(e);
    }
  }

  /// Full desktop security scan
  Future<Map<String, dynamic>> fullDesktopScan() async {
    try {
      final response = await _dio.post(ApiEndpoints.desktopFullScan);
      return response.data as Map<String, dynamic>? ?? {};
    } on DioException catch (e) {
      throw ApiError.fromDioException(e);
    }
  }
}

/// Typed 409 state for GET /api/v1/ml/anomalies: the backend's anomaly
/// models have not been trained yet. Callers can catch this to render a
/// "models not trained" state instead of a generic error.
class MlModelsNotTrainedError extends ApiError {
  MlModelsNotTrainedError({
    required super.message,
    super.details,
  }) : super(statusCode: 409, code: 'models_not_trained');
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
    // The backend list envelope is { "data": [...], "total": N, "limit": N,
    // "has_more": bool } (intelligence, campaigns, actors, sources).
    final itemsList = json['data'];
    if (itemsList is! List) {
      throw const FormatException(
        'Unexpected list response: missing "data" array',
      );
    }
    final total = json['total'] as int? ?? itemsList.length;
    final limit = json['limit'] as int? ?? 100;

    return PaginatedResponse(
      items: itemsList.map(fromJson).toList(),
      page: json['page'] as int? ?? 1,
      limit: limit,
      total: total,
      totalPages: limit > 0 ? (total / limit).ceil() : 1,
      hasMore: json['has_more'] as bool? ?? false,
    );
  }
}
