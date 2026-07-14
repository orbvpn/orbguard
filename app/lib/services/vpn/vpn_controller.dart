// VPN Controller abstraction
//
// OrbGuard depends on this interface, not on any concrete VPN engine, so the
// multi-phase port of OrbVPN's SmartConnect tunnel stack (see
// docs/VPN_PORT_PLAN.md) can land behind a stable API. Phase 1 ships the
// interim [OrbVpnHandoffController]; Phases 2-3 add AndroidVpnController /
// IosVpnController backed by the real native tunnel.

import 'dart:async';

/// Connection state exposed to the UI.
enum VpnStatus {
  /// Not connected and idle.
  disconnected,

  /// A connect attempt is in progress.
  connecting,

  /// Tunnel is up.
  connected,

  /// Last attempt failed.
  error,

  /// No VPN engine is available on this build/platform (e.g. before the native
  /// tunnel is ported); use the hand-off controller instead.
  unavailable,
}

/// Abstraction over the VPN engine.
abstract class VpnController {
  /// Current status.
  VpnStatus get status;

  /// Stream of status transitions.
  Stream<VpnStatus> get statusStream;

  /// Begin a connection (or hand off to the OrbVPN app in the interim impl).
  Future<void> connect();

  /// Tear down the connection.
  Future<void> disconnect();

  /// Release resources.
  void dispose();
}
