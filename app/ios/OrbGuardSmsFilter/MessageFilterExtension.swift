// MessageFilterExtension.swift
// OrbGuard SMS Filter: on-device scam-text sorting via Apple's IdentityLookup.
// Location: ios/OrbGuardSmsFilter/MessageFilterExtension.swift
//
// WHAT THIS IS
// An ILMessageFilterExtension. Once the person turns it on, iOS hands OrbGuard
// each SMS, MMS or RCS message from an UNKNOWN sender (not in their contacts,
// and not someone they have replied to three times or more) and asks for an
// action: .none (deliver normally), .transaction, .promotion or .junk.
//
// ON THE DEVICE ONLY
// A self-contained heuristic (URLs, shorteners, punycode or raw-IP hosts,
// urgency, credential, payment, prize and delivery wording, one-time-code
// shape) decides. Clear scams are .junk, codes .transaction, marketing with an
// opt-out .promotion; anything it is unsure about is delivered normally. There
// is no network deferral: the OrbGuard API cannot answer the request iOS sends
// (it requires an Authorization header iOS never adds, and the host serves no
// messagefilter apple-app-site-association), so a deferral could only fail.
// Message text never leaves the iPhone.
//
// HONESTY / ACTIVATION CONTRACT
// iOS runs this extension only after the person turns it on. On iOS 26 that is
// in Messages: the Filter button at the top right, Manage Filtering, Text
// Message Filter, then OrbGuard. No entitlement or portal capability is
// involved. Until it is on, iOS never calls it and it filters nothing.

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

        // A nil verdict means the classifier is unsure: deliver normally. We
        // never file a message we could not positively classify.
        // Spelled out: inside an optional context a bare `.none` is nil.
        let action: ILMessageFilterAction =
            SmishingClassifier.decisiveAction(body: body, sender: sender) ?? ILMessageFilterAction.none
        Self.logger.debug("Message filter action: \(action.rawValue, privacy: .public)")
        completion(Self.response(for: action))
    }

    private static func response(for action: ILMessageFilterAction) -> ILMessageFilterQueryResponse {
        let response = ILMessageFilterQueryResponse()
        response.action = action
        return response
    }
}

// MARK: - Smishing classifier (on-device)

/// Self-contained smishing heuristics. Kept dependency-free so the extension
/// target compiles against IdentityLookup alone.
enum SmishingClassifier {

    // MARK: Offline decision

    /// Returns a decisive `ILMessageFilterAction` for clear cases, or `nil`
    /// when the message is ambiguous (the caller then delivers it normally).
    static func decisiveAction(body rawBody: String, sender: String) -> ILMessageFilterAction? {
        let body = rawBody.lowercased()
        if body.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            // ILMessageFilterAction.none, spelled out: in this function's
            // optional return type a bare `.none` would be nil ("unsure").
            return ILMessageFilterAction.none // nothing to classify: deliver normally
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
            return ILMessageFilterAction.none
        }

        // --- Uncertain: the caller delivers it normally ---------------------
        return nil
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
