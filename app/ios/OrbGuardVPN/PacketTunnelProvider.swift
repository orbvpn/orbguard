// PacketTunnelProvider.swift
// OrbGuard VPN - Network Extension for DNS Filtering
// Location: ios/OrbGuardVPN/PacketTunnelProvider.swift

import NetworkExtension
import os.log

class PacketTunnelProvider: NEPacketTunnelProvider {

    // MARK: - Properties

    private let logger = Logger(subsystem: "com.orb.guard.vpn", category: "PacketTunnel")
    private var dnsProxy: DNSProxy?
    private let sharedData = SharedDataManager.shared
    private let blocklist = BlocklistCache.shared

    // DNS server configuration
    private let localDNSAddress = "10.10.10.1"
    private let tunnelSubnet = "10.10.10.0/24"
    private let upstreamDNS = ["1.1.1.1", "8.8.8.8"]  // Cloudflare & Google

    // MARK: - Tunnel Lifecycle

    override func startTunnel(options: [String : NSObject]?, completionHandler: @escaping (Error?) -> Void) {
        logger.info("Starting OrbGuard VPN tunnel")

        // Update VPN status
        var status = VPNStatus(
            connectionStatus: .connecting,
            connectedSince: nil,
            serverAddress: localDNSAddress,
            bytesReceived: 0,
            bytesSent: 0,
            lastError: nil
        )
        sharedData.saveVPNStatus(status)

        // Configure tunnel
        let tunnelSettings = createTunnelSettings()

        setTunnelNetworkSettings(tunnelSettings) { [weak self] error in
            guard let self = self else { return }

            if let error = error {
                self.logger.error("Failed to set tunnel settings: \(error.localizedDescription)")
                status.connectionStatus = .error
                status.lastError = error.localizedDescription
                self.sharedData.saveVPNStatus(status)
                completionHandler(error)
                return
            }

            // Start DNS proxy
            self.dnsProxy = DNSProxy(
                blocklist: self.blocklist,
                upstreamServers: self.upstreamDNS,
                sharedData: self.sharedData
            )
            self.dnsProxy?.start()

            // Update status to connected
            status.connectionStatus = .connected
            status.connectedSince = Date()
            self.sharedData.saveVPNStatus(status)

            self.logger.info("OrbGuard VPN tunnel started successfully")
            completionHandler(nil)

            // Start packet handling
            self.handlePackets()
        }
    }

    override func stopTunnel(with reason: NEProviderStopReason, completionHandler: @escaping () -> Void) {
        logger.info("Stopping OrbGuard VPN tunnel, reason: \(String(describing: reason))")

        // Update status
        var status = sharedData.loadVPNStatus() ?? VPNStatus(
            connectionStatus: .disconnecting,
            connectedSince: nil,
            serverAddress: nil,
            bytesReceived: 0,
            bytesSent: 0,
            lastError: nil
        )
        status.connectionStatus = .disconnecting
        sharedData.saveVPNStatus(status)

        // Stop DNS proxy
        dnsProxy?.stop()
        dnsProxy = nil

        // Final status update
        status.connectionStatus = .disconnected
        status.connectedSince = nil
        sharedData.saveVPNStatus(status)

        logger.info("OrbGuard VPN tunnel stopped")
        completionHandler()
    }

    override func handleAppMessage(_ messageData: Data, completionHandler: ((Data?) -> Void)?) {
        // Handle messages from the main app
        guard let message = try? JSONDecoder().decode(VPNMessage.self, from: messageData) else {
            completionHandler?(nil)
            return
        }

        switch message.type {
        case .refreshBlocklist:
            logger.info("Refreshing blocklist from app message")
            // Blocklist is shared via App Group, just rebuild bloom filter
            completionHandler?(nil)

        case .getStats:
            let stats = sharedData.loadStats()
            if let data = try? JSONEncoder().encode(stats) {
                completionHandler?(data)
            } else {
                completionHandler?(nil)
            }

        case .addToAllowlist:
            if let domain = message.payload {
                _ = blocklist.addToAllowlist(domain)
            }
            completionHandler?(nil)

        case .removeFromAllowlist:
            if let domain = message.payload {
                _ = blocklist.removeFromAllowlist(domain)
            }
            completionHandler?(nil)
        }
    }

    override func sleep(completionHandler: @escaping () -> Void) {
        logger.info("VPN going to sleep")
        completionHandler()
    }

    override func wake() {
        logger.info("VPN waking up")
    }

    // MARK: - Tunnel Configuration

    private func createTunnelSettings() -> NEPacketTunnelNetworkSettings {
        let settings = NEPacketTunnelNetworkSettings(tunnelRemoteAddress: localDNSAddress)

        // IPv4 settings
        let ipv4Settings = NEIPv4Settings(addresses: [localDNSAddress], subnetMasks: ["255.255.255.0"])
        ipv4Settings.includedRoutes = [NEIPv4Route.default()]
        ipv4Settings.excludedRoutes = []
        settings.ipv4Settings = ipv4Settings

        // DNS settings - route all DNS through our proxy
        let dnsSettings = NEDNSSettings(servers: [localDNSAddress])
        dnsSettings.matchDomains = [""]  // Match all domains
        dnsSettings.searchDomains = []
        settings.dnsSettings = dnsSettings

        // MTU
        settings.mtu = 1400

        return settings
    }

