// OrbGuardSystemChannel.swift — com.orb.guard/system for macOS
//
// The Dart scan pipeline (lib/services/security/device_scan_service.dart) runs
// every stage over this channel. macOS never registered it, so ALL stages
// failed, `anyStageSucceeded` stayed false, and the scan surfaced
// DeviceScanUnavailableException as an error screen — the app's primary action
// was broken.
//
// Honesty contract (inherited from MainFlutterWindow): a check macOS cannot
// perform returns an explicit UNSUPPORTED FlutterError so the pipeline reports
// it as unavailable. It is never answered with an empty list, because an empty
// list reads as "ran and found nothing" — a fabricated all-clear.
//
// Scope is dictated by the App Sandbox, which Mac App Store builds must use.
// A sandboxed app cannot enumerate other applications' files, read another
// process's memory, inspect system-wide privacy (TCC) records, or read the
// kernel's socket table. What it CAN do — and what this implements for real —
// is inspect the applications currently running.

import AppKit
import Foundation
import FlutterMacOS

enum OrbGuardSystemChannel {

  static let name = "com.orb.guard/system"

  static func register(messenger: FlutterBinaryMessenger) {
    let channel = FlutterMethodChannel(name: name, binaryMessenger: messenger)
    channel.setMethodCallHandler { call, result in
      handle(call: call, result: result)
    }
  }

  // MARK: - Dispatch

  private static func handle(call: FlutterMethodCall, result: @escaping FlutterResult) {
    switch call.method {
    case "initializeScan":
      result(true)

    case "checkRootAccess":
      // A Mac App Store build is sandboxed and can never hold elevated rights.
      result(["hasRoot": false, "method": "Sandboxed"])

    case "scanProcesses":
      result(["threats": scanRunningApplications()])

    // Everything below needs access the App Sandbox does not grant. Say so.
    case "scanNetwork":
      result(unsupported(call, "Reading this Mac's network connection table requires access the App Sandbox does not grant."))
    case "scanFileSystem":
      result(unsupported(call, "Scanning startup items and other applications' files requires access the App Sandbox does not grant."))
    case "scanDatabases":
      result(unsupported(call, "System privacy records (camera, microphone and location usage by other apps) are protected by macOS and cannot be read by a sandboxed app."))
    case "scanMemory":
      result(unsupported(call, "Inspecting another process's loaded code requires access the App Sandbox does not grant."))
    case "getInstalledCertificates":
      result(unsupported(call, "The system trust store cannot be enumerated from a sandboxed app."))
    case "getInstalledApps":
      result(unsupported(call, "Enumerating installed applications and their permissions is not available to a sandboxed app."))
    case "getEnabledAccessibilityServices":
      result(unsupported(call, "macOS does not expose which apps hold Accessibility access to other apps."))
    case "getInstalledKeyboards":
      result(unsupported(call, "macOS does not expose third-party input sources to a sandboxed app."))
    case "getLocationAccessHistory":
      result(unsupported(call, "Per-app location usage history is protected by macOS and cannot be read by a sandboxed app."))

    default:
      result(FlutterMethodNotImplemented)
    }
  }

  private static func unsupported(_ call: FlutterMethodCall, _ message: String) -> FlutterError {
    // Code "UNSUPPORTED" is what the Dart detection modules translate into
    // DetectionUnsupportedException → "not supported on this device".
    FlutterError(code: "UNSUPPORTED",
                 message: message,
                 details: ["method": call.method, "platform": "macos"])
  }

  // MARK: - Running applications (the one check the sandbox permits)

  /// Directories a standard user can write to without authentication. Software
  /// that lives here did not go through an installer with admin rights.
  private static let userWritablePrefixes: [String] = {
    let home = NSHomeDirectory()
    return [
      "\(home)/Downloads/",
      "\(home)/Desktop/",
      "\(home)/Public/",
      "/tmp/",
      "/private/tmp/",
      "/var/tmp/",
      "/Volumes/",
    ]
  }()

  private static func scanRunningApplications() -> [[String: Any]] {
    var threats: [[String: Any]] = []

    for app in NSWorkspace.shared.runningApplications {
      let bundleId = app.bundleIdentifier ?? ""
      // Apple's own processes are not findings.
      if bundleId.hasPrefix("com.apple.") { continue }
      // Never report ourselves.
      if bundleId == Bundle.main.bundleIdentifier { continue }

      let name = app.localizedName ?? bundleId
      guard !name.isEmpty || !bundleId.isEmpty else { continue }
      let path = app.bundleURL?.path ?? app.executableURL?.path ?? ""

      // 1. Running from a folder any user can write to. Legitimate Mac software
      //    installs to /Applications; running from Downloads or a mounted image
      //    is how unsigned tooling is side-loaded.
      if !path.isEmpty,
         userWritablePrefixes.contains(where: { path.hasPrefix($0) }) {
        threats.append(threat(
          id: "mac-loose-\(app.processIdentifier)",
          name: name,
          description: "This app is running from a folder that does not require an administrator to write to, rather than from your Applications folder. Check that you installed it deliberately.",
          severity: "HIGH",
          type: "process",
          path: path,
          metadata: [
            "pid": Int(app.processIdentifier),
            "bundleId": bundleId,
            "processName": name,
          ]))
        continue
      }

      // 2. A non-Apple app running with no Dock icon and no menu bar. Normal
      //    apps are .regular; monitoring tools hide as .prohibited so nothing
      //    about them appears on screen.
      if app.activationPolicy == .prohibited && !bundleId.isEmpty {
        threats.append(threat(
          id: "mac-hidden-\(app.processIdentifier)",
          name: name,
          description: "This app is running with no icon in the Dock and no menu bar, so it stays invisible while it runs. Some helper tools are legitimately like this — confirm you recognise it.",
          severity: "MEDIUM",
          type: "process",
          path: path,
          metadata: [
            "pid": Int(app.processIdentifier),
            "bundleId": bundleId,
            "processName": name,
            "hidden": true,
          ]))
      }
    }

    return threats
  }

  private static func threat(id: String,
                             name: String,
                             description: String,
                             severity: String,
                             type: String,
                             path: String,
                             metadata: [String: Any]) -> [String: Any] {
    [
      "id": id,
      "name": name,
      "description": description,
      "severity": severity,
      "type": type,
      "path": path,
      // Nothing here needs elevation — it is all read through NSWorkspace.
      "requiresRoot": false,
      "metadata": metadata,
    ]
  }
}
