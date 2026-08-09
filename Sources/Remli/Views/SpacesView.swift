import SwiftData
import SwiftUI

/// All your Spaces, as a deck you swipe through.
///
/// It was a grid of small tiles, which is the right shape for a folder list and the wrong
/// one for this. Spaces are not files; the claim the app makes is that each one is a
/// different part of your life and should *feel* different, and four thumbnails in a
/// two-up grid flattens them all into one screen of samey rectangles.
///
/// One card at a time, filling most of the width, with its neighbours peeking in at the
/// edges. The peeking is the whole trick: it says "there are more of these" without a
/// control, and it makes the sideways swipe the obvious thing to try. The card you are on
/// is the only one at full size and full brightness, so arriving at a Space is an event
/// rather than a row selection.
///
/// The ground behind the deck takes on the centred Space's own picture, blurred past
/// recognition. That is the cheapest possible way to make moving between Spaces feel like
/// moving between rooms, and it costs no new artwork — it reuses the cover already chosen.
struct SpacesView: View {

    @Query(sort: \IdeaCategory.name)
    private var allPlaces: [IdeaCategory]

    @Environment(\.modelContext) private var context

    @State private var isNaming = false
    @State private var newName = ""

    /// Which card is under the reader. Drives the backdrop and the position indicator.
    @State private var centredSpaceID: UUID?

    @State private var containerWidth: CGFloat = 0

    private var spaces: [IdeaCategory] {
        // Busiest first: a Space you are actually using should not sit below one the model
        // invented once and never filled.
        allPlaces
            .filter(\.isSpace)
            .sorted { lhs, rhs in
                if lhs.totalIdeaCount == rhs.totalIdeaCount {
                    return lhs.name.localizedStandardCompare(rhs.name) == .orderedAscending
                }
                return lhs.totalIdeaCount > rhs.totalIdeaCount
            }
    }

    private var centredSpace: IdeaCategory? {
        guard let centredSpaceID else { return spaces.first }
        return spaces.first { $0.id == centredSpaceID } ?? spaces.first
    }

    /// Wide enough to dominate, narrow enough that both neighbours show. Below about 0.7
    /// the card stops feeling like a place and starts feeling like a tile again.
    private var cardWidth: CGFloat {
        max(containerWidth * 0.72, 200)
    }

    /// Half the leftover, so the first and last cards can sit dead centre like every other.
    private var sideMargin: CGFloat {
        max((containerWidth - cardWidth) / 2, 0)
    }

    private var cardHeight: CGFloat {
        min(cardWidth * 1.34, 430)
    }

