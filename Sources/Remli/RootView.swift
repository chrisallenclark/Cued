import Combine
import SwiftData
import SwiftUI

/// The app shell.
///
/// Four tabs, each earning its place: Ideas is everything you have thought, Spaces is what
/// you are working on, Map shows the whole library at once, and Roadmaps finds something to
/// start on. Capture is a floating action rather than a tab, because it has to be reachable
/// from anywhere without a mode change.
///
/// Review sits in the toolbar rather than the tab bar. It is a deliberate sit-down you do
/// occasionally, not somewhere you navigate to between thoughts, and a tab bar should hold
/// the places you move *between* — spending a fifth of it on a weekly ritual crowds out
/// Spaces, which you touch constantly.
struct RootView: View {

    var storeIsEphemeral: Bool = false

    @Environment(\.modelContext) private var context
    @Environment(\.scenePhase) private var scenePhase

    @State private var isCapturing = false
    @State private var isShowingSettings = false
    @State private var isShowingReview = false

    /// Set by the widget / Action Button / Siri route, which open with the mic already hot.
    @State private var captureStartsWithVoice = false

    /// Built here rather than in `RemliApp.init` so they can take the environment's model
    /// context and stay on the main actor without any isolation gymnastics.
    @State private var enrichment: EnrichmentService?
    @State private var connections: ConnectionEngine?
    @State private var coordinator: ResurfacingCoordinator?
    @State private var settingsStore = ResurfacingSettingsStore()
    @State private var appearance = AppearanceStore()
    @State private var router = NotificationRouter()

    var body: some View {
        TabView {
            Tab("Ideas", systemImage: "square.stack") {
                NavigationStack {
                    IdeasListView()
                        .background(Theme.Palette.canvas)
                        .navigationTitle("Ideas")
                        .navigationBarTitleDisplayMode(.large)
                        .toolbar {
                            ToolbarItem(placement: .topBarTrailing) {
                                Button {
                                    isShowingReview = true
                                } label: {
                                    Image(systemName: "calendar.day.timeline.left")
                                }
                            }

                            ToolbarItem(placement: .topBarTrailing) {
                                Button {
                                    isShowingSettings = true
                                } label: {
                                    Image(systemName: "gearshape")
                                }
                            }
                        }
                        .safeAreaInset(edge: .bottom) {
                            CaptureButton {
                                captureStartsWithVoice = false
                                isCapturing = true
                            }
                        }
                }
            }

            Tab("Spaces", systemImage: "square.grid.2x2") {
                NavigationStack { SpacesView() }
            }

            Tab("Map", systemImage: "point.3.filled.connected.trianglepath.dotted") {
                NavigationStack { MapView() }
            }

            Tab("Roadmaps", systemImage: "arrow.triangle.branch") {
                NavigationStack { RoadmapsView() }
            }

        }
        .sheet(isPresented: $isCapturing, onDismiss: runBacklog) {
            CaptureSheet(autoStartVoice: captureStartsWithVoice)
        }
        // Widgets still arrive as URLs — `widgetURL` is the only mechanism they have — so
        // this stays. The Action Button, Control Centre and Siri no longer use it.
        .onOpenURL { url in
            guard let wantsVoice = CaptureRoute.wantsVoice(url) else { return }
            captureStartsWithVoice = wantsVoice
            isCapturing = true
        }
        // Three chances to notice, because the intent and the app race and either can win.
        //
        // Cold launch: the intent runs before this view exists, so the request is already
        // waiting when `onAppear` fires. Warm launch: the app comes forward first and the
        // notification arrives after. Everything else: becoming active catches it. All
        // three read the same one-shot flag, so whichever gets there first wins and the
        // other two find nothing.
        .onAppear(perform: consumeCaptureRequest)
        .onReceive(NotificationCenter.default.publisher(for: .remliCaptureRequested)) { _ in
            consumeCaptureRequest()
        }
        .sheet(isPresented: $isShowingSettings) {
            if let coordinator {
                SettingsView(
                    store: settingsStore,
                    coordinator: coordinator,
                    appearance: appearance
                )
            }
        }
        .sheet(isPresented: $isShowingReview) {
            NavigationStack {
                ReviewView(coordinator: coordinator)
            }
        }
        // A tapped notification opens the idea it was about. Landing on a generic list
        // would waste the interruption entirely.
        .sheet(item: Binding(
            get: { router.pendingIdeaID.map(IdentifiedUUID.init) },
            set: { router.pendingIdeaID = $0?.id }
        )) { wrapper in
            NavigationStack {
                SurfacedIdeaView(ideaID: wrapper.id, coordinator: coordinator)
            }
        }
        .overlay(alignment: .top) {
            if storeIsEphemeral {
                EphemeralStoreBanner()
            }
        }
        .task {
            if enrichment == nil {
                enrichment = EnrichmentService(context: context)
                connections = ConnectionEngine(context: context)
                coordinator = ResurfacingCoordinator(context: context, settingsStore: settingsStore)
                router.install()
            }
            await processBacklog()
            await coordinator?.refresh()
        }
        // Applied once, at the root, so every sheet and every tab inherits it. Nil means
        // follow the phone, which is the default and the only answer that is never wrong.
        .preferredColorScheme(appearance.appearance.colorScheme)
        .onChange(of: scenePhase) { _, phase in
            if phase == .active {
                consumeCaptureRequest()
            }

            // Leaving the app is the moment to queue the next background pass and make
            // sure the plan reflects anything captured this session.
            if phase == .background {
                ResurfacingCoordinator.scheduleBackgroundRefresh()
            }
        }
    }

