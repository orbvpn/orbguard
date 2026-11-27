// GlanceLogic.swift - OrbGuard widget
//
// The pure half of the glance: the stored map, what words and numbers show at
// a given moment, the check time, the stale rule, the ring's arcs and the
// redraw moments. Foundation only (no SwiftUI, no WidgetKit), so it can be
// compiled and checked outside the extension.
//
// The Dart side (lib/services/home/glance.dart) decides the glance from the
// same data Home draws. This file draws it as given and adds only the time of
// the check. It never invents a state: anything it cannot read is treated as
// "no reading yet" (the logo and `Open OrbGuard`).

import Foundation

// MARK: - Storage

/// Where the host app leaves the latest glance and the widget reads it.
/// Runner's GlanceChannelHandler writes the same suite and key.
enum GlanceStore {
    static let suiteName = "group.com.orb.guard.shared"
    static let key = "glance.v1"

    /// The latest glance, or nil when the app has never sent one (or it cannot be read).
    static func load(from defaults: UserDefaults? = UserDefaults(suiteName: suiteName)) -> Glance? {
        guard let data = defaults?.data(forKey: key) else { return nil }
        return Glance.decode(data)
    }
}

// MARK: - The map

enum GlanceMoment: String {
    case fresh, clear, gap
}

enum GlanceRing: String {
    /// Never checked: dots on the centre line.
    case fresh
    /// The band, cut at each gap.
    case open
    /// The band greyed: nothing on watch.
    case still
}

/// The channel's map (`com.orb.guard/glance`, version 1).
struct Glance: Equatable {
    var moment: GlanceMoment
    var title: String
    var line: String?
    var score: Int?
    var gaps: [Double]
    var ring: GlanceRing
    var checkedAt: Date?
    var staleAt: Date?
    var staleTitle: String?
    var staleLine: String?

    /// Reads the JSON the host app stored. Returns nil for anything that is not
    /// a version 1 map with a known moment and ring, so a broken or future
    /// payload falls back to the logo rather than to a guessed state.
    static func decode(_ data: Data) -> Glance? {
        guard let object = try? JSONSerialization.jsonObject(with: data),
              let map = object as? [String: Any] else { return nil }
        return Glance(map: map)
    }

    init?(map: [String: Any]) {
        guard Self.number(map["v"]).map({ Int($0) }) == 1,
              let moment = (map["moment"] as? String).flatMap(GlanceMoment.init(rawValue:)),
              let ring = (map["ring"] as? String).flatMap(GlanceRing.init(rawValue:)),
              let title = map["title"] as? String, !title.isEmpty
        else { return nil }
        self.moment = moment
        self.ring = ring
        self.title = title
        self.line = Self.text(map["line"])
        self.score = Self.number(map["score"]).map { Int($0.rounded()) }
        self.gaps = (map["gaps"] as? [Any] ?? []).compactMap(Self.number)
        self.checkedAt = Self.number(map["checkedAt"]).map(Self.date(ms:))
        self.staleAt = Self.number(map["staleAt"]).map(Self.date(ms:))
        self.staleTitle = Self.text(map["staleTitle"])
        self.staleLine = Self.text(map["staleLine"])
    }

    init(moment: GlanceMoment, title: String, line: String? = nil, score: Int? = nil,
         gaps: [Double] = [], ring: GlanceRing, checkedAt: Date? = nil, staleAt: Date? = nil,
         staleTitle: String? = nil, staleLine: String? = nil) {
        self.moment = moment
        self.title = title
        self.line = line
        self.score = score
        self.gaps = gaps
        self.ring = ring
        self.checkedAt = checkedAt
        self.staleAt = staleAt
        self.staleTitle = staleTitle
        self.staleLine = staleLine
    }

    static func date(ms: Double) -> Date { Date(timeIntervalSince1970: ms / 1000) }

    private static func number(_ value: Any?) -> Double? {
        // JSONSerialization hands back NSNumber; a Bool is an NSNumber too, so
        // keep it out.
        guard let n = value as? NSNumber, CFGetTypeID(n) != CFBooleanGetTypeID() else { return nil }
        let d = n.doubleValue
        return d.isFinite ? d : nil
    }

    private static func text(_ value: Any?) -> String? {
        guard let s = value as? String, !s.isEmpty else { return nil }
        return s
    }
}

// MARK: - What shows at a moment

/// Everything a widget draws at one instant. Built only from the map, plus the
/// check time.
struct GlanceFace: Equatable {
    /// No reading yet: the logo mark and `Open OrbGuard`, nothing else.
    var isPlaceholder: Bool
    var title: String
    /// The line under the title: the map's line (or stale line). Nil when the
    /// map gives none.
    var line: String?
    /// `Checked 09:41` / `Checked 22 Nov`, when the map gives a check time.
    var checked: String?
    /// The check time alone (`09:41`, `22 Nov`), for `..., checked 09:41`.
    var checkTime: String?
    /// The score for the hole, or nil (before a check, and after staleAt).
    var score: Int?
    var ring: GlanceRing
    var gaps: [Double]
    /// The amber `Open OrbGuard` chip: something waits, or no check has run.
    var showsChip: Bool
    var isStale: Bool

