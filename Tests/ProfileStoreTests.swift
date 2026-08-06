import Foundation
import Testing
@testable import ChatGPTProfileKeys

@MainActor
private func isolatedDefaults() -> UserDefaults {
    let suite = "ProfileStoreTests.\(UUID().uuidString)"
    let defaults = UserDefaults(suiteName: suite)!
    defaults.removePersistentDomain(forName: suite)
    return defaults
}

@MainActor
@Test func missingConfigurationStartsWithNoShortcuts() {
    let store = ProfileStore(defaults: isolatedDefaults())
    #expect(store.entries.isEmpty)
    #expect(store.isValid)
}

@MainActor
@Test func addedAndEditedShortcutSurvivesRelaunch() throws {
    let defaults = isolatedDefaults()
    let store = ProfileStore(defaults: defaults)
    let id = try #require(store.addEntry())
    let shortcut = try KeyboardShortcut(keyCode: 18, keyLabel: "1", modifiers: [.command, .shift])

    try store.setShortcut(shortcut, for: id)
    store.setModel(.luna56, for: id)
    store.setEffort(.max, for: id)

    let relaunched = ProfileStore(defaults: defaults)
    #expect(relaunched.entries == [ShortcutEntry(id: id, shortcut: shortcut, selection: ProfileSelection(model: .luna56, effort: .max))])
}

@MainActor
@Test func duplicateShortcutIsRejectedWithoutChangingEitherEntry() throws {
    let store = ProfileStore(defaults: isolatedDefaults())
    let first = try #require(store.addEntry())
    let second = try #require(store.addEntry())
    let shortcut = try KeyboardShortcut(keyCode: 18, keyLabel: "1", modifiers: [.command])
    try store.setShortcut(shortcut, for: first)

    #expect(throws: ShortcutAssignmentError.duplicate) {
        try store.setShortcut(shortcut, for: second)
    }
    #expect(store.entry(id: first)?.shortcut == shortcut)
    #expect(store.entry(id: second)?.shortcut == nil)
}

@MainActor
@Test func deletingAnEntryPersists() throws {
    let defaults = isolatedDefaults()
    let store = ProfileStore(defaults: defaults)
    let id = try #require(store.addEntry())
    store.deleteEntry(id)
    #expect(store.entries.isEmpty)
    #expect(ProfileStore(defaults: defaults).entries.isEmpty)
}

@MainActor
@Test func corruptPayloadFailsClosedUntilReset() {
    let defaults = isolatedDefaults()
    defaults.set(Data("not-json".utf8), forKey: ProfileStore.storageKey)
    let store = ProfileStore(defaults: defaults)

    #expect(!store.isValid)
    #expect(store.entries.isEmpty)

    store.reset()
    #expect(store.isValid)
    #expect(store.entries.isEmpty)
}