    /// Opens capture if a button asked for it. Safe to call repeatedly — the request is
    /// cleared as it is read, so the second and third callers get nothing.
    private func consumeCaptureRequest() {
        guard let mode = CaptureLaunchRequest.take() else { return }
        captureStartsWithVoice = mode == .voice
        isCapturing = true
    }

    private func runBacklog() {
        Task {
            await processBacklog()
            await coordinator?.refresh()
        }
    }

    /// Enrichment first, then linking — linking reads the title and category that
    /// enrichment produces, so the order is a real dependency rather than a preference.
    private func processBacklog() async {
        await enrichment?.run()
        await connections?.run()
    }
}

/// `sheet(item:)` needs an `Identifiable`, and `UUID` alone is not.
private struct IdentifiedUUID: Identifiable {
    let id: UUID
}

/// Resolves the idea a notification referred to, and records that it was surfaced.
private struct SurfacedIdeaView: View {
    let ideaID: UUID
    let coordinator: ResurfacingCoordinator?

    @Query private var matches: [Idea]

    init(ideaID: UUID, coordinator: ResurfacingCoordinator?) {
        self.ideaID = ideaID
        self.coordinator = coordinator
        _matches = Query(filter: #Predicate<Idea> { $0.id == ideaID })
    }

    var body: some View {
        Group {
            if let idea = matches.first {
                IdeaDetailView(idea: idea)
            } else {
                // The idea was deleted between the notification being scheduled and tapped.
                ContentUnavailableView(
                    "That idea is gone",
                    systemImage: "questionmark.circle",
                    description: Text("It was deleted after this reminder was scheduled.")
                )
            }
        }
        .onAppear { coordinator?.markSurfaced(ideaID: ideaID) }
    }
}

/// The primary action, and the reason the app exists. Given prominence accordingly: a
/// wide target at the bottom of the screen, reachable one-handed.
private struct CaptureButton: View {
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: Theme.Space.xs) {
                Image(systemName: "plus.circle.fill")
                    .font(.system(size: 20, weight: .semibold))
                Text("Capture")
                    .font(Theme.Typography.control)
            }
            .foregroundStyle(Theme.Palette.canvas)
            .frame(maxWidth: .infinity)
            .padding(.vertical, Theme.Space.md)
            .background(
                Capsule(style: .continuous).fill(Theme.Palette.ember)
            )
        }
        .buttonStyle(.plain)
        .padding(.horizontal, Theme.Space.lg)
        .padding(.bottom, Theme.Space.xs)
        .background(.ultraThinMaterial)
    }
}

/// Shown when the persistent store could not be opened and the app is running against
/// memory only. Being loud about this is the honest choice — anything captured in this
/// state will not survive a relaunch.
private struct EphemeralStoreBanner: View {
    var body: some View {
        Text("Storage unavailable — ideas captured now won't be saved.")
            .font(Theme.Typography.meta)
            .foregroundStyle(Theme.Palette.canvas)
            .padding(.horizontal, Theme.Space.md)
            .padding(.vertical, Theme.Space.xs)
            .frame(maxWidth: .infinity)
            .background(Color.red.opacity(0.9))
    }
}

#Preview {
    RootView()
        .modelContainer(try! RemliSchema.makeContainer(inMemory: true))
}
