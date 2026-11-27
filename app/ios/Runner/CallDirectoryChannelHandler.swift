// CallDirectoryChannelHandler.swift - OrbGuard iOS
// Hosts the com.orb.guard/call_directory method channel.
//
// Purpose: bridge the Dart-side call block list (numbers the person chose to
// block) into the shared App Group container (group.com.orb.guard.shared, via
// CallDirectoryStore) that the OrbGuardCallDirectory CXCallDirectoryProvider
// extension reads, and ask iOS to reload that extension so the new data takes
// effect.
//
// Honesty contract: this channel performs DATA SYNC + a reload request only. It
// never claims that calls are being blocked. Whether the call directory is live
// is governed entirely by the person turning OrbGuard on in Settings, Apps,
// Phone, Call Blocking & Identification (iOS 26 wording; `openSettings` opens
// that page). The `status` method reports the real enablement state via
// CXCallDirectoryManager and states plainly that the person must turn it on.

import CallKit
import Flutter
import Foundation
import os.log

final class CallDirectoryChannelHandler {

    static let channelName = "com.orb.guard/call_directory"
    // Must match the OrbGuardCallDirectory app-extension bundle identifier.
    static let extensionIdentifier = "com.orb.guard.OrbGuardCallDirectory"

    private let logger = Logger(subsystem: "com.orb.guard", category: "CallDirectory")
    private let store = CallDirectoryStore()

    func register(with messenger: FlutterBinaryMessenger) {
        let channel = FlutterMethodChannel(name: Self.channelName, binaryMessenger: messenger)
        channel.setMethodCallHandler { [weak self] call, result in
            self?.handle(call: call, result: result)
        }
    }

    private func handle(call: FlutterMethodCall, result: @escaping FlutterResult) {
        switch call.method {
        case "syncNumbers":
            syncNumbers(call: call, result: result)
        case "reload":
            reload(result: result)
        case "status":
            reportStatus(result: result)
        case "list":
            result(["blocked": store.loadBlockedNumbers()])
        case "block":
            editBlocked(call: call, result: result, adding: true)
        case "unblock":
            editBlocked(call: call, result: result, adding: false)
        case "openSettings":
            openSettings(result: result)
        default:
            result(FlutterMethodNotImplemented)
        }
    }

    // MARK: - Sync

