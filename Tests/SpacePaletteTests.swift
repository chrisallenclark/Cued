import Foundation
import SwiftData
import Testing

@testable import Remli

/// The palette's whole claim is that no two Spaces can clash. That is a measurable
/// property, not a matter of taste, so it is measured here — otherwise the next colour
/// somebody adds by eye quietly undoes the reason the set was generated in the first place.
@Suite("Space palette")
struct SpacePaletteTests {

    // MARK: OKLab, enough of it to check the claim

    private static func linear(_ channel: Double) -> Double {
        channel <= 0.04045 ? channel / 12.92 : pow((channel + 0.055) / 1.055, 2.4)
    }

    /// Returns perceptual lightness and chroma for a hex colour.
    private static func oklch(_ hex: String) throws -> (lightness: Double, chroma: Double) {
        let value = try #require(UInt32(hex, radix: 16))
        let r = linear(Double((value >> 16) & 0xFF) / 255)
        let g = linear(Double((value >> 8) & 0xFF) / 255)
        let b = linear(Double(value & 0xFF) / 255)

        let l = 0.4122214708 * r + 0.5363325363 * g + 0.0514459929 * b
        let m = 0.2119034982 * r + 0.6806995451 * g + 0.1073969566 * b
        let s = 0.0883024619 * r + 0.2817188376 * g + 0.6299787005 * b

        let lRoot = cbrt(l), mRoot = cbrt(m), sRoot = cbrt(s)

        let lightness = 0.2104542553 * lRoot + 0.7936177850 * mRoot - 0.0040720468 * sRoot
        let a = 1.9779984951 * lRoot - 2.4285922050 * mRoot + 0.4505937099 * sRoot
        let bb = 0.0259040371 * lRoot + 0.7827717662 * mRoot - 0.8086757660 * sRoot

        return (lightness, (a * a + bb * bb).squareRoot())
    }

    // MARK: The guarantee

    @Test("Every colour sits at the same perceptual lightness")
    func lightnessIsUniform() throws {
        var values: [Double] = []
        for choice in SpaceColor.allCases {
            values.append(try Self.oklch(choice.hex).lightness)
        }
        let spread = try #require(values.max()) - (try #require(values.min()))
        #expect(spread < 0.01, "lightness varies by \(spread) — colours will clash")
    }

    @Test("Colours in the same chroma tier carry exactly the same amount of colour")
    func chromaIsUniformWithinATier() throws {
        for tier in [SpaceColor.ChromaTier.full, .subdued, .quiet] {
            var values: [Double] = []
            for choice in SpaceColor.allCases where choice.chromaTier == tier {
                values.append(try Self.oklch(choice.hex).chroma)
            }
            #expect(!values.isEmpty, "a chroma tier has no colours in it")
            let spread = try #require(values.max()) - (try #require(values.min()))
            #expect(spread < 0.01, "chroma varies by \(spread) within a tier — some will shout")
        }
    }

    @Test("The tiers actually descend")
    func tiersDescend() throws {
        func chroma(_ tier: SpaceColor.ChromaTier) throws -> Double {
            let choice = try #require(SpaceColor.allCases.first { $0.chromaTier == tier })
            return try Self.oklch(choice.hex).chroma
        }
        // Subdued that is not actually subdued, or a quiet swatch at full colour, would
        // each defeat the point of offering the tier at all.
        let quiet = try chroma(.quiet)
        let subdued = try chroma(.subdued)
        let full = try chroma(.full)

        #expect(quiet < subdued)
        #expect(subdued < full)
    }

    @Test("Nothing is dark enough to be mistaken for a cold node")
    func nothingIsDark() throws {
        // The map uses dimness to mean "untouched for a while". A genuinely dark Space
        // colour would collide with that channel and read as neglect.
        for choice in SpaceColor.allCases {
            let lightness = try Self.oklch(choice.hex).lightness
            #expect(lightness > 0.55, "\(choice.name) is too dark for the map")
        }
    }

    @Test("Every hex is well-formed and unique")
    func hexesAreValid() {
        var seen = Set<String>()
        for choice in SpaceColor.allCases {
            #expect(choice.hex.count == 6)
            #expect(UInt32(choice.hex, radix: 16) != nil)
            #expect(choice.hex == choice.hex.uppercased())
            #expect(seen.insert(choice.hex).inserted, "\(choice.name) duplicates another swatch")
        }
    }

    @Test("Every family has at least one colour and every colour one family")
    func groupingIsComplete() {
        let grouped = SpaceColor.grouped()
        let flattened = grouped.flatMap(\.colors)
        #expect(Set(flattened) == Set(SpaceColor.allCases))
        #expect(flattened.count == SpaceColor.allCases.count)
        for entry in grouped {
            #expect(!entry.colors.isEmpty, "\(entry.family.rawValue) is empty")
        }
    }

    // MARK: Matching old colours

