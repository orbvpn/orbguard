// GlanceRing.swift - OrbGuard macOS
//
// The glance's look on the native side: the OrbVPN 2026 brand tokens, the
// bundled brand fonts, and the ring drawn exactly as Home draws it
// (lib/widgets/home/orb_ring.dart). Used by the menu bar item (16 to 18 pt)
// and by the popover (76 pt). No Flutter import, so it renders on its own.

import AppKit
import CoreText

// MARK: - Brand tokens

/// The kit's values for one appearance. Nothing outside this struct picks a colour.
struct GlanceBrand {
  let dark: Bool

  static func rgb(_ hex: UInt32, _ alpha: CGFloat = 1) -> NSColor {
    NSColor(
      srgbRed: CGFloat((hex >> 16) & 0xFF) / 255,
      green: CGFloat((hex >> 8) & 0xFF) / 255,
      blue: CGFloat(hex & 0xFF) / 255,
      alpha: alpha)
  }

  var bg: NSColor { dark ? Self.rgb(0x08080A) : Self.rgb(0xF4F5F1) }
  var text: NSColor { dark ? Self.rgb(0xF5F6F8) : Self.rgb(0x0B0B0E) }
  var text2: NSColor { dark ? Self.rgb(0x9A9CA6) : Self.rgb(0x5A5C66) }
  var text3: NSColor { dark ? Self.rgb(0x6F717C) : Self.rgb(0x8A8C96) }
  var hairline: NSColor { dark ? Self.rgb(0xFFFFFF, 0.08) : Self.rgb(0x12121C, 0.07) }

  // Glass (BrandGlass): fill, a brighter top 15 px, a hairline border and a top rim.
  var glassFill: NSColor { dark ? Self.rgb(0xFFFFFF, 0.08) : Self.rgb(0xFFFFFF, 0.55) }
  var glassTop: NSColor { dark ? Self.rgb(0xFFFFFF, 0.17) : Self.rgb(0xFFFFFF, 0.80) }
  var glassBorder: NSColor { dark ? Self.rgb(0xFFFFFF, 0.18) : Self.rgb(0x12121C, 0.08) }
  var glassRim: NSColor { dark ? Self.rgb(0xFFFFFF, 0.35) : Self.rgb(0xFFFFFF, 0.90) }
  var shadow: NSColor { dark ? Self.rgb(0x000000, 0.45) : Self.rgb(0x14142D, 0.12) }

  // Volt lime is a fill only; lime-coloured marks use limeInk.
  var lime: NSColor { Self.rgb(0xC6FF3D) }
  var onLime: NSColor { Self.rgb(0x08080A) }
  var limeInk: NSColor { dark ? Self.rgb(0xC6FF3D) : Self.rgb(0x4A7000) }
  var limeGlow: NSColor { dark ? Self.rgb(0xC6FF3D, 0.26) : Self.rgb(0x96C414, 0.30) }
  var amber: NSColor { Self.rgb(0xFFB800) }

  // The ring.
  var track: NSColor { dark ? Self.rgb(0xFFFFFF, 0.065) : Self.rgb(0x12121C, 0.06) }
  var orbStops: [NSColor] {
    dark
      ? [0xF6FFDA, 0xE6FBAE, 0xCDF57A, 0xA9E36C, 0x86CB6B, 0x63AD5C].map { Self.rgb($0) }
      : [0xF2FCD0, 0xE0F4B0, 0xC4E896, 0xA0D87C, 0x84C86C, 0x68B060].map { Self.rgb($0) }
  }
  var bloom: NSColor { dark ? Self.rgb(0xBEFA50, 0.30) : Self.rgb(0x96D25A, 0.34) }
  /// The logo mark's own ramp (assets/branding/orbguard_icon.svg), same in both themes.
  static let logoStops: [NSColor] =
    [0xF2FCD0, 0xE0F4B0, 0xC4E896, 0xA0D87C, 0x84C86C, 0x68B060].map { rgb($0) }

  static func isDark(_ appearance: NSAppearance) -> Bool {
    appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
  }
}

// MARK: - Brand fonts

/// Archivo, IBM Plex Sans and IBM Plex Mono, read from the fonts Flutter already
/// bundles (App.framework/.../flutter_assets/assets/fonts), so nothing is shipped
/// twice. Archivo and Plex Sans are variable: the weight is set on the wght axis.
/// Falls back to the system font only if the files are missing.
enum GlanceFonts {

  /// Overridable for the offline renderer; the app reads Flutter's asset folder.
  static var directory: URL? = {
    guard let frameworks = Bundle.main.privateFrameworksURL else { return nil }
    let dir = frameworks.appendingPathComponent(
      "App.framework/Resources/flutter_assets/assets/fonts", isDirectory: true)
    return FileManager.default.fileExists(atPath: dir.path) ? dir : nil
  }()

  private static var descriptors: [String: CTFontDescriptor] = [:]
  private static let wght = NSNumber(value: 0x7767_6874)  // 'wght'

