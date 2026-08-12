import AppIntents
import Foundation

/// Deep links into capture.
///
/// This file is deliberately the *only* shared code the widget extension compiles. It
/// imports nothing beyond Foundation and AppIntents, which keeps SwiftData, Speech,
/// EventKit and the whole services layer out of the extension binary.
enum CaptureRoute {
    static let scheme = "remli"
    static let voiceURL = URL(string: "remli://capture/voice")!
    static let textURL = URL(string: "remli://capture/text")!

    /// Returns whether the link asks for voice capture, or nil if it isn't a capture link.
    static func wantsVoice(_ url: URL) -> Bool? {
        guard url.scheme == scheme, url.host == "capture" else { return nil }
        return url.lastPathComponent == "voice"
    }
}

extension Notification.Name {
    /// Posted the moment a capture intent runs, so an app that is already on screen reacts
    /// without waiting for a lifecycle event that has already been and gone.
    static let remliCaptureRequested = Notification.Name("com.chrisallenclark.remli.captureRequested")
}

/// "Somebody pressed a button and wants to capture" — recorded, then picked up by the app.
///
/// This replaces routing the Action Button through a `remli://` URL, which never arrived.
/// The intent declared `openAppWhenRun` *and* returned an `OpenURLIntent`, which are two
/// different ways of asking for the same thing: the system foregrounded the app to satisfy
/// the first and dropped the second, so Remli opened on whatever tab you left it on and the
/// recording never started. Exactly the symptom, and invisible from a build log.
///
/// A recorded request cannot be dropped. It is written before the app is on screen and read
/// whenever the app gets there, so the ordering between launch and intent stops mattering.
enum CaptureLaunchRequest {

    enum Mode: String, Sendable {
        case voice
        case text
    }

    private static let modeKey = "remli.capture.pendingMode"
    private static let stampKey = "remli.capture.pendingAt"

    /// Long enough to survive a cold launch on a slow morning, short enough that a request
    /// nobody consumed cannot switch the microphone on hours later. A stale flag opening a
    /// live recording by itself would be the worst bug in the app.
    static let staleAfter: TimeInterval = 25

    static func request(
        _ mode: Mode,
        now: Date = .now,
        defaults: UserDefaults = .standard
    ) {
        defaults.set(mode.rawValue, forKey: modeKey)
        defaults.set(now.timeIntervalSince1970, forKey: stampKey)
        NotificationCenter.default.post(name: .remliCaptureRequested, object: nil)
    }

    /// Reads and clears in one go. Nil when there is nothing pending, or when what is
    /// pending is too old to have been meant for this launch.
    ///
    /// Clearing even on the stale path matters: otherwise a request that missed its moment
    /// sits in defaults forever, failing the freshness check on every launch and never
    /// getting tidied up.
    static func take(now: Date = .now, defaults: UserDefaults = .standard) -> Mode? {
        let raw = defaults.string(forKey: modeKey)
        let stamp = defaults.double(forKey: stampKey)

        defaults.removeObject(forKey: modeKey)
        defaults.removeObject(forKey: stampKey)

        guard let raw, let mode = Mode(rawValue: raw), stamp > 0 else { return nil }
        let age = now.timeIntervalSince1970 - stamp
        guard age >= 0, age <= staleAfter else { return nil }
        return mode
    }
}

/// "Hey Siri, capture an idea" — and the action behind the Control Center control, which
/// is what makes the Action Button work.
///
/// Opens the app straight into a live recording. The whole premise is that the gap between
/// having a thought and capturing it must be near zero, so this skips every confirmation.
struct CaptureIdeaIntent: AppIntent {

    static var title: LocalizedStringResource = "Capture an idea"
    static var description = IntentDescription("Start recording an idea in Remli.")

    /// Recording needs the microphone and a foreground audio session, so this cannot run
    /// in the background.
    static var openAppWhenRun: Bool = true

    init() {}

    @MainActor
    func perform() async throws -> some IntentResult {
        // Records the request rather than returning an `OpensIntent`. Returning one
        // alongside `openAppWhenRun` is what stopped this working: the app came forward
        // and the URL went nowhere.
        CaptureLaunchRequest.request(.voice)
        return .result()
    }
}

/// The same thing, with the keyboard instead of the microphone.
///
/// Voice is faster when you can speak, and useless when you cannot. A meeting, a quiet
/// carriage, someone asleep in the next room — in all of them the mic is the wrong tool and
/// the choice is between typing and losing the thought. Having both as controls means
/// whichever surface you set up, the Action Button or the Lock Screen, you pick which one
/// it is rather than accepting the one that happened to be built.
struct CaptureTextIntent: AppIntent {

    static var title: LocalizedStringResource = "Write an idea"
    static var description = IntentDescription("Open Remli with the keyboard ready.")

    static var openAppWhenRun: Bool = true

    init() {}

    @MainActor
    func perform() async throws -> some IntentResult {
        CaptureLaunchRequest.request(.text)
        return .result()
    }
}
