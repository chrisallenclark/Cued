import Foundation
import SwiftData

/// A captured thought.
///
/// **Every stored property has a default and every relationship is optional.** That is not
/// stylistic — it is what CloudKit requires of a SwiftData model. Getting this wrong only
/// shows up when sync is switched on, at which point fixing it means a migration, so the
/// constraint is honoured from the first commit even though CloudKit arrives later.
///
/// Note also that there are no `@Attribute(.unique)` constraints anywhere in the schema:
/// CloudKit does not support them.
@Model
final class Idea {

    // MARK: Identity

    var id: UUID = UUID()
    var createdAt: Date = Date.now
    var updatedAt: Date = Date.now

    // MARK: Content

    /// A short human title. Written by the model during enrichment; until then it is
    /// empty and the UI falls back to the first line of `text`.
    var title: String = ""

    /// The idea itself, as the user will read it back.
    var text: String = ""

    /// For voice captures, the untouched transcript before any clean-up. Kept so a bad
    /// tidy-up is always recoverable. The audio itself is never retained.
    var transcriptRaw: String?

    // MARK: Classification

    var kindRaw: String = IdeaKind.idea.rawValue
    var statusRaw: String = IdeaStatus.seed.rawValue
    var captureModeRaw: String = CaptureMode.text.rawValue

    var tags: [String] = []

    /// 0–1, written during enrichment. The *model's* guess, never the last word.
    var importanceScore: Double = 0

    /// Your correction to that guess, when you have made one.
    ///
    /// Kept as a second field rather than overwriting `importanceScore`, for two reasons.
    /// Enrichment can keep running and re-guessing without ever silently undoing your
    /// judgement — which it would, since a re-enriched idea is a completely normal event.
    /// And the guess stays available next to your answer, which is the only way to ever
    /// find out whether the model is any good at this.
    ///
    /// Optional rather than a sentinel: `nil` means *you have not weighed in*, which is a
    /// different statement from *you said zero*.
    var importanceOverride: Double?

    /// Rough effort in minutes. Used to match an idea to a gap in the calendar — there is
    /// no point suggesting a two-day project for a twenty-minute window.
    var estimatedMinutes: Int = 0

    var pinned: Bool = false

    /// Marked by the person as something they intend to build.
    ///
    /// This is what gives Roadmaps a starting point. Before it existed, a roadmap could
    /// only appear if the model spontaneously decided one idea unlocked another — so a
    /// library of genuinely good, genuinely unrelated ideas produced an empty screen and no
    /// way to change that. Declaring a goal is the one judgement the app should never make
    /// on your behalf: it is the difference between an idea you had and a thing you are
    /// doing, and only you know which is which.
    var isGoal: Bool = false

    /// Where this sits among a goal's steps. Only meaningful for roadmap steps.
    var stepOrder: Int = 0

    /// Steps and questions turned down in the workshop.
    ///
    /// Kept per-idea rather than globally: "who is your first customer" is a lazy question
    /// about a finished product and the right question about a new one, so a rejection here
    /// says something about *this* idea, not about the question. Fed back into the prompt so
    /// the same miss is never offered twice, which is the whole of the learning loop —
    /// dismissals are the only signal given for free.
    var dismissedSuggestions: [String] = []

    // MARK: Resurfacing state

    /// Set when the user explicitly snoozes an idea to a date.
    var remindAt: Date?
    var lastSurfacedAt: Date?
    var surfaceCount: Int = 0

    // MARK: Machine state

    /// False until the intelligence layer has been over this idea. Capture writes the
    /// record immediately and enrichment patches it afterwards, so an un-enriched idea is
    /// a completely normal state, not an error.
    var isEnriched: Bool = false

    /// Counts failed enrichment attempts so a thought the model consistently chokes on
    /// gets left alone rather than retried on every single app launch forever.
    var enrichmentAttempts: Int = 0

    /// Sentence embedding, stored as packed little-endian `Float32`. `Data` rather than
    /// `[Double]` keeps the record small enough that CloudKit sync stays cheap.
    var embedding: Data?

    /// When the connection engine last looked for links from this idea. Nil means it never
    /// has. Kept as a date rather than a flag so ideas can be re-linked later, once there
    /// are more neighbours for them to connect to.
    var linkedAt: Date?

    /// Retry budget for link finding, for the same reason `enrichmentAttempts` exists.
    var linkAttempts: Int = 0

    // MARK: Relationships

    var category: IdeaCategory?

    @Relationship(deleteRule: .cascade, inverse: \IdeaLink.source)
    var outgoingLinks: [IdeaLink]?

    @Relationship(deleteRule: .cascade, inverse: \IdeaLink.target)
    var incomingLinks: [IdeaLink]?

    // MARK: Init

    init(
        text: String,
        kind: IdeaKind = .idea,
        captureMode: CaptureMode = .text,
        transcriptRaw: String? = nil
    ) {
        self.id = UUID()
        self.createdAt = .now
        self.updatedAt = .now
        self.text = text
        self.kindRaw = kind.rawValue
        self.captureModeRaw = captureMode.rawValue
        self.transcriptRaw = transcriptRaw
    }
}

