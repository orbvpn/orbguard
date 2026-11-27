// GlancePopoverView.swift - OrbGuard macOS
//
// The glance as the Dart side sends it over com.orb.guard/glance (the map is
// worked out in lib/services/home/glance.dart), and the menu bar popover that
// draws it. The native side draws only what it is given and adds the time of a
// check. It never invents a state, a score or a time.

import AppKit
import SwiftUI

// MARK: - The glance

struct GlanceEvent: Equatable {
  let kind: String   // check | blocked | breach
  let text: String
  let at: Date?      // nil: a count for today with no single moment
}

struct Glance: Equatable {
  let moment: String        // fresh | clear | gap
  let title: String
  let line: String?
  let score: Int?
  let gaps: [Double]
  let ring: String          // fresh | open | still
  let checkedAt: Date?
  let staleAt: Date?
  let staleTitle: String?
  let staleLine: String?
  let headline: String
  let proof: String?
  let events: [GlanceEvent]

  // MARK: Decoding (standard method codec values, or the same map read back from JSON)

  private static func int64(_ v: Any?) -> Int64? {
    if let n = v as? NSNumber { return n.int64Value }
    return nil
  }
  private static func date(_ v: Any?) -> Date? {
    int64(v).map { Date(timeIntervalSince1970: Double($0) / 1000) }
  }
  private static func string(_ v: Any?) -> String? { v as? String }
  private static func doubles(_ v: Any?) -> [Double] {
    if let list = v as? [Any] { return list.compactMap { ($0 as? NSNumber)?.doubleValue } }
    return []
  }

  init?(map: [String: Any]) {
    guard let moment = map["moment"] as? String,
      let title = map["title"] as? String,
      let ring = map["ring"] as? String
    else { return nil }
    self.moment = moment
    self.title = title
    self.ring = ring
    line = Self.string(map["line"])
    score = Self.int64(map["score"]).map { Int($0) }
    gaps = Self.doubles(map["gaps"])
    checkedAt = Self.date(map["checkedAt"])
    staleAt = Self.date(map["staleAt"])
    staleTitle = Self.string(map["staleTitle"])
    staleLine = Self.string(map["staleLine"])
    headline = Self.string(map["headline"]) ?? title
    proof = Self.string(map["proof"])
    events = (map["events"] as? [Any] ?? []).compactMap { raw in
      guard let e = raw as? [String: Any], let kind = e["kind"] as? String, let text = e["text"] as? String
      else { return nil }
      return GlanceEvent(kind: kind, text: text, at: Self.date(e["at"]))
    }
  }

  /// JSON-safe copy of the map, for storing the last glance across launches.
  var jsonMap: [String: Any] {
    func ms(_ d: Date?) -> Any { d.map { NSNumber(value: Int64(($0.timeIntervalSince1970 * 1000).rounded())) } ?? NSNull() }
    return [
      "v": 1,
      "moment": moment, "title": title, "line": line ?? NSNull(),
      "score": score.map { NSNumber(value: $0) } ?? NSNull(),
      "gaps": gaps, "ring": ring,
      "checkedAt": ms(checkedAt), "staleAt": ms(staleAt),
      "staleTitle": staleTitle ?? NSNull(), "staleLine": staleLine ?? NSNull(),
      "headline": headline, "proof": proof ?? NSNull(),
      "events": events.map { ["kind": $0.kind, "text": $0.text, "at": ms($0.at)] },
    ]
  }

  // MARK: What to show at a given moment

  func isStale(at now: Date) -> Bool { staleAt.map { now >= $0 } ?? false }

  /// The score, unless the reading has gone stale.
  func shownScore(at now: Date) -> Int? { isStale(at: now) ? nil : score }

  /// Few words (menu bar tooltip): staleTitle replaces title once stale.
  func shownTitle(at now: Date) -> String {
    if isStale(at: now), let staleTitle { return staleTitle }
    return title
  }

  /// The popover's big line. Once stale with a stale title, the stale words take over,
  /// because Home's headline spoke for a reading that is now old.
  func shownHeadline(at now: Date) -> String {
    if isStale(at: now), let staleTitle { return staleTitle }
    return headline
  }
  func shownProof(at now: Date) -> String? {
    if isStale(at: now), staleTitle != nil { return staleLine }
    return proof
  }