    var body: some View {
        ZStack {
            ambience

            if spaces.isEmpty {
                emptyState
            } else {
                VStack(spacing: Theme.Space.md) {
                    Spacer(minLength: 0)
                    deck
                    positionIndicator
                    Spacer(minLength: 0)
                }
            }
        }
        .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { containerWidth = $0 }
        .navigationTitle("Spaces")
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    newName = ""
                    isNaming = true
                } label: {
                    Image(systemName: "plus")
                }
                .accessibilityLabel("New Space")
            }
        }
        // An alert rather than an inline field. The deck fills the screen by design, so
        // there is no longer a sensible strip of it to grow a text box in.
        .alert("New Space", isPresented: $isNaming) {
            TextField("Name", text: $newName)
                .autocorrectionDisabled()
            Button("Cancel", role: .cancel) { newName = "" }
            Button("Create", action: commit)
        } message: {
            Text("A part of your life rather than a project — Business, Health, Macrova.")
        }
        .task(id: spaces.count) {
            if centredSpaceID == nil || !spaces.contains(where: { $0.id == centredSpaceID }) {
                centredSpaceID = spaces.first?.id
            }
        }
    }

    // MARK: - The deck

    private var deck: some View {
        ScrollView(.horizontal) {
            LazyHStack(spacing: Theme.Space.sm) {
                ForEach(spaces) { space in
                    NavigationLink {
                        SpaceView(space: space)
                    } label: {
                        SpaceCard(
                            space: space,
                            isCentred: space.id == centredSpaceID
                        )
                        .frame(width: cardWidth, height: cardHeight)
                    }
                    .buttonStyle(.plain)
                    // Interactive rather than stepped, so the card under your thumb grows
                    // as you drag instead of snapping when it wins. The movement is what
                    // makes the deck feel like objects rather than pages.
                    .scrollTransition(.interactive, axis: .horizontal) { content, phase in
                        content
                            .scaleEffect(1 - abs(phase.value) * 0.10)
                            .opacity(1 - abs(phase.value) * 0.45)
                    }
                }
            }
            .scrollTargetLayout()
        }
        .scrollTargetBehavior(.viewAligned)
        .scrollIndicators(.hidden)
        .contentMargins(.horizontal, sideMargin, for: .scrollContent)
        .scrollPosition(id: $centredSpaceID)
        .frame(height: cardHeight)
    }

    /// Dots while there are few enough to count at a glance, a tally once there are not.
    @ViewBuilder
    private var positionIndicator: some View {
        if spaces.count > 1 {
            if spaces.count <= 8 {
                HStack(spacing: 6) {
                    ForEach(spaces) { space in
                        Circle()
                            .fill(
                                space.id == centredSpaceID
                                    ? space.color
                                    : Theme.Palette.inkMuted.opacity(0.3)
                            )
                            .frame(
                                width: space.id == centredSpaceID ? 7 : 5,
                                height: space.id == centredSpaceID ? 7 : 5
                            )
                    }
                }
                .animation(Theme.Motion.standard, value: centredSpaceID)
            } else {
                let index = spaces.firstIndex { $0.id == centredSpaceID }.map { $0 + 1 } ?? 1
                Text("\(index) of \(spaces.count)")
                    .font(.system(.caption2, design: .monospaced))
                    .foregroundStyle(Theme.Palette.inkMuted)
            }
        }
    }

    // MARK: - The room

    /// The centred Space's own cover, blurred past recognition, behind everything.
    ///
    /// Cross-faded rather than cut, because the point is that you have moved somewhere.
    private var ambience: some View {
        ZStack {
            Theme.Palette.canvas

            if let centredSpace {
                SpaceAmbience(space: centredSpace)
                    .id(centredSpace.id)
                    .transition(.opacity)
            }
        }
        .animation(.easeInOut(duration: 0.5), value: centredSpaceID)
        .ignoresSafeArea()
    }

    // MARK: - Creating one

    private var trimmedName: String {
        newName.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func commit() {
        let name = trimmedName
        guard !name.isEmpty else {
            newName = ""
            return
        }

        let normalized = name.lowercased()
        if !spaces.contains(where: { $0.name.lowercased() == normalized }) {
            let space = IdeaCategory(
                name: name,
                // Guessed from the name rather than the same hard-coded glyph for
                // everything. The icon's job on the deck is to let you recognise a card
                // without reading it, and six identical icons cannot do that at all.
                symbolName: SpaceSymbol.suggested(for: name).symbolName,
                isUserOwned: true
            )
            context.insert(space)
            centredSpaceID = space.id
        }

        newName = ""
    }

    private var emptyState: some View {
        VStack(spacing: Theme.Space.sm) {
            Image(systemName: "square.stack.3d.up")
                .font(.system(size: 34, weight: .light))
                .foregroundStyle(Theme.Palette.ember)

            Text("No Spaces yet")
                .font(Theme.Typography.title)
                .foregroundStyle(Theme.Palette.ink)

            Text("Capture a few ideas and Remli will start\nsorting them into Spaces. You can make\nyour own at any time.")
                .font(Theme.Typography.meta)
                .multilineTextAlignment(.center)
                .foregroundStyle(Theme.Palette.inkMuted)
                .lineSpacing(3)
        }
        .frame(maxWidth: .infinity)
        .padding(.horizontal, Theme.Space.lg)
    }
}

/// One Space, as a card you could walk into.
private struct SpaceCard: View {
    let space: IdeaCategory
    let isCentred: Bool

    private var subtitle: String {
        let count = space.totalIdeaCount
        return "\(count) \(count == 1 ? "idea" : "ideas")"
    }

    var body: some View {
        ZStack(alignment: .bottomLeading) {
            SpaceCover(space: space, cornerRadius: Theme.Radius.lg)

            VStack(alignment: .leading, spacing: 3) {
                Image(systemName: space.symbolName)
                    .font(.system(size: 22, weight: .light))
                    .foregroundStyle(.white.opacity(0.94))
                    .padding(.bottom, Theme.Space.xs)

                Text(space.name)
                    .font(Theme.Typography.title)
                    .foregroundStyle(.white)
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)
                    .fixedSize(horizontal: false, vertical: true)

                Text(subtitle)
                    .font(Theme.Typography.meta)
                    .foregroundStyle(.white.opacity(0.74))
            }
            .padding(Theme.Space.md)
            // Type sits over an unknown photograph, so it carries its own shadow rather
            // than trusting the darkening ramp alone.
            .shadow(color: .black.opacity(0.5), radius: 8, y: 1)
        }
        // A ring in the Space's own colour, on the card you are actually on. Faint, because
        // scale and brightness have already said which one it is — this only confirms it.
        .overlay(
            RoundedRectangle(cornerRadius: Theme.Radius.lg, style: .continuous)
                .strokeBorder(
                    isCentred ? space.color.opacity(0.55) : .white.opacity(0.08),
                    lineWidth: isCentred ? 1.5 : 0.5
                )
        )
        .shadow(color: .black.opacity(isCentred ? 0.45 : 0.2), radius: isCentred ? 22 : 10, y: 10)
        .animation(Theme.Motion.standard, value: isCentred)
    }
}
