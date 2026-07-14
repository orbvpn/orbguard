// MainFlutterWindow.swift - OrbGuard macOS
// Hosts the com.orb.guard/wifi, com.orbguard/supply_chain and
// com.orb.guard/logs method channels for the macOS build.
//
// Honesty contract: capabilities macOS does not expose return explicit
// FlutterError codes (UNSUPPORTED / PERMISSION_DENIED / UNAVAILABLE) instead of
// fabricated zeros or empty "clean" results.

import Cocoa
import FlutterMacOS
import CoreWLAN
import CoreLocation
import OSLog

class MainFlutterWindow: NSWindow {

  private var wifiHandler: MacWifiChannelHandler?

  override func awakeFromNib() {
    let flutterViewController = FlutterViewController()
    let windowFrame = self.frame
    self.contentViewController = flutterViewController
    self.setFrame(windowFrame, display: true)

    RegisterGeneratedPlugins(registry: flutterViewController)

    registerOrbGuardChannels(messenger: flutterViewController.engine.binaryMessenger)

    super.awakeFromNib()
  }

  private func registerOrbGuardChannels(messenger: FlutterBinaryMessenger) {
    // WiFi channel (W5.1 macOS mirror): real CoreWLAN implementation.
    let wifiChannel = FlutterMethodChannel(
      name: "com.orb.guard/wifi",
      binaryMessenger: messenger)
    let wifiHandler = MacWifiChannelHandler()
    self.wifiHandler = wifiHandler
    wifiChannel.setMethodCallHandler { call, result in
      wifiHandler.handle(call: call, result: result)
    }

    // Supply-chain channel (W5.13 macOS mirror): not implemented on macOS —
    // the dependency scanner targets mobile app packages.
    let supplyChainChannel = FlutterMethodChannel(
      name: "com.orbguard/supply_chain",
      binaryMessenger: messenger)
    supplyChainChannel.setMethodCallHandler { call, result in
      result(FlutterError(
        code: "UNSUPPORTED",
        message: "Supply-chain scanning of other installed applications is not available on macOS.",
        details: ["method": call.method, "platform": "macos"]))
    }

    // Logs channel (W5.15 macOS mirror): own-process logs via OSLogStore (macOS 12+).
    let logsChannel = FlutterMethodChannel(
      name: "com.orb.guard/logs",
      binaryMessenger: messenger)
    logsChannel.setMethodCallHandler { call, result in
      MacLogStoreReader.handle(call: call, result: result)
    }
  }
}

// ============================================================================
// MARK: - WiFi Channel Handler (com.orb.guard/wifi) — macOS / CoreWLAN
// ============================================================================

/// Real WiFi support on macOS: current network via CWInterface and nearby
/// networks via CWInterface.scanForNetworks. macOS redacts SSID/BSSID without
/// location permission, so the handler requests it and reports
/// PERMISSION_DENIED honestly when the user declines.
final class MacWifiChannelHandler: NSObject, CLLocationManagerDelegate {

  private let locationManager = CLLocationManager()
  /// Calls queued while waiting for the user to answer the location prompt.
  private var pendingCalls: [(method: String, result: FlutterResult)] = []

  override init() {
    super.init()
    locationManager.delegate = self
  }

  func handle(call: FlutterMethodCall, result: @escaping FlutterResult) {
    switch call.method {
    case "getCurrentNetwork", "scanNetworks", "scanWifiNetworks":
      dispatch(method: call.method, result: result)
    default:
      result(FlutterMethodNotImplemented)
    }
  }

