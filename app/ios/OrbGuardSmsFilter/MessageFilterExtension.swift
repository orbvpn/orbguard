// MessageFilterExtension.swift
// OrbGuard SMS Filter — real anti-smishing via Apple's IdentityLookup framework.
// Location: ios/OrbGuardSmsFilter/MessageFilterExtension.swift
//
// WHAT THIS IS
// A real ILMessageFilterExtension. When enabled by the user it lets iOS hand
// OrbGuard every message from an UNKNOWN sender (not in the user's contacts)
// and asks us to classify it as .none / .promotion / .transaction / .junk.
//
// TWO-STAGE CLASSIFICATION
//   1. OFFLINE — a self-contained heuristic (URLs, shorteners, punycode/raw-IP
//      hosts, urgency/credential/payment/prize/delivery keywords, OTP shape)
//      returns a decisive action for clear cases with NO network round-trip.
//   2. NETWORK DEFERRAL — for uncertain cases we call
//      context.deferQueryRequestToNetwork(). iOS itself performs an HTTPS
//      request to the URL declared in Info.plist
//      (ILMessageFilterExtensionNetworkURL = the OrbGuard backend
//      /api/v1/sms/analyze endpoint) and hands us back the server's response,
//      which we map to an action in handle(_:context:completion:).
//
// HONESTY / ACTIVATION CONTRACT
// This extension only RUNS after the user turns it on in
//   Settings > Messages > Unknown & Spam > (enable "OrbGuard").
// and only in a build signed with an Apple provisioning profile that carries
// the `com.apple.developer.identitylookup.message-filter` capability. Until
// both are true iOS does not invoke it; it filters nothing. It never reads
// messages from known contacts, and it cannot exfiltrate message content — iOS
// controls exactly what is sent on the network deferral (only to the declared
// URL, only when the user has enabled filtering).
//
// PRIVACY OF THE NETWORK PATH
// The extension never builds the outgoing request body itself. When we call
// deferQueryRequestToNetwork(), the SYSTEM issues the HTTPS request to the
// declared URL on our behalf and returns the server response. We own only the
// response mapping. The backend endpoint must therefore accept the system's
// message-filter deferral format and answer with OrbGuard's SMSAnalysisResult
// JSON ({ "is_threat", "threat_level", "threat_type", ... }).

import Foundation
import IdentityLookup
import os.log

final class MessageFilterExtension: ILMessageFilterExtension {}

// MARK: - Query handling

extension MessageFilterExtension: ILMessageFilterQueryHandling {

    private static let logger = Logger(subsystem: "com.orb.guard.smsfilter", category: "MessageFilter")

    func handle(_ queryRequest: ILMessageFilterQueryRequest,
                context: ILMessageFilterExtensionContext,
                completion: @escaping (ILMessageFilterQueryResponse) -> Void) {

        let body = queryRequest.messageBody ?? ""
        let sender = queryRequest.sender ?? ""

        // Stage 1 — offline classification. A non-nil result is decisive.
        if let action = SmishingClassifier.decisiveAction(body: body, sender: sender) {
            Self.logger.debug("Offline decisive action: \(action.rawValue, privacy: .public)")
            completion(Self.response(for: action))
            return
        }

        // Stage 2 — uncertain: defer to the backend. iOS performs the HTTPS
        // request to ILMessageFilterExtensionNetworkURL and returns the result.
        context.deferQueryRequestToNetwork { [weak self] networkResponse, error in
            if let error = error {
                Self.logger.error("Network deferral failed: \(error.localizedDescription, privacy: .public)")
            }
            // Route through the network-response handler (also usable directly).
            (self ?? MessageFilterExtension())
                .handle(networkResponse, context: context, completion: completion)
        }
    }

    /// Maps the backend's response (delivered by the system after a network
    /// deferral) to a message-filter action. On any parse failure or missing
    /// response it returns `.none` — we NEVER junk a message we could not
    /// positively classify.
    func handle(_ networkResponse: ILNetworkResponse?,
                context: ILMessageFilterExtensionContext,
                completion: @escaping (ILMessageFilterQueryResponse) -> Void) {
        let action = SmishingClassifier.action(fromBackendResponse: networkResponse?.data)
        Self.logger.debug("Network-mapped action: \(action.rawValue, privacy: .public)")
        completion(Self.response(for: action))
    }