    @Test("An old colour snaps to the same part of the wheel")
    func nearestPreservesHue() {
        // The retired palette, and where each should sensibly land.
        #expect(SpaceColor.nearest(toHex: "1F6F63").family == .water)   // pine
        #expect(SpaceColor.nearest(toHex: "3A6EA5").family == .water)   // slate blue
        #expect(SpaceColor.nearest(toHex: "B4561A").family == .earth)   // ember
        #expect(SpaceColor.nearest(toHex: "8A4B2A").family == .earth)   // clay
        #expect(SpaceColor.nearest(toHex: "7A6220").family == .earth)   // olive
        #expect(SpaceColor.nearest(toHex: "A03D5B").family == .earth)   // rose
    }

    @Test("A near-grey lands on a quiet colour rather than guessing a hue")
    func greysStayGrey() {
        #expect(SpaceColor.nearest(toHex: "807E7C").family == .quiet)
        #expect(SpaceColor.nearest(toHex: "6E7276").family == .quiet)
    }

    @Test("Nonsense input still produces a usable colour")
    func matchingNeverFails() {
        #expect(SpaceColor.hexes.contains(SpaceColor.nearest(toHex: "").hex))
        #expect(SpaceColor.hexes.contains(SpaceColor.nearest(toHex: "zzzzzz").hex))
        #expect(SpaceColor.hexes.contains(SpaceColor.nearest(toHex: "#C69176").hex))
    }

    @Test("Hue distance goes the short way round the wheel")
    func hueDistanceWraps() {
        #expect(abs(HueProbe.distance(350, 10) - 20) < 0.001)
        #expect(abs(HueProbe.distance(10, 350) - 20) < 0.001)
        #expect(abs(HueProbe.distance(0, 180) - 180) < 0.001)
    }
}

/// Recolouring a Space, and what happens to the ones already on the device.
@Suite("Space colour choice")
struct SpaceColorChoiceTests {

    private func makeContext() throws -> ModelContext {
        let container = try RemliSchema.makeContainer(inMemory: true)
        return ModelContext(container)
    }

    @Test("A new Space is born inside the palette")
    func newSpacesAreHarmonious() throws {
        let context = try makeContext()
        for name in ["Business", "Health", "Macrova", "Music", "Topless Tenders"] {
            let space = IdeaCategory(name: name, isUserOwned: true)
            context.insert(space)
            #expect(
                SpaceColor.contains(hex: space.colorHex),
                "\(name) was given \(space.colorHex), which is not in the palette"
            )
        }
    }

    @Test("Choosing a colour marks it as yours")
    func choosingSticks() throws {
        let context = try makeContext()
        let space = IdeaCategory(name: "Business", isUserOwned: true)
        context.insert(space)

        #expect(space.colorIsUserSet == false)
        space.setColor(.teal)
        #expect(space.colorHex == SpaceColor.teal.hex)
        #expect(space.colorIsUserSet)
        #expect(space.paletteColor == .teal)
    }

    @Test("Recolouring a Space carries its Collections with it")
    func colorCascades() throws {
        let context = try makeContext()
        let space = IdeaCategory(name: "Business", isUserOwned: true)
        context.insert(space)
        let child = IdeaCategory(name: "Trainer tools", parent: space, isUserOwned: true)
        context.insert(child)

        space.setColor(.moss)
        #expect(child.colorHex == SpaceColor.moss.hex)
    }

    @Test("A Collection you coloured yourself is left alone")
    func cascadeRespectsAChoice() throws {
        let context = try makeContext()
        let space = IdeaCategory(name: "Business", isUserOwned: true)
        context.insert(space)
        let child = IdeaCategory(name: "Trainer tools", parent: space, isUserOwned: true)
        context.insert(child)

        child.setColor(.rose)
        space.setColor(.moss)

        #expect(child.colorHex == SpaceColor.rose.hex)
    }

    @Test("Migration pulls old colours in and leaves chosen ones alone")
    func migrationHarmonises() throws {
        let context = try makeContext()

        let legacy = IdeaCategory(name: "Old", colorHex: "1F6F63")
        let chosen = IdeaCategory(name: "Mine", colorHex: "1F6F63")
        chosen.colorIsUserSet = true
        let already = IdeaCategory(name: "Fine", colorHex: SpaceColor.amber.hex)
        for category in [legacy, chosen, already] { context.insert(category) }

        let changed = IdeaCategory.harmonisePalette(in: context)

        #expect(changed == 1)
        #expect(SpaceColor.contains(hex: legacy.colorHex))
        #expect(chosen.colorHex == "1F6F63", "a chosen colour was overwritten")
        #expect(already.colorHex == SpaceColor.amber.hex)
    }

    @Test("Running the migration twice changes nothing the second time")
    func migrationIsIdempotent() throws {
        let context = try makeContext()
        for hex in ["1F6F63", "5B4B8A", "A03D5B", "45636F"] {
            context.insert(IdeaCategory(name: hex, colorHex: hex))
        }

        #expect(IdeaCategory.harmonisePalette(in: context) == 4)
        #expect(IdeaCategory.harmonisePalette(in: context) == 0)
    }
}