  private var authorizationStatus: CLAuthorizationStatus {
    if #available(macOS 11.0, *) {
      return locationManager.authorizationStatus
    } else {
      return CLLocationManager.authorizationStatus()
    }
  }

  private func dispatch(method: String, result: @escaping FlutterResult) {
    switch authorizationStatus {
    case .notDetermined:
      pendingCalls.append((method, result))
      locationManager.requestWhenInUseAuthorization()
      return
    case .denied, .restricted:
      result(FlutterError(
        code: "PERMISSION_DENIED",
        message: "macOS requires location permission to read WiFi network names (SSID/BSSID). Grant Location access to OrbGuard in System Settings > Privacy & Security > Location Services.",
        details: [
          "platform": "macos",
          "authorizationStatus": authorizationStatus == .denied ? "denied" : "restricted",
        ]))
      return
    default:
      break
    }

    switch method {
    case "getCurrentNetwork":
      getCurrentNetwork(result: result)
    case "scanNetworks", "scanWifiNetworks":
      scanNetworks(result: result)
    default:
      result(FlutterMethodNotImplemented)
    }
  }

  // MARK: Current network

  private func getCurrentNetwork(result: @escaping FlutterResult) {
    guard let interface = CWWiFiClient.shared().interface() else {
      result(FlutterError(
        code: "UNAVAILABLE",
        message: "No WiFi interface is present on this Mac.",
        details: ["platform": "macos"]))
      return
    }
    guard interface.powerOn() else {
      result(FlutterError(
        code: "UNAVAILABLE",
        message: "WiFi is turned off.",
        details: ["platform": "macos"]))
      return
    }
    guard let ssid = interface.ssid() else {
      // Location permission was already verified above, so a nil SSID here
      // genuinely means the interface is not associated with a network.
      result(nil)
      return
    }

    var payload: [String: Any] = [
      "ssid": ssid,
      "signal_strength": interface.rssiValue(),
      "noise": interface.noiseMeasurement(),
      "security": MacWifiChannelHandler.securityString(interface.security()),
      "is_connected": true,
    ]
    if let bssid = interface.bssid() {
      payload["bssid"] = bssid
    }
    if let channel = interface.wlanChannel() {
      payload["frequency"] = MacWifiChannelHandler.frequencyMHz(for: channel)
      payload["channel"] = channel.channelNumber
    }
    result(payload)
  }

  // MARK: Scan

  private func scanNetworks(result: @escaping FlutterResult) {
    guard let interface = CWWiFiClient.shared().interface() else {
      result(FlutterError(
        code: "UNAVAILABLE",
        message: "No WiFi interface is present on this Mac.",
        details: ["platform": "macos"]))
      return
    }
    guard interface.powerOn() else {
      result(FlutterError(
        code: "UNAVAILABLE",
        message: "WiFi is turned off; cannot scan for networks.",
        details: ["platform": "macos"]))
      return
    }

    // scanForNetworks performs a live scan and can block for a few seconds —
    // run it off the platform thread.
    DispatchQueue.global(qos: .userInitiated).async {
      do {
        let networks = try interface.scanForNetworks(withSSID: nil)
        let currentSsid = interface.ssid()

        let payload: [[String: Any]] = networks
          .sorted { $0.rssiValue > $1.rssiValue }
          .map { network in
            var entry: [String: Any] = [
              "signal_strength": network.rssiValue,
              "security": MacWifiChannelHandler.securityString(for: network),
              "is_hidden": network.ssid == nil,
              "is_connected": network.ssid != nil && network.ssid == currentSsid,
            ]
            if let ssid = network.ssid {
              entry["ssid"] = ssid
            }
            if let bssid = network.bssid {
              entry["bssid"] = bssid
            }
            if let channel = network.wlanChannel {
              entry["frequency"] = MacWifiChannelHandler.frequencyMHz(for: channel)
              entry["channel"] = channel.channelNumber
            }
            return entry
          }

        DispatchQueue.main.async { result(payload) }
      } catch {
        DispatchQueue.main.async {
          result(FlutterError(
            code: "SCAN_FAILED",
            message: "WiFi scan failed: \(error.localizedDescription)",
            details: ["platform": "macos"]))
        }
      }
    }
  }

  // MARK: Mapping helpers

  /// Center frequency in MHz from the WLAN channel (standard 802.11 formulas).
  static func frequencyMHz(for channel: CWChannel) -> Int {
    let number = channel.channelNumber
    switch channel.channelBand.rawValue {
    case 1: // 2.4 GHz
      return number == 14 ? 2484 : 2407 + 5 * number
    case 2: // 5 GHz
      return 5000 + 5 * number
    case 3: // 6 GHz
      return 5950 + 5 * number
    default:
      return 0
    }
  }

  static func securityString(_ security: CWSecurity) -> String {
    switch security.rawValue {
    case CWSecurity.none.rawValue:
      return "Open"
    case CWSecurity.WEP.rawValue, CWSecurity.dynamicWEP.rawValue:
      return "WEP"
    case CWSecurity.wpaPersonal.rawValue, CWSecurity.wpaPersonalMixed.rawValue:
      return "WPA"
    case CWSecurity.wpa2Personal.rawValue, CWSecurity.personal.rawValue:
      return "WPA2"
    case CWSecurity.wpaEnterprise.rawValue,
         CWSecurity.wpaEnterpriseMixed.rawValue,
         CWSecurity.wpa2Enterprise.rawValue,
         CWSecurity.enterprise.rawValue:
      return "WPA2-Enterprise"
    case CWSecurity.wpa3Personal.rawValue, CWSecurity.wpa3Transition.rawValue:
      return "WPA3"
    case CWSecurity.wpa3Enterprise.rawValue:
      return "WPA3-Enterprise"
    default:
      return "Unknown"
    }
  }

  static func securityString(for network: CWNetwork) -> String {
    if network.supportsSecurity(.wpa3Personal) || network.supportsSecurity(.wpa3Transition) {
      return "WPA3"
    }
    if network.supportsSecurity(.wpa3Enterprise) {
      return "WPA3-Enterprise"
    }
    if network.supportsSecurity(.wpa2Enterprise)
      || network.supportsSecurity(.enterprise)
      || network.supportsSecurity(.wpaEnterprise)
      || network.supportsSecurity(.wpaEnterpriseMixed) {
      return "WPA2-Enterprise"
    }
    if network.supportsSecurity(.wpa2Personal) || network.supportsSecurity(.personal) {
      return "WPA2"
    }
    if network.supportsSecurity(.wpaPersonal) || network.supportsSecurity(.wpaPersonalMixed) {
      return "WPA"
    }
    if network.supportsSecurity(.WEP) || network.supportsSecurity(.dynamicWEP) {
      return "WEP"
    }
    if network.supportsSecurity(.none) {
      return "Open"
    }
    return "Unknown"
  }

  // MARK: CLLocationManagerDelegate

  @available(macOS 11.0, *)
  func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
    resolvePendingCalls()
  }

  // macOS 10.15 fallback delegate callback.
  func locationManager(
    _ manager: CLLocationManager,
    didChangeAuthorization status: CLAuthorizationStatus
  ) {
    resolvePendingCalls()
  }

  private func resolvePendingCalls() {
    guard !pendingCalls.isEmpty else { return }
    // Still waiting for the user's answer — keep the calls queued.
    guard authorizationStatus != .notDetermined else { return }
    let pending = pendingCalls
    pendingCalls.removeAll()
    for queued in pending {
      dispatch(method: queued.method, result: queued.result)
    }
  }
}