  private static func descriptor(_ file: String) -> CTFontDescriptor? {
    if let cached = descriptors[file] { return cached }
    guard let url = directory?.appendingPathComponent(file),
      FileManager.default.fileExists(atPath: url.path),
      let list = CTFontManagerCreateFontDescriptorsFromURL(url as CFURL) as? [CTFontDescriptor],
      let first = list.first
    else { return nil }
    descriptors[file] = first
    return first
  }

  private static func font(_ file: String, size: CGFloat, weight: CGFloat?, fallback: NSFont.Weight) -> NSFont {
    guard var d = descriptor(file) else { return .systemFont(ofSize: size, weight: fallback) }
    if let weight {
      d = CTFontDescriptorCreateCopyWithVariation(d, wght, weight)
    }
    return CTFontCreateWithFontDescriptor(d, size, nil) as NSFont
  }

  /// Titles and numerals.
  static func archivo(_ size: CGFloat, weight: CGFloat = 700) -> NSFont {
    font("Archivo-Variable.ttf", size: size, weight: weight, fallback: .bold)
  }
  /// Body and UI text.
  static func plexSans(_ size: CGFloat, weight: CGFloat = 400) -> NSFont {
    font("IBMPlexSans-Variable.ttf", size: size, weight: weight, fallback: weight >= 600 ? .semibold : .regular)
  }
  /// Tiny labels and times.
  static func plexMono(_ size: CGFloat) -> NSFont {
    font("IBMPlexMono-Medium.ttf", size: size, weight: nil, fallback: .medium)
  }
}

// MARK: - The ring

/// What the ring shows. `logo` is the mark before any glance has arrived.
enum GlanceRingMode: Equatable {
  case logo
  case fresh
  case band(gaps: [Double], still: Bool)
}

/// Draws the ring on a 200 unit box centred on the ring (the logo on its own
/// 100 unit box), scaled to `diameter`. The context must be y-down (flipped).
enum GlanceRingPainter {

  // Geometry, in the ring's 200 unit box.
  static let r: CGFloat = 74          // centre line
  static let w: CGFloat = 44          // band thickness
  static let gapHalf: Double = 24.53  // centre-line cut each side of a gap
  static let sparkR: CGFloat = 4.6
  static let dotR: CGFloat = 1.6

  /// Radius of the bloom behind the ring as a share of `diameter`, so callers can
  /// leave room for it.
  static let bloomReach: CGFloat = 0.7

  /// saturate(.12) then brightness(.82), as orb_ring.dart's _stillFilter.
  private static func still(_ c: NSColor) -> NSColor {
    let s = c.usingColorSpace(.sRGB) ?? c
    let r = s.redComponent, g = s.greenComponent, b = s.blueComponent
    return NSColor(
      srgbRed: 0.2521 * r + 0.5159 * g + 0.0520 * b,
      green: 0.1537 * r + 0.6143 * g + 0.0520 * b,
      blue: 0.1537 * r + 0.5159 * g + 0.1504 * b,
      alpha: s.alphaComponent)
  }

  private static func gradient(_ colors: [NSColor]) -> CGGradient {
    let locs: [CGFloat] = colors.indices.map { CGFloat($0) / CGFloat(max(colors.count - 1, 1)) }
    return CGGradient(
      colorsSpace: CGColorSpace(name: CGColorSpace.sRGB),
      colors: colors.map { $0.cgColor } as CFArray,
      locations: locs)!
  }

  /// Angle in the y-down unit box: degrees clockwise from twelve o'clock.
  private static func rad(_ fromTop: Double) -> CGFloat { CGFloat((fromTop - 90) * .pi / 180) }
  private static func point(_ fromTop: Double, _ radius: CGFloat) -> CGPoint {
    CGPoint(x: radius * cos(rad(fromTop)), y: radius * sin(rad(fromTop)))
  }

  /// The band's centre line: one whole circle, or the arcs between gaps.
  static func centreLine(gaps: [Double]) -> CGPath {
    let path = CGMutablePath()
    let sorted = gaps.map { ($0.truncatingRemainder(dividingBy: 360) + 360).truncatingRemainder(dividingBy: 360) }.sorted()
    if sorted.isEmpty {
      path.addEllipse(in: CGRect(x: -r, y: -r, width: 2 * r, height: 2 * r))
      return path
    }
    for (i, g) in sorted.enumerated() {
      let next = i + 1 < sorted.count ? sorted[i + 1] : sorted[0] + 360
      let start = g + gapHalf, end = next - gapHalf
      guard end > start else { continue }  // two gaps too close: no arc between them
      let sub = CGMutablePath()
      sub.addArc(center: .zero, radius: r, startAngle: rad(start), endAngle: rad(end), clockwise: false)
      path.addPath(sub)
    }
    return path
  }