  var ringMode: GlanceRingMode {
    switch ring {
    case "fresh": return .fresh
    case "still": return .band(gaps: gaps, still: true)
    default: return .band(gaps: gaps, still: false)
    }
  }
}

// MARK: - Times

enum GlanceTime {
  /// Clock time in the system's own format when `date` is today (local), else a
  /// short date such as "22 Nov".
  static func label(_ date: Date, now: Date = Date(), calendar: Calendar = .current) -> String {
    let f = DateFormatter()
    f.locale = .current
    if calendar.isDate(date, inSameDayAs: now) {
      f.dateStyle = .none
      f.timeStyle = .short
    } else {
      f.setLocalizedDateFormatFromTemplate("d MMM")
    }
    return f.string(from: date)
  }

  /// "Checked 09:41" or "Checked 22 Nov".
  static func checked(_ date: Date, now: Date = Date()) -> String { "Checked " + label(date, now: now) }

  static func nextMidnight(after now: Date, calendar: Calendar = .current) -> Date {
    calendar.nextDate(after: now, matching: DateComponents(hour: 0, minute: 0, second: 0), matchingPolicy: .nextTime)
      ?? now.addingTimeInterval(86_400)
  }
}

// MARK: - Popover model and view

final class GlancePopoverModel: ObservableObject {
  @Published var glance: Glance?
  @Published var now = Date()
  init(glance: Glance? = nil, now: Date = Date()) {
    self.glance = glance
    self.now = now
  }
}

/// Event row icons: the real Solar duotone art (Assets.xcassets, template PDFs).
enum GlanceIcons {
  /// Overridable for the offline renderer.
  static var loader: (String) -> NSImage? = { NSImage(named: $0) }

  static func image(for kind: String) -> NSImage? {
    let name: String
    switch kind {
    case "blocked": name = "glance_blocked"
    case "breach": name = "glance_breach"
    default: name = "glance_check"
    }
    let img = loader(name)
    img?.isTemplate = true
    return img
  }
}

struct GlanceRingView: View {
  let mode: GlanceRingMode
  let score: Int?
  let size: CGFloat
  let dark: Bool

  var body: some View {
    let reach = size * GlanceRingPainter.bloomReach
    let canvas = max(size, 2 * reach)
    let brand = GlanceBrand(dark: dark)
    ZStack {
      Canvas { ctx, sz in
        ctx.withCGContext { cg in
          GlanceRingPainter.draw(
            in: cg, center: CGPoint(x: sz.width / 2, y: sz.height / 2), diameter: size,
            mode: mode, brand: brand, bloom: true)
        }
      }
      .frame(width: canvas, height: canvas)
      .allowsHitTesting(false)
      if let score {
        Text(String(score))
          .font(Font(GlanceFonts.archivo(size * 0.158, weight: 700)))
          .monospacedDigit()
          .foregroundColor(Color(nsColor: brand.text))
      }
    }
    .frame(width: size, height: size)
  }
}

struct GlancePopoverView: View {
  @ObservedObject var model: GlancePopoverModel
  var onCheckNow: () -> Void = {}
  var onOpen: () -> Void = {}
  @Environment(\.colorScheme) private var scheme

  static let width: CGFloat = 340
  private var brand: GlanceBrand { GlanceBrand(dark: scheme == .dark) }
  private func c(_ ns: NSColor) -> Color { Color(nsColor: ns) }

  var body: some View {
    card
      .padding(12)
      .frame(width: Self.width)
      .background(c(brand.bg).ignoresSafeArea())
  }

  @ViewBuilder private var card: some View {
    if let glance = model.glance {
      reading(glance).modifier(GlassCard(brand: brand))
    } else {
      // Before the first glance ever: the mark and "Open OrbGuard", nothing else.
      Button(action: onOpen) {
        HStack(spacing: 14) {
          GlanceRingView(mode: .logo, score: nil, size: 76, dark: scheme == .dark)
          Text("Open OrbGuard")
            .font(Font(GlanceFonts.plexSans(16, weight: 600)))
            .tracking(-0.2)
            .foregroundColor(c(brand.text))
          Spacer(minLength: 0)
        }
        .contentShape(Rectangle())
      }
      .buttonStyle(.plain)
      .modifier(GlassCard(brand: brand))
    }
  }