// ============================================================================
// MARK: - OSLogStore Reader (com.orb.guard/logs) — macOS 12+
// ============================================================================

/// Retrieves this app's own recent unified-system-log entries via OSLogStore.
/// Older systems report UNSUPPORTED.
enum MacLogStoreReader {

  static func handle(call: FlutterMethodCall, result: @escaping FlutterResult) {
    switch call.method {
    case "getRecentLogs":
      let args = call.arguments as? [String: Any]
      let minutes = args?["minutes"] as? Int ?? 15
      let limit = args?["limit"] as? Int ?? 500
      getRecentLogs(minutes: minutes, limit: limit, result: result)
    default:
      result(FlutterMethodNotImplemented)
    }
  }

  private static func getRecentLogs(minutes: Int, limit: Int, result: @escaping FlutterResult) {
    guard #available(macOS 12.0, *) else {
      result(FlutterError(
        code: "UNSUPPORTED",
        message: "Reading the app's own log entries requires macOS 12 or later (OSLogStore).",
        details: ["platform": "macos"]))
      return
    }

    DispatchQueue.global(qos: .userInitiated).async {
      do {
        let store = try OSLogStore(scope: .currentProcessIdentifier)
        let since = Date().addingTimeInterval(-Double(max(minutes, 1)) * 60.0)
        let position = store.position(date: since)
        let entries = try store.getEntries(at: position)

        var logs: [[String: Any]] = []
        for entry in entries {
          guard let logEntry = entry as? OSLogEntryLog else { continue }
          logs.append([
            "timestamp": logEntry.date.timeIntervalSince1970,
            "level": levelString(logEntry.level),
            "subsystem": logEntry.subsystem,
            "category": logEntry.category,
            "message": logEntry.composedMessage,
          ])
          if logs.count >= limit { break }
        }
        DispatchQueue.main.async {
          result([
            "logs": logs,
            "source": "OSLogStore.currentProcessIdentifier",
            "sinceMinutes": minutes,
            "truncated": logs.count >= limit,
          ])
        }
      } catch {
        DispatchQueue.main.async {
          result(FlutterError(
            code: "UNAVAILABLE",
            message: "Failed to read OSLogStore: \(error.localizedDescription)",
            details: nil))
        }
      }
    }
  }

  @available(macOS 12.0, *)
  private static func levelString(_ level: OSLogEntryLog.Level) -> String {
    switch level {
    case .undefined: return "undefined"
    case .debug: return "debug"
    case .info: return "info"
    case .notice: return "notice"
    case .error: return "error"
    case .fault: return "fault"
    @unknown default: return "unknown"
    }
  }
}
