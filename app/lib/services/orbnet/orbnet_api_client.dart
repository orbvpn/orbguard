// lib/services/orbnet/orbnet_api_client.dart
//
// REST client for the OrbNet backend (api.orbai.world) — the shared
// OrbVPN/OrbNet account backend. Ported from OrbX's RestApiClient and
// SIMPLIFIED: the OrbVPN FailoverService / region-domain logic is dropped in
// favour of the single fixed base URL below. Kept: Dio singleton, bearer
// injection on non-public endpoints, 401 auto-refresh + one retry, and the
// "only log out on a POSITIVE 401/403 auth rejection" rule.
//
// This is a DIFFERENT backend from OrbGuard's own `guard.orbai.world` client
// (`OrbGuardApiClient`), which continues to handle anonymous device/scan ops.

import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// The single OrbNet API base URL (Go REST, versioned under /api/v1).
const String kOrbNetBaseUrl = 'https://api.orbai.world/api/v1';

/// Callback that performs a token refresh. Returns true on success.
typedef TokenRefreshCallback = Future<bool> Function();

/// Returns the freshest access token from the repository's in-memory cache
/// (updated synchronously on refresh, before the slower secure-storage write).
typedef CachedTokenGetter = String? Function();

/// Callback that forces a logout when the session is confirmed dead.
typedef SessionExpiredCallback = Future<void> Function();

/// Returns true ONLY when the most recent refresh failed because the server
/// positively rejected the refresh token (401/403).
typedef RefreshAuthRejectionProbe = bool Function();

/// REST client for OrbNet auth + account endpoints.
class OrbNetApiClient {
  static final OrbNetApiClient _instance = OrbNetApiClient._internal();
  static OrbNetApiClient get instance => _instance;

  late Dio _dio;
  bool _dioBuilt = false;
  final FlutterSecureStorage _storage = const FlutterSecureStorage();

  TokenRefreshCallback? _onTokenRefresh;
  CachedTokenGetter? _onGetCachedToken;
  SessionExpiredCallback? _onSessionExpired;
  RefreshAuthRejectionProbe? _onRefreshAuthRejectionProbe;

  bool _isInitialized = false;

  OrbNetApiClient._internal();

  /// Register the refresh callback (called by AuthRepository).
  void setTokenRefreshCallback(TokenRefreshCallback callback) =>
      _onTokenRefresh = callback;

  /// Register the synchronous cached-token getter (called by AuthRepository).
  void setCachedTokenGetter(CachedTokenGetter getter) =>
      _onGetCachedToken = getter;

  /// Register the session-expired (logout) callback.
  void setSessionExpiredCallback(SessionExpiredCallback callback) =>
      _onSessionExpired = callback;

  /// Register the probe that distinguishes a server auth rejection from a
  /// network/transient refresh failure (called by AuthRepository).
  void setRefreshAuthRejectionProbe(RefreshAuthRejectionProbe probe) =>
      _onRefreshAuthRejectionProbe = probe;

  /// Build the Dio client. Idempotent.
  Future<void> initialize() async {
    if (_isInitialized) return;
    _buildClient();
    _isInitialized = true;
  }

  /// Ensure the client is built before a request.
  Future<void> ensureInitialized() async {
    if (!_isInitialized) await initialize();
  }

