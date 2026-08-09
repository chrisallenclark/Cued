import Foundation
import SwiftData
import Testing

@testable import Remli

/// Icons have to distinguish Spaces, which is the one thing the old behaviour could not do:
/// every hand-made Space was given the same hard-coded glyph, so the most prominent element
/// on the Spaces grid carried no information whatsoever.
@Suite("Space symbols")
struct SpaceSymbolTests {

    private func makeContext() throws -> ModelContext {
        let container = try RemliSchema.makeContainer(inMemory: true)
        return ModelContext(container)
    }

    @Test("Every symbol is distinct and every group is populated")
    func setIsWellFormed() {
        let names = SpaceSymbol.allCases.map(\.symbolName)
        #expect(Set(names).count == names.count, "two entries share an SF Symbol name")
        #expect(names.count >= 10, "the point was to offer a real choice")

        let grouped = SpaceSymbol.grouped()
        #expect(Set(grouped.flatMap(\.symbols)) == Set(SpaceSymbol.allCases))
        for entry in grouped {
            #expect(!entry.symbols.isEmpty, "\(entry.group.rawValue) is empty")
        }
    }

    @Test("No symbol is one of the placeholders it replaces")
    func noPlaceholdersInTheSet() {
        for choice in SpaceSymbol.allCases {
            #expect(
                !SpaceSymbol.genericNames.contains(choice.symbolName),
                "\(choice.symbolName) is treated as a placeholder and would be replaced on launch"
            )
        }
    }

    @Test("Names the table knows get the obvious icon")
    func hintsMatch() {
        #expect(SpaceSymbol.suggested(for: "Business") == .briefcase)
        #expect(SpaceSymbol.suggested(for: "Client tracking app") == .laptop)
        #expect(SpaceSymbol.suggested(for: "Meal prep service") == .food)
        #expect(SpaceSymbol.suggested(for: "Topless Tenders") == .food)
        #expect(SpaceSymbol.suggested(for: "Health & fitness") == .run)
        #expect(SpaceSymbol.suggested(for: "Content system") == .talk)
        #expect(SpaceSymbol.suggested(for: "Travel") == .flight)
    }

    @Test("Names the table does not know still get different icons")
    func unknownNamesDiverge() {
        let names = ["Macrova", "Zephyr", "Quiet things", "Odds and ends", "Blue", "Kx7"]
        let chosen = names.map { SpaceSymbol.suggested(for: $0) }
        // The old behaviour gave all of these the same glyph. Anything better than one
        // shared icon is the whole point; requiring perfection would be requiring taste.
        #expect(Set(chosen).count >= names.count - 1, "unknown names collapsed onto one icon")
    }

    @Test("The same name always gets the same icon")
    func suggestionIsStable() {
        for name in ["Macrova", "Business", "Whatever"] {
            #expect(SpaceSymbol.suggested(for: name) == SpaceSymbol.suggested(for: name))
        }
        #expect(SpaceSymbol.suggested(for: "Business") == SpaceSymbol.suggested(for: "business"))
    }

    @Test("An empty name still resolves to something drawable")
    func emptyNameIsSafe() {
        let choice = SpaceSymbol.suggested(for: "")
        #expect(SpaceSymbol.allCases.contains(choice))
    }

    // MARK: On the model

    @Test("Choosing an icon marks it as yours")
    func choosingSticks() throws {
        let context = try makeContext()
        let space = IdeaCategory(name: "Business", isUserOwned: true)
        context.insert(space)

        #expect(space.symbolIsUserSet == false)
        space.setSymbol(.outdoors)
        #expect(space.symbolName == SpaceSymbol.outdoors.symbolName)
        #expect(space.symbolIsUserSet)
        #expect(space.paletteSymbol == .outdoors)
    }

    @Test("Launch replaces placeholder icons and leaves real ones alone")
    func migrationFillsInPlaceholders() throws {
        let context = try makeContext()

        let placeholder = IdeaCategory(name: "Macrova", symbolName: "square.stack.3d.up")
        let specific = IdeaCategory(name: "Music", symbolName: "guitars")
        let chosen = IdeaCategory(name: "Health", symbolName: "square.stack.3d.up")
        chosen.symbolIsUserSet = true
        for category in [placeholder, specific, chosen] { context.insert(category) }

        IdeaCategory.harmonisePalette(in: context)

        #expect(placeholder.symbolName != "square.stack.3d.up", "a placeholder survived")
        #expect(specific.symbolName == "guitars", "a real icon was overwritten")
        #expect(chosen.symbolName == "square.stack.3d.up", "a chosen icon was overwritten")
    }

    @Test("Two Spaces made by hand no longer look identical")
    func newSpacesDiffer() throws {
        let context = try makeContext()
        var symbols: [String] = []
        for name in ["Business", "Health", "Macrova", "Music", "Travel"] {
            let space = IdeaCategory(
                name: name,
                symbolName: SpaceSymbol.suggested(for: name).symbolName,
                isUserOwned: true
            )
            context.insert(space)
            symbols.append(space.symbolName)
        }
        #expect(Set(symbols).count == symbols.count, "two new Spaces got the same icon")
    }

    @Test("Recolouring a Space does not disturb its icon")
    func colourAndIconAreIndependent() throws {
        let context = try makeContext()
        let space = IdeaCategory(name: "Business", isUserOwned: true)
        context.insert(space)
        space.setSymbol(.target)
        space.setColor(.moss)

        #expect(space.symbolName == SpaceSymbol.target.symbolName)
        #expect(space.colorHex == SpaceColor.moss.hex)
    }

    @Test("An icon does not cascade to Collections, but the colour does")
    func iconStaysPutWhileColourSpreads() throws {
        let context = try makeContext()
        let space = IdeaCategory(name: "Business", isUserOwned: true)
        context.insert(space)
        let child = IdeaCategory(name: "Trainer tools", parent: space, isUserOwned: true)
        context.insert(child)
        child.setSymbol(.run)

        space.setSymbol(.briefcase)
        space.setColor(.teal)

        // The colour makes the group read as one thing; the icon is what tells the
        // Collections inside it apart.
        #expect(child.symbolName == SpaceSymbol.run.symbolName)
        #expect(child.colorHex == SpaceColor.teal.hex)
    }
}