  private func reading(_ g: Glance) -> some View {
    let now = model.now
    let rows = Array(g.events.prefix(2))
    return VStack(alignment: .leading, spacing: 12) {
      HStack(alignment: .center, spacing: 14) {
        GlanceRingView(mode: g.ringMode, score: g.shownScore(at: now), size: 76, dark: scheme == .dark)
        VStack(alignment: .leading, spacing: 3) {
          Text(g.shownHeadline(at: now))
            .font(Font(GlanceFonts.plexSans(16, weight: 600)))
            .tracking(-0.2)
            .lineSpacing(2)
            .foregroundColor(c(brand.text))
            .fixedSize(horizontal: false, vertical: true)
          if let proof = g.shownProof(at: now) {
            Text(proof)
              .font(Font(GlanceFonts.plexSans(13.5)))
              .lineSpacing(2)
              .foregroundColor(c(brand.text2))
              .fixedSize(horizontal: false, vertical: true)
          }
        }
        Spacer(minLength: 0)
      }

      if !rows.isEmpty {
        VStack(spacing: 0) {
          ForEach(Array(rows.enumerated()), id: \.offset) { i, e in
            if i > 0 { Rectangle().fill(c(brand.hairline)).frame(height: 1) }
            eventRow(e, now: now)
          }
        }
      }

      Button(action: onCheckNow) {
        Text("Check now")
          .font(Font(GlanceFonts.plexSans(15, weight: 600)))
          .tracking(-0.2)
          .foregroundColor(c(brand.onLime))
          .frame(maxWidth: .infinity)
          .frame(height: 44)
          .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(c(brand.lime)))
          .shadow(color: c(brand.limeGlow), radius: 10, x: 0, y: 6)
          .contentShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
      }
      .buttonStyle(.plain)
      .keyboardShortcut(.defaultAction)
    }
  }

  private func eventRow(_ e: GlanceEvent, now: Date) -> some View {
    HStack(spacing: 10) {
      if let icon = GlanceIcons.image(for: e.kind) {
        Image(nsImage: icon)
          .renderingMode(.template)
          .resizable()
          .frame(width: 17, height: 17)
          .foregroundColor(c(brand.limeInk))
      }
      Text(e.text)
        .font(Font(GlanceFonts.plexSans(13.5)))
        .foregroundColor(c(brand.text))
        .lineLimit(2)
        .frame(maxWidth: .infinity, alignment: .leading)
      if let at = e.at {
        Text(GlanceTime.label(at, now: now))
          .font(Font(GlanceFonts.plexMono(11.5)))
          .monospacedDigit()
          .foregroundColor(c(brand.text2))
      }
    }
    .padding(.vertical, 9)
  }
}

/// BrandGlass: a brighter top 15 px over the glass fill, a hairline border, a top rim.
private struct GlassCard: ViewModifier {
  let brand: GlanceBrand
  func body(content: Content) -> some View {
    let shape = RoundedRectangle(cornerRadius: 18, style: .continuous)
    return content
      .padding(14)
      .background(
        GeometryReader { geo in
          let top = min(15 / max(geo.size.height, 1), 1)
          shape.fill(
            LinearGradient(
              stops: [
                .init(color: Color(nsColor: brand.glassTop), location: 0),
                .init(color: Color(nsColor: brand.glassFill), location: top),
                .init(color: Color(nsColor: brand.glassFill), location: 1),
              ],
              startPoint: .top, endPoint: .bottom))
        }
      )
      .overlay(shape.strokeBorder(Color(nsColor: brand.glassBorder), lineWidth: 1))
      .overlay(alignment: .top) {
        // The top rim: 1 px of light just inside the upper edge.
        Rectangle().fill(Color(nsColor: brand.glassRim)).frame(height: 1)
          .padding(.horizontal, 14).padding(.top, 1)
      }
      .shadow(color: Color(nsColor: brand.shadow).opacity(0.5), radius: 12, x: 0, y: 8)
  }
}
