// CallDirectoryHandler.swift
// OrbGuard Call Directory — real spam-call blocking + caller ID via CallKit.
// Location: ios/OrbGuardCallDirectory/CallDirectoryHandler.swift
//
// WHAT THIS IS
// A real CXCallDirectoryProvider. When enabled by the user it supplies iOS
// with two lists, sourced from the SHARED APP GROUP container that the host app
// writes (group.com.orb.guard.shared, via CallDirectoryStore):
//   * BLOCKING entries      — numbers iOS should silently reject.
//   * IDENTIFICATION entries — (number, label) pairs iOS shows on the incoming
//     call screen (e.g. "OrbGuard: Reported Scam").
// Numbers come from the user's own block list plus OrbGuard threat-intel phone
// reputation. If the app has written nothing yet, both lists are empty and the
// extension correctly adds nothing — it never fabricates numbers.
//
// CALLKIT ORDERING CONTRACT
// CallKit requires every entry to be added in ASCENDING, STRICTLY-INCREASING
// numeric order, separately for blocking and identification. CallDirectoryStore
// already returns sorted, de-duplicated Int64 arrays; if that contract is
// violated iOS fails the request and the extension is disabled, so we rely on
// the store's normalization rather than re-sorting here.
//
// HONESTY / ACTIVATION CONTRACT
// This extension only takes effect after the user enables it in
//   Settings > Phone > Call Blocking & Identification > (enable "OrbGuard").
// and only in a build signed with a profile carrying the CallKit call-directory
// capability and the group.com.orb.guard.shared App Group. Until both are true
// iOS does not load it; it blocks/identifies nothing.

import CallKit
import Foundation
import os.log

class CallDirectoryHandler: CXCallDirectoryProvider {

    private let logger = Logger(subsystem: "com.orb.guard.calldirectory", category: "CallDirectory")

    override func beginRequest(with context: CXCallDirectoryExtensionContext) {
        context.delegate = self

        let store = CallDirectoryStore()

        // iOS may ask for an INCREMENTAL update (only changes since the last
        // successful load) or a FULL load. We do not persist per-entry deltas,
        // so for an incremental request we perform a full refresh: clear the
        // existing entries, then re-add the complete current lists below. A full
        // (non-incremental) request starts empty, so no clearing is needed.
        if context.isIncremental {
            context.removeAllBlockingEntries()
            context.removeAllIdentificationEntries()
        }

        let blocked = store.loadBlockedNumbers()          // sorted, unique, ascending
        for number in blocked {
            context.addBlockingEntry(withNextSequentialPhoneNumber: number)
        }

        let identified = store.loadIdentificationEntries() // sorted by number, unique
        for entry in identified {
            context.addIdentificationEntry(
                withNextSequentialPhoneNumber: entry.number,
                label: entry.label)
        }

        logger.info("Call directory loaded: \(blocked.count) blocked, \(identified.count) identified (incremental=\(context.isIncremental))")

        context.completeRequest()
    }
}

// MARK: - CXCallDirectoryExtensionContextDelegate

extension CallDirectoryHandler: CXCallDirectoryExtensionContextDelegate {

    func requestFailed(for extensionContext: CXCallDirectoryExtensionContext,
                       withError error: Error) {
        // A failure here (most often the ascending-order contract being
        // violated, or the App Group being unreachable) causes iOS to keep the
        // previous data and retry later. Surface it for diagnostics.
        logger.error("Call directory request failed: \(error.localizedDescription, privacy: .public)")
    }
}