  /// - Parameters:
  ///   - center: ring centre in the context's points.
  ///   - diameter: the ring's 200 unit box in points.
  ///   - bloom: draw the glow behind it (off in the menu bar).
  static func draw(
    in cg: CGContext, center: CGPoint, diameter: CGFloat, mode: GlanceRingMode,
    brand: GlanceBrand, bloom: Bool
  ) {
    cg.saveGState()
    defer { cg.restoreGState() }
    let small = diameter < 40

    if bloom, mode != .logo {
      let strength: CGFloat
      if case .band(_, let isStill) = mode, !isStill { strength = 0.86 } else { strength = 0.25 }
      let glow = brand.bloom
      let a = glow.alphaComponent * strength
      let grad = CGGradient(
        colorsSpace: CGColorSpace(name: CGColorSpace.sRGB),
        colors: [glow.withAlphaComponent(a).cgColor, glow.withAlphaComponent(0).cgColor] as CFArray,
        locations: [0, 0.74])!
      cg.drawRadialGradient(
        grad, startCenter: center, startRadius: 0, endCenter: center,
        endRadius: diameter * bloomReach, options: [])
    }

    cg.translateBy(x: center.x, y: center.y)

    if mode == .logo {
      // orbguard_icon.svg: circle r 34, stroke 22, in a 100 box; ramp centred at (38, 38) r 62.
      let u = diameter / 100
      cg.scaleBy(x: u, y: u)
      cg.addEllipse(in: CGRect(x: -34, y: -34, width: 68, height: 68))
      cg.setLineWidth(22)
      cg.replacePathWithStrokedPath()
      cg.clip()
      cg.drawRadialGradient(
        gradient(GlanceBrand.logoStops), startCenter: CGPoint(x: -12, y: -12), startRadius: 0,
        endCenter: CGPoint(x: -12, y: -12), endRadius: 62, options: [.drawsAfterEndLocation])
      return
    }

    let u = diameter / 200
    cg.scaleBy(x: u, y: u)

    // The track: a full circle under everything.
    cg.setStrokeColor(brand.track.cgColor)
    cg.setLineWidth(w)
    cg.strokeEllipse(in: CGRect(x: -r, y: -r, width: 2 * r, height: 2 * r))

    switch mode {
    case .logo:
      break

    case .fresh:
      // No band: dots on the centre line. Fewer, relatively larger dots when tiny,
      // so they still read as dots at 16 px.
      let count = small ? 12 : Int((2 * .pi * r / 9.1).rounded())
      let dot = small ? max(dotR, 0.8 / u) : dotR
      cg.setFillColor(brand.text3.withAlphaComponent(0.9).cgColor)
      for i in 0..<count {
        let p = point(Double(i) * 360 / Double(count), r)
        cg.fillEllipse(in: CGRect(x: p.x - dot, y: p.y - dot, width: 2 * dot, height: 2 * dot))
      }

    case .band(let gaps, let isStill):
      let line = centreLine(gaps: gaps)
      let ramp = isStill ? brand.orbStops.map(still) : brand.orbStops

      cg.saveGState()
      cg.addPath(line)
      cg.setLineWidth(w)
      cg.setLineCap(.round)
      cg.replacePathWithStrokedPath()
      cg.clip()
      // Body: the logo's ramp, centred up and left of the ring's centre.
      cg.drawRadialGradient(
        gradient(ramp), startCenter: CGPoint(x: -20, y: -22), startRadius: 0,
        endCenter: CGPoint(x: -20, y: -22), endRadius: 124, options: [.drawsAfterEndLocation])
      // Sheen from the top left, falling to shade at the bottom right.
      let sheen = CGGradient(
        colorsSpace: CGColorSpace(name: CGColorSpace.sRGB),
        colors: [
          NSColor(white: 1, alpha: 0.18).cgColor,
          NSColor(white: 1, alpha: 0).cgColor,
          NSColor(white: 0, alpha: 0.14).cgColor,
        ] as CFArray,
        locations: [0, 0.42, 1])!
      cg.drawLinearGradient(
        sheen, start: CGPoint(x: -80, y: -80), end: CGPoint(x: 80, y: 80),
        options: [.drawsBeforeStartLocation, .drawsAfterEndLocation])
      cg.restoreGState()

      // An amber spark where the circle is open. At menu bar size it is held at a
      // visible minimum so the gap still says "something waits".
      let spark = small ? max(sparkR, 0.95 / u) : sparkR
      cg.setFillColor(brand.amber.cgColor)
      for g in gaps {
        let p = point(g, r)
        cg.fillEllipse(in: CGRect(x: p.x - spark, y: p.y - spark, width: 2 * spark, height: 2 * spark))
      }
    }
  }

  /// The menu bar image. Drawn lazily so it follows the menu bar's own appearance.
  static func statusImage(mode: GlanceRingMode, side: CGFloat = 18, ring: CGFloat = 17) -> NSImage {
    let image = NSImage(size: NSSize(width: side, height: side), flipped: true) { rect in
      guard let cg = NSGraphicsContext.current?.cgContext else { return false }
      let brand = GlanceBrand(dark: GlanceBrand.isDark(NSAppearance.currentDrawing()))
      draw(in: cg, center: CGPoint(x: rect.midX, y: rect.midY), diameter: ring, mode: mode, brand: brand, bloom: false)
      return true
    }
    image.isTemplate = false
    return image
  }
}
