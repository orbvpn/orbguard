// ContentFilterChannelHandler.swift - OrbGuard iOS
// Hosts the com.orb.guard/content_filter method channel.
//
// Purpose: bridge the Dart threat-intel domain block list into the shared App
// Group container (group.com.orb.guard.shared) that the OrbGuardFilter
// NEFilterDataProvider content-filter extension reads. The app process writes
// the block list into the shared BlocklistCache SQLite database; the extension
// process reads the same database via BlocklistCache.shared.
//
// Honesty contract: this channel performs DATA SYNC ONLY. It never starts or
// stops filtering and never reports that on-device enforcement is active.
//
// Apple only ACTIVATES an NEFilterDataProvider on an MDM-supervised
// ("enterprise-managed") device. On a normal consumer iPhone the extension is
// installed but iOS will not run it. This handler therefore deliberately
// exposes no "enable"/"active" surface that could imply protection that isn't
// there. The consumer on-device firewall engine (com.orbvpn.orbguard/firewall)
// remains correctly reported as UNAVAILABLE on iOS; only Android provides a
// real on-device firewall (OrbFirewallVpnService).

import Flutter
import Foundation
import os.log

final class ContentFilterChannelHandler {

    static let channelName = "com.orb.guard/content_filter"

    private let logger = Logger(subsystem: "com.orb.guard", category: "ContentFilter")
    private let blocklist = BlocklistCache.shared
    private let sharedData = SharedDataManager.shared

    func register(with messenger: FlutterBinaryMessenger) {
        let channel = FlutterMethodChannel(name: Self.channelName, binaryMessenger: messenger)
        channel.setMethodCallHandler { [weak self] call, result in
            self?.handle(call: call, result: result)
        }
    }

    private func handle(call: FlutterMethodCall, result: @escaping FlutterResult) {
        switch call.method {
        case "syncBlocklist":
            syncBlocklist(call: call, result: result)
        case "status":
            reportStatus(result: result)
        default:
            result(FlutterMethodNotImplemented)
        }
    }

    // MARK: - Blocklist Sync

    /// Writes the supplied domains into the shared App Group blocklist database
    /// that the content-filter extension reads. Idempotent: the `domain` column
    /// is UNIQUE and rows are upserted (INSERT OR REPLACE), so re-syncing the
    /// same list never creates duplicates.
    private func syncBlocklist(call: FlutterMethodCall, result: @escaping FlutterResult) {
        guard let container = sharedData.getSharedContainerURL() else {
            result(FlutterError(
                code: "APP_GROUP_UNAVAILABLE",
                message: "The App Group container (group.com.orb.guard.shared) is not provisioned for this build; the content-filter block list cannot be written. This requires the App Groups capability in the signing profile.",
                details: ["platform": "ios"]))
            return
        }

        let args = call.arguments as? [String: Any]
        let domains = (args?["domains"] as? [String]) ?? []
        // IPs are accepted for API parity with the Android firewall channel, but
        // an NEFilterBrowserFlow filter matches on URL host (domain), not on raw
        // IP, so they are counted and reported — not silently "enforced".
        let ipCount = (args?["ips"] as? [String])?.count ?? 0

        DispatchQueue.global(qos: .utility).async { [weak self] in
            guard let self = self else { return }

            let rules = domains
                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() }
                .filter { !$0.isEmpty }
                .map { (domain: $0, category: BlockRule.BlockCategory.custom, source: Optional("app-threat-intel")) }

            self.blocklist.bulkAddRules(rules)
            let ruleCount = self.blocklist.getRuleCount()

            self.logger.info("Synced \(rules.count) domains into content-filter blocklist (\(ruleCount) total rules); \(ipCount) IPs received (not URL-filterable)")

            DispatchQueue.main.async {
                result([
                    "domainsWritten": rules.count,
                    "ruleCount": ruleCount,
                    "ipsReceivedNotEnforced": ipCount,
                    "containerPath": container.path,
                ])
            }
        }
    }

    // MARK: - Status

    /// Reports whether the shared container is reachable and how many rules it
    /// currently holds. Explicitly states that enforcement is MDM-gated so a
    /// caller can never read this as "filtering is on".
    private func reportStatus(result: @escaping FlutterResult) {
        let container = sharedData.getSharedContainerURL()
        result([
            "containerAvailable": container != nil,
            "containerPath": container?.path ?? "",
            "ruleCount": blocklist.getRuleCount(),
            "enforcementActive": false,
            "requiresSupervision": true,
            "note": "OrbGuard's iOS content filter (NEFilterDataProvider) only enforces on MDM-supervised devices. This status reports block-list sync only, not active filtering.",
        ])
    }
}