    // MARK: - Packet Handling

    private func handlePackets() {
        // Read packets from the tunnel
        packetFlow.readPackets { [weak self] packets, protocols in
            guard let self = self else { return }

            for (index, packet) in packets.enumerated() {
                self.processPacket(packet, protocolNumber: protocols[index])
            }

            // Continue reading
            self.handlePackets()
        }
    }

    private func processPacket(_ packet: Data, protocolNumber: NSNumber) {
        // Check if it's a DNS packet (UDP port 53)
        guard packet.count >= 28 else { return }  // Minimum IP + UDP header

        // Parse IP header to check protocol
        let ipVersion = (packet[0] & 0xF0) >> 4
        guard ipVersion == 4 else { return }  // IPv4 only for now

        let ipHeaderLength = Int(packet[0] & 0x0F) * 4
        guard packet.count >= ipHeaderLength + 8 else { return }

        let protocolByte = packet[9]
        guard protocolByte == 17 else { return }  // UDP

        // Get destination port (big-endian)
        let destPort = UInt16(packet[ipHeaderLength + 2]) << 8 | UInt16(packet[ipHeaderLength + 3])

        if destPort == 53 {
            // This is a DNS query - let DNSProxy handle it
            handleDNSPacket(packet, ipHeaderLength: ipHeaderLength)
        } else {
            // Forward non-DNS packets
            packetFlow.writePackets([packet], withProtocols: [protocolNumber])
        }
    }

    private func handleDNSPacket(_ packet: Data, ipHeaderLength: Int) {
        // Extract DNS payload
        let udpHeaderLength = 8
        let dnsPayloadStart = ipHeaderLength + udpHeaderLength
        guard packet.count > dnsPayloadStart else { return }

        let dnsPayload = packet.subdata(in: dnsPayloadStart..<packet.count)

        // Pass to DNS proxy for filtering
        dnsProxy?.handleDNSQuery(dnsPayload) { [weak self] response in
            guard let self = self, let response = response else { return }

            // Build response packet
            if let responsePacket = self.buildDNSResponsePacket(originalPacket: packet, dnsResponse: response) {
                self.packetFlow.writePackets([responsePacket], withProtocols: [AF_INET as NSNumber])
            }
        }
    }

    private func buildDNSResponsePacket(originalPacket: Data, dnsResponse: Data) -> Data? {
        // Create a response packet by swapping source/dest in original and adding DNS response
        var response = originalPacket

        // Swap source and destination IP
        let srcIP = originalPacket[12..<16]
        let dstIP = originalPacket[16..<20]
        response.replaceSubrange(12..<16, with: dstIP)
        response.replaceSubrange(16..<20, with: srcIP)

        // Swap source and destination ports
        let ipHeaderLength = Int(originalPacket[0] & 0x0F) * 4
        let srcPort = originalPacket[ipHeaderLength..<(ipHeaderLength + 2)]
        let dstPort = originalPacket[(ipHeaderLength + 2)..<(ipHeaderLength + 4)]
        response.replaceSubrange(ipHeaderLength..<(ipHeaderLength + 2), with: dstPort)
        response.replaceSubrange((ipHeaderLength + 2)..<(ipHeaderLength + 4), with: srcPort)

        // Replace DNS payload
        let dnsPayloadStart = ipHeaderLength + 8
        response.replaceSubrange(dnsPayloadStart..<response.count, with: dnsResponse)

        // Update UDP length
        let udpLength = UInt16(8 + dnsResponse.count)
        response[(ipHeaderLength + 4)] = UInt8(udpLength >> 8)
        response[(ipHeaderLength + 5)] = UInt8(udpLength & 0xFF)

        // Update IP total length
        let totalLength = UInt16(ipHeaderLength + 8 + dnsResponse.count)
        response[2] = UInt8(totalLength >> 8)
        response[3] = UInt8(totalLength & 0xFF)

        // Recalculate IP checksum
        response[10] = 0
        response[11] = 0
        let checksum = calculateIPChecksum(Data(response[0..<ipHeaderLength]))
        response[10] = UInt8(checksum >> 8)
        response[11] = UInt8(checksum & 0xFF)

        return response
    }

    private func calculateIPChecksum(_ data: Data) -> UInt16 {
        var sum: UInt32 = 0

        for i in stride(from: 0, to: data.count - 1, by: 2) {
            let word = UInt32(data[i]) << 8 | UInt32(data[i + 1])
            sum += word
        }

        if data.count % 2 == 1 {
            sum += UInt32(data[data.count - 1]) << 8
        }

        while sum >> 16 != 0 {
            sum = (sum & 0xFFFF) + (sum >> 16)
        }

        return ~UInt16(sum)
    }
}

// MARK: - VPN Message Types

struct VPNMessage: Codable {
    let type: VPNMessageType
    let payload: String?

    enum VPNMessageType: String, Codable {
        case refreshBlocklist
        case getStats
        case addToAllowlist
        case removeFromAllowlist
    }
}

