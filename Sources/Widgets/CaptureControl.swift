import AppIntents
import SwiftUI
import WidgetKit

/// The Control Center / Lock Screen control — and, crucially, what can be bound to the
/// Action Button.
///
/// Any Control Widget can be assigned to the Action Button in Settings, which is the only
/// supported way for a third-party app to get there. That makes this the fastest possible
/// path from thought to recording: press and hold, and the mic is already listening.
struct CaptureControl: ControlWidget {

    static let kind = "com.chrisallenclark.remli.control.capture"

    var body: some ControlWidgetConfiguration {
        StaticControlConfiguration(kind: Self.kind) {
            ControlWidgetButton(action: CaptureIdeaIntent()) {
                Label("Capture", systemImage: "mic.fill")
            }
        }
        .displayName("Capture an idea")
        .description("Start recording in Remli.")
    }
}

/// The same control, for typing.
///
/// A separate control rather than a toggle inside one: controls are assigned to a slot —
/// the Action Button, a Lock Screen button — and a slot that sometimes opens the mic and
/// sometimes the keyboard would be a slot you have to think about. Two controls means one
/// decision, made once, at setup.
struct CaptureTextControl: ControlWidget {

    static let kind = "com.chrisallenclark.remli.control.capture.text"

    var body: some ControlWidgetConfiguration {
        StaticControlConfiguration(kind: Self.kind) {
            ControlWidgetButton(action: CaptureTextIntent()) {
                Label("Write", systemImage: "square.and.pencil")
            }
        }
        .displayName("Write an idea")
        .description("Open Remli with the keyboard ready.")
    }
}
