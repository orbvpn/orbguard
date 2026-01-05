/// API Interceptors for OrbGuard Lab API
/// Handles authentication, retry logic, logging, and caching

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:dio/dio.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'api_config.dart';

/// Authentication interceptor for JWT token management
class AuthInterceptor extends Interceptor {
  static const String _tokenKey = 'orbguard_auth_token';
  static const String _refreshTokenKey = 'orbguard_refresh_token';
  static const String _deviceIdKey = 'orbguard_device_id';

  String? _accessToken;
  String? _refreshToken;
  String? _deviceId;
  bool _isRefreshing = false;
  final List<Function> _refreshQueue = [];

  final Dio _dio;

  AuthInterceptor(this._dio);

  /// Initialize tokens from storage
  Future<void> init() async {
    final prefs = await SharedPreferences.getInstance();
    _accessToken = prefs.getString(_tokenKey);
    _refreshToken = prefs.getString(_refreshTokenKey);
    _deviceId = prefs.getString(_deviceIdKey);
  }

  /// Save tokens to storage
  Future<void> saveTokens({
    required String accessToken,
    String? refreshToken,
  }) async {
    _accessToken = accessToken;
    if (refreshToken != null) {
      _refreshToken = refreshToken;
    }

    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_tokenKey, accessToken);
    if (refreshToken != null) {
      await prefs.setString(_refreshTokenKey, refreshToken);
    }
  }

  /// Clear tokens (logout)
  Future<void> clearTokens() async {
    _accessToken = null;
    _refreshToken = null;

    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_tokenKey);
    await prefs.remove(_refreshTokenKey);
  }

  /// Set device ID
  Future<void> setDeviceId(String deviceId) async {
    _deviceId = deviceId;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_deviceIdKey, deviceId);
  }

  @override
  void onRequest(RequestOptions options, RequestInterceptorHandler handler) {
    // Add authorization header if token exists
    if (_accessToken != null) {
      options.headers['Authorization'] = 'Bearer $_accessToken';
    }

    // Add device ID header
    if (_deviceId != null) {
      options.headers['X-Device-ID'] = _deviceId;
    }

    // Add common headers
    options.headers['X-Client-Version'] = '1.0.0';
    options.headers['X-Platform'] = Platform.isIOS ? 'ios' : 'android';

    handler.next(options);
  }

  @override
  void onError(DioException err, ErrorInterceptorHandler handler) async {
    // Handle 401 Unauthorized - attempt token refresh
    if (err.response?.statusCode == 401 && _refreshToken != null) {
      if (!_isRefreshing) {
        _isRefreshing = true;

        try {
          final newToken = await _refreshAccessToken();
          if (newToken != null) {
            // Retry original request with new token
            err.requestOptions.headers['Authorization'] = 'Bearer $newToken';
            final response = await _dio.fetch(err.requestOptions);
            handler.resolve(response);

            // Process queued requests
            for (final callback in _refreshQueue) {
              callback();
            }
            _refreshQueue.clear();
            return;
          }
        } catch (e) {
          // Refresh failed, clear tokens
          await clearTokens();
        } finally {
          _isRefreshing = false;
        }
      } else {
        // Queue this request until refresh completes
        final completer = Completer<void>();
        _refreshQueue.add(() {
          completer.complete();
        });

        await completer.future;

        // Retry with new token
        err.requestOptions.headers['Authorization'] = 'Bearer $_accessToken';
        try {
          final response = await _dio.fetch(err.requestOptions);
          handler.resolve(response);
          return;
        } catch (e) {
          handler.next(err);
          return;
        }
      }
    }

    handler.next(err);
  }

  Future<String?> _refreshAccessToken() async {
    try {
      final response = await _dio.post(
        '${ApiConfig.baseUrl}${ApiEndpoints.authRefresh}',
        data: {'refresh_token': _refreshToken},
        options: Options(
          headers: {'Authorization': 'Bearer $_refreshToken'},
        ),
      );

      if (response.statusCode == 200) {
        final data = response.data;
        final newAccessToken = data['access_token'] as String?;
        final newRefreshToken = data['refresh_token'] as String?;

        if (newAccessToken != null) {
          await saveTokens(
            accessToken: newAccessToken,
            refreshToken: newRefreshToken,
          );
          return newAccessToken;
        }
      }
    } catch (e) {
      // Refresh failed
    }
    return null;
  }

  bool get isAuthenticated => _accessToken != null;
  String? get deviceId => _deviceId;
}

/// Retry interceptor with exponential backoff
class RetryInterceptor extends Interceptor {
  final Dio _dio;
  final int maxRetries;
  final int baseDelayMs;

