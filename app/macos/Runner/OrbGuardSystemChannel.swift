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
// is inspect the applications currently running, read the code signature of
// a file it can read (Security framework), and read the network interfaces
// and the system proxy settings (getifaddrs, SystemConfiguration).

import AppKit
import Darwin
import Foundation
import FlutterMacOS
import Security
import SystemConfiguration

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

    case "codeSignatures":
      // Verified off the main thread: a large app takes a moment.
      let args = call.arguments as? [String: Any]
      let paths = (args?["paths"] as? [String]) ?? []
      DispatchQueue.global(qos: .userInitiated).async {
        var signatures: [String: Any] = [:]
        for path in paths { signatures[path] = codeSignature(of: path) }
        DispatchQueue.main.async { result(signatures) }
      }

    case "networkReroute":
      result(networkReroute())

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

  // MARK: - Code signatures (Security framework, works in the sandbox)

  /// Errors that mean the signature is there but does not check out: the
  /// code or its sealed parts were changed after signing.
  private static let brokenSignature: Set<OSStatus> = [
    errSecCSSignatureFailed,
    errSecCSSignatureInvalid,
    errSecCSResourcesNotSealed,
    errSecCSResourcesNotFound,
    errSecCSResourcesInvalid,
    errSecCSBadResource,
    errSecCSResourceRulesInvalid,
    errSecCSInfoPlistFailed,
    errSecCSResourceDirectoryFailed,
    errSecCSBadNestedCode,
    errSecCSUnsignedNestedCode,
    errSecCSBadMainExecutable,
  ]

  /// One file's signature: "apple" (signed by Apple), "valid" (signed by a
  /// developer and intact), "unsigned", "broken" (signed but changed since),
  /// or "unknown" when macOS would not let it be read. "unknown" is never
  /// reported as unsigned.
  private static func codeSignature(of path: String) -> [String: Any] {
    var code: SecStaticCode?
    let opened = SecStaticCodeCreateWithPath(
      URL(fileURLWithPath: path) as CFURL, SecCSFlags(), &code)
    guard opened == errSecSuccess, let code = code else {
      return ["status": "unknown", "error": Int(opened)]
    }
    // The signature and the main executable are checked; the hashes of every
    // resource in a large bundle are not, so this stays quick.
    let flags = SecCSFlags(rawValue: kSecCSDoNotValidateResources)
    let validity = SecStaticCodeCheckValidity(code, flags, nil)
    if validity == errSecCSUnsigned {
      return ["status": "unsigned"]
    }
    var status: String
    if validity == errSecSuccess {
      status = "valid"
    } else if brokenSignature.contains(validity) {
      status = "broken"
    } else {
      return ["status": "unknown", "error": Int(validity)]
    }

    var info: CFDictionary?
    SecCodeCopySigningInformation(
      code, SecCSFlags(rawValue: kSecCSSigningInformation), &info)
    let signing = (info as? [String: Any]) ?? [:]
    var out: [String: Any] = [:]
    if let team = signing[kSecCodeInfoTeamIdentifier as String] as? String {
      out["teamId"] = team
    }
    if let identifier = signing[kSecCodeInfoIdentifier as String] as? String {
      out["identifier"] = identifier
    }
    if let certificates = signing[kSecCodeInfoCertificates as String] as? [SecCertificate],
       let leaf = certificates.first,
       let summary = SecCertificateCopySubjectSummary(leaf) as String? {
      out["authority"] = summary
    }

    if status == "valid" {
      var requirement: SecRequirement?
      if SecRequirementCreateWithString(
        "anchor apple" as CFString, SecCSFlags(), &requirement) == errSecSuccess,
         let requirement = requirement,
         SecStaticCodeCheckValidity(code, flags, requirement) == errSecSuccess {
        status = "apple"
      }
    }
    out["status"] = status
    return out
  }

  // MARK: - VPN tunnels and the system proxy

  /// Interfaces a VPN brings up: utun (most VPN apps and Network Extension),
  /// ipsec (the built-in IKEv2 client), ppp (L2TP), tun and tap (OpenVPN).
  private static let tunnelPrefixes = ["utun", "ipsec", "ppp", "tun", "tap"]

  /// The tunnel interfaces that are up with a routable address, the
  /// interface the system sends its traffic through, and the proxy settings.
  /// macOS keeps a few utun interfaces of its own with only a link-local
  /// address; those carry no traffic off the Mac and are left out.
  private static func networkReroute() -> [String: Any] {
    var tunnels: [String: [String]] = [:]
    var list: UnsafeMutablePointer<ifaddrs>?
    if getifaddrs(&list) == 0, let first = list {
      var cursor: UnsafeMutablePointer<ifaddrs>? = first
      while let entry = cursor {
        defer { cursor = entry.pointee.ifa_next }
        let name = String(cString: entry.pointee.ifa_name)
        guard tunnelPrefixes.contains(where: { name.hasPrefix($0) }) else { continue }
        let flags = Int32(entry.pointee.ifa_flags)
        guard flags & IFF_UP != 0, flags & IFF_RUNNING != 0 else { continue }
        guard let address = entry.pointee.ifa_addr,
              let text = numericHost(address) else { continue }
        let family = Int32(address.pointee.sa_family)
        if family == AF_INET6 && text.lowercased().hasPrefix("fe80") { continue }
        if family != AF_INET && family != AF_INET6 { continue }
        tunnels[name, default: []].append(text)
      }
      freeifaddrs(first)
    }

    let store = SCDynamicStoreCreate(nil, "OrbGuard" as CFString, nil, nil)
    let owners = store.map(vpnOwners) ?? [:]
    var out: [String: Any] = [
      "tunnels": tunnels.keys.sorted().map { name -> [String: Any] in
        var entry: [String: Any] = ["name": name, "addresses": tunnels[name]!]
        if let owner = owners[name] {
          entry["owner"] = owner.app
          if let label = owner.name { entry["ownerName"] = label }
        }
        return entry
      },
    ]
    if let store = store,
       let global = SCDynamicStoreCopyValue(store, "State:/Network/Global/IPv4" as CFString) as? [String: Any],
       let primary = global["PrimaryInterface"] as? String {
      out["primaryInterface"] = primary
    }
    if let proxies = CFNetworkCopySystemProxySettings()?.takeRetainedValue() as? [String: Any] {
      out["proxy"] = proxySettings(proxies)
    }
    return out
  }

  /// The VPN behind each tunnel interface that a VPN configuration on this
  /// Mac has up: the app the configuration belongs to (its bundle
  /// identifier, which macOS records for a Network Extension VPN) and the
  /// name it shows in System Settings. A tunnel no configuration claims is
  /// left out, so its owner stays unknown.
  private static func vpnOwners(_ store: SCDynamicStore) -> [String: (app: String, name: String?)] {
    var owners: [String: (app: String, name: String?)] = [:]
    for family in ["IPv4", "IPv6"] {
      let pattern = "State:/Network/Service/[^/]+/\(family)" as CFString
      guard let keys = SCDynamicStoreCopyKeyList(store, pattern) as? [String] else { continue }
      for key in keys {
        let parts = key.split(separator: "/")
        guard parts.count >= 4 else { continue }
        let service = String(parts[3])
        guard let state = SCDynamicStoreCopyValue(store, key as CFString) as? [String: Any],
              let interface = state["InterfaceName"] as? String,
              owners[interface] == nil,
              let setup = SCDynamicStoreCopyValue(
                store, "Setup:/Network/Service/\(service)/Interface" as CFString) as? [String: Any],
              setup["Type"] as? String == "VPN",
              let app = setup["SubType"] as? String, !app.isEmpty
        else { continue }
        let named = SCDynamicStoreCopyValue(
          store, "Setup:/Network/Service/\(service)" as CFString) as? [String: Any]
        owners[interface] = (app: app, name: named?["UserDefinedName"] as? String)
      }
    }
    return owners
  }

  private static func numericHost(_ address: UnsafeMutablePointer<sockaddr>) -> String? {
    var host = [CChar](repeating: 0, count: Int(NI_MAXHOST))
    let length = socklen_t(address.pointee.sa_len)
    guard getnameinfo(address, length, &host, socklen_t(host.count), nil, 0, NI_NUMERICHOST) == 0 else {
      return nil
    }
    return String(cString: host)
  }

  /// The proxies the system sends traffic through, by kind, as host:port.
  private static func proxySettings(_ p: [String: Any]) -> [String: Any] {
    func on(_ key: CFString) -> Bool { (p[key as String] as? Int ?? 0) != 0 }
    func endpoint(_ host: CFString, _ port: CFString) -> String? {
      guard let h = p[host as String] as? String, !h.isEmpty else { return nil }
      if let n = p[port as String] as? Int { return "\(h):\(n)" }
      return h
    }
    var out: [String: Any] = [:]
    if on(kCFNetworkProxiesHTTPEnable),
       let e = endpoint(kCFNetworkProxiesHTTPProxy, kCFNetworkProxiesHTTPPort) {
      out["http"] = e
    }
    if on(kCFNetworkProxiesHTTPSEnable),
       let e = endpoint(kCFNetworkProxiesHTTPSProxy, kCFNetworkProxiesHTTPSPort) {
      out["https"] = e
    }
    if on(kCFNetworkProxiesSOCKSEnable),
       let e = endpoint(kCFNetworkProxiesSOCKSProxy, kCFNetworkProxiesSOCKSPort) {
      out["socks"] = e
    }
    if on(kCFNetworkProxiesProxyAutoConfigEnable) {
      out["pac"] = (p[kCFNetworkProxiesProxyAutoConfigURLString as String] as? String) ?? ""
    }
    if on(kCFNetworkProxiesProxyAutoDiscoveryEnable) {
      out["autoDiscovery"] = true
    }
    return out
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
