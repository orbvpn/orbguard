// OrbRingView.swift - OrbGuard widget
//
// The brand ring, drawn with SwiftUI Canvas from the numbers in
// app/lib/widgets/home/orb_ring.dart (a 200 unit box centred on the ring),
// at rest: widgets never animate. Also the logo mark for "no reading yet".
// Compiles on iOS and macOS (the macOS build is only for rendering checks).

import SwiftUI
import CoreText
#if os(iOS) && canImport(WidgetKit)
import WidgetKit
#endif

extension RGBA {
    var color: Color { Color(.sRGB, red: r, green: g, blue: b, opacity: a) }
}

// MARK: - Fonts

/// Archivo and IBM Plex Sans, bundled in the extension (and listed in its
/// UIAppFonts). Both are variable fonts, so weight and width are set on their
/// axes. The faces are read from the bundled files themselves, so a different
/// font of the same name can never stand in. Falls back to the system font
/// when a file is missing.
enum BrandFont {
    static let archivo = "Archivo-Variable"
    static let plexSans = "IBMPlexSans-Variable"

    /// Where the .ttf files are. Nil: the extension's own bundle. The macOS
    /// render check points it at the extension's Fonts folder.
    static var directory: URL?

    /// Titles: Archivo 620, width 112 (Home's heading; tracking -0.018 em).
    static func heading(_ size: CGFloat) -> Font {
        variable(archivo, size: size, axes: ["wght": 620, "wdth": 112], fallback: .semibold)
    }

    /// Numerals: Archivo 640, width 108 (Home's score; tracking -0.02 em).
    static func numeral(_ size: CGFloat) -> Font {
        variable(archivo, size: size, axes: ["wght": 640, "wdth": 108], fallback: .bold)
    }

    /// Body: IBM Plex Sans at a weight from 100 to 700.
    static func body(_ size: CGFloat, weight: CGFloat = 400) -> Font {
        let fallback: Font.Weight = weight >= 600 ? .semibold : weight >= 500 ? .medium : .regular
        return variable(plexSans, size: size, axes: ["wght": weight], fallback: fallback)
    }

    static func variable(_ file: String, size: CGFloat, axes: [String: CGFloat],
                         fallback: Font.Weight) -> Font {
        guard let font = ctFont(file, size: size, axes: axes) else {
            return .system(size: size, weight: fallback)
        }
        return Font(font)
    }

    static func ctFont(_ file: String, size: CGFloat, axes: [String: CGFloat]) -> CTFont? {
        guard let base = descriptor(file) else { return nil }
        var variation: [NSNumber: NSNumber] = [:]
        for (tag, value) in axes {
            let code = tag.utf8.reduce(UInt32(0)) { ($0 << 8) | UInt32($1) }
            variation[NSNumber(value: code)] = NSNumber(value: Double(value))
        }
        let attributes = [kCTFontVariationAttribute: variation] as CFDictionary
        return CTFontCreateWithFontDescriptor(
            CTFontDescriptorCreateCopyWithAttributes(base, attributes), size, nil)
    }

    private static var descriptors: [String: CTFontDescriptor] = [:]

    private static func descriptor(_ file: String) -> CTFontDescriptor? {
        if let known = descriptors[file] { return known }
        let url = directory.map { $0.appendingPathComponent(file + ".ttf") }
            ?? Bundle.main.url(forResource: file, withExtension: "ttf")
        guard let url,
              let all = CTFontManagerCreateFontDescriptorsFromURL(url as CFURL) as? [CTFontDescriptor],
              let first = all.first else { return nil }
        descriptors[file] = first
        return first
    }
}

// MARK: - The ring

/// The ring at rest. [mono] draws it for the lock screen: one ink, tinted by
/// the system, with the band in the accent group.
struct OrbRingView: View {
    var ring: GlanceRing
    var gaps: [Double] = []
    var size: CGFloat
    var dark: Bool
    var mono: Bool = false

    /// The bloom reaches 0.7 of the size from the centre, past the band's box.
    private var canvasSide: CGFloat { mono ? size : size * 1.4 }

    var body: some View {
        Group {
            if mono {
                ZStack {
                    Canvas { ctx, box in drawMonoTrack(&ctx, box) }
                    Canvas { ctx, box in drawMonoBody(&ctx, box) }
                        .glanceAccentable()
                }
            } else {
                Canvas { ctx, box in drawColour(&ctx, box) }
            }
        }
        .frame(width: canvasSide, height: canvasSide)
        .frame(width: size, height: size)
        .accessibilityHidden(true)
    }

    private var palette: GlancePalette { GlancePalette(dark: dark) }
    private var unit: CGFloat { size / CGFloat(OrbGeometry.box) }

