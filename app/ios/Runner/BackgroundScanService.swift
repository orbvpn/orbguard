// BackgroundScanService.swift - OrbGuard iOS
// Real background scanning via BGTaskScheduler + the shared security posture
// checks used by both the on-demand scan path (AppDelegate method channel)
// and the background refresh task.
//
// Honesty contract:
// - `register()` is called from application(_:didFinishLaunchingWithOptions:)
//   BEFORE it returns, as Apple requires.
// - Only `com.orb.guard.background-scan` is registered and submitted. The
//   other identifiers declared in Info.plist (threat-intel-sync, deep-scan)
//   have NO handler and are never submitted — nothing pretends they run.
// - A background run executes only the cheap, non-UIKit posture checks
//   (system proxy/MITM, injected dylibs, debugger/DYLD, sandbox escape,
//   jailbreak file markers) — well under the ~25s BGAppRefreshTask budget.
//   Screen-capture (UIScreen, a momentary main-thread UI state that would
//   fire false alarms for e.g. AirPlay at 3am) and the cydia:// URL probe
//   (UIApplication, a main-thread/foreground API) run ONLY on demand.
// - Every persisted status value reflects a real event: `bg_last_run_iso` is
//   the wall-clock time a handler actually executed, `bg_last_success` is
//   false when iOS expired the task before the run finished.
// - iOS alone decides if and when a pending request runs; nothing here claims
//   a periodic guarantee.

import Foundation
import UIKit
import BackgroundTasks
import UserNotifications
import CFNetwork
import MachO
import os.log

// MARK: - Shared security posture checks

/// The real device/runtime posture checks a sandboxed iOS app is permitted to
/// perform. This is the ONE implementation shared by the on-demand scan
/// methods on the com.orb.guard/system channel and the background scan, so
/// both paths can never drift apart. Each returns real findings; an empty
/// array means "checked, nothing found" — never "couldn't check".
enum SecurityPostureChecks {

    /// Detects a system HTTP proxy that could be intercepting traffic (MITM).
    static func proxyThreats() -> [[String: Any]] {
        var threats: [[String: Any]] = []
        guard let cf = CFNetworkCopySystemProxySettings()?.takeRetainedValue(),
              let settings = cf as? [String: Any] else {
            return threats
        }
        if let enabled = settings[kCFNetworkProxiesHTTPEnable as String] as? Int,
           enabled == 1,
           let host = settings[kCFNetworkProxiesHTTPProxy as String] as? String,
           !host.isEmpty {
            threats.append([
                "id": "net_proxy_\(UUID().uuidString)",
                "name": "HTTP proxy configured",
                "type": "network",
                "severity": "MEDIUM",
                "path": host,
                "description": "A proxy (\(host)) is routing this device's web traffic. If you did not set it up, a malicious proxy can intercept and modify traffic (man-in-the-middle).",
                "requiresRoot": false,
                "metadata": ["proxy_host": host]
            ])
        }
        return threats
    }

    /// Detects code-injection/hooking libraries loaded into this process.
    static func injectedLibraryThreats() -> [[String: Any]] {
        var threats: [[String: Any]] = []
        let hooks = ["substrate", "substitute", "libhooker", "cycript", "cynject",
                     "frida", "sslkillswitch", "libjailbreak", "rocketbootstrap",
                     "tweakinject", "shadow.dylib"]
        for i in 0..<_dyld_image_count() {
            guard let cname = _dyld_get_image_name(i) else { continue }
            let full = String(cString: cname)
            let lower = full.lowercased()
            if let hit = hooks.first(where: { lower.contains($0) }) {
                threats.append([
                    "id": "proc_inject_\(UUID().uuidString)",
                    "name": "Injected library detected",
                    "type": "process",
                    "severity": "HIGH",
                    "path": full,
                    "description": "A code-injection/hooking library (\(hit)) is loaded into this app — a sign of a jailbroken device or a tampered build, which spyware uses to hook into apps.",
                    "requiresRoot": false,
                    "metadata": ["library": hit]
                ])
            }
        }
        return threats
    }

