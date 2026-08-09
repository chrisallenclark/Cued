import SwiftUI

/// The colours a Space may wear.
///
/// **These were generated, not picked by eye, and that is the whole point.** The old set
/// was eight hand-chosen hexes whose saturation ran from 0.38 to 0.86 and whose luminance
/// varied by nearly a factor of two. That is exactly the "bright pink next to baby blue"
/// problem: two colours clash when they disagree about how *loud* they are, far more than
/// when they disagree about hue.
///
/// So every swatch here sits at the same perceptual lightness (OKLab L = 0.70) and, within
/// the chromatic group, the same chroma (C = 0.075). **Hue is the only thing that varies.**
/// That is a mathematical guarantee rather than a matter of taste: any two of these, side
/// by side, read as siblings, because there is nothing left for them to disagree about.
///
/// OKLab rather than HSB because HSB lies. Equal "saturation" in HSB looks wildly different
/// across hues — a red at 0.48 shouts while a green at 0.48 whispers — which is precisely
/// how the old palette drifted apart despite looking systematic on paper.
///
/// The chroma is deliberately well under the gamut ceiling (the tightest hue, teal, could
/// reach 0.109). Muted is the brief: these are earth pigments, not highlighter pens. The
/// four **Quiet** entries drop the chroma further still while holding the same lightness,
/// so a near-neutral Space recedes without going dark — a dark Space colour would collide
/// with the map, where dimness already means "you have not touched this in a while".
enum SpaceColor: String, CaseIterable, Identifiable, Sendable {

    // Earth
    case clay
    case rust
    case rose
    case amber
    case ochre
    case dune

    // Field
    case sage
    case moss

    // Water
    case teal
    case lagoon
    case denim
    case slate

    // Quiet
    case bone
    case charcoal

    var id: String { rawValue }

    /// Six-digit RRGGBB, no leading hash — the form `IdeaCategory.colorHex` stores.
    var hex: String {
        switch self {
        case .clay:     return "C69176"
        case .rust:     return "C98C87"
        case .rose:     return "C68B9B"
        case .amber:    return "BC976A"
        case .ochre:    return "A9A069"
        case .dune:     return "AD9B86"
        case .sage:     return "91A875"
        case .moss:     return "78AD8A"
        case .teal:     return "63AEA9"
        case .lagoon:   return "66AABF"
        case .denim:    return "7FA1CD"
        case .slate:    return "89A3B2"
        case .bone:     return "A39E95"
        case .charcoal: return "979FA8"
        }
    }

    var name: String {
        switch self {
        case .clay:     return "Clay"
        case .rust:     return "Rust"
        case .rose:     return "Rose"
        case .amber:    return "Amber"
        case .ochre:    return "Ochre"
        case .dune:     return "Dune"
        case .sage:     return "Sage"
        case .moss:     return "Moss"
        case .teal:     return "Teal"
        case .lagoon:   return "Lagoon"
        case .denim:    return "Denim"
        case .slate:    return "Slate"
        case .bone:     return "Bone"
        case .charcoal: return "Charcoal"
        }
    }

    var color: Color {
        Color(hex: hex) ?? Theme.Palette.ember
    }

    enum Family: String, CaseIterable, Sendable {
        case earth = "Earth"
        case field = "Field"
        case water = "Water"
        case quiet = "Quiet"
    }

    var family: Family {
        switch self {
        case .clay, .rust, .rose, .amber, .ochre, .dune: return .earth
        case .sage, .moss:                               return .field
        case .teal, .lagoon, .denim, .slate:             return .water
        case .bone, .charcoal:                           return .quiet
        }
    }

    static func grouped() -> [(family: Family, colors: [SpaceColor])] {
        Family.allCases.map { family in
            (family, allCases.filter { $0.family == family })
        }
    }