// MARK: - Typed accessors

extension Idea {
    var kind: IdeaKind {
        get { IdeaKind(rawValue: kindRaw) ?? .idea }
        set { kindRaw = newValue.rawValue }
    }

    var status: IdeaStatus {
        get { IdeaStatus(rawValue: statusRaw) ?? .seed }
        set { statusRaw = newValue.rawValue }
    }

    var captureMode: CaptureMode {
        get { CaptureMode(rawValue: captureModeRaw) ?? .text }
        set { captureModeRaw = newValue.rawValue }
    }

    /// What to show as a heading. Enrichment may not have run — or may have failed — so
    /// this always has something sensible to fall back on.
    var displayTitle: String {
        if !title.isEmpty { return title }

        let firstLine = text
            .split(separator: "\n", omittingEmptySubsequences: true)
            .first
            .map(String.init)?
            .trimmingCharacters(in: .whitespaces) ?? ""

        if firstLine.isEmpty { return "Untitled" }
        return firstLine.count <= 60 ? firstLine : String(firstLine.prefix(60)) + "…"
    }

    // MARK: Importance

    /// What importance actually is: yours if you said, the model's otherwise.
    ///
    /// **Everything that ranks ideas reads this, not `importanceScore`** — resurfacing for
    /// what comes back at you, the map for how big a node sits. An override that changed
    /// nothing visible would be a placebo, and the fastest way to teach someone that their
    /// input does not matter.
    var importance: Double {
        importanceOverride ?? importanceScore
    }

    /// Whether you have weighed in.
    var importanceIsUserSet: Bool { importanceOverride != nil }

    /// The effective level, as a person would say it.
    var importanceLevel: ImportanceLevel { .nearest(to: importance) }

    /// What enrichment landed on, kept reachable after you disagree so the two can be
    /// compared. Meaningless until the idea has actually been enriched.
    var importanceGuessLevel: ImportanceLevel { .nearest(to: importanceScore) }

    /// Sets your level, or clears back to the model's guess when passed `nil`.
    func setImportance(_ level: ImportanceLevel?) {
        importanceOverride = level?.score
        touch()
    }

    /// Names the idea yourself.
    ///
    /// Enrichment only ever writes `title` when it is empty, so a name you have typed is
    /// safe from the next pass without needing a flag to protect it.
    ///
    /// Clearing it back to nothing is a real choice rather than a mistake: `displayTitle`
    /// then falls back to the first line of the idea, which for a short thought is often
    /// the best name it could have. Note that on an idea Remli has *already* named, that
    /// fallback is where it stays — enrichment does not run twice, so the generated name
    /// is not recoverable once replaced.
    func setTitle(_ newTitle: String) {
        let trimmed = newTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed != title else { return }
        title = trimmed
        touch()
    }

    /// Every link touching this idea, in either direction.
    var allLinks: [IdeaLink] {
        (outgoingLinks ?? []) + (incomingLinks ?? [])
    }

    /// A to-do that exists as a step towards something else.
    ///
    /// These are created by the workshop and by adding a step to a roadmap, and they belong
    /// **only** on that roadmap. Left in the Ideas list they read as ideas you had, which is
    /// exactly wrong: "Price three suppliers" is not a thought worth keeping, it is a thing
    /// to do on the way to one — and a list of twenty of them buries the ideas underneath.
    ///
    /// Derived rather than stored, so detaching a step from its roadmap quietly turns it
    /// back into an ordinary to-do instead of leaving it invisible forever.
    var isRoadmapStep: Bool {
        guard kind == .task else { return false }
        return (outgoingLinks ?? []).contains { $0.isActive && $0.kind == .prerequisiteFor }
    }

    /// Position on its roadmap. Ties break on creation order, which is the order they were
    /// added and usually the order they were meant.
    var stepRank: Int { stepOrder }

    /// The colour of the **Space** this idea lives in, not the Collection inside it.
    ///
    /// A Collection inherits its Space's colour, so most of the time these are the same —
    /// but "most of the time" is not good enough for the map, where a Collection that has
    /// drifted would draw a node in a colour matching no filter chip on the screen. Reading
    /// the root makes "the nodes are the colour of their Space" true by construction rather
    /// than by everything downstream staying in step.
    var spaceColorHex: String? { category?.rootFolder.colorHex }

    func touch() {
        updatedAt = .now
    }
}

// MARK: - Listing

extension Sequence where Element == Idea {

    /// Everything except roadmap steps.
    ///
    /// **Every screen that lists or counts ideas must go through this.** Steps were being
    /// filtered in exactly one place — the Ideas list — which is how they went on appearing
    /// inside Spaces, inflating Space counts and padding the weekly total, all while
    /// looking fixed. Filtering by hand at each call site is what produced that, so the
    /// rule now has one name and one implementation.
    ///
    /// "Price three suppliers" is not a thought worth keeping; it is a thing to do on the
    /// way to one. It belongs under its goal and nowhere else. A to-do *list* may still
    /// show it — it genuinely is a to-do — but an *idea* listing may not.
    var excludingSteps: [Idea] {
        filter { !$0.isRoadmapStep }
    }
}
