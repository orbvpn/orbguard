// FilterDataProvider.swift
// OrbGuard Content Filter - Enterprise URL Filtering via MDM
// Location: ios/OrbGuardFilter/FilterDataProvider.swift
//
// NOTE: NEFilterDataProvider only works on supervised iOS devices (MDM-managed)
// or in the iOS Simulator. It requires MDM enrollment for consumer devices.

import NetworkExtension
import os.log

class FilterDataProvider: NEFilterDataProvider {

    // MARK: - Properties

    private let logger = Logger(subsystem: "com.orb.guard.filter", category: "FilterData")
    private let sharedData = SharedDataManager.shared
    private let blocklist = BlocklistCache.shared

    // In-memory URL cache for fast lookups
    private var urlCache: [String: FilterAction] = [:]
    private let urlCacheLimit = 10000

    // MARK: - Filter Lifecycle

    override func startFilter(completionHandler: @escaping (Error?) -> Void) {
        logger.info("Starting OrbGuard content filter")

        // Load initial blocklist
        loadBlocklist()

        completionHandler(nil)
    }

    override func stopFilter(with reason: NEProviderStopReason, completionHandler: @escaping () -> Void) {
        logger.info("Stopping OrbGuard content filter, reason: \(String(describing: reason))")

        // Clear cache
        urlCache.removeAll()

        completionHandler()
    }

    // MARK: - Flow Handling

    override func handleNewFlow(_ flow: NEFilterFlow) -> NEFilterNewFlowVerdict {
        // Only filter browser flows (Safari, Chrome, etc.)
        guard let browserFlow = flow as? NEFilterBrowserFlow,
              let url = browserFlow.url else {
            return .allow()
        }

        let urlString = url.absoluteString
        let domain = url.host ?? ""

        logger.debug("Handling flow for: \(domain)")

        // Check cache first
        if let cachedAction = urlCache[domain] {
            return cachedAction == .block ? .drop() : .allow()
        }

        // Check blocklist
        let (shouldBlock, rule) = blocklist.shouldBlock(domain)

        if shouldBlock {
            logger.info("Blocking domain: \(domain), category: \(rule?.category.rawValue ?? "unknown")")

            // Cache the result
            cacheResult(domain: domain, action: .block)

            // Record block
            if let rule = rule {
                blocklist.recordBlock(domain: domain, category: rule.category)
            }

            // Update stats
            sharedData.incrementStat(\.blockedQueries)

            return .drop()
        }

        // Allow and cache
        cacheResult(domain: domain, action: .allow)
        sharedData.incrementStat(\.totalQueries)

        return .allow()
    }

    override func handleInboundData(from flow: NEFilterFlow, readBytesStartOffset: Int, readBytes: Data) -> NEFilterDataVerdict {
        // For data inspection - could analyze content here
        return .allow()
    }

    override func handleOutboundData(from flow: NEFilterFlow, readBytesStartOffset: Int, readBytes: Data) -> NEFilterDataVerdict {
        // For data inspection - could analyze content here
        return .allow()
    }

    override func handleRemediationForFlow(_ flow: NEFilterFlow) -> NEFilterRemediationVerdict {
        // Show remediation page for blocked content
        guard let browserFlow = flow as? NEFilterBrowserFlow,
              let url = browserFlow.url else {
            return .needRules()
        }

        let domain = url.host ?? "unknown"
        let (_, rule) = blocklist.shouldBlock(domain)

        // Create remediation URL (would point to your block page)
        let remediationURL = URL(string: "https://block.orbguard.com/?domain=\(domain)&category=\(rule?.category.rawValue ?? "unknown")")

        if let remediation = remediationURL {
            return .needRules()  // In production, return remediation URL
        }

        return .needRules()
    }

    // MARK: - Private Methods

    private func loadBlocklist() {
        // Blocklist is loaded from shared App Group
        let ruleCount = blocklist.getRuleCount()
        logger.info("Loaded \(ruleCount) blocklist rules")
    }

    private func cacheResult(domain: String, action: FilterAction) {
        // Limit cache size
        if urlCache.count >= urlCacheLimit {
            // Remove oldest entries (simple FIFO)
            let keysToRemove = Array(urlCache.keys.prefix(1000))
            keysToRemove.forEach { urlCache.removeValue(forKey: $0) }
        }

        urlCache[domain] = action
    }

    enum FilterAction {
        case allow
        case block
    }
}

// MARK: - Filter Control Provider

class FilterControlProvider: NEFilterControlProvider {

    private let logger = Logger(subsystem: "com.orb.guard.filter", category: "FilterControl")
    private let sharedData = SharedDataManager.shared

    override func startFilter(completionHandler: @escaping (Error?) -> Void) {
        logger.info("Filter control provider starting")
        completionHandler(nil)
    }

    override func stopFilter(with reason: NEProviderStopReason, completionHandler: @escaping () -> Void) {
        logger.info("Filter control provider stopping")
        completionHandler()
    }

    override func handleNewFlow(_ flow: NEFilterFlow, completionHandler: @escaping (NEFilterControlVerdict) -> Void) {
        // Control provider can make allow/block decisions
        // Typically used for initial filtering before data provider

        guard let browserFlow = flow as? NEFilterBrowserFlow,
              let url = browserFlow.url,
              let domain = url.host else {
            completionHandler(.allow(withUpdateRules: false))
            return
        }

        // Quick check against blocklist
        let (shouldBlock, _) = BlocklistCache.shared.shouldBlock(domain)

        if shouldBlock {
            completionHandler(.drop(withUpdateRules: false))
        } else {
            completionHandler(.allow(withUpdateRules: false))
        }
    }

    override func handleRemediationForFlow(_ flow: NEFilterFlow, completionHandler: @escaping (NEFilterControlVerdict) -> Void) {
        // Handle remediation requests
        completionHandler(.allow(withUpdateRules: false))
    }

    override func handleRulesChanged() {
        // Called when rules are updated
        logger.info("Filter rules changed - reloading")
    }
}
