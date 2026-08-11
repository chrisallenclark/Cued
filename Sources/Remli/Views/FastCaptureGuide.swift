import SwiftUI

/// How to get an idea into Remli without opening Remli.
///
/// Every route on this screen already worked before the screen existed. That is exactly the
/// problem it solves: the Action Button, the Lock Screen button, Control Centre, Back Tap
/// and two Siri phrases have all shipped for months, and none of them were mentioned
/// anywhere in the app, so none of them were ever set up. A capability nobody knows about
/// is worth precisely as much as one that was never built.
///
/// So this is documentation, deliberately, rather than a feature. It says what each route
/// does, how fast it is, and the exact taps to set it up — including the one route that
/// needs no setup at all and is faster than all the others.
struct FastCaptureGuide: View {

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Theme.Space.lg) {

                VStack(alignment: .leading, spacing: Theme.Space.xs) {
                    Text("The gap between having a thought and capturing it is the only thing that decides whether you keep it. Every route below closes that gap differently — pick one and set it up once.")
                        .font(Theme.Typography.meta)
                        .foregroundStyle(Theme.Palette.inkMuted)
                        .lineSpacing(3)
                        .fixedSize(horizontal: false, vertical: true)
                }

                ForEach(FastCaptureRoute.all) { route in
                    RouteCard(route: route)
                }

                limitNote

                Spacer(minLength: Theme.Space.xl)
            }
            .padding(Theme.Space.md)
        }
        .background(Theme.Palette.canvas)
        .navigationTitle("Fast capture")
        .navigationBarTitleDisplayMode(.inline)
    }

    /// The thing it would be dishonest to leave out.
    private var limitNote: some View {
        VStack(alignment: .leading, spacing: Theme.Space.xxs) {
            Label("Why most of these still open Remli", systemImage: "info.circle")
                .font(Theme.Typography.control)
                .foregroundStyle(Theme.Palette.ink)

            Text("Recording needs the microphone, and iOS only gives an app the microphone while it is on screen. So the button routes open Remli — straight into a live recording, with nothing to tap. Siri is the only way to capture without the app appearing at all, because Siri does the listening.")
                .font(Theme.Typography.meta)
                .foregroundStyle(Theme.Palette.inkMuted)
                .lineSpacing(3)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .cardBackground()
    }
}

// MARK: - The routes

struct FastCaptureRoute: Identifiable {

    let id: String
    let name: String
    let symbol: String
    /// A short verdict rather than a number — "two taps" means more than "1.4 seconds".
    let speed: String
    /// What the phone has to be, when that matters.
    let requires: String?
    let happens: String
    let steps: [String]