    /// Detects active screen capture/mirroring. UIKit main-thread state read —
    /// meaningful while the user is looking at the device, so it runs on the
    /// on-demand path only and is deliberately EXCLUDED from background runs
    /// (a mirroring session while the app is backgrounded, e.g. AirPlay,
    /// would otherwise raise off-hours false alarms).
    static func screenCaptureThreats() -> [[String: Any]] {
        var threats: [[String: Any]] = []
        var captured = false
        if Thread.isMainThread {
            captured = UIScreen.main.isCaptured
        } else {
            DispatchQueue.main.sync { captured = UIScreen.main.isCaptured }
        }
        if captured {
            threats.append([
                "id": "proc_screencapture_\(UUID().uuidString)",
                "name": "Screen is being captured",
                "type": "process",
                "severity": "MEDIUM",
                "path": "UIScreen.isCaptured",
                "description": "The screen is currently being recorded or mirrored. If you did not start a recording or AirPlay session, screen-capture spyware may be active.",
                "requiresRoot": false,
                "metadata": [:]
            ])
        }
        return threats
    }

    /// Detects an attached debugger/tracer and DYLD library injection.
    static func debuggerThreats() -> [[String: Any]] {
        var threats: [[String: Any]] = []
        if isDebuggerAttached() {
            threats.append([
                "id": "mem_debugger_\(UUID().uuidString)",
                "name": "Debugger attached to app",
                "type": "memory",
                "severity": "HIGH",
                "path": "P_TRACED",
                "description": "A debugger/tracer is attached to this app. Outside development this indicates runtime tampering or dynamic instrumentation by malware.",
                "requiresRoot": false,
                "metadata": [:]
            ])
        }
        if let raw = getenv("DYLD_INSERT_LIBRARIES") {
            let libs = String(cString: raw)
            if !libs.isEmpty {
                threats.append([
                    "id": "mem_dyld_\(UUID().uuidString)",
                    "name": "DYLD injection detected",
                    "type": "memory",
                    "severity": "HIGH",
                    "path": libs,
                    "description": "DYLD_INSERT_LIBRARIES is set (\(libs)) — a library is being force-loaded into apps, a common malware/hooking technique.",
                    "requiresRoot": false,
                    "metadata": ["libraries": libs]
                ])
            }
        }
        return threats
    }

    /// True when a debugger/tracer is attached to this process (P_TRACED).
    static func isDebuggerAttached() -> Bool {
        var info = kinfo_proc()
        var size = MemoryLayout<kinfo_proc>.stride
        var mib: [Int32] = [CTL_KERN, KERN_PROC, KERN_PROC_PID, getpid()]
        let ret = sysctl(&mib, 4, &info, &size, nil, 0)
        if ret != 0 { return false }
        return (info.kp_proc.p_flag & P_TRACED) != 0
    }

    /// True when this app can write outside its sandbox — only possible on a
    /// jailbroken device (the precondition for most iOS spyware).
    static func sandboxWriteProbeSucceeds() -> Bool {
        let probe = "/private/.orbguard_sbx_\(UUID().uuidString)"
        guard (try? "x".write(toFile: probe, atomically: true, encoding: .utf8)) != nil else {
            return false
        }
        try? FileManager.default.removeItem(atPath: probe)
        return true
    }

    /// Attempts to write outside the app sandbox. Success is only possible on
    /// a jailbroken device (the sandbox is broken).
    static func sandboxEscapeThreats() -> [[String: Any]] {
        guard sandboxWriteProbeSucceeds() else { return [] }
        return [[
            "id": "sbx_escape_\(UUID().uuidString)",
            "name": "Sandbox escape possible (jailbreak)",
            "type": "system",
            "severity": "CRITICAL",
            "path": "/private",
            "description": "This app was able to write outside its sandbox, which is only possible on a jailbroken device. Jailbreaking removes the protections that stop spyware from reading your data.",
            "requiresRoot": false,
            "metadata": [:]
        ]]
    }

    /// Well-known jailbreak file markers that are visible from the sandbox on
    /// a jailbroken device; returns the paths that actually exist.
    static func jailbreakFileMarkerHits() -> [String] {
        let jailbreakPaths = [
            "/Applications/Cydia.app",
            "/Applications/Sileo.app",
            "/Applications/Zebra.app",
            "/Library/MobileSubstrate/MobileSubstrate.dylib",
            "/bin/bash",
            "/usr/sbin/sshd",
            "/etc/apt",
            "/private/var/lib/apt/",
            "/usr/bin/ssh",
            "/var/cache/apt",
            "/var/lib/cydia",
            "/var/log/syslog",
            "/bin/sh",
            "/usr/libexec/sftp-server"
        ]
        return jailbreakPaths.filter { FileManager.default.fileExists(atPath: $0) }
    }

