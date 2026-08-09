import Foundation
import SwiftData
import SwiftUI

/// A **Space** — or, one level down, a **Collection** inside one.
///
/// Both are this one type, distinguished only by whether `parent` is set. Two levels is
/// the whole hierarchy, deliberately: Space → Collection → Idea, with tags cutting across
/// all of it. Anything deeper is a filing system, and a filing system is the thing this
/// app exists to replace.
///
/// Remli ships with no Spaces at all. A fixed taxonomy would impose someone else's mental
/// model; letting Spaces emerge from real captures means they end up matching how the
/// person actually thinks. The cost is that the first few captures look unstructured,
/// which the empty state acknowledges rather than hides.
///
/// **The type is still called `IdeaCategory` on purpose.** A SwiftData model's class name
/// is its CloudKit record type, so renaming this would orphan every record already synced
/// to a device. "Space" is the language in the interface; the schema keeps the name it was
/// born with. Do not rename it without a migration plan.
@Model
final class IdeaCategory {

    var id: UUID = UUID()
    var createdAt: Date = Date.now

    var name: String = ""

    /// Six-digit RRGGBB, no leading hash. Assigned from `SpaceColor` when the category is
    /// created, so the colour set stays harmonious no matter what the model names things.
    var colorHex: String = "BC976A"

    /// True once a person has picked this colour themselves.
    ///
    /// The same bargain as `isUserOwned` and the importance override: a colour Remli chose
    /// is a suggestion it may revise, and a colour you chose is yours. Without this flag
    /// the palette migration would flatten a deliberate choice back to whatever the hue
    /// matcher preferred, which is the sort of thing that only shows up months later when
    /// someone notices their Space is the wrong green again.
    var colorIsUserSet: Bool = false

    /// True once a person has picked the icon themselves. Same bargain as the colour.
    var symbolIsUserSet: Bool = false

    /// An SF Symbol name chosen at creation. Validated before use — a hallucinated symbol
    /// name would otherwise render as a blank space.
    var symbolName: String = "lightbulb"

    @Relationship(deleteRule: .nullify, inverse: \Idea.category)
    var ideas: [Idea]?

    /// The Space this Collection sits inside. Nil means this *is* a Space.
    ///
    /// A Space answers "what part of my life is this" — Business, Health, Macrova. It does
    /// not answer "which of my three businesses". A Collection does, without making the
    /// first capture of the day ask you to pick a project: the model still files into a
    /// Space, and you sort the inside out later, once there is enough there to be worth
    /// sorting.
    var parent: IdeaCategory?

    @Relationship(deleteRule: .nullify, inverse: \IdeaCategory.parent)
    var children: [IdeaCategory]?

    /// True when a person named this, false when the model proposed it.
    ///
    /// This is what stops Spaces being quietly reshaped underneath you. The model may
    /// suggest a Space, and until you touch it, it stays a suggestion that later passes are
    /// free to rename or merge. The moment you create or rename one yourself it becomes
    /// yours, and enrichment may file *into* it but never edits it.
    ///
    /// Defaults to false so every Space that already exists — all of them model-invented —
    /// keeps its current behaviour after the migration.
    var isUserOwned: Bool = false

    /// A picture the person chose for this Space, already downscaled and JPEG-encoded.
    ///
    /// `.externalStorage` keeps the bytes out of the SQLite row and, under CloudKit, turns
    /// them into a `CKAsset` rather than bloating every fetch of a Space's name. Images are
    /// resized to at most 900pt on the long edge before they get here — a full-resolution
    /// photo is around 4 MB and would make sync miserable for no visible benefit at the
    /// size these are drawn.
    ///
    /// Nil is the normal case and renders a generated gradient instead. Remli cannot ship
    /// photography that matches a Space it has never heard of, so the choice belongs to
    /// whoever named it.
    @Attribute(.externalStorage)
    var coverImageData: Data?

    /// A built-in cover, when no photo was chosen. Stored as the preset's id rather than
    /// its colours so the art can be redrawn later without migrating anyone's Spaces.
    var coverPresetID: String?

    init(
        name: String,
        colorHex: String? = nil,
        symbolName: String = "lightbulb",
        parent: IdeaCategory? = nil,
        isUserOwned: Bool = false
    ) {
        self.id = UUID()
        self.createdAt = .now
        self.name = name
        self.symbolName = symbolName
        self.parent = parent
        self.isUserOwned = isUserOwned
        // A Collection inherits its Space's colour, so a glance at the list still reads as
        // "these three things are all Business" before you read a single word.
        self.colorHex = colorHex ?? parent?.colorHex ?? Self.suggestedColor(for: name)
    }
}

extension IdeaCategory {

    /// What a Space is allowed to be. See `SpaceColor` for why these particular values.
    static let palette: [String] = SpaceColor.allCases.map(\.hex)

    /// Stable per name, so a category keeps its colour across devices without needing the
    /// choice synced, and the same name never flickers between colours.
    static func suggestedColor(for name: String) -> String {
        guard !palette.isEmpty else { return SpaceColor.amber.hex }
        var hash: UInt64 = 5381
        for byte in name.lowercased().utf8 {
            hash = (hash &* 33) &+ UInt64(byte)
        }
        return palette[Int(hash % UInt64(palette.count))]
    }