    /// Writes the supplied block/identify lists into the shared container and
    /// asks iOS to reload the extension. Numbers may arrive as Int or String
    /// (E.164 digits); non-numeric junk is dropped rather than guessed at.
    private func syncNumbers(call: FlutterMethodCall, result: @escaping FlutterResult) {
        guard store.isContainerAvailable else {
            result(FlutterError(
                code: "APP_GROUP_UNAVAILABLE",
                message: "The App Group container (group.com.orb.guard.shared) is not provisioned for this build; the call-directory lists cannot be written. This requires the App Groups capability in the signing profile.",
                details: ["platform": "ios"]))
            return
        }

        let args = call.arguments as? [String: Any]
        let blocked = ((args?["blocked"] as? [Any]) ?? []).compactMap(Self.parseNumber)
        let identified = ((args?["identified"] as? [[String: Any]]) ?? []).compactMap {
            dict -> CallDirectoryStore.IdentificationEntry? in
            guard let number = Self.parseNumber(dict["number"]),
                  let label = (dict["label"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines),
                  !label.isEmpty else { return nil }
            return CallDirectoryStore.IdentificationEntry(number: number, label: label)
        }

        guard store.save(blocked: blocked, identified: identified) else {
            result(FlutterError(
                code: "WRITE_FAILED",
                message: "Failed to write the call-directory lists to the shared App Group container.",
                details: ["platform": "ios"]))
            return
        }

        let counts = store.counts()
        logger.info("Synced call directory: \(counts.blocked) blocked, \(counts.identified) identified")

        // Ask iOS to reload the extension so the new data is picked up.
        CXCallDirectoryManager.sharedInstance.reloadExtension(withIdentifier: Self.extensionIdentifier) { error in
            DispatchQueue.main.async {
                result([
                    "blockedWritten": counts.blocked,
                    "identifiedWritten": counts.identified,
                    "reloadRequested": error == nil,
                    "reloadError": error?.localizedDescription as Any,
                ])
            }
        }
    }

    // MARK: - Block list edits

    /// Adds or removes one number in the stored block list, keeps any
    /// identification entries as they are, and asks iOS to reload the
    /// extension. Returns the new list plus the reload outcome.
    private func editBlocked(call: FlutterMethodCall, result: @escaping FlutterResult, adding: Bool) {
        guard store.isContainerAvailable else {
            result(FlutterError(
                code: "APP_GROUP_UNAVAILABLE",
                message: "The App Group container (group.com.orb.guard.shared) is not provisioned for this build; the block list cannot be written.",
                details: ["platform": "ios"]))
            return
        }
        guard let number = Self.parseNumber((call.arguments as? [String: Any])?["number"]) else {
            result(FlutterError(code: "BAD_NUMBER", message: "Expected a phone number with its country code.", details: nil))
            return
        }

        var blocked = store.loadBlockedNumbers()
        if adding {
            blocked.append(number)
        } else {
            blocked.removeAll { $0 == number }
        }
        guard store.save(blocked: blocked, identified: store.loadIdentificationEntries()) else {
            result(FlutterError(
                code: "WRITE_FAILED",
                message: "Failed to write the block list to the shared App Group container.",
                details: ["platform": "ios"]))
            return
        }

        let saved = store.loadBlockedNumbers()
        CXCallDirectoryManager.sharedInstance.reloadExtension(withIdentifier: Self.extensionIdentifier) { error in
            DispatchQueue.main.async {
                result([
                    "blocked": saved,
                    "reloadRequested": error == nil,
                    "reloadError": error?.localizedDescription as Any,
                ])
            }
        }
    }

    // MARK: - Settings

    /// Opens Settings at Call Blocking & Identification, where the person
    /// turns OrbGuard on (CXCallDirectoryManager.openSettings, iOS 13.4+).
    private func openSettings(result: @escaping FlutterResult) {
        CXCallDirectoryManager.sharedInstance.openSettings { error in
            DispatchQueue.main.async {
                if let error = error {
                    result(FlutterError(code: "OPEN_SETTINGS_FAILED", message: error.localizedDescription, details: nil))
                } else {
                    result(true)
                }
            }
        }
    }

    // MARK: - Reload

    private func reload(result: @escaping FlutterResult) {
        CXCallDirectoryManager.sharedInstance.reloadExtension(withIdentifier: Self.extensionIdentifier) { error in
            DispatchQueue.main.async {
                if let error = error {
                    result(FlutterError(code: "RELOAD_FAILED", message: error.localizedDescription, details: nil))
                } else {
                    result(true)
                }
            }
        }
    }

    // MARK: - Status

    /// Reports how many entries are stored and the REAL enablement state of the
    /// extension, making clear that the user must enable it for any blocking to
    /// occur. Never reports "blocking is active" on its own authority.
    private func reportStatus(result: @escaping FlutterResult) {
        let counts = store.counts()
        CXCallDirectoryManager.sharedInstance.getEnabledStatusForExtension(
            withIdentifier: Self.extensionIdentifier
        ) { status, error in
            let statusString: String
            switch status {
            case .enabled: statusString = "enabled"
            case .disabled: statusString = "disabled"
            case .unknown: statusString = "unknown"
            @unknown default: statusString = "unknown"
            }
            DispatchQueue.main.async {
                result([
                    "containerAvailable": self.store.isContainerAvailable,
                    "blockedCount": counts.blocked,
                    "identifiedCount": counts.identified,
                    "extensionStatus": statusString,
                    "extensionEnabled": status == .enabled,
                    "requiresUserEnable": true,
                    "note": "OrbGuard's call directory only blocks or labels calls after the person turns OrbGuard on in Settings, Apps, Phone, Call Blocking & Identification. This status reports data sync and enablement only.",
                    "error": error?.localizedDescription as Any,
                ])
            }
        }
    }

    // MARK: - Parsing

    /// Accepts an Int, Int64, NSNumber or String of digits and returns a
    /// positive CallKit phone number (country-code-prefixed Int64) or nil.
    private static func parseNumber(_ value: Any?) -> Int64? {
        switch value {
        case let n as Int64:
            return n > 0 ? n : nil
        case let n as Int:
            return n > 0 ? Int64(n) : nil
        case let n as NSNumber:
            let v = n.int64Value
            return v > 0 ? v : nil
        case let s as String:
            let digits = s.filter(\.isNumber)
            guard let v = Int64(digits), v > 0 else { return nil }
            return v
        default:
            return nil
        }
    }
}
