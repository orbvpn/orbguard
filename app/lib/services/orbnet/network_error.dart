/// Network-error classification helpers for the OrbNet auth stack.
///
/// Used to decide whether an error represents a recoverable network problem
/// (retry, do NOT force logout) or a confirmed server-side auth rejection
/// (session is dead -> logout). Ported from OrbX and kept self-contained under
/// `lib/services/orbnet/`.
library;

import 'dart:async';
import 'dart:io';

import 'package:dio/dio.dart';

import 'orbnet_api_client.dart'
    show AuthenticationException, AuthorizationException, NetworkException;

/// True when the error represents a network-layer failure.
///
/// Covers DNS resolution failure, connection refused, connect/send/receive
/// timeouts, TLS handshake failures, broken sockets, and any Dio error that
/// never received an HTTP response. These should be retried, never treated as
/// a logout signal.
bool isNetworkError(Object? error) {
  if (error is NetworkException) return true;
  if (error is DioException) {
    switch (error.type) {
      case DioExceptionType.connectionTimeout:
      case DioExceptionType.sendTimeout:
      case DioExceptionType.receiveTimeout:
      case DioExceptionType.transformTimeout:
      case DioExceptionType.connectionError:
        return true;
      case DioExceptionType.unknown:
        // Unknown is a network error only if no response came back.
        return error.response == null;
      case DioExceptionType.badResponse:
      case DioExceptionType.cancel:
      case DioExceptionType.badCertificate:
        return false;
    }
  }
  return error is SocketException ||
      error is HttpException ||
      error is TimeoutException ||
      error is TlsException;
}

/// True when the error is a confirmed server-side auth rejection (401 or 403).
///
/// Network errors return false — the server never rendered an opinion, so we
/// cannot treat those as auth failures.
bool isAuthRejectionError(Object? error) {
  if (error is AuthenticationException) return true;
  if (error is AuthorizationException) return true;
  if (error is DioException) {
    final status = error.response?.statusCode;
    return status == 401 || status == 403;
  }
  return false;
}
