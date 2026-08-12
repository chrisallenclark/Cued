import Foundation
import Testing

@testable import Remli

/// The handoff between a button press and the app opening on the microphone.
///
/// This is where the Action Button silently failed: the intent asked for the app to open
/// *and* returned a URL to open, the system honoured the first and dropped the second, and
/// Remli launched onto whatever tab you left it on. Nothing logged, nothing crashed — it
/// just quietly did half the job. These tests cover the replacement, which cannot be
/// dropped because it is written down rather than handed over.
@Suite("Capture launch request")
struct CaptureLaunchRequestTests {

    private func scratchDefaults(_ name: String = #function) -> UserDefaults {
        let suite = "remli.tests.capture.\(name)"
        UserDefaults().removePersistentDomain(forName: suite)
        return UserDefaults(suiteName: suite) ?? .standard
    }

    @Test("A request survives long enough to be read after launch")
    func roundTrips() {
        let defaults = scratchDefaults()
        CaptureLaunchRequest.request(.voice, defaults: defaults)
        #expect(CaptureLaunchRequest.take(defaults: defaults) == .voice)
    }

    @Test("Both modes round-trip")
    func bothModes() {
        let defaults = scratchDefaults()

        CaptureLaunchRequest.request(.text, defaults: defaults)
        #expect(CaptureLaunchRequest.take(defaults: defaults) == .text)

        CaptureLaunchRequest.request(.voice, defaults: defaults)
        #expect(CaptureLaunchRequest.take(defaults: defaults) == .voice)
    }

    @Test("Reading it consumes it")
    func onlyFiresOnce() {
        let defaults = scratchDefaults()
        CaptureLaunchRequest.request(.voice, defaults: defaults)

        // Three call sites race to read this — launch, the notification, and becoming
        // active. Exactly one must win, or pressing the button once opens capture twice.
        #expect(CaptureLaunchRequest.take(defaults: defaults) == .voice)
        #expect(CaptureLaunchRequest.take(defaults: defaults) == nil)
        #expect(CaptureLaunchRequest.take(defaults: defaults) == nil)
    }

    @Test("Nothing pending reads as nothing")
    func emptyIsNil() {
        #expect(CaptureLaunchRequest.take(defaults: scratchDefaults()) == nil)
    }

    @Test("A request older than the window is ignored")
    func staleRequestsAreDropped() {
        let defaults = scratchDefaults()
        let pressed = Date(timeIntervalSince1970: 1_800_000_000)

        CaptureLaunchRequest.request(.voice, now: pressed, defaults: defaults)

        // Opening the app the next morning must not switch the microphone on because of a
        // button pressed yesterday.
        let later = pressed.addingTimeInterval(CaptureLaunchRequest.staleAfter + 1)
        #expect(CaptureLaunchRequest.take(now: later, defaults: defaults) == nil)
    }

    @Test("A request inside the window still counts")
    func freshRequestsSurvive() {
        let defaults = scratchDefaults()
        let pressed = Date(timeIntervalSince1970: 1_800_000_000)

        CaptureLaunchRequest.request(.voice, now: pressed, defaults: defaults)

        // A cold launch is slow, and the whole point is that it still works.
        let later = pressed.addingTimeInterval(CaptureLaunchRequest.staleAfter - 1)
        #expect(CaptureLaunchRequest.take(now: later, defaults: defaults) == .voice)
    }

    @Test("A stale request is cleared, not left to fail forever")
    func staleRequestsAreTidiedUp() {
        let defaults = scratchDefaults()
        let pressed = Date(timeIntervalSince1970: 1_800_000_000)
        CaptureLaunchRequest.request(.voice, now: pressed, defaults: defaults)

        let later = pressed.addingTimeInterval(CaptureLaunchRequest.staleAfter + 1)
        _ = CaptureLaunchRequest.take(now: later, defaults: defaults)

        // If it were merely rejected rather than removed, it would sit in defaults being
        // rejected again on every single launch.
        CaptureLaunchRequest.request(.text, now: later, defaults: defaults)
        #expect(CaptureLaunchRequest.take(now: later, defaults: defaults) == .text)
    }

    @Test("A clock that has gone backwards does not trigger a recording")
    func negativeAgeIsRejected() {
        let defaults = scratchDefaults()
        let pressed = Date(timeIntervalSince1970: 1_800_000_000)
        CaptureLaunchRequest.request(.voice, now: pressed, defaults: defaults)

        let earlier = pressed.addingTimeInterval(-60)
        #expect(CaptureLaunchRequest.take(now: earlier, defaults: defaults) == nil)
    }

    @Test("A newer request replaces an older one")
    func latestWins() {
        let defaults = scratchDefaults()
        CaptureLaunchRequest.request(.voice, defaults: defaults)
        CaptureLaunchRequest.request(.text, defaults: defaults)
        #expect(CaptureLaunchRequest.take(defaults: defaults) == .text)
    }

    @Test("Widget URLs still route, since widgets have no other mechanism")
    func widgetURLsStillWork() {
        #expect(CaptureRoute.wantsVoice(CaptureRoute.voiceURL) == true)
        #expect(CaptureRoute.wantsVoice(CaptureRoute.textURL) == false)
        #expect(CaptureRoute.wantsVoice(URL(string: "https://example.com")!) == nil)
        #expect(CaptureRoute.wantsVoice(URL(string: "remli://settings")!) == nil)
    }
}