    static let openOrbGuard = "Open OrbGuard"

    static let placeholder = GlanceFace(
        isPlaceholder: true, title: openOrbGuard, line: nil, checked: nil, checkTime: nil,
        score: nil, ring: .fresh, gaps: [], showsChip: false, isStale: false)

    /// The one line the medium widget shows under the title: the map's line,
    /// else the check time.
    var detail: String? { line ?? checked }

    /// The lock screen's summary line: `All clear, checked 09:41` when the map
    /// gives no line, otherwise the title alone (the line goes under it).
    var lockSummary: String {
        if line == nil, let time = checkTime { return "\(title), checked \(time)" }
        return title
    }
}

enum GlanceLogic {

    /// From `staleAt` on, the reading is old: no score, and the stale words.
    static func isStale(_ glance: Glance, at now: Date) -> Bool {
        guard let staleAt = glance.staleAt else { return false }
        return now >= staleAt
    }

    /// The check time in the system's own format: the clock time when it is
    /// today (local), a short date otherwise.
    static func checkTime(_ checkedAt: Date, now: Date, calendar: Calendar = .current,
                          locale: Locale = .current) -> String {
        let formatter = DateFormatter()
        formatter.locale = locale
        formatter.calendar = calendar
        formatter.timeZone = calendar.timeZone
        if calendar.isDate(checkedAt, inSameDayAs: now) {
            formatter.dateStyle = .none
            formatter.timeStyle = .short
        } else {
            formatter.setLocalizedDateFormatFromTemplate("dMMM")
        }
        return formatter.string(from: checkedAt)
    }

    static func face(for glance: Glance?, at now: Date, calendar: Calendar = .current,
                     locale: Locale = .current) -> GlanceFace {
        guard let glance else { return .placeholder }
        let stale = isStale(glance, at: now)
        let useStaleWords = stale && glance.staleTitle != nil
        let time = glance.checkedAt.map { checkTime($0, now: now, calendar: calendar, locale: locale) }
        return GlanceFace(
            isPlaceholder: false,
            title: useStaleWords ? glance.staleTitle! : glance.title,
            line: useStaleWords ? glance.staleLine : glance.line,
            checked: time.map { "Checked \($0)" },
            checkTime: time,
            score: stale ? nil : glance.score,
            ring: glance.ring,
            gaps: glance.ring == .fresh ? [] : glance.gaps,
            showsChip: glance.moment == .gap || glance.moment == .fresh,
            isStale: stale)
    }

    // MARK: Redraws

    static func nextMidnight(after now: Date, calendar: Calendar = .current) -> Date {
        let start = calendar.startOfDay(for: now)
        return calendar.date(byAdding: .day, value: 1, to: start) ?? now.addingTimeInterval(86_400)
    }

    /// The moments a widget must be drawn: now, at staleAt (when still ahead)
    /// and at the next local midnight, so "today" stays true.
    static func timelineDates(for glance: Glance?, now: Date, calendar: Calendar = .current) -> [Date] {
        guard let glance else { return [now] }
        var dates = [now, nextMidnight(after: now, calendar: calendar)]
        if let staleAt = glance.staleAt, staleAt > now { dates.append(staleAt) }
        return Array(Set(dates)).sorted()
    }
}

// MARK: - The ring's arithmetic (from app/lib/widgets/home/orb_ring.dart)

/// One arc of the band, degrees clockwise from twelve o'clock.
struct OrbArc: Equatable {
    var start: Double
    var sweep: Double
    var isWhole: Bool { sweep >= 360 }
}

/// All numbers on a 200 unit box centred on the ring.
enum OrbGeometry {
    static let box: Double = 200
    static let outer: Double = 96
    static let inner: Double = 52
    static let centre: Double = (outer + inner) / 2        // 74
    static let thickness: Double = outer - inner           // 44
    /// Degrees a round end reaches past the arc it caps (17.03).
    static let capDegrees: Double = (thickness / 2) / centre * 180 / .pi
    /// Daylight between the two round ends of a gap.
    static let gapOpening: Double = 15
    /// How far either side of its centre a gap is cut on the centre line (24.53).
    static let gapHalf: Double = gapOpening / 2 + capDegrees
    /// Radius of the amber dot at a gap.
    static let sparkRadius: Double = 4.6
    /// Radius of each dot of a never-checked ring.
    static let dotRadius: Double = 1.6

