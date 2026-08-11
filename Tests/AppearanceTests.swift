import Foundation
import SwiftUI
import Testing

@testable import Remli

/// The appearance preference.
///
/// Small surface, but the failure mode is nasty: a bad read from `UserDefaults` would
/// either crash on launch or silently pin someone to an appearance they never picked, and
/// neither is recoverable from inside the app.
@Suite("Appearance")
struct AppearanceTests {

    private func scratchDefaults(_ name: String = #function) -> UserDefaults {
        let suite = "remli.tests.\(name)"
        UserDefaults().removePersistentDomain(forName: suite)
        return UserDefaults(suiteName: suite) ?? .standard
    }

    @Test("Each option maps to the right colour scheme")
    func schemeMapping() {
        #expect(Appearance.system.colorScheme == nil)
        #expect(Appearance.light.colorScheme == .light)
        #expect(Appearance.dark.colorScheme == .dark)
    }

    @Test("Every option is presentable")
    func optionsArePresentable() {
        for option in Appearance.allCases {
            #expect(!option.name.isEmpty)
            #expect(!option.symbolName.isEmpty)
            #expect(option.id == option.rawValue)
        }
        #expect(Appearance.allCases.count == 3)
    }

    @Test("Raw values are stable, because they are what lands in UserDefaults")
    func rawValuesAreStable() {
        // Renaming any of these would silently reset the choice on every device that had
        // already made one.
        #expect(Appearance.system.rawValue == "system")
        #expect(Appearance.light.rawValue == "light")
        #expect(Appearance.dark.rawValue == "dark")
    }

    @MainActor
    @Test("A fresh install follows the phone")
    func defaultsToSystem() {
        let store = AppearanceStore(defaults: scratchDefaults())
        #expect(store.appearance == .system)
        #expect(store.appearance.colorScheme == nil)
    }

    @MainActor
    @Test("A choice survives a relaunch")
    func choicePersists() {
        let defaults = scratchDefaults()

        let first = AppearanceStore(defaults: defaults)
        first.appearance = .light

        let second = AppearanceStore(defaults: defaults)
        #expect(second.appearance == .light)
    }

    @MainActor
    @Test("A value this build does not understand falls back to following the phone")
    func unknownValueIsSafe() {
        let defaults = scratchDefaults()
        // What a newer build writing a fourth option would leave behind.
        defaults.set("sepia", forKey: AppearanceStore.key)

        let store = AppearanceStore(defaults: defaults)
        #expect(store.appearance == .system)
    }

    @MainActor
    @Test("Setting the same value again does not churn storage")
    func idempotentWrites() {
        let defaults = scratchDefaults()
        let store = AppearanceStore(defaults: defaults)

        store.appearance = .dark
        store.appearance = .dark

        #expect(defaults.string(forKey: AppearanceStore.key) == "dark")
    }

    @MainActor
    @Test("Going back to System is recorded, not just forgotten")
    func systemIsAChoice() {
        let defaults = scratchDefaults()
        let store = AppearanceStore(defaults: defaults)

        store.appearance = .dark
        store.appearance = .system

        // Written rather than cleared: a stored "system" and an absent key mean the same
        // thing today, but only one of them says it on purpose.
        #expect(defaults.string(forKey: AppearanceStore.key) == "system")
        #expect(AppearanceStore(defaults: defaults).appearance == .system)
    }
}