  void _buildClient() {
    _dio = Dio(BaseOptions(
      baseUrl: kOrbNetBaseUrl,
      connectTimeout: const Duration(seconds: 30),
      receiveTimeout: const Duration(seconds: 60),
      sendTimeout: const Duration(seconds: 30),
      headers: {
        'Content-Type': 'application/json',
        'Accept': 'application/json',
        'User-Agent': 'OrbGuard-Mobile-App',
      },
    ));

    _dio.interceptors.add(InterceptorsWrapper(
      onRequest: (options, handler) async {
        final isPublicEndpoint = _isPublicEndpoint(options.path) ||
            options.extra['skipAuth'] == true;

        if (!isPublicEndpoint) {
          final token = await _storage.read(key: 'auth_token');
          if (token != null && token.isNotEmpty) {
            options.headers['Authorization'] = 'Bearer $token';
          }
        }
        return handler.next(options);
      },
      onError: (error, handler) async {
        // 401 on a non-auth endpoint -> try a refresh + one retry.
        if (error.response?.statusCode == 401) {
          final isAuthEndpoint =
              error.requestOptions.path.contains('/auth/');

          if (!isAuthEndpoint) {
            final success = await _attemptTokenRefresh();

            if (success) {
              try {
                // Prefer the in-memory cached token (updated synchronously by
                // refresh) over re-reading storage, which may lag.
                final token = _onGetCachedToken?.call() ??
                    await _storage.read(key: 'auth_token');
                error.requestOptions.headers['Authorization'] = 'Bearer $token';
                final response = await _dio.fetch(error.requestOptions);
                return handler.resolve(response);
              } catch (e) {
                // Only force logout when the RETRY itself is a 401 — i.e. the
                // freshly-refreshed token is also unauthorized (session truly
                // revoked). Network errors / other statuses must NOT log out.
                final retryStatus =
                    e is DioException ? e.response?.statusCode : null;
                if (retryStatus == 401) {
                  await _handleSessionExpired();
                } else if (e is DioException) {
                  return handler.reject(e);
                }
              }
            } else {
              // Refresh failed. Decide logout vs. keep-session by the REASON:
              // ONLY a positive 401/403 auth rejection justifies a logout.
              final wasAuthRejection =
                  _onRefreshAuthRejectionProbe?.call() ?? false;
              if (wasAuthRejection) {
                await _handleSessionExpired();
              } else {
                // Convert into a network error so callers see "network", not
                // "auth expired". Reachability is the real problem.
                return handler.reject(
                  DioException(
                    requestOptions: error.requestOptions,
                    type: DioExceptionType.connectionError,
                    error: 'Network unreachable during token refresh',
                  ),
                );
              }
            }
          }
        }
        return handler.next(error);
      },
    ));

    _dioBuilt = true;
  }

  /// Endpoints that never carry a bearer token.
  bool _isPublicEndpoint(String path) {
    const publicPaths = [
      '/auth/login',
      '/auth/register',
      '/auth/refresh',
      '/auth/forgot-password',
      '/auth/reset-password',
      '/auth/magic-link',
      '/auth/oauth',
      '/health',
    ];
    return publicPaths.any((p) => path.startsWith(p));
  }

  Future<bool> _attemptTokenRefresh() async {
    if (_onTokenRefresh == null) return false;
    try {
      return await _onTokenRefresh!();
    } catch (e) {
      _log('Token refresh error: $e');
      return false;
    }
  }

  Future<void> _handleSessionExpired() async {
    if (_onSessionExpired != null) {
      await _onSessionExpired!();
    }
  }

  // ---- HTTP methods --------------------------------------------------------

  /// Tolerate empty/204 bodies: `data as T` would crash on null/empty.
  T _castBody<T>(dynamic data) {
    if (data == null || (data is String && data.isEmpty)) {
      return null as T;
    }
    return data as T;
  }

  Future<T> get<T>(
    String path, {
    Map<String, dynamic>? queryParameters,
    Options? options,
    bool skipAuth = false,
  }) async {
    await ensureInitialized();
    try {
      final response = await _dio.get<T>(
        path,
        queryParameters: queryParameters,
        options: _mergeOptions(options, skipAuth),
      );
      return _castBody<T>(response.data);
    } on DioException catch (e) {
      throw _handleDioError(e);
    }
  }

  Future<T> post<T>(
    String path, {
    dynamic data,
    Map<String, dynamic>? queryParameters,
    Options? options,
    bool skipAuth = false,
  }) async {
    await ensureInitialized();
    try {
      final response = await _dio.post<T>(
        path,
        data: data,
        queryParameters: queryParameters,
        options: _mergeOptions(options, skipAuth),
      );
      return _castBody<T>(response.data);
    } on DioException catch (e) {
      throw _handleDioError(e);
    }
  }

