// VPNManager.swift
// OrbGuard iOS - VPN Control Manager for Main App
// Location: ios/Runner/VPNManager.swift

import Foundation
import NetworkExtension
import os.log

// MARK: - VPN Manager Delegate

protocol VPNManagerDelegate: AnyObject {
    func vpnStatusDidChange(_ status: NEVPNStatus)
    func vpnDidConnect()
    func vpnDidDisconnect()
    func vpnDidFailWithError(_ error: Error)
}

// MARK: - VPN Manager

class VPNManager {

    // MARK: - Properties

    static let shared = VPNManager()

    weak var delegate: VPNManagerDelegate?

    private var vpnManager: NETunnelProviderManager?
    private let logger = Logger(subsystem: "com.orb.guard", category: "VPNManager")
    private let sharedData = SharedDataManager.shared

    private(set) var currentStatus: NEVPNStatus = .disconnected {
        didSet {
            delegate?.vpnStatusDidChange(currentStatus)
        }
    }

    // Configuration
    private let tunnelBundleId = "com.orb.guard.OrbGuardVPN"
    private let tunnelDescription = "OrbGuard DNS Protection"

    // MARK: - Initialization

    private init() {
        loadVPNConfiguration()
        observeVPNStatus()
    }

    // MARK: - Public Methods

    /// Load or create VPN configuration
    func loadVPNConfiguration(completion: ((Error?) -> Void)? = nil) {
        NETunnelProviderManager.loadAllFromPreferences { [weak self] managers, error in
            guard let self = self else { return }

            if let error = error {
                self.logger.error("Failed to load VPN configurations: \(error.localizedDescription)")
                completion?(error)
                return
            }

            // Find or create our VPN configuration
            if let existingManager = managers?.first(where: {
                ($0.protocolConfiguration as? NETunnelProviderProtocol)?.providerBundleIdentifier == self.tunnelBundleId
            }) {
                self.vpnManager = existingManager
                self.currentStatus = existingManager.connection.status
                self.logger.info("Loaded existing VPN configuration")
            } else {
                // Create new configuration
                self.createVPNConfiguration { error in
                    completion?(error)
                }
                return
            }

            completion?(nil)
        }
    }

    /// Start VPN protection
    func startVPN(completion: @escaping (Error?) -> Void) {
        guard let vpnManager = vpnManager else {
            loadVPNConfiguration { [weak self] error in
                if let error = error {
                    completion(error)
                    return
                }
                self?.startVPN(completion: completion)
            }
            return
        }

        // Ensure VPN is enabled
        vpnManager.isEnabled = true
        vpnManager.saveToPreferences { [weak self] error in
            guard let self = self else { return }

            if let error = error {
                self.logger.error("Failed to save VPN configuration: \(error.localizedDescription)")
                completion(error)
                return
            }

            // Start the tunnel
            do {
                try vpnManager.connection.startVPNTunnel()
                self.logger.info("VPN tunnel start requested")
                completion(nil)
            } catch {
                self.logger.error("Failed to start VPN tunnel: \(error.localizedDescription)")
                completion(error)
            }
        }
    }

    /// Stop VPN protection
    func stopVPN() {
        vpnManager?.connection.stopVPNTunnel()
        logger.info("VPN tunnel stop requested")
    }

    /// Check if VPN is enabled
    var isVPNEnabled: Bool {
        return vpnManager?.isEnabled ?? false
    }

    /// Check if VPN is connected
    var isVPNConnected: Bool {
        return currentStatus == .connected
    }

    /// Get VPN status string
    var statusString: String {
        switch currentStatus {
        case .invalid:
            return "Invalid"
        case .disconnected:
            return "Disconnected"
        case .connecting:
            return "Connecting..."
        case .connected:
            return "Connected"
        case .reasserting:
            return "Reconnecting..."
        case .disconnecting:
            return "Disconnecting..."
        @unknown default:
            return "Unknown"
        }
    }

    /// Send message to VPN extension
    func sendMessageToExtension(_ message: VPNMessage, completion: ((Data?) -> Void)? = nil) {
        guard let session = vpnManager?.connection as? NETunnelProviderSession else {
            completion?(nil)
            return
        }

        guard let messageData = try? JSONEncoder().encode(message) else {
            completion?(nil)
            return
        }

        do {
            try session.sendProviderMessage(messageData) { response in
                completion?(response)
            }
        } catch {
            logger.error("Failed to send message to VPN extension: \(error.localizedDescription)")
            completion?(nil)
        }
    }