    // Degrees clockwise from twelve to a point on a circle, in ring units.
    private static func point(_ degrees: Double, _ radius: Double) -> CGPoint {
        let a = (degrees - 90) * .pi / 180
        return CGPoint(x: radius * cos(a), y: radius * sin(a))
    }

    private var arcs: [OrbArc] { OrbGeometry.body(gaps) }

    private var bandPath: Path {
        var path = Path()
        let r = CGFloat(OrbGeometry.centre)
        for arc in arcs {
            if arc.isWhole {
                path.addEllipse(in: CGRect(x: -r, y: -r, width: 2 * r, height: 2 * r))
            } else {
                // A positive delta runs clockwise on screen (y grows downwards).
                let start = Self.point(arc.start, OrbGeometry.centre)
                path.move(to: start)
                path.addRelativeArc(center: .zero, radius: r,
                                    startAngle: .degrees(arc.start - 90),
                                    delta: .degrees(arc.sweep))
            }
        }
        return path
    }

    private var bandStroke: StrokeStyle {
        StrokeStyle(lineWidth: CGFloat(OrbGeometry.thickness), lineCap: .round)
    }

    private func circle(_ r: Double) -> Path {
        let r = CGFloat(r)
        return Path(ellipseIn: CGRect(x: -r, y: -r, width: 2 * r, height: 2 * r))
    }

    private func dotsPath() -> Path {
        var path = Path()
        let n = OrbGeometry.dotCount(forSize: Double(size))
        let d = CGFloat(OrbGeometry.dotRadius)
        for i in 0..<n {
            let p = Self.point(Double(i) * 360 / Double(n), OrbGeometry.centre)
            path.addEllipse(in: CGRect(x: p.x - d, y: p.y - d, width: 2 * d, height: 2 * d))
        }
        return path
    }

    private func sparks(_ radius: Double) -> Path {
        var path = Path()
        let d = CGFloat(radius)
        for g in gaps {
            let p = Self.point(g, OrbGeometry.centre)
            path.addEllipse(in: CGRect(x: p.x - d, y: p.y - d, width: 2 * d, height: 2 * d))
        }
        return path
    }

    /// Moves the context into the ring's 200 unit box, centred.
    private func enterRing(_ ctx: inout GraphicsContext, _ box: CGSize) {
        ctx.translateBy(x: box.width / 2, y: box.height / 2)
        ctx.scaleBy(x: unit, y: unit)
    }

    // MARK: Colour

    private func drawColour(_ ctx: inout GraphicsContext, _ box: CGSize) {
        let still = ring == .still
        let c = CGPoint(x: box.width / 2, y: box.height / 2)

        // Bloom behind the ring.
        let glow = palette.orbGlow
        let strength = GlancePalette.bloom(for: ring)
        let bloomRadius = size * 0.7
        ctx.fill(
            Path(ellipseIn: CGRect(x: c.x - bloomRadius, y: c.y - bloomRadius,
                                   width: 2 * bloomRadius, height: 2 * bloomRadius)),
            with: .radialGradient(
                Gradient(stops: [
                    .init(color: glow.opacity(glow.a * strength).color, location: 0),
                    .init(color: glow.opacity(0).color, location: 0.74),
                ]),
                center: c, startRadius: 0, endRadius: bloomRadius))

        enterRing(&ctx, box)

        // Track: the full channel the band runs in.
        ctx.stroke(circle(OrbGeometry.centre), with: .color(palette.orbTrack.color),
                   lineWidth: CGFloat(OrbGeometry.thickness))

        if ring == .fresh {
            ctx.fill(dotsPath(), with: .color(palette.dots.color))
            return
        }

        let band = bandPath
        let tone: (RGBA) -> RGBA = { still ? $0.still : $0 }

        // Contact shadow.
        var shadow = ctx
        shadow.addFilter(.blur(radius: 3 * unit))
        shadow.stroke(band.offsetBy(dx: 0, dy: 2.5), with: .color(tone(palette.orbShadow).color),
                      style: bandStroke)

        // Body: the logo's ramp, radial from (-20, -22), radius 124.
        let stops = palette.orbFill.enumerated().map { i, colour in
            Gradient.Stop(color: tone(colour).color, location: Double(i) / 5)
        }
        ctx.stroke(band, with: .radialGradient(Gradient(stops: stops),
                                               center: CGPoint(x: -20, y: -22),
                                               startRadius: 0, endRadius: 124),
                   style: bandStroke)

        // Sheen: light at the top left, shade at the bottom right.
        ctx.stroke(band, with: .linearGradient(
            Gradient(stops: [
                .init(color: RGBA(1, 1, 1, 0.18).color, location: 0),
                .init(color: RGBA(1, 1, 1, 0).color, location: 0.42),
                .init(color: RGBA(0, 0, 0, 0.14).color, location: 1),
            ]),
            startPoint: CGPoint(x: -80, y: -80), endPoint: CGPoint(x: 80, y: 80)),
            style: bandStroke)

        // Depth: both edges shaded, a highlight along the upper outer edge,
        // kept inside the band so a gap's round ends stay clean.
        let depth: Double = still ? 0.5 : 1
        var inside = ctx
        inside.clip(to: band.strokedPath(bandStroke))
        var soft = inside
        soft.addFilter(.blur(radius: 3.2 * unit))
        soft.stroke(circle(OrbGeometry.inner + 1),
                    with: .color(palette.orbDepth.opacity(0.28 * depth).color), lineWidth: 8)
        soft.stroke(circle(OrbGeometry.outer - 1),
                    with: .color(palette.orbDepth.opacity(0.2 * depth).color), lineWidth: 6)
        var lit = inside
        lit.addFilter(.blur(radius: 1.7 * unit))
        var highlight = Path()
        highlight.addRelativeArc(center: .zero, radius: CGFloat(OrbGeometry.outer - 9),
                                 startAngle: .degrees(-62 - 90), delta: .degrees(76))
        lit.stroke(highlight, with: .color(RGBA(1, 1, 1, 0.62 * depth).color),
                   style: StrokeStyle(lineWidth: 3.4, lineCap: .round))

        // An amber spark where the circle is open.
        ctx.fill(sparks(OrbGeometry.sparkRadius), with: .color(palette.amber.color))
    }