    /// The Space's colour as something drawable, with the fallback in one place rather than
    /// repeated at a dozen call sites.
    var color: Color {
        Color(hex: colorHex) ?? Theme.Palette.ember
    }

    /// Which palette entry this is, when it is one.
    var paletteColor: SpaceColor? { SpaceColor.named(hex: colorHex) }

    var paletteSymbol: SpaceSymbol? { SpaceSymbol.named(symbolName) }

    /// Records a chosen icon. Unlike the colour this does **not** cascade: a Collection
    /// shares its Space's colour so the group reads as one thing, but its icon is the only
    /// way to tell "Trainer tools" from "Lead gen" at a glance.
    func setSymbol(_ choice: SpaceSymbol) {
        symbolName = choice.symbolName
        symbolIsUserSet = true
    }

    /// Records a chosen colour, and marks it as chosen.
    ///
    /// A Collection follows its Space, so recolouring Business recolours everything filed
    /// under it — the whole reason a Collection inherits its colour in the first place is
    /// that a glance at the list should read as "these all belong together".
    func setColor(_ choice: SpaceColor, cascadeToChildren: Bool = true) {
        colorHex = choice.hex
        colorIsUserSet = true

        guard cascadeToChildren else { return }
        for child in children ?? [] where !child.colorIsUserSet {
            child.colorHex = choice.hex
        }
    }

    // MARK: - Palette migration

    /// Pulls Spaces coloured under the old scheme into the new palette.
    ///
    /// The previous set was eight hand-picked hexes with luminance varying by nearly 2×,
    /// so any two Spaces on screen together disagreed about how loud they were. Adding a
    /// picker without this would leave every Space that already exists clashing with every
    /// one chosen afterwards — which is the exact complaint the picker is meant to answer.
    ///
    /// Matching is by hue, so a Space that was blue stays blue. Anything the person picked
    /// themselves is left alone, and anything already in the palette is skipped, which
    /// makes this idempotent and free to run on every launch.
    @discardableResult
    static func harmonisePalette(in context: ModelContext) -> Int {
        let descriptor = FetchDescriptor<IdeaCategory>()
        guard let all = try? context.fetch(descriptor) else { return 0 }

        var changed = 0
        for category in all {
            if !category.colorIsUserSet, !SpaceColor.contains(hex: category.colorHex) {
                category.colorHex = SpaceColor.nearest(toHex: category.colorHex).hex
                changed += 1
            }

            // Every hand-made Space was born with the same hard-coded icon, so the icon on
            // the Spaces grid distinguished nothing. Only placeholders are replaced —
            // anything specific, whether picked by a person or proposed by the model, is
            // already doing its job and is left alone.
            if !category.symbolIsUserSet, SpaceSymbol.genericNames.contains(category.symbolName) {
                category.symbolName = SpaceSymbol.suggested(for: category.name).symbolName
                changed += 1
            }
        }
        return changed
    }

    /// How many ideas are filed here — roadmap steps excluded.
    ///
    /// A Space reading "Business · 14 ideas" when nine of them are steps towards one goal
    /// is a lie about how much thinking is in there, and the number people use to decide
    /// which Space to open.
    var ideaCount: Int { (ideas ?? []).excludingSteps.count }

    // MARK: - Hierarchy

    /// How deep this sits. 0 for a top-level folder.
    ///
    /// Every walk up the chain is bounded. A parent cycle should be impossible — the picker
    /// refuses to create one — but a corrupt or badly merged CloudKit record must not be
    /// able to hang the UI, and these run inside view bodies.
    var depth: Int {
        var count = 0
        var current = parent
        while let node = current, count < 8 {
            count += 1
            current = node.parent
        }
        return count
    }

    var isRoot: Bool { parent == nil }

    /// A Space is a top-level container; a Collection lives inside one. Same type, and the
    /// only thing separating them is `parent`.
    var isSpace: Bool { parent == nil }
    var isCollection: Bool { parent != nil }

    /// What to call this in the interface, so copy never has to branch on `parent` itself.
    var kindLabel: String { isSpace ? "Space" : "Collection" }

    /// The top-level folder this belongs to — itself, when it is already top-level.
    var rootFolder: IdeaCategory {
        var current = self
        var guardCount = 0
        while let next = current.parent, guardCount < 8 {
            current = next
            guardCount += 1
        }
        return current
    }

    var sortedChildren: [IdeaCategory] {
        (children ?? []).sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }

    /// "Business › Meal Prep", or just "Business" at the top level.
    var displayPath: String {
        guard let parent else { return name }
        return "\(parent.name) › \(name)"
    }

    /// Ideas filed here plus everything in the subfolders, which is what a count next to a
    /// parent folder has to mean — otherwise "Business 0" sits above three subfolders that
    /// between them hold everything.
    var totalIdeaCount: Int {
        ideaCount + (children ?? []).reduce(0) { $0 + $1.ideaCount }
    }

    /// True when `other` is this folder or one of its subfolders. Used to keep the picker
    /// from reparenting a folder into its own descendant.
    func contains(_ other: IdeaCategory) -> Bool {
        if other.id == id { return true }
        return (children ?? []).contains { $0.id == other.id }
    }
}
