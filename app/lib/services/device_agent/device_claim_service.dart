// lib/services/device_agent/device_claim_service.dart
//
// Ownership bootstrap: links THIS device to the signed-in OrbNet account so the
// user can control it from the web panel. OrbGuard's backend records the owner
// from a verified OrbNet JWT the first time a device is claimed
// (POST /device/{id}/claim); afterwards only that account may command it.
//
// This runs best-effort and idempotently — after login and at agent start —
// whenever both an OrbNet token and a registered device id are present. It uses
// the OrbNet JWT (not the device api-key) as the bearer, because the backend
// identifies the OWNER from that token.

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../api/api_config.dart';
import 'device_agent.dart' show kRegisteredDeviceIdPrefsKey;

class DeviceClaimService {
  DeviceClaimService._();
  static final DeviceClaimService instance = DeviceClaimService._();

  static const _tokenKey = 'auth_token'; // OrbNet access token (AuthRepository)
  final FlutterSecureStorage _storage = const FlutterSecureStorage();

  /// Claim this device for the signed-in OrbNet account. No-op (returns false)
  /// when the user isn't signed in or the device isn't registered yet — a later
  /// call (next login / agent start) will pick it up. Never throws.
  Future<bool> claimIfReady() async {
    try {
      final token = await _storage.read(key: _tokenKey);
      if (token == null || token.isEmpty) return false; // not signed in

      final prefs = await SharedPreferences.getInstance();
      final deviceId = prefs.getString(kRegisteredDeviceIdPrefsKey);
      if (deviceId == null || deviceId.isEmpty) return false; // not registered

      final dio = Dio(BaseOptions(
        baseUrl: ApiConfig.baseUrl,
        connectTimeout: const Duration(seconds: 12),
        receiveTimeout: const Duration(seconds: 12),
      ));
      final resp = await dio.post(
        '${ApiConfig.apiVersion}/device/$deviceId/claim',
        options: Options(
          headers: {'Authorization': 'Bearer $token'},
          validateStatus: (_) => true,
        ),
      );

      final code = resp.statusCode ?? 0;
      if (code == 200) {
        debugPrint('[OrbGuard] device claimed for OrbNet account');
        return true;
      }
      if (code == 409) {
        // Owned by a different account — honest, not silently swallowed.
        debugPrint('[OrbGuard] device already linked to another account');
        return false;
      }
      debugPrint('[OrbGuard] device claim skipped (HTTP $code)');
      return false;
    } catch (e) {
      // Best-effort — a failed claim must never block login or the agent.
      debugPrint('[OrbGuard] device claim error: $e');
      return false;
    }
  }
}