  Future<T> put<T>(
    String path, {
    dynamic data,
    Map<String, dynamic>? queryParameters,
    Options? options,
    bool skipAuth = false,
  }) async {
    await ensureInitialized();
    try {
      final response = await _dio.put<T>(
        path,
        data: data,
        queryParameters: queryParameters,
        options: _mergeOptions(options, skipAuth),
      );
      return _castBody<T>(response.data);
    } on DioException catch (e) {
      throw _handleDioError(e);
    }
  }

  Options? _mergeOptions(Options? options, bool skipAuth) {
    if (!skipAuth) return options;
    return (options ?? Options()).copyWith(extra: {'skipAuth': true});
  }

  /// Convert a DioException into a meaningful, typed exception.
  Exception _handleDioError(DioException error) {
    switch (error.type) {
      case DioExceptionType.connectionTimeout:
      case DioExceptionType.sendTimeout:
      case DioExceptionType.receiveTimeout:
      case DioExceptionType.transformTimeout:
        return NetworkException('Connection timeout. Please check your network.');
      case DioExceptionType.connectionError:
        return NetworkException('Connection error. Please check your network.');
      case DioExceptionType.badResponse:
        final statusCode = error.response?.statusCode;
        final data = error.response?.data;
        String message = 'Request failed';
        if (data is Map<String, dynamic>) {
          message = (data['detail'] ??
              data['message'] ??
              data['title'] ??
              data['error'] ??
              message) as String;
        }
        if (statusCode == 401) {
          return AuthenticationException(message);
        } else if (statusCode == 403) {
          return AuthorizationException(message);
        } else if (statusCode == 402) {
          return PaymentRequiredException(message);
        } else if (statusCode == 404) {
          return NotFoundException(message);
        } else if (statusCode == 422) {
          return ValidationException(message);
        } else if (statusCode != null && statusCode >= 500) {
          return ServerException(message);
        }
        return ApiException(message);
      case DioExceptionType.cancel:
        return ApiException('Request cancelled');
      case DioExceptionType.badCertificate:
        return NetworkException('Certificate error.');
      case DioExceptionType.unknown:
        if (error.response == null) {
          return NetworkException('Network error. Please check your connection.');
        }
        return ApiException('An unexpected error occurred');
    }
  }

  void _log(String message) {
    if (kDebugMode) debugPrint('[OrbNetApiClient] $message');
  }

  // ---- Testing seams -------------------------------------------------------

  /// Override the underlying HTTP adapter (e.g. a fake in unit tests).
  /// Call after [initialize] so the Dio client exists.
  @visibleForTesting
  set httpClientAdapter(HttpClientAdapter adapter) {
    _dio.httpClientAdapter = adapter;
  }

  /// Reset registered callbacks + init flag between tests.
  @visibleForTesting
  void debugReset() {
    _onTokenRefresh = null;
    _onGetCachedToken = null;
    _onSessionExpired = null;
    _onRefreshAuthRejectionProbe = null;
    if (_dioBuilt) {
      try {
        _dio.close(force: true);
      } catch (_) {}
    }
    _dioBuilt = false;
    _isInitialized = false;
  }
}

// ===========================================================================
// Exception classes
// ===========================================================================

/// Base API exception.
class ApiException implements Exception {
  final String message;
  ApiException(this.message);
  @override
  String toString() => message;
}

/// Authentication exception (401).
class AuthenticationException extends ApiException {
  AuthenticationException(super.message);
}

/// Authorization exception (403).
class AuthorizationException extends ApiException {
  AuthorizationException(super.message);
}

/// Payment/quota required (402). The server positively refused an operation the
/// account can't currently afford — used by scan-credit consumption to signal an
/// empty balance ("out of credits, watch an ad").
class PaymentRequiredException extends ApiException {
  PaymentRequiredException(super.message);
}

/// Not found exception (404).
class NotFoundException extends ApiException {
  NotFoundException(super.message);
}

/// Validation exception (422).
class ValidationException extends ApiException {
  ValidationException(super.message);
}

/// Server exception (5xx).
class ServerException extends ApiException {
  ServerException(super.message);
}

/// Network-layer exception (timeout, connection refused, DNS, TLS). No HTTP
/// response was received, so the server never rendered an opinion.
class NetworkException extends ApiException {
  NetworkException(super.message);
}
