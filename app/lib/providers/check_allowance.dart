/// The free tier's one free check, and the device the paywall is drawn for.
///
/// The first check on a device costs nothing, whatever kind it is: the full
/// check on Home, a pasted link, a QR code, a Wi-Fi check. Every check a
/// person starts after that goes through the scan-credit gate
/// (`ensureScanCredit`). This object remembers whether the free one is gone.
///
/// It is kept on the device, not on the account: signing in or out must not
/// hand out another. A check Home has on record counts as the free one too
/// (the gate reads that from `LastScanVerdictController`), so a device that
/// already checked before this existed gets no second free check.
///
/// [platform] is the device the gate speaks to. It is given, never read from
/// the machine here, so a test can ask for the phone, Mac or Windows paywall
/// on any build server.
library;

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

class CheckAllowance extends ChangeNotifier {
  CheckAllowance({
    required this.platform,
    Future<SharedPreferences> Function()? prefs,
  }) : _prefs = prefs ?? SharedPreferences.getInstance;

  /// The device the paywall is drawn for. Null is a browser.
  final TargetPlatform? platform;

  final Future<SharedPreferences> Function() _prefs;

  static const String prefsKey = 'free_check_used';

  bool _used = false;
  Future<void>? _loading;

  /// Whether this device has had its free check.
  Future<bool> freeCheckUsed() async {
    await (_loading ??= _load());
    return _used;
  }

  /// Marks the free check as taken. Call it as the check is let through.
  Future<void> useFreeCheck() async {
    await (_loading ??= _load());
    if (_used) return;
    _used = true;
    notifyListeners();
    try {
      await (await _prefs()).setBool(prefsKey, true);
    } on Object catch (e) {
      // Still used for as long as the app runs. Never a reason to give
      // another.
      debugPrint('CheckAllowance: could not save: $e');
    }
  }

  Future<void> _load() async {
    try {
      _used = (await _prefs()).getBool(prefsKey) ?? false;
    } on Object catch (e) {
      debugPrint('CheckAllowance: could not read: $e');
    }
  }
}