    private static func response(for action: ILMessageFilterAction) -> ILMessageFilterQueryResponse {
        let response = ILMessageFilterQueryResponse()
        response.action = action
        return response
    }
}

// MARK: - Smishing classifier (offline + backend-response mapping)

/// Self-contained smishing heuristics. Kept dependency-free so the extension
/// target compiles against IdentityLookup alone.
enum SmishingClassifier {

    // MARK: Offline decision

    /// Returns a decisive `ILMessageFilterAction` for clear cases, or `nil`
    /// when the message is ambiguous and should be deferred to the backend.
    static func decisiveAction(body rawBody: String, sender: String) -> ILMessageFilterAction? {
        let body = rawBody.lowercased()
        if body.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return .none // nothing to classify — deliver normally
        }

        let hosts = extractHosts(from: rawBody)
        let hasURL = !hosts.isEmpty || rawBody.range(of: "https?://", options: .regularExpression) != nil
        let hasShortener = hosts.contains { isShortener($0) }
        let hasPunycode = hosts.contains { $0.contains("xn--") }
        let hasRawIPHost = hosts.contains { isRawIPv4Host($0) }

        let urgency = containsAny(body, Keywords.urgency)
        let credential = containsAny(body, Keywords.credential)
        let payment = containsAny(body, Keywords.payment)
        let prize = containsAny(body, Keywords.prize)
        let delivery = containsAny(body, Keywords.delivery)
        let optOut = containsAny(body, Keywords.optOut)
        let otp = looksLikeOneTimeCode(body)

        let pretextSignals =
            (credential ? 1 : 0) + (payment ? 1 : 0) + (urgency ? 1 : 0) +
            (prize ? 1 : 0) + (delivery ? 1 : 0)

        // --- Decisive malicious (smishing) --------------------------------
        // A deceptive host (punycode or raw IP) is a strong, low-false-positive
        // signal on its own.
        if hasPunycode || hasRawIPHost {
            return .junk
        }
        // A link plus a phishing pretext is the classic smishing shape. A URL
        // shortener (which hides the destination) needs only one pretext
        // signal; an ordinary link needs two.
        if hasURL {
            let threshold = hasShortener ? 1 : 2
            if pretextSignals >= threshold {
                return .junk
            }
        }

        // --- Decisive transactional (OTP / verification, no link) ----------
        if otp && !hasURL {
            return transactionAction()
        }

        // --- Decisive promotional (marketing with opt-out, no risky link) --
        if optOut && !hasShortener && !hasPunycode && !hasRawIPHost {
            return promotionAction()
        }

        // --- Clearly benign: no link and no pretext signals ----------------
        if !hasURL && pretextSignals == 0 && !otp {
            return .none
        }

