// OrbVPN hand-off controller (interim, Phase 1 — see docs/VPN_PORT_PLAN.md)
//
// OrbGuard has no bundled VPN tunnel yet. Until the native OrbVPN engine is
// ported (Phases 2-3), "connect" hands off to the OrbVPN app via a deep link,
// falling back to the app store when it isn't installed. This keeps the VPN
// entry point honest today instead of presenting dead controls.

import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:url_launcher/url_launcher.dart';

import 'vpn_controller.dart';

/// OrbVPN app identifiers used for the hand-off. Both are confirmed against the
/// shipping OrbVPN apps: the `orbvpn` custom scheme is registered on iOS
/// (CFBundleURLSchemes) and Android, and the download page routes to every
/// platform's store.
class OrbVpnLinks {
  OrbVpnLinks._();

  /// Custom-scheme deep link that opens the OrbVPN app when installed.
  static const String deepLink = 'orbvpn://';

  /// Official cross-platform download page — the fallback when OrbVPN isn't
  /// installed (covers iOS, Android, and desktop stores).
  static const String downloadPage = 'https://orbvpn.com/en/download';
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

  /// Opens the OrbVPN app (deep link), falling back to the official download
  /// page when it isn't installed. Status stays [VpnStatus.unavailable] because
  /// OrbGuard itself is not the tunnel here — the OrbVPN app owns the connection.
  @override
  Future<void> connect() async {
    try {
      final deep = Uri.parse(OrbVpnLinks.deepLink);
      if (await _canLaunch(deep)) {
        await _launch(deep, mode: LaunchMode.externalApplication);
        return;
      }
    } catch (e) {
      // canLaunch/launch of the custom scheme failed — fall through to the
      // download page below.
      debugPrint('OrbVpnHandoffController: deep link unavailable: $e');
    }
    try {
      await _launch(Uri.parse(OrbVpnLinks.downloadPage),
          mode: LaunchMode.externalApplication);
    } catch (e) {
      debugPrint('OrbVpnHandoffController: download page failed: $e');
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
