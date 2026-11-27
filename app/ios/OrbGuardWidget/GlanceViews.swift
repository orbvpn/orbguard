// GlanceViews.swift - OrbGuard widget
//
// One view per widget family, drawn from a GlanceFace (GlanceLogic.swift).
// No WidgetKit types here, so the views also build on macOS for the render
// check; OrbGuardWidget.swift maps WidgetFamily onto GlanceFamily.
//
// Approved look: app/docs/flagship-prototype (buildWidgets, .wg in 00-page.css).
// Small: ring 92 with the score in the hole, then the title. Medium: ring 92
// left; title, then the line or the check time, and an amber `Open OrbGuard`
// chip when something waits or no check has run. Lock screen: the mono ring,
// `OrbGuard`, `All clear, checked 09:41`.

import SwiftUI
#if os(iOS)
import WidgetKit // AccessoryWidgetBackground only
#endif

enum GlanceFamily {
    case small, medium, rectangular, circular
}

struct GlanceView: View {
    var face: GlanceFace
    var family: GlanceFamily
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        switch family {
        case .small: GlanceSmallView(face: face, dark: colorScheme == .dark)
        case .medium: GlanceMediumView(face: face, dark: colorScheme == .dark)
        case .rectangular: GlanceRectangularView(face: face)
        case .circular: GlanceCircularView(face: face)
        }
    }
}

/// The widget's background for a family and appearance.
struct GlanceBackground: View {
    var family: GlanceFamily
    var dark: Bool

    var body: some View {
        switch family {
        case .small, .medium:
            GlancePalette(dark: dark).surface.color
        case .rectangular:
            Color.clear
        case .circular:
            #if os(iOS)
            if #available(iOS 16, *) { AccessoryWidgetBackground() } else { Color.clear }
            #else
            Circle().fill(Color.primary.opacity(0.14))
            #endif
        }
    }
}

// MARK: - Pieces

/// The ring with the score in its hole.
private struct GlanceRingMark: View {
    var face: GlanceFace
    var size: CGFloat
    var dark: Bool
    var mono = false

    var body: some View {
        ZStack {
            if face.isPlaceholder {
                OrbLogoView(size: size, mono: mono)
            } else {
                OrbRingView(ring: face.ring, gaps: face.gaps, size: size, dark: dark, mono: mono)
                hole
            }
        }
        .frame(width: size, height: size)
    }

    @ViewBuilder private var hole: some View {
        let palette = GlancePalette(dark: dark)
        // Only the number fits the hole at widget sizes (and not below a 56
        // point ring, where it would be under 9 points); the caption needs a
        // ring of 140 points or more.
        let roomy = size >= 140
        VStack(spacing: 2) {
            if let score = face.score, size >= 56 {
                let numeral = size * 0.158
                Text(String(score))
                    .font(BrandFont.numeral(numeral))
                    .tracking(-0.02 * numeral)
                    .monospacedDigit()
                    .foregroundColor(mono ? .primary : palette.text.color)
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
            }
            if roomy {
                let caption = face.ring == .fresh ? "Not checked yet"
                    : face.score != nil ? "privacy score" : nil
                if let caption {
                    Text(caption)
                        .font(BrandFont.body(max(10.5, size * 0.053), weight: 500))
                        .foregroundColor(mono ? .secondary : palette.text2.color)
                }
            }
        }
        .frame(width: size * CGFloat(OrbGeometry.inner * 2 / OrbGeometry.box) * 0.9)
        .accessibilityHidden(true)
    }
}

private struct GlanceTitle: View {
    var text: String
    var dark: Bool
    var size: CGFloat = 15

    var body: some View {
        Text(text)
            .font(BrandFont.heading(size))
            .tracking(-0.018 * size)
            .foregroundColor(GlancePalette(dark: dark).text.color)
            .lineLimit(2)
            .minimumScaleFactor(0.85)
            .fixedSize(horizontal: false, vertical: true)
    }
}

private struct GlanceChip: View {
    var dark: Bool

