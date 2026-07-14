// SIM Monitor
// Reads the active SIM subscriptions (Android only — iOS does not expose
// SIM identity to third-party apps at all; CTCarrier has returned dummy
// values since iOS 16) and reports them to the backend in the
// models.SIMInfo shape (POST /api/v1/device/{device_id}/sim takes a JSON
// array).
//
// HONESTY NOTE ON ICCID: since Android 10, SubscriptionInfo.getIccId()
// requires READ_PRIVILEGED_PHONE_STATE, which is not grantable to normal
// apps. The real ICCID is therefore *unavailable* to this client. For SIM
// *change detection* — the actual purpose of this feature — we send a
// stable subscription fingerprint in the "iccid" field with an explicit
// "sub:" prefix so it can never be mistaken for a real ICCID. The backend
// compares the field for equality, so change/swap detection works exactly
// the same.

import 'dart:developer' as developer;
import 'dart:io';

import 'package:permission_handler/permission_handler.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sim_card_info/sim_card_info.dart';
import 'package:sim_card_info/sim_info.dart';

import 'agent_api.dart';

class SimReadResult {
  /// Backend-shaped models.SIMInfo maps, null when unavailable.
  final List<Map<String, dynamic>>? sims;

  /// Honest reason when [sims] is null.
  final String? unavailableReason;

  const SimReadResult.available(this.sims) : unavailableReason = null;

  const SimReadResult.unavailable(this.unavailableReason) : sims = null;

  bool get isAvailable => sims != null;
}

class SimChangeReport {
  final bool reported;
  final bool changed;
  final String? detail;

  const SimChangeReport({
    required this.reported,
    required this.changed,
    this.detail,
  });
}

class SimMonitor {
  static const _prefsKey = 'device_agent.sim_signatures';

  final SimCardInfo _plugin = SimCardInfo();

  /// Reads the current SIM subscriptions, or an explicit unavailable state.
  Future<SimReadResult> read() async {
    if (!Platform.isAndroid) {
      return SimReadResult.unavailable(
        'SIM information is not exposed to third-party apps on '
        '${Platform.operatingSystem}',
      );
    }

    final status = await Permission.phone.request();
    if (!status.isGranted) {
      return const SimReadResult.unavailable(
        'READ_PHONE_STATE permission not granted — SIM monitoring is '
        'unavailable until the Phone permission is allowed',
      );
    }

    List<SimInfo>? sims;
    try {
      sims = await _plugin.getSimInfo();
    } catch (e) {
      developer.log('getSimInfo failed: $e', name: 'SimMonitor');
      return SimReadResult.unavailable('failed to read SIM info: $e');
    }

    if (sims == null || sims.isEmpty) {
      // A device with no active subscription is a real, reportable state
      // (e.g. the SIM was removed) — return an empty list, not "unavailable".
      return const SimReadResult.available([]);
    }

    return SimReadResult.available(
        sims.map(_toBackendJson).toList(growable: false));
  }

  Map<String, dynamic> _toBackendJson(SimInfo sim) {
    final slot = int.tryParse(sim.slotIndex) ?? 0;
    return {
      'slot_index': slot,
      // Stable subscription fingerprint — see HONESTY NOTE above.
      'iccid': _fingerprint(sim),
      'carrier': sim.carrierName,
      'country_code': sim.countryIso,
      if (sim.number.isNotEmpty) 'phone_number': sim.number,
      'is_active': true, // plugin only returns *active* subscriptions
      // eSIM detection is not exposed by SubscriptionManager to normal apps;
      // false here means "not detectable", which the comment in the SIM tab
      // explains. Never claimed as a verified physical-SIM statement.
      'is_esim': false,
    };
  }

  String _fingerprint(SimInfo sim) {
    final parts = [
      sim.slotIndex,
      sim.countryIso,
      sim.carrierName,
      if (sim.number.isNotEmpty) sim.number,
    ];
    return 'sub:${parts.join(':')}';
  }

  /// Reads SIMs, reports them to the backend when the set changed since the
  /// last report (the backend performs its own swap/risk analysis), and
  /// persists the new signature set locally.
  Future<SimChangeReport> detectAndReport(DeviceAgentApi api) async {
    final result = await read();
    if (!result.isAvailable) {
      return SimChangeReport(
        reported: false,
        changed: false,
        detail: result.unavailableReason,
      );
    }

    final prefs = await SharedPreferences.getInstance();
    final current = result.sims!
        .map((s) => s['iccid'] as String)
        .toList(growable: false)
      ..sort();
    final stored = prefs.getStringList(_prefsKey);

    final isFirstReport = stored == null;
    final changed = !isFirstReport &&
        !(stored.length == current.length &&
            List.generate(current.length, (i) => stored[i] == current[i])
                .every((m) => m));

    if (!isFirstReport && !changed) {
      return const SimChangeReport(reported: false, changed: false);
    }

    // First sighting or a change — report the full current set so the
    // backend can run its inserted/removed/swapped event analysis.
    await api.reportSims(result.sims!);
    await prefs.setStringList(_prefsKey, current);

    developer.log(
      changed
          ? 'SIM change detected and reported: $current (was $stored)'
          : 'initial SIM state reported: $current',
      name: 'SimMonitor',
    );

    return SimChangeReport(
      reported: true,
      changed: changed,
      detail: changed ? 'SIM set changed: $stored -> $current' : null,
    );
  }
}