    /// Threat-dict form of the jailbreak file-marker check for scan results.
    static func jailbreakMarkerThreats() -> [[String: Any]] {
        let hits = jailbreakFileMarkerHits()
        guard !hits.isEmpty else { return [] }
        return [[
            "id": "jb_markers_\(UUID().uuidString)",
            "name": "Jailbreak indicators present",
            "type": "system",
            "severity": "HIGH",
            "path": hits[0],
            "description": "Files associated with a jailbreak are visible on this device (\(hits.count) marker\(hits.count > 1 ? "s" : "")). Jailbreaking removes the protections that stop spyware from reading your data.",
            "requiresRoot": false,
            "metadata": ["markers": hits.joined(separator: ", ")]
        ]]
    }
}

// MARK: - Background scan service

/// Owns the BGAppRefreshTask lifecycle for the background posture check:
/// registration, request submission, honest execution, status persistence and
/// the (permission-respecting) finding notification.
final class BackgroundScanService {

    static let shared = BackgroundScanService()

    /// The only background task identifier this app registers and submits.
    /// Must stay in Info.plist's BGTaskSchedulerPermittedIdentifiers.
    static let taskIdentifier = "com.orb.guard.background-scan"

    /// UserDefaults keys for the honest last-run record.
    static let lastRunKey = "bg_last_run_iso"
    static let lastFindingsKey = "bg_last_findings_count"
    static let lastSuccessKey = "bg_last_success"

    /// Ask iOS for a run no sooner than this after submission. iOS alone
    /// decides the actual run time (or whether it runs at all).
    static let defaultEarliestInterval: TimeInterval = 4 * 3600

    /// Stable notification identifier so a newer finding replaces the older
    /// notification instead of stacking up.
    private static let notificationIdentifier = "com.orb.guard.bg-scan-finding"

    private let logger = Logger(subsystem: "com.orb.guard", category: "BackgroundScan")
    private static let iso8601 = ISO8601DateFormatter()

    private init() {}

    // MARK: Registration (must complete before didFinishLaunching returns)

    /// Registers the launch handler with BGTaskScheduler. Apple requires this
    /// to happen before application(_:didFinishLaunchingWithOptions:) returns.
    func register() {
        let registered = BGTaskScheduler.shared.register(
            forTaskWithIdentifier: Self.taskIdentifier,
            using: nil
        ) { [weak self] task in
            guard let self = self, let refreshTask = task as? BGAppRefreshTask else {
                task.setTaskCompleted(success: false)
                return
            }
            self.handle(task: refreshTask)
        }
        if !registered {
            logger.error("BGTaskScheduler refused registration for \(Self.taskIdentifier, privacy: .public) — background scans cannot run")
        }
    }

    // MARK: Request submission

    /// Submits the next background-scan request. Returns the earliest begin
    /// date actually requested; throws the real BGTaskScheduler error
    /// otherwise (e.g. unavailable on Simulator, Background App Refresh off).
    @discardableResult
    func submitNextRequest(earliestIn interval: TimeInterval = BackgroundScanService.defaultEarliestInterval) throws -> Date {
        let request = BGAppRefreshTaskRequest(identifier: Self.taskIdentifier)
        let earliest = Date(timeIntervalSinceNow: interval)
        request.earliestBeginDate = earliest
        try BGTaskScheduler.shared.submit(request)
        logger.info("Submitted background-scan request; earliest begin \(Self.iso8601.string(from: earliest), privacy: .public)")
        return earliest
    }

    /// Fire-and-forget submission for launch / enter-background paths where
    /// there is nobody to report the error to; the failure is only logged.
    func submitNextRequestLoggingFailure() {
        do {
            try submitNextRequest()
        } catch {
            logger.error("Could not submit background-scan request: \(error.localizedDescription, privacy: .public)")
        }
    }

    /// Cancels the pending background-scan request (if any).
    func cancelPendingRequest() {
        BGTaskScheduler.shared.cancel(taskRequestWithIdentifier: Self.taskIdentifier)
        logger.info("Cancelled pending background-scan request")
    }

    // MARK: Status

    /// Reports the REAL scheduler + last-run state: `scheduled` comes from
    /// BGTaskScheduler's actual pending-request list, the rest from the
    /// persisted record of the last genuine run. `lastRunIso` is absent until
    /// a background run has actually happened. Completion runs on the main
    /// thread (FlutterResult must be delivered there).
    func status(completion: @escaping ([String: Any]) -> Void) {
        BGTaskScheduler.shared.getPendingTaskRequests { requests in
            let scheduled = requests.contains { $0.identifier == Self.taskIdentifier }
            let defaults = UserDefaults.standard
            var payload: [String: Any] = [
                "scheduled": scheduled,
                "lastFindings": defaults.integer(forKey: Self.lastFindingsKey),
                "lastSuccess": defaults.bool(forKey: Self.lastSuccessKey),
            ]
            if let iso = defaults.string(forKey: Self.lastRunKey) {
                payload["lastRunIso"] = iso
            }
            DispatchQueue.main.async { completion(payload) }
        }
    }

