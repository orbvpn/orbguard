// CallDirectoryStore.swift
// OrbGuard iOS — shared App Group store for the CallKit call-directory data.
// Location: ios/Shared/CallDirectoryStore.swift
//
// Compiled into BOTH the host app (writer, via CallDirectoryChannelHandler) and
// the OrbGuardCallDirectory extension (reader, via CallDirectoryHandler). It
// persists two lists as a single JSON file inside the shared App Group
// container (group.com.orb.guard.shared):
//   * blocked    — [Int64] phone numbers to silently reject.
//   * identified — [(Int64, String)] number → caller-ID label pairs.
//
// The reader path returns numbers already sorted ascending and de-duplicated,
// which is exactly the order CallKit's addBlockingEntry / addIdentificationEntry
// require. All numbers are the CallKit CXCallDirectoryPhoneNumber form: the full
// number including country code as a plain Int64 (e.g. +1 (408) 555-0123 →
// 14085550123). No leading '+', spaces or punctuation.

import Foundation
import os.log

struct CallDirectoryStore {

    struct IdentificationEntry {
        let number: Int64
        let label: String
    }

    private static let appGroupIdentifier = "group.com.orb.guard.shared"
    private static let fileName = "call_directory.json"
    private let logger = Logger(subsystem: "com.orb.guard", category: "CallDirectoryStore")

    private var fileURL: URL? {
        FileManager.default
            .containerURL(forSecurityApplicationGroupIdentifier: Self.appGroupIdentifier)?
            .appendingPathComponent(Self.fileName)
    }

    /// Whether the shared App Group container is reachable in this build.
    var isContainerAvailable: Bool { fileURL != nil }

    // On-disk representation.
    private struct Payload: Codable {
        var blocked: [Int64]
        var identified: [Identified]
        struct Identified: Codable {
            let number: Int64
            let label: String
        }
        static let empty = Payload(blocked: [], identified: [])
    }

    // MARK: - Read (extension side)

    /// Blocked numbers, sorted ascending and de-duplicated — ready to feed
    /// straight into CXCallDirectoryExtensionContext.addBlockingEntry.
    func loadBlockedNumbers() -> [Int64] {
        normalized(load().blocked)
    }

    /// Identification entries, unique by number and sorted ascending — ready
    /// for CXCallDirectoryExtensionContext.addIdentificationEntry.
    func loadIdentificationEntries() -> [IdentificationEntry] {
        var seen = Set<Int64>()
        var out: [IdentificationEntry] = []
        for entry in load().identified.sorted(by: { $0.number < $1.number }) {
            guard entry.number > 0, !entry.label.isEmpty, !seen.contains(entry.number) else { continue }
            seen.insert(entry.number)
            out.append(IdentificationEntry(number: entry.number, label: entry.label))
        }
        return out
    }

    // MARK: - Write (host app side)

    /// Overwrites the stored lists atomically. Returns false only when the App
    /// Group container is not provisioned (capability missing from the build).
    @discardableResult
    func save(blocked: [Int64], identified: [IdentificationEntry]) -> Bool {
        guard let url = fileURL else {
            logger.error("App Group container unavailable; call-directory data not written")
            return false
        }
        let payload = Payload(
            blocked: normalized(blocked),
            identified: identified.map { Payload.Identified(number: $0.number, label: $0.label) })
        do {
            let data = try JSONEncoder().encode(payload)
            try data.write(to: url, options: .atomic)
            return true
        } catch {
            logger.error("Failed to write call-directory data: \(error.localizedDescription, privacy: .public)")
            return false
        }
    }

    /// Current stored counts (post-normalization) for status reporting.
    func counts() -> (blocked: Int, identified: Int) {
        let payload = load()
        return (normalized(payload.blocked).count, loadIdentificationEntries().count)
    }

    // MARK: - Helpers

    private func load() -> Payload {
        guard let url = fileURL,
              let data = try? Data(contentsOf: url),
              let payload = try? JSONDecoder().decode(Payload.self, from: data) else {
            return .empty
        }
        return payload
    }

    private func normalized(_ numbers: [Int64]) -> [Int64] {
        Array(Set(numbers.filter { $0 > 0 })).sorted()
    }
}
