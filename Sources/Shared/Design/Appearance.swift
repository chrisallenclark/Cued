import SwiftUI

/// Light, dark, or whatever the phone is doing.
///
/// Remli shipped locked to dark — `UIUserInterfaceStyle` in the Info.plist — even though
/// every colour in the asset catalog has carried a light value since the first commit. The
/// light half of the design system existed and had simply never been switched on.
///
/// Stored as a raw string rather than an `Int`, so the value in `UserDefaults` is legible
/// when something goes wrong, and so reordering the cases can never silently change what a
/// device has already chosen.
enum Appearance: String, CaseIterable, Identifiable, Sendable {
    case system
    case light
    case dark

    var id: String { rawValue }

    var name: String {
        switch self {
        case .system: return "System"
        case .light:  return "Light"
        case .dark:   return "Dark"
        }
    }

    var symbolName: String {
        switch self {
        case .system: return "iphone"
        case .light:  return "sun.max"
        case .dark:   return "moon"
        }
    }

    /// What to hand `.preferredColorScheme`. Nil means "stop asking and follow the phone",
    /// which is why this is an optional rather than a third scheme.
    var colorScheme: ColorScheme? {
        switch self {
        case .system: return nil
        case .light:  return .light
        case .dark:   return .dark
        }
    }
}

/// Where the choice lives.
///
/// `@AppStorage` rather than SwiftData: this is a property of *this device*, not of the
/// person's library. Syncing it would mean choosing dark on a phone at night and finding an
/// iPad had gone dark on a desk in daylight.
@MainActor
@Observable
final class AppearanceStore {

    static let key = "remli.appearance"

    var appearance: Appearance {
        didSet {
            guard appearance != oldValue else { return }
            defaults.set(appearance.rawValue, forKey: Self.key)
        }
    }

    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        let stored = defaults.string(forKey: Self.key)
        // Unset, or a value written by a newer build that this one does not understand,
        // both mean "follow the phone" — the one answer that is never wrong.
        self.appearance = stored.flatMap(Appearance.init(rawValue:)) ?? .system
    }
}