// MARK: - DNS Proxy

class DNSProxy {

    private let blocklist: BlocklistCache
    private let upstreamServers: [String]
    private let sharedData: SharedDataManager
    private let logger = Logger(subsystem: "com.orb.guard.vpn", category: "DNSProxy")

    private var isRunning = false

    init(blocklist: BlocklistCache, upstreamServers: [String], sharedData: SharedDataManager) {
        self.blocklist = blocklist
        self.upstreamServers = upstreamServers
        self.sharedData = sharedData
    }

    func start() {
        isRunning = true
        logger.info("DNS Proxy started")
    }

    func stop() {
        isRunning = false
        logger.info("DNS Proxy stopped")
    }

    func handleDNSQuery(_ query: Data, completion: @escaping (Data?) -> Void) {
        guard isRunning else {
            completion(nil)
            return
        }

        // Parse DNS query to extract domain
        guard let domain = parseDNSQuery(query) else {
            // Forward unparseable queries
            forwardToUpstream(query, completion: completion)
            return
        }

        // Check blocklist
        let (shouldBlock, rule) = blocklist.shouldBlock(domain)

        if shouldBlock {
            logger.info("Blocked domain: \(domain)")

            // Update stats
            sharedData.incrementStat(\.blockedQueries)
            if let rule = rule {
                blocklist.recordBlock(domain: domain, category: rule.category)
                updateCategoryStats(rule.category)
            }

            // Return NXDOMAIN response
            let response = createNXDomainResponse(for: query)
            completion(response)
        } else {
            // Update total queries stat
            sharedData.incrementStat(\.totalQueries)

            // Forward to upstream DNS
            forwardToUpstream(query, completion: completion)
        }
    }

    private func parseDNSQuery(_ data: Data) -> String? {
        guard data.count >= 12 else { return nil }

        // Skip DNS header (12 bytes)
        var offset = 12
        var domainParts: [String] = []

        while offset < data.count {
            let length = Int(data[offset])
            if length == 0 {
                break
            }

            offset += 1
            guard offset + length <= data.count else { return nil }

            let part = data[offset..<(offset + length)]
            if let str = String(data: part, encoding: .utf8) {
                domainParts.append(str)
            }
            offset += length
        }

        return domainParts.isEmpty ? nil : domainParts.joined(separator: ".")
    }

    private func createNXDomainResponse(for query: Data) -> Data {
        var response = query

        // Set response flags (QR=1, RCODE=3 NXDOMAIN)
        if response.count >= 4 {
            response[2] = 0x81  // QR=1, Opcode=0, AA=0, TC=0, RD=1
            response[3] = 0x83  // RA=1, RCODE=3 (NXDOMAIN)
        }

        // Zero out answer/authority/additional counts
        if response.count >= 12 {
            response[6] = 0
            response[7] = 0
            response[8] = 0
            response[9] = 0
            response[10] = 0
            response[11] = 0
        }

        return response
    }

    private func forwardToUpstream(_ query: Data, completion: @escaping (Data?) -> Void) {
        guard let server = upstreamServers.first,
              let serverIP = IPv4Address(server) else {
            completion(nil)
            return
        }

        // Create UDP socket and send query
        let queue = DispatchQueue.global(qos: .userInitiated)

        queue.async {
            let socket = socket(AF_INET, SOCK_DGRAM, IPPROTO_UDP)
            guard socket >= 0 else {
                completion(nil)
                return
            }

            defer { close(socket) }

            // Set timeout
            var timeout = timeval(tv_sec: 2, tv_usec: 0)
            setsockopt(socket, SOL_SOCKET, SO_RCVTIMEO, &timeout, socklen_t(MemoryLayout<timeval>.size))

            // Server address
            var serverAddr = sockaddr_in()
            serverAddr.sin_family = sa_family_t(AF_INET)
            serverAddr.sin_port = UInt16(53).bigEndian
            serverAddr.sin_addr = in_addr(s_addr: inet_addr(server))

            // Send query
            let sendResult = query.withUnsafeBytes { ptr in
                sendto(socket, ptr.baseAddress, query.count, 0,
                       withUnsafePointer(to: &serverAddr) { $0.withMemoryRebound(to: sockaddr.self, capacity: 1) { $0 } },
                       socklen_t(MemoryLayout<sockaddr_in>.size))
            }

            guard sendResult >= 0 else {
                completion(nil)
                return
            }

            // Receive response
            var buffer = [UInt8](repeating: 0, count: 512)
            let recvResult = recv(socket, &buffer, buffer.count, 0)

            if recvResult > 0 {
                completion(Data(buffer[0..<recvResult]))
            } else {
                completion(nil)
            }
        }
    }

    private func updateCategoryStats(_ category: BlockRule.BlockCategory) {
        switch category {
        case .malware:
            sharedData.incrementStat(\.malwareBlocked)
        case .phishing:
            sharedData.incrementStat(\.phishingBlocked)
        case .tracker:
            sharedData.incrementStat(\.trackersBlocked)
        case .ads:
            sharedData.incrementStat(\.adsBlocked)
        default:
            break
        }
    }
}
