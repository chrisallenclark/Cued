import Foundation

/// The icons a Space may wear.
///
/// Every Space someone created by hand was given `square.stack.3d.up`, because that string
/// was hard-coded at the one place Spaces are made. Six Spaces, six identical icons, and no
/// way to change any of them — the icon was carrying no information at all while taking up
/// the most prominent spot on the Space's banner.
///
/// Thirty-six, in six groups of six. Grouped because a flat wall of icons is something you
/// scroll past, whereas "Body" with six under it is a decision you make in a second — the
/// same reasoning as the cover chooser.
///
/// All of these are long-established SF Symbols. A hallucinated or too-new symbol name
/// renders as an empty gap rather than failing loudly, so the set is fixed here rather than
/// left to whatever the model suggests.
enum SpaceSymbol: String, CaseIterable, Identifiable, Sendable {

    // Work
    case briefcase
    case growth = "chart.line.uptrend.xyaxis"
    case money = "dollarsign.circle"
    case building = "building.2"
    case people = "person.2"
    case target

    // Make
    case hammer
    case paintbrush
    case tools = "wrench.and.screwdriver"
    case camera
    case music = "music.note"
    case stage = "theatermasks"

    // Mind
    case puzzle = "puzzlepiece"
    case book
    case study = "graduationcap"
    case brain = "brain.head.profile"
    case pencil
    case talk = "bubble.left.and.bubble.right"

    // Body
    case heart
    case run = "figure.run"
    case food = "fork.knife"
    case leaf
    case rest = "bed.double"
    case care = "cross.case"

    // Place
    case house
    case flight = "airplane"
    case map
    case globe
    case car
    case outdoors = "mountain.2"

    // Build
    case laptop = "laptopcomputer"
    case phone = "iphone"
    case network
    case terminal
    case settings = "gearshape"
    case signal = "antenna.radiowaves.left.and.right"

    var id: String { rawValue }

    /// The SF Symbol name, which is also what `IdeaCategory.symbolName` stores.
    var symbolName: String { rawValue }

    enum Group: String, CaseIterable, Sendable {
        case work = "Work"
        case make = "Make"
        case mind = "Mind"
        case body = "Body"
        case place = "Place"
        case build = "Build"
    }

    var group: Group {
        switch self {
        case .briefcase, .growth, .money, .building, .people, .target:  return .work
        case .hammer, .paintbrush, .tools, .camera, .music, .stage:     return .make
        case .puzzle, .book, .study, .brain, .pencil, .talk:            return .mind
        case .heart, .run, .food, .leaf, .rest, .care:                  return .body
        case .house, .flight, .map, .globe, .car, .outdoors:            return .place
        case .laptop, .phone, .network, .terminal, .settings, .signal:  return .build
        }
    }

    static func grouped() -> [(group: Group, symbols: [SpaceSymbol])] {
        Group.allCases.map { group in
            (group, allCases.filter { $0.group == group })
        }
    }

    static func named(_ symbolName: String) -> SpaceSymbol? {
        SpaceSymbol(rawValue: symbolName)
    }

    // MARK: - Choosing one

    /// Words that point at an icon, checked against the Space's name.
    ///
    /// Longer phrases first so "meal prep" is not claimed by "prep", and specific before
    /// general so a Space called "Client tracking app" reads as software rather than as
    /// clients. This is a lookup table, not intelligence — it exists so that a new Space
    /// arrives looking like *something* instead of like every other Space.
    private static let hints: [(needles: [String], symbol: SpaceSymbol)] = [
        (["workout", "fitness", "gym", "training", "trainer", "run", "exercise"], .run),
        (["meal", "food", "recipe", "cook", "kitchen", "restaurant", "tender", "menu"], .food),
        (["app", "software", "code", "coding", "dev", "engineering", "product"], .laptop),
        (["business", "client", "company", "consult", "agency", "work"], .briefcase),
        (["money", "finance", "invest", "budget", "revenue", "pricing", "sales"], .money),
        (["market", "brand", "content", "social", "audience", "newsletter"], .talk),
        (["music", "song", "audio", "podcast", "record"], .music),
        (["photo", "video", "film", "camera", "shoot"], .camera),
        (["health", "medical", "therapy", "doctor", "wellness"], .care),
        (["home", "house", "family", "renovation", "garden"], .house),
        (["travel", "trip", "holiday", "flight", "vacation"], .flight),
        (["study", "learn", "course", "school", "university", "class"], .study),
        (["write", "writing", "book", "reading", "blog", "essay"], .book),
        (["build", "make", "craft", "wood", "diy", "repair"], .tools),
        (["property", "real estate", "office", "building"], .building),
        (["outdoor", "hike", "camp", "nature", "mountain"], .outdoors),
        (["car", "vehicle", "drive", "auto"], .car),
        (["team", "people", "hiring", "community", "network"], .people),
        (["goal", "target", "plan", "strategy"], .target),
        (["idea", "thought", "concept", "brainstorm"], .brain),
    ]

    /// A sensible icon for a name, and never the same one for everything.
    ///
    /// Falls back to a hash of the name rather than to a default, so two Spaces the table
    /// knows nothing about still get different icons. A wrong-but-distinct icon is a far
    /// better outcome than six identical ones: the icon's job on the Spaces grid is to let
    /// you find the right tile without reading, and identical icons cannot do that at all.
    static func suggested(for name: String) -> SpaceSymbol {
        let lowered = name.lowercased()

        for hint in hints where hint.needles.contains(where: { lowered.contains($0) }) {
            return hint.symbol
        }

        var hash: UInt64 = 5381
        for byte in lowered.utf8 {
            hash = (hash &* 33) &+ UInt64(byte)
        }
        return allCases[Int(hash % UInt64(allCases.count))]
    }

    /// The placeholders that mean "nobody has chosen yet" — the hard-coded default every
    /// hand-made Space was born with, and the model's stock answer.
    static let genericNames: Set<String> = ["square.stack.3d.up", "folder", "tray", "lightbulb"]
}