        // --- Uncertain: defer to backend -----------------------------------
        return nil
    }

    // MARK: Backend-response mapping

    /// Maps OrbGuard's `SMSAnalysisResult` JSON to an action. Returns `.none`
    /// on any failure so we never misfile a message we could not classify.
    static func action(fromBackendResponse data: Data?) -> ILMessageFilterAction {
        guard let data = data,
              let object = try? JSONSerialization.jsonObject(with: data),
              let json = object as? [String: Any] else {
            return .none
        }

        let isThreat = (json["is_threat"] as? Bool) ?? false
        let level = (json["threat_level"] as? String)?.lowercased() ?? ""
        let type = (json["threat_type"] as? String)?.lowercased() ?? ""

        if isThreat {
            switch level {
            case "critical", "high", "medium":
                return .junk
            case "low":
                // Low-confidence threat: junk only outright spam, otherwise
                // route to the Promotions tab rather than penalising the sender.
                return type == "spam" ? promotionAction() : .none
            default:
                // is_threat == true but an unrecognised level — treat as junk.
                return .junk
            }
        }

        // Not a threat. Bucket obvious marketing spam into Promotions.
        if type == "spam" {
            return promotionAction()
        }
        return .none
    }

    // MARK: Action helpers (iOS 16 sub-tabs, else deliver normally)

    private static func transactionAction() -> ILMessageFilterAction {
        if #available(iOS 16.0, *) { return .transaction }
        return .none
    }

    private static func promotionAction() -> ILMessageFilterAction {
        if #available(iOS 16.0, *) { return .promotion }
        return .none
    }

    // MARK: Signal extraction

    private static func extractHosts(from text: String) -> [String] {
        guard let detector = try? NSDataDetector(types: NSTextCheckingResult.CheckingType.link.rawValue) else {
            return []
        }
        let range = NSRange(text.startIndex..., in: text)
        var hosts: [String] = []
        detector.enumerateMatches(in: text, options: [], range: range) { match, _, _ in
            if let host = match?.url?.host {
                hosts.append(host.lowercased())
            }
        }
        return hosts
    }

    private static func isShortener(_ host: String) -> Bool {
        let bare = host.hasPrefix("www.") ? String(host.dropFirst(4)) : host
        return Keywords.shorteners.contains(bare)
    }

    private static func isRawIPv4Host(_ host: String) -> Bool {
        let parts = host.split(separator: ".")
        guard parts.count == 4 else { return false }
        return parts.allSatisfy { part in
            guard let n = Int(part) else { return false }
            return n >= 0 && n <= 255
        }
    }

    private static func looksLikeOneTimeCode(_ body: String) -> Bool {
        // "verification code", "one-time", "otp", "code is 123456", "g-123456"
        if containsAny(body, Keywords.otpPhrases) {
            return body.range(of: "\\d{4,8}", options: .regularExpression) != nil
        }
        return false
    }

    private static func containsAny(_ haystack: String, _ needles: [String]) -> Bool {
        needles.contains { haystack.contains($0) }
    }

    // MARK: Keyword banks

    private enum Keywords {
        static let urgency = [
            "urgent", "immediately", "right now", "as soon as possible", "asap",
            "act now", "final notice", "last warning", "account suspended",
            "suspended", "locked", "will be closed", "expires today",
            "within 24 hours", "verify now", "action required",
        ]
        static let credential = [
            "verify your account", "confirm your identity", "log in", "login",
            "sign in", "password", "one time password", "unlock your account",
            "reactivate", "update your details", "confirm your account",
            "validate your", "re-verify", "security alert",
        ]
        static let payment = [
            "payment", "invoice", "refund", "billing", "credit card",
            "debit card", "bank account", "wire transfer", "gift card",
            "overdue", "outstanding balance", "tax", "irs", "hmrc",
            "toll", "unpaid", "fee", "fine",
        ]
        static let prize = [
            "congratulations", "you have won", "you won", "winner", "prize",
            "claim your", "free gift", "reward", "lottery", "voucher",
            "selected", "lucky",
        ]
        static let delivery = [
            "package", "parcel", "delivery", "shipment", "courier", "usps",
            "fedex", "ups", "dhl", "royal mail", "tracking", "held at",
            "reschedule your delivery", "address confirmation",
        ]
        static let optOut = [
            "reply stop", "text stop", "unsubscribe", "opt out", "opt-out",
            "to stop receiving", "msg&data rates", "stop to end",
        ]
        static let otpPhrases = [
            "verification code", "one-time", "one time code", "otp",
            "security code", "your code", "code is", "login code",
            "authentication code", "2fa", "passcode",
        ]
        // Well-known URL shorteners that hide their true destination.
        static let shorteners: Set<String> = [
            "bit.ly", "tinyurl.com", "t.co", "goo.gl", "ow.ly", "is.gd",
            "buff.ly", "rebrand.ly", "cutt.ly", "t.ly", "rb.gy", "shorturl.at",
            "bl.ink", "s.id", "tiny.cc", "lnkd.in", "trib.al", "shrtco.de",
            "v.gd", "clck.ru", "qr.link",
        ]
    }
}