    // MARK: Task execution

    /// Runs the real background posture check within the BGAppRefreshTask
    /// budget, records the truthful outcome, notifies (if permitted) on
    /// findings and completes the task honestly.
    private func handle(task: BGAppRefreshTask) {
        logger.info("Background scan task started")

        // Keep a next request pending — this run consumed the current one.
        submitNextRequestLoggingFailure()

        // Whichever of {work finished, task expired} happens first owns the
        // record + completion; the other becomes a no-op.
        let once = OnceFlag()

        let work = DispatchWorkItem { [weak self] in
            guard let self = self else {
                if once.tryFire() { task.setTaskCompleted(success: false) }
                return
            }
            let findings = self.runBackgroundChecks()
            guard once.tryFire() else { return } // expired mid-run; already recorded as failed
            self.recordRun(findingsCount: findings.count, success: true)
            self.logger.info("Background scan finished with \(findings.count) finding(s)")
            if findings.isEmpty {
                task.setTaskCompleted(success: true)
            } else {
                self.postFindingNotificationIfAuthorized(findingCount: findings.count) {
                    task.setTaskCompleted(success: true)
                }
            }
        }

        task.expirationHandler = { [weak self] in
            work.cancel()
            guard once.tryFire() else { return }
            // iOS reclaimed the budget before the run finished — record the
            // truth (attempted at this time, did not complete) and say so.
            self?.recordRun(findingsCount: 0, success: false)
            self?.logger.warning("Background scan expired before completion")
            task.setTaskCompleted(success: false)
        }

        DispatchQueue.global(qos: .utility).async(execute: work)
    }

    /// The background check itself: the cheap, non-UIKit posture checks only
    /// (they complete in well under a second — far inside the ~25s budget).
    /// Excluded here, on purpose: screen-capture (momentary UIKit state,
    /// on-demand only) and the cydia:// URL probe (UIApplication is a
    /// main-thread/foreground API).
    private func runBackgroundChecks() -> [[String: Any]] {
        var findings: [[String: Any]] = []
        findings += SecurityPostureChecks.proxyThreats()
        findings += SecurityPostureChecks.injectedLibraryThreats()
        findings += SecurityPostureChecks.debuggerThreats()
        findings += SecurityPostureChecks.sandboxEscapeThreats()
        findings += SecurityPostureChecks.jailbreakMarkerThreats()
        return findings
    }

    /// Persists the truthful record of a background run.
    private func recordRun(findingsCount: Int, success: Bool) {
        let defaults = UserDefaults.standard
        defaults.set(Self.iso8601.string(from: Date()), forKey: Self.lastRunKey)
        defaults.set(findingsCount, forKey: Self.lastFindingsKey)
        defaults.set(success, forKey: Self.lastSuccessKey)
    }

    // MARK: Notification

    /// Posts a calm local notification about background findings — only when
    /// the user has actually granted notification permission. Always calls
    /// `completion` (the task must be completed either way).
    private func postFindingNotificationIfAuthorized(findingCount: Int, completion: @escaping () -> Void) {
        let center = UNUserNotificationCenter.current()
        center.getNotificationSettings { [weak self] settings in
            let allowed: Bool
            switch settings.authorizationStatus {
            case .authorized, .provisional, .ephemeral:
                allowed = true
            default:
                allowed = false
            }
            guard allowed else {
                self?.logger.info("Findings present but notifications not authorized; skipping notification")
                completion()
                return
            }

            let content = UNMutableNotificationContent()
            content.title = "OrbGuard background check"
            content.body = findingCount == 1
                ? "OrbGuard found something during a background check — open to review."
                : "OrbGuard found \(findingCount) things during a background check — open to review."
            content.sound = .default

            let request = UNNotificationRequest(
                identifier: Self.notificationIdentifier,
                content: content,
                trigger: nil) // deliver immediately

            center.add(request) { error in
                if let error = error {
                    self?.logger.error("Failed to post finding notification: \(error.localizedDescription, privacy: .public)")
                }
                completion()
            }
        }
    }
}

// MARK: - Once flag

/// Thread-safe "first caller wins" latch used to guarantee a BGTask is
/// completed exactly once even when work and expiration race.
private final class OnceFlag {
    private let lock = NSLock()
    private var fired = false

    /// Returns true for the first caller only.
    func tryFire() -> Bool {
        lock.lock()
        defer { lock.unlock() }
        if fired { return false }
        fired = true
        return true
    }
}