    var body: some View {
        let palette = GlancePalette(dark: dark)
        Text(GlanceFace.openOrbGuard)
            .font(BrandFont.body(12, weight: 600))
            .foregroundColor(palette.amberText.color)
            .lineLimit(1)
            .padding(.horizontal, 10)
            .frame(height: 26)
            .background(Capsule().fill(palette.amberPill.color))
    }
}

/// What VoiceOver reads for the whole widget: the words on it, in order.
private func spoken(_ parts: String?...) -> String {
    parts.compactMap { $0 }.joined(separator: ". ")
}

// MARK: - Home screen

struct GlanceSmallView: View {
    var face: GlanceFace
    var dark: Bool

    var body: some View {
        GeometryReader { geo in
            // Ring 92, smaller only when the widget is too short for ring and title.
            let ring = min(92, max(56, geo.size.height - 48))
            VStack(spacing: 9) {
                GlanceRingMark(face: face, size: ring, dark: dark)
                GlanceTitle(text: face.title, dark: dark)
                    .multilineTextAlignment(.center)
            }
            .frame(width: geo.size.width, height: geo.size.height)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(spoken(face.title, face.score.map { "Privacy score \($0)" }))
    }
}

struct GlanceMediumView: View {
    var face: GlanceFace
    var dark: Bool

    var body: some View {
        let palette = GlancePalette(dark: dark)
        HStack(spacing: 16) {
            GlanceRingMark(face: face, size: 92, dark: dark)
            VStack(alignment: .leading, spacing: 2) {
                GlanceTitle(text: face.title, dark: dark)
                if !face.isPlaceholder, let detail = face.detail {
                    Text(detail)
                        .font(BrandFont.body(12.5))
                        .foregroundColor(palette.text2.color)
                        .lineLimit(2)
                        .fixedSize(horizontal: false, vertical: true)
                }
                // A stale line takes the line's place; the time still says when.
                if face.isStale, face.line != nil, let checked = face.checked {
                    Text(checked)
                        .font(BrandFont.body(12.5))
                        .foregroundColor(palette.text2.color)
                        .lineLimit(1)
                }
                if !face.isPlaceholder, face.showsChip {
                    GlanceChip(dark: dark).padding(.top, 7)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.horizontal, 2)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(spoken(face.title, face.score.map { "Privacy score \($0)" },
                                   face.isPlaceholder ? nil : face.detail))
    }
}

// MARK: - Lock screen

struct GlanceRectangularView: View {
    var face: GlanceFace

    var body: some View {
        HStack(spacing: 8) {
            GlanceRingMark(face: face, size: 34, dark: true, mono: true)
            VStack(alignment: .leading, spacing: 1) {
                if face.isPlaceholder {
                    Text(GlanceFace.openOrbGuard)
                        .font(BrandFont.body(14, weight: 600))
                        .lineLimit(1)
                } else if let line = face.line {
                    // Something to say beyond the title (a gap, no check yet, an
                    // old reading): the ring names the app, the title leads and
                    // the line gets two rows.
                    Text(face.title)
                        .font(BrandFont.body(14, weight: 600))
                        .lineLimit(2)
                        .minimumScaleFactor(0.9)
                        .layoutPriority(1)
                    Text(line)
                        .font(BrandFont.body(13))
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                        .minimumScaleFactor(0.9)
                } else {
                    Text("OrbGuard")
                        .font(BrandFont.body(14, weight: 600))
                        .lineLimit(1)
                    Text(face.lockSummary)
                        .font(BrandFont.body(13))
                        .lineLimit(2)
                        .minimumScaleFactor(0.9)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(face.isPlaceholder ? GlanceFace.openOrbGuard
                            : face.line == nil ? spoken("OrbGuard", face.lockSummary)
                            : spoken("OrbGuard", face.title, face.line))
    }
}

struct GlanceCircularView: View {
    var face: GlanceFace

    var body: some View {
        GeometryReader { geo in
            let side = min(geo.size.width, geo.size.height)
            GlanceRingMark(face: face, size: side * 0.9, dark: true, mono: true)
                .frame(width: geo.size.width, height: geo.size.height)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(face.isPlaceholder ? GlanceFace.openOrbGuard
                            : spoken(face.title, face.score.map { "Privacy score \($0)" }))
    }
}