    /// The band, broken where the gaps are: one arc from each gap's far side
    /// to the next gap's near side. No gaps: one whole circle.
    static func body(_ gaps: [Double]) -> [OrbArc] {
        let at = Array(Set(gaps.map(onDial))).sorted()
        if at.isEmpty { return [OrbArc(start: 0, sweep: 360)] }
        var arcs: [OrbArc] = []
        for i in at.indices {
            let last = i == at.count - 1
            let next = last ? at[0] + 360 : at[i + 1]
            let from = at[i] + gapHalf
            let to = next - gapHalf
            arcs.append(OrbArc(start: from, sweep: to - from))
        }
        return arcs
    }

    /// Dots for a never-checked ring: 51, fewer at very small sizes (about 12 at 16 points).
    static func dotCount(forSize size: Double) -> Int {
        min(51, max(12, Int((size * 0.75).rounded())))
    }

    static func onDial(_ degrees: Double) -> Double {
        let d = degrees.truncatingRemainder(dividingBy: 360)
        return d < 0 ? d + 360 : d
    }
}

// MARK: - Colour

/// An sRGB colour with alpha, 0 to 1.
struct RGBA: Equatable {
    var r: Double, g: Double, b: Double, a: Double

    init(_ r: Double, _ g: Double, _ b: Double, _ a: Double = 1) {
        self.r = r; self.g = g; self.b = b; self.a = a
    }

    init(hex: UInt32, alpha: Double = 1) {
        self.init(Double((hex >> 16) & 0xFF) / 255, Double((hex >> 8) & 0xFF) / 255,
                  Double(hex & 0xFF) / 255, alpha)
    }

    func opacity(_ a: Double) -> RGBA { RGBA(r, g, b, a) }

    /// CSS saturate(.12) then brightness(.82): the band with nothing on watch.
    /// Same matrix as OrbRing's still filter.
    var still: RGBA {
        RGBA(min(1, 0.2521 * r + 0.5159 * g + 0.0520 * b),
             min(1, 0.1537 * r + 0.6143 * g + 0.0520 * b),
             min(1, 0.1537 * r + 0.5159 * g + 0.1504 * b), a)
    }
}

/// The brand kit's colours for one appearance (OrbVPN 2026).
struct GlancePalette {
    let dark: Bool

    var bg: RGBA { dark ? RGBA(hex: 0x08080A) : RGBA(hex: 0xF4F5F1) }
    var surface: RGBA { dark ? RGBA(hex: 0x131316) : RGBA(hex: 0xFFFFFF) }
    var text: RGBA { dark ? RGBA(hex: 0xF5F6F8) : RGBA(hex: 0x0B0B0E) }
    var text2: RGBA { dark ? RGBA(hex: 0x9A9CA6) : RGBA(hex: 0x5A5C66) }
    var text3: RGBA { dark ? RGBA(hex: 0x6F717C) : RGBA(hex: 0x8A8C96) }
    var hairline: RGBA { dark ? RGBA(1, 1, 1, 0.08) : RGBA(hex: 0x12121C, alpha: 0.07) }

    var amber: RGBA { RGBA(hex: 0xFFB800) }
    var amberText: RGBA { dark ? RGBA(hex: 0xFFB800) : RGBA(hex: 0x8A6500) }
    var amberPill: RGBA { RGBA(hex: 0xFFB800, alpha: dark ? 0.12 : 0.16) }

    /// The ring body's six even stops, lit edge to deep edge.
    var orbFill: [RGBA] {
        (dark
            ? [0xF6FFDA, 0xE6FBAE, 0xCDF57A, 0xA9E36C, 0x86CB6B, 0x63AD5C]
            : [0xF2FCD0, 0xE0F4B0, 0xC4E896, 0xA0D87C, 0x84C86C, 0x68B060]
        ).map { RGBA(hex: $0) }
    }

    /// The logo's own ramp (assets/branding/orbguard_icon.svg).
    var logoFill: [RGBA] {
        [0xF2FCD0, 0xE0F4B0, 0xC4E896, 0xA0D87C, 0x84C86C, 0x68B060].map { RGBA(hex: $0) }
    }

    var orbTrack: RGBA { dark ? RGBA(1, 1, 1, 0.065) : RGBA(hex: 0x12121C, alpha: 0.06) }
    var orbGlow: RGBA { dark ? RGBA(hex: 0xBEFA50, alpha: 0.30) : RGBA(hex: 0x96D25A, alpha: 0.34) }
    var orbShadow: RGBA { RGBA(hex: 0x6A9858, alpha: dark ? 0.45 : 0.42) }
    var orbDepth: RGBA { RGBA(hex: 0x12300A) }
    var dots: RGBA { text3.opacity(0.9) }

    /// The bloom's strength: 0.86 when checked, 0.25 when fresh or still.
    static func bloom(for ring: GlanceRing) -> Double {
        ring == .open ? 0.86 : 0.25
    }
}