    /// How much colour a swatch carries. Three steps, and every swatch in a step carries
    /// exactly the same amount.
    ///
    /// Separate from `family`, which only says *which* hue: Dune is an earth colour and a
    /// subdued one, Slate is a water colour and a subdued one. Keeping the two ideas apart
    /// is what lets the chooser group by hue while the harmony guarantee is enforced by
    /// tier — and it is why the browsing labels can be rearranged later without anyone
    /// accidentally breaking the thing that stops Spaces clashing.
    enum ChromaTier: Sendable {
        /// The full-colour set, C = 0.075.
        case full
        /// Softened, C = 0.036 — the monochromatic end of a family.
        case subdued
        /// Near-neutral, C = 0.015.
        case quiet
    }

    var chromaTier: ChromaTier {
        switch self {
        case .dune, .slate:    return .subdued
        case .bone, .charcoal: return .quiet
        default:               return .full
        }
    }

    // MARK: - Matching

    static let hexes: Set<String> = Set(allCases.map(\.hex))

    /// Whether a stored hex is already one of ours.
    static func contains(hex: String) -> Bool {
        hexes.contains(hex.uppercased())
    }

    static func named(hex: String) -> SpaceColor? {
        let wanted = hex.uppercased()
        return allCases.first { $0.hex == wanted }
    }

    /// The palette entry closest in hue to an arbitrary colour.
    ///
    /// Used to bring Spaces coloured under the old scheme into the new one without
    /// scrambling them: a Space that was blue stays blue, it just becomes *this* blue.
    /// Matching on hue alone is deliberate — lightness and chroma are the very things
    /// being normalised, so letting them influence the choice would defeat the exercise.
    ///
    /// A source with almost no colour in it lands on a Quiet swatch, because snapping a
    /// grey to whichever chromatic hue it leans towards by a rounding error would be a
    /// worse answer than admitting it is grey.
    static func nearest(toHex hex: String) -> SpaceColor {
        guard let source = HueProbe(hex: hex) else { return .amber }

        if source.saturation < 0.12 {
            return source.hue > 90 && source.hue < 300 ? .charcoal : .bone
        }

        // Only full-chroma swatches are candidates. Dune sits within a degree of Amber on
        // the wheel, so including the subdued tier would make the result a coin toss
        // between them — and would quietly answer "what colour was this?" with a muted
        // version of itself.
        let candidates = allCases.filter { $0.chromaTier == .full }
        return candidates.min { lhs, rhs in
            HueProbe.distance(source.hue, HueProbe(hex: lhs.hex)?.hue ?? 0)
                < HueProbe.distance(source.hue, HueProbe(hex: rhs.hex)?.hue ?? 0)
        } ?? .amber
    }
}

/// Just enough colour maths to compare two hues, without pulling in UIKit.
struct HueProbe {
    let hue: Double
    let saturation: Double

    init?(hex: String) {
        let cleaned = hex.hasPrefix("#") ? String(hex.dropFirst()) : hex
        guard cleaned.count == 6, let value = UInt32(cleaned, radix: 16) else { return nil }

        let r = Double((value >> 16) & 0xFF) / 255
        let g = Double((value >> 8) & 0xFF) / 255
        let b = Double(value & 0xFF) / 255

        let high = max(r, g, b)
        let low = min(r, g, b)
        let delta = high - low

        self.saturation = high <= 0 ? 0 : delta / high

        guard delta > 0 else {
            self.hue = 0
            return
        }

        let raw: Double
        if high == r {
            raw = 60 * (((g - b) / delta).truncatingRemainder(dividingBy: 6))
        } else if high == g {
            raw = 60 * (((b - r) / delta) + 2)
        } else {
            raw = 60 * (((r - g) / delta) + 4)
        }
        self.hue = raw < 0 ? raw + 360 : raw
    }

    /// Shortest way round the wheel, so 350° and 10° are twenty degrees apart, not 340.
    static func distance(_ a: Double, _ b: Double) -> Double {
        let raw = abs(a - b).truncatingRemainder(dividingBy: 360)
        return min(raw, 360 - raw)
    }
}