    /// Fastest first, which is also roughly hardest-to-discover first.
    static let all: [FastCaptureRoute] = [

        FastCaptureRoute(
            id: "siri-save",
            name: "Say it to Siri",
            symbol: "waveform",
            speed: "Fastest — Remli never opens",
            requires: nil,
            happens: """
                Say “Add an idea to Remli: buy a tripod for the YouTube setup.” Siri answers \
                “Saved.” and that is the whole interaction — the app does not launch, and you \
                stay in whatever you were doing. Remli reads it, titles it and files it into a \
                Space the next time you open the app.
                """,
            steps: [
                "Nothing to set up. Try it now.",
                "It works with the screen locked.",
            ]
        ),

        FastCaptureRoute(
            id: "action-button",
            name: "Action Button",
            symbol: "bolt.circle",
            speed: "Press and hold",
            requires: "iPhone 15 Pro and later, or any iPhone 16",
            happens: """
                Hold the button and Remli opens already recording — no tap, no screen to find. \
                Speak, and the words appear as you talk. Let go and it saves.
                """,
            steps: [
                "Settings → Action Button",
                "Swipe across to Controls",
                "Tap Choose a Control",
                "Pick Capture an idea, or Write an idea for the keyboard instead",
            ]
        ),

        FastCaptureRoute(
            id: "back-tap",
            name: "Tap the back of the phone",
            symbol: "hand.tap",
            speed: "Two taps, screen off",
            requires: nil,
            happens: """
                Double-tap the back of the phone and Remli opens recording. The closest thing \
                to a hardware button on a phone that has not got one, and it works through a \
                case.
                """,
            steps: [
                "Open Shortcuts and make a new shortcut",
                "Add the action Capture an idea, and name it",
                "Settings → Accessibility → Touch → Back Tap",
                "Choose Double Tap, then pick the shortcut you made",
            ]
        ),

        FastCaptureRoute(
            id: "lock-screen-button",
            name: "Lock Screen button",
            symbol: "lock.iphone",
            speed: "One tap, still locked",
            requires: nil,
            happens: """
                Replaces the torch or camera button at the bottom of the Lock Screen. One tap \
                from a locked phone into a live recording.
                """,
            steps: [
                "Press and hold the Lock Screen, then tap Customise",
                "Tap Lock Screen",
                "Tap the torch or camera button to swap it",
                "Choose Capture an idea",
            ]
        ),

        FastCaptureRoute(
            id: "control-centre",
            name: "Control Centre",
            symbol: "switch.2",
            speed: "Swipe and tap",
            requires: nil,
            happens: """
                A Remli button alongside the torch and the calculator. Useful as a backup to \
                whichever route you actually set up.
                """,
            steps: [
                "Swipe down from the top-right corner",
                "Tap the + in the corner, then Add a Control",
                "Search for Remli",
            ]
        ),

        FastCaptureRoute(
            id: "widgets",
            name: "Widgets",
            symbol: "square.grid.2x2",
            speed: "One tap",
            requires: nil,
            happens: """
                A capture button on the Lock Screen under the clock, or on the Home Screen. \
                The Home Screen one is the least fast route here, and the easiest to remember \
                is there.
                """,
            steps: [
                "Press and hold the Lock Screen or Home Screen",
                "Tap Customise or the + in the corner",
                "Add Remli’s Capture widget",
            ]
        ),

        FastCaptureRoute(
            id: "siri-open",
            name: "Ask Siri to open recording",
            symbol: "mic.badge.plus",
            speed: "Hands free",
            requires: nil,
            happens: """
                Say “Capture an idea in Remli” and it opens listening, so you can talk for as \
                long as you like rather than fitting the thought into one sentence for Siri.
                """,
            steps: [
                "Nothing to set up.",
                "Say “Write an idea in Remli” for the keyboard instead.",
            ]
        ),
    ]
}

private struct RouteCard: View {
    let route: FastCaptureRoute

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Space.sm) {

            HStack(alignment: .top, spacing: Theme.Space.sm) {
                Image(systemName: route.symbol)
                    .font(.system(size: 17, weight: .light))
                    .foregroundStyle(Theme.Palette.ember)
                    .frame(width: 26)

                VStack(alignment: .leading, spacing: 2) {
                    Text(route.name)
                        .font(Theme.Typography.title)
                        .foregroundStyle(Theme.Palette.ink)
                        .fixedSize(horizontal: false, vertical: true)

                    Text(route.speed)
                        .font(.system(.caption2, design: .monospaced))
                        .foregroundStyle(Theme.Palette.ember.opacity(0.9))

                    if let requires = route.requires {
                        Text(requires)
                            .font(Theme.Typography.meta)
                            .foregroundStyle(Theme.Palette.inkMuted.opacity(0.8))
                    }
                }
            }

            Text(route.happens)
                .font(Theme.Typography.meta)
                .foregroundStyle(Theme.Palette.inkMuted)
                .lineSpacing(3)
                .fixedSize(horizontal: false, vertical: true)

            Divider().overlay(Theme.Palette.hairline)

            VStack(alignment: .leading, spacing: Theme.Space.xxs) {
                ForEach(Array(route.steps.enumerated()), id: \.offset) { index, step in
                    HStack(alignment: .top, spacing: Theme.Space.xs) {
                        // Numbered only when the order matters. A single line that says
                        // "nothing to set up" is not step one of anything.
                        if route.steps.count > 1 {
                            Text("\(index + 1)")
                                .font(.system(.caption2, design: .monospaced))
                                .foregroundStyle(Theme.Palette.inkMuted.opacity(0.7))
                                .frame(width: 12, alignment: .trailing)
                        }

                        Text(step)
                            .font(Theme.Typography.meta)
                            .foregroundStyle(Theme.Palette.ink.opacity(0.85))
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .cardBackground()
    }
}