  RetryInterceptor(
    this._dio, {
    this.maxRetries = ApiConfig.maxRetries,
    this.baseDelayMs = ApiConfig.retryDelayMs,
  });

  @override
  void onError(DioException err, ErrorInterceptorHandler handler) async {
    // Get retry count from request
    final retryCount = err.requestOptions.extra['retryCount'] ?? 0;

    // Check if we should retry
    if (_shouldRetry(err) && retryCount < maxRetries) {
      // Calculate delay with exponential backoff
      final delay = baseDelayMs * (1 << retryCount); // 1s, 2s, 4s
      await Future.delayed(Duration(milliseconds: delay));

      // Increment retry count
      err.requestOptions.extra['retryCount'] = retryCount + 1;

      try {
        final response = await _dio.fetch(err.requestOptions);
        handler.resolve(response);
        return;
      } catch (e) {
        if (e is DioException) {
          handler.next(e);
          return;
        }
      }
    }

    handler.next(err);
  }

  bool _shouldRetry(DioException err) {
    // Retry on network errors
    if (err.type == DioExceptionType.connectionTimeout ||
        err.type == DioExceptionType.sendTimeout ||
        err.type == DioExceptionType.receiveTimeout ||
        err.type == DioExceptionType.connectionError) {
      return true;
    }

    // Retry on 5xx server errors
    final statusCode = err.response?.statusCode;
    if (statusCode != null && statusCode >= 500 && statusCode < 600) {
      return true;
    }

    // Retry on 429 Too Many Requests
    if (statusCode == 429) {
      return true;
    }

    return false;
  }
}

/// Logging interceptor for debugging
class LoggingInterceptor extends Interceptor {
  final bool enabled;
  final bool logRequestBody;
  final bool logResponseBody;

  LoggingInterceptor({
    this.enabled = true,
    this.logRequestBody = false,
    this.logResponseBody = false,
  });

  @override
  void onRequest(RequestOptions options, RequestInterceptorHandler handler) {
    if (enabled) {
      print('┌──────────────────────────────────────────────────────────────');
      print('│ REQUEST: ${options.method} ${options.uri}');
      print('│ Headers: ${_sanitizeHeaders(options.headers)}');
      if (logRequestBody && options.data != null) {
        print('│ Body: ${_truncate(options.data.toString(), 500)}');
      }
      print('└──────────────────────────────────────────────────────────────');
    }
    handler.next(options);
  }

  @override
  void onResponse(Response response, ResponseInterceptorHandler handler) {
    if (enabled) {
      print('┌──────────────────────────────────────────────────────────────');
      print('│ RESPONSE: ${response.statusCode} ${response.requestOptions.uri}');
      print('│ Duration: ${DateTime.now().difference(
        response.requestOptions.extra['startTime'] ?? DateTime.now()
      ).inMilliseconds}ms');
      if (logResponseBody && response.data != null) {
        print('│ Body: ${_truncate(response.data.toString(), 500)}');
      }
      print('└──────────────────────────────────────────────────────────────');
    }
    handler.next(response);
  }

  @override
  void onError(DioException err, ErrorInterceptorHandler handler) {
    if (enabled) {
      print('┌──────────────────────────────────────────────────────────────');
      print('│ ERROR: ${err.type} ${err.requestOptions.uri}');
      print('│ Status: ${err.response?.statusCode}');
      print('│ Message: ${err.message}');
      print('└──────────────────────────────────────────────────────────────');
    }
    handler.next(err);
  }

  Map<String, dynamic> _sanitizeHeaders(Map<String, dynamic> headers) {
    final sanitized = Map<String, dynamic>.from(headers);
    // Hide sensitive headers
    if (sanitized.containsKey('Authorization')) {
      sanitized['Authorization'] = '***';
    }
    return sanitized;
  }

  String _truncate(String text, int maxLength) {
    if (text.length <= maxLength) return text;
    return '${text.substring(0, maxLength)}...';
  }
}

/// Cache interceptor for offline support and performance
class CacheInterceptor extends Interceptor {
  final Map<String, CacheEntry> _cache = {};
  final int maxCacheSize;

  CacheInterceptor({this.maxCacheSize = 100});

  @override
  void onRequest(RequestOptions options, RequestInterceptorHandler handler) {
    // Only cache GET requests
    if (options.method != 'GET') {
      handler.next(options);
      return;
    }

    // Check for force refresh
    if (options.extra['forceRefresh'] == true) {
      handler.next(options);
      return;
    }

    // Check cache
    final cacheKey = _getCacheKey(options);
    final cached = _cache[cacheKey];

    if (cached != null && !cached.isExpired) {
      // Return cached response
      handler.resolve(Response(
        requestOptions: options,
        data: cached.data,
        statusCode: 200,
        statusMessage: 'OK (cached)',
      ));
      return;
    }

    // Add start time for duration tracking
    options.extra['startTime'] = DateTime.now();
    handler.next(options);
  }