    // MARK: Mono (lock screen)

    private func drawMonoTrack(_ ctx: inout GraphicsContext, _ box: CGSize) {
        enterRing(&ctx, box)
        ctx.stroke(circle(OrbGeometry.centre), with: .color(.primary.opacity(0.2)),
                   lineWidth: CGFloat(OrbGeometry.thickness))
        if ring == .fresh {
            ctx.fill(dotsPath(), with: .color(.primary.opacity(0.9)))
        }
    }

    private func drawMonoBody(_ ctx: inout GraphicsContext, _ box: CGSize) {
        guard ring != .fresh else { return }
        enterRing(&ctx, box)
        // One ink: the cut alone shows the gap (an ink spark would merge with
        // the round ends at lock screen sizes).
        ctx.stroke(bandPath, with: .color(.primary.opacity(ring == .still ? 0.55 : 1)),
                   style: bandStroke)
    }
}

// MARK: - The logo mark

/// assets/branding/orbguard_icon.svg as drawn in the brief: a circle of radius
/// 34, stroke 22, in a 100 box, filled with the logo's radial ramp (centre
/// 38,38, radius 62) under its luminance sheen.
struct OrbLogoView: View {
    var size: CGFloat
    var mono: Bool = false

    var body: some View {
        Canvas { ctx, box in
            let u = min(box.width, box.height) / 100
            ctx.translateBy(x: (box.width - 100 * u) / 2, y: (box.height - 100 * u) / 2)
            ctx.scaleBy(x: u, y: u)
            let ring = Path(ellipseIn: CGRect(x: 16, y: 16, width: 68, height: 68))
            let stroke = StrokeStyle(lineWidth: 22)
            if mono {
                ctx.stroke(ring, with: .color(.primary), style: stroke)
                return
            }
            let ramp = GlancePalette(dark: false).logoFill.enumerated().map { i, colour in
                Gradient.Stop(color: colour.color, location: Double(i) / 5)
            }
            ctx.stroke(ring, with: .radialGradient(Gradient(stops: ramp), center: CGPoint(x: 38, y: 38),
                                                   startRadius: 0, endRadius: 62), style: stroke)
            ctx.stroke(ring, with: .linearGradient(
                Gradient(stops: [
                    .init(color: RGBA(1, 1, 1, 0.14).color, location: 0),
                    .init(color: RGBA(1, 1, 1, 0).color, location: 0.4),
                    .init(color: RGBA(0, 0, 0, 0.12).color, location: 1),
                ]),
                startPoint: CGPoint(x: 10, y: 10), endPoint: CGPoint(x: 90, y: 90)), style: stroke)
        }
        .frame(width: size, height: size)
        .glanceAccentable()
        .accessibilityHidden(true)
    }
}

// MARK: - WidgetKit hooks that must not break the macOS check build

extension View {
    /// Puts the view in the widget's accent group (lock screen, tinted home screen).
    @ViewBuilder
    func glanceAccentable() -> some View {
        #if os(iOS) && canImport(WidgetKit)
        if #available(iOS 16, *) {
            self.widgetAccentable()
        } else {
            self
        }
        #else
        self
        #endif
    }
}