    /// Refresh blocklist in VPN extension
    func refreshBlocklist() {
        let message = VPNMessage(type: .refreshBlocklist, payload: nil)
        sendMessageToExtension(message)
    }

    /// Add domain to allowlist
    func addToAllowlist(_ domain: String) {
        let message = VPNMessage(type: .addToAllowlist, payload: domain)
        sendMessageToExtension(message)
    }

    /// Remove domain from allowlist
    func removeFromAllowlist(_ domain: String) {
        let message = VPNMessage(type: .removeFromAllowlist, payload: domain)
        sendMessageToExtension(message)
    }

    /// Get protection stats from VPN extension
    func getStats(completion: @escaping (ProtectionStats?) -> Void) {
        let message = VPNMessage(type: .getStats, payload: nil)
        sendMessageToExtension(message) { data in
            guard let data = data,
                  let stats = try? JSONDecoder().decode(ProtectionStats.self, from: data) else {
                completion(nil)
                return
            }
            completion(stats)
        }
    }

    // MARK: - Private Methods

    private func createVPNConfiguration(completion: @escaping (Error?) -> Void) {
        let manager = NETunnelProviderManager()

        // Protocol configuration
        let protocolConfig = NETunnelProviderProtocol()
        protocolConfig.providerBundleIdentifier = tunnelBundleId
        protocolConfig.serverAddress = "OrbGuard DNS"
        protocolConfig.disconnectOnSleep = false

        manager.protocolConfiguration = protocolConfig
        manager.localizedDescription = tunnelDescription
        manager.isEnabled = true

        // On-demand rules (optional - connect on untrusted Wi-Fi)
        if sharedData.loadSettings().autoConnectOnUntrustedWifi {
            let wifiRule = NEOnDemandRuleConnect()
            wifiRule.interfaceTypeMatch = .wiFi
            manager.onDemandRules = [wifiRule]
            manager.isOnDemandEnabled = true
        }

        // Save configuration
        manager.saveToPreferences { [weak self] error in
            guard let self = self else { return }

            if let error = error {
                self.logger.error("Failed to create VPN configuration: \(error.localizedDescription)")
                completion(error)
                return
            }

            // Reload to get the saved configuration
            manager.loadFromPreferences { error in
                if let error = error {
                    self.logger.error("Failed to reload VPN configuration: \(error.localizedDescription)")
                    completion(error)
                    return
                }

                self.vpnManager = manager
                self.currentStatus = manager.connection.status
                self.logger.info("Created new VPN configuration")
                completion(nil)
            }
        }
    }

    private func observeVPNStatus() {
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(vpnStatusChanged),
            name: .NEVPNStatusDidChange,
            object: nil
        )
    }

    @objc private func vpnStatusChanged(_ notification: Notification) {
        guard let connection = notification.object as? NEVPNConnection else { return }

        currentStatus = connection.status

        switch connection.status {
        case .connected:
            delegate?.vpnDidConnect()
        case .disconnected:
            delegate?.vpnDidDisconnect()
        case .invalid:
            if let error = connection.connectedDate {
                // Connection became invalid
                logger.warning("VPN connection became invalid")
            }
        default:
            break
        }

        logger.info("VPN status changed to: \(self.statusString)")
    }

    // MARK: - Configuration Management

    /// Update VPN settings
    func updateSettings(_ settings: SharedSettings) {
        sharedData.saveSettings(settings)

        // Update on-demand rules if needed
        if let manager = vpnManager {
            if settings.autoConnectOnUntrustedWifi {
                let wifiRule = NEOnDemandRuleConnect()
                wifiRule.interfaceTypeMatch = .wiFi
                manager.onDemandRules = [wifiRule]
                manager.isOnDemandEnabled = true
            } else {
                manager.onDemandRules = []
                manager.isOnDemandEnabled = false
            }

            manager.saveToPreferences { error in
                if let error = error {
                    self.logger.error("Failed to update VPN settings: \(error.localizedDescription)")
                }
            }
        }
    }

    /// Remove VPN configuration completely
    func removeVPNConfiguration(completion: @escaping (Error?) -> Void) {
        vpnManager?.removeFromPreferences { [weak self] error in
            if let error = error {
                self?.logger.error("Failed to remove VPN configuration: \(error.localizedDescription)")
            } else {
                self?.vpnManager = nil
                self?.currentStatus = .disconnected
                self?.logger.info("VPN configuration removed")
            }
            completion(error)
        }
    }
}

// MARK: - VPN Message Types (duplicated for main app)

extension VPNMessage {
    // VPNMessage is defined in PacketTunnelProvider.swift
    // This extension is just for clarity
}
