// OrbVPN hand-off controller (interim, Phase 1 — see docs/VPN_PORT_PLAN.md)
//
// OrbGuard has no bundled VPN tunnel yet. Until the native OrbVPN engine is
// ported (Phases 2-3), "connect" hands off to the OrbVPN app via a deep link,
// falling back to the app store when it isn't installed. This keeps the VPN
// entry point honest today instead of presenting dead controls.

import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:url_launcher/url_launcher.dart';

import 'vpn_controller.dart';

/// OrbVPN app identifiers used for the hand-off.
///
/// TODO(vpn): confirm these against the shipping OrbVPN apps before relying on
/// the deep link in production. The Android package is known
/// (`com.orbvpn.android`); the iOS App Store id and the deep-link scheme should
/// be verified with the OrbVPN team.
class OrbVpnLinks {
  OrbVpnLinks._();

  /// Custom-scheme deep link that opens the OrbVPN app (and, ideally, starts a
  /// connection). Confirm the exact scheme/host with the OrbVPN app.
  static const String deepLink = 'orbvpn://connect';

  static const String androidPackage = 'com.orbvpn.android';

  static const String androidStore =
      'https://play.google.com/store/apps/details?id=$androidPackage';

  /// iOS App Store page. TODO(vpn): replace with the real numeric app id.
  static const String iosStore = 'https://apps.apple.com/app/orbvpn/id0000000000';
}

/// Interim [VpnController] that defers the actual tunnel to the OrbVPN app.
class OrbVpnHandoffController implements VpnController {
  OrbVpnHandoffController({
    Future<bool> Function(Uri, {LaunchMode mode})? launcher,
    Future<bool> Function(Uri)? canLaunch,
  })  : _launch = launcher ?? launchUrl,
        _canLaunch = canLaunch ?? canLaunchUrl;

  final Future<bool> Function(Uri, {LaunchMode mode}) _launch;
  final Future<bool> Function(Uri) _canLaunch;

  final _statusController = StreamController<VpnStatus>.broadcast();
  VpnStatus _status = VpnStatus.unavailable;

  @override
  VpnStatus get status => _status;

  @override
  Stream<VpnStatus> get statusStream => _statusController.stream;

  void _setStatus(VpnStatus s) {
    _status = s;
    if (!_statusController.isClosed) _statusController.add(s);
  }

  /// Opens the OrbVPN app (deep link), falling back to the platform store.
  /// Status stays [VpnStatus.unavailable] because OrbGuard itself is not the
  /// tunnel here — the OrbVPN app owns the connection.
  @override
  Future<void> connect() async {
    try {
      final deep = Uri.parse(OrbVpnLinks.deepLink);
      if (await _canLaunch(deep)) {
        await _launch(deep, mode: LaunchMode.externalApplication);
        return;
      }
      final store = Uri.parse(
          Platform.isIOS ? OrbVpnLinks.iosStore : OrbVpnLinks.androidStore);
      await _launch(store, mode: LaunchMode.externalApplication);
    } catch (e) {
      debugPrint('OrbVpnHandoffController: hand-off failed: $e');
      _setStatus(VpnStatus.error);
    }
  }

  /// Nothing to tear down — the OrbVPN app manages its own tunnel.
  @override
  Future<void> disconnect() async {}

  @override
  void dispose() {
    _statusController.close();
  }
}