  @override
  void onResponse(Response response, ResponseInterceptorHandler handler) {
    // Only cache successful GET requests
    if (response.requestOptions.method == 'GET' &&
        response.statusCode != null &&
        response.statusCode! >= 200 &&
        response.statusCode! < 300) {
      final cacheKey = _getCacheKey(response.requestOptions);
      final ttl = _getTtl(response.requestOptions);

      // Manage cache size
      if (_cache.length >= maxCacheSize) {
        _evictOldest();
      }

      _cache[cacheKey] = CacheEntry(
        data: response.data,
        timestamp: DateTime.now(),
        ttlSeconds: ttl,
      );
    }

    handler.next(response);
  }

  String _getCacheKey(RequestOptions options) {
    final queryString = options.queryParameters.entries
        .map((e) => '${e.key}=${e.value}')
        .join('&');
    return '${options.method}:${options.path}?$queryString';
  }

  int _getTtl(RequestOptions options) {
    // Check for custom TTL
    final customTtl = options.extra['cacheTtl'];
    if (customTtl is int) {
      return customTtl;
    }

    // Default TTL based on endpoint type
    final path = options.path;
    if (path.contains('/stats') || path.contains('/dashboard')) {
      return ApiConfig.cacheTtlShort;
    }
    if (path.contains('/indicators') || path.contains('/rules')) {
      return ApiConfig.cacheTtlMedium;
    }
    if (path.contains('/mitre') || path.contains('/trackers')) {
      return ApiConfig.cacheTtlLong;
    }

    return ApiConfig.cacheTtlShort;
  }

  void _evictOldest() {
    if (_cache.isEmpty) return;

    String? oldestKey;
    DateTime? oldestTime;

    for (final entry in _cache.entries) {
      if (oldestTime == null || entry.value.timestamp.isBefore(oldestTime)) {
        oldestTime = entry.value.timestamp;
        oldestKey = entry.key;
      }
    }

    if (oldestKey != null) {
      _cache.remove(oldestKey);
    }
  }

  /// Clear all cached data
  void clearCache() {
    _cache.clear();
  }

  /// Clear cache for specific endpoint
  void clearCacheFor(String path) {
    _cache.removeWhere((key, _) => key.contains(path));
  }
}

/// Cache entry with expiration
class CacheEntry {
  final dynamic data;
  final DateTime timestamp;
  final int ttlSeconds;

  CacheEntry({
    required this.data,
    required this.timestamp,
    required this.ttlSeconds,
  });

  bool get isExpired {
    return DateTime.now().difference(timestamp).inSeconds > ttlSeconds;
  }
}

/// Error response model
class ApiError {
  final int? statusCode;
  final String message;
  final String? code;
  final Map<String, dynamic>? details;

  ApiError({
    this.statusCode,
    required this.message,
    this.code,
    this.details,
  });

  factory ApiError.fromDioException(DioException e) {
    final response = e.response;

    if (response != null && response.data is Map<String, dynamic>) {
      final data = response.data as Map<String, dynamic>;
      return ApiError(
        statusCode: response.statusCode,
        message: data['message'] as String? ??
            data['error'] as String? ??
            e.message ??
            'Unknown error',
        code: data['code'] as String?,
        details: data['details'] as Map<String, dynamic>?,
      );
    }

    // Map Dio exception types to user-friendly messages
    switch (e.type) {
      case DioExceptionType.connectionTimeout:
      case DioExceptionType.sendTimeout:
      case DioExceptionType.receiveTimeout:
        return ApiError(
          statusCode: null,
          message: 'Connection timed out. Please check your internet connection.',
          code: 'TIMEOUT',
        );
      case DioExceptionType.connectionError:
        return ApiError(
          statusCode: null,
          message: 'Unable to connect to server. Please check your internet connection.',
          code: 'CONNECTION_ERROR',
        );
      case DioExceptionType.cancel:
        return ApiError(
          statusCode: null,
          message: 'Request was cancelled.',
          code: 'CANCELLED',
        );
      default:
        return ApiError(
          statusCode: response?.statusCode,
          message: e.message ?? 'An unexpected error occurred.',
          code: 'UNKNOWN',
        );
    }
  }

  @override
  String toString() => 'ApiError($statusCode): $message';
}
