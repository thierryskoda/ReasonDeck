import Foundation
import Testing
@testable import ReasonDeck

@MainActor
private func unconfiguredDefaults() -> UserDefaults {
    let suite = "ProfileStoreTests.\(UUID().uuidString)"
    let defaults = UserDefaults(suiteName: suite)!
    defaults.removePersistentDomain(forName: suite)
    return defaults
}

@MainActor
private func isolatedDefaults() -> UserDefaults {
    let defaults = unconfiguredDefaults()
    ProfileStore(defaults: defaults).reset()
    return defaults
}

@MainActor
@Test func missingConfigurationStartsWithDefaultShortcutsAndPersistsThem() throws {
    let defaults = unconfiguredDefaults()
    let store = ProfileStore(defaults: defaults)

    #expect(store.isValid)
    #expect(store.entries.count == 2)

    let economicalShortcut = try KeyboardShortcut(
        keyCode: 18,
        keyLabel: "1",
        modifiers: [.command, .shift]
    )
    let economical = try #require(store.entries.first)
    #expect(economical.shortcut == economicalShortcut)
    #expect(economical.chatGPT == ChatGPTSelection(model: .luna56, effort: .high))
    #expect(economical.cursor == CursorSelection(model: .composer25Fast, effort: .high))
    #expect(economical.antigravity == AntigravitySelection(model: .gemini37Flash, effort: .medium))
    #expect(economical.claudeCode == ClaudeCodeSelection(model: .sonnet5, effort: .medium))

    let premiumShortcut = try KeyboardShortcut(
        keyCode: 19,
        keyLabel: "2",
        modifiers: [.command, .shift]
    )
    let premium = try #require(store.entries.last)
    #expect(premium.shortcut == premiumShortcut)
    #expect(premium.chatGPT == ChatGPTSelection(model: .sol56, effort: .high))
    #expect(premium.cursor == CursorSelection(model: .gpt56Sol, effort: .high))
    #expect(premium.antigravity == AntigravitySelection(model: .claudeOpus46, effort: .thinking))
    #expect(premium.claudeCode == ClaudeCodeSelection(model: .sonnet5, effort: .high))

    #expect(ProfileStore(defaults: defaults).entries == store.entries)
}

@MainActor
@Test func enablingClaudeUsesVerifiedHomeCompatibleDefault() throws {
    let store = ProfileStore(defaults: isolatedDefaults())
    let id = try #require(store.addEntry())

    try store.setTarget(.claudeCode, enabled: true, for: id)

    #expect(
        store.entry(id: id)?.claudeCode
            == ClaudeCodeSelection(model: .sonnet5, effort: .medium)
    )
}

@MainActor
@Test func enablingAntigravityUsesAnExactVersion281Row() throws {
    let store = ProfileStore(defaults: isolatedDefaults())
    let id = try #require(store.addEntry())

    try store.setTarget(.antigravity, enabled: true, for: id)

    #expect(
        store.entry(id: id)?.antigravity
            == AntigravitySelection(model: .gemini31Pro, effort: .low)
    )
}

@MainActor
@Test func establishedInstallWithoutSavedConfigurationStaysEmpty() {
    let defaults = unconfiguredDefaults()
    defaults.set(true, forKey: ProfileStore.didOpenInitialSettingsKey)

    let store = ProfileStore(defaults: defaults)

    #expect(store.isValid)
    #expect(store.entries.isEmpty)
    #expect(ProfileStore(defaults: defaults).entries.isEmpty)
}

@MainActor
@Test func addedAndEditedShortcutSurvivesRelaunch() throws {
    let defaults = isolatedDefaults()
    let store = ProfileStore(defaults: defaults)
    let id = try #require(store.addEntry())
    let shortcut = try KeyboardShortcut(keyCode: 18, keyLabel: "1", modifiers: [.command, .shift])

    try store.setShortcut(shortcut, for: id)
    store.setChatGPTModel(.luna56, for: id)
    store.setChatGPTEffort(.max, for: id)

    let relaunched = ProfileStore(defaults: defaults)
    #expect(relaunched.entries == [ShortcutEntry(id: id, shortcut: shortcut, chatGPT: ChatGPTSelection(model: .luna56, effort: .max), claudeCode: nil, cursor: nil)])
}

@MainActor
@Test func independentClaudeAssignmentSurvivesRelaunch() throws {
    let defaults = isolatedDefaults()
    let store = ProfileStore(defaults: defaults)
    let id = try #require(store.addEntry())
    try store.setTarget(.claudeCode, enabled: true, for: id)
    store.setClaudeCodeModel(.sonnet5, for: id)
    store.setClaudeCodeEffort(.ultracode, for: id)

    let relaunched = ProfileStore(defaults: defaults)
    #expect(relaunched.entry(id: id)?.chatGPT == ChatGPTSelection(model: .sol56, effort: .extraHigh))
    #expect(relaunched.entry(id: id)?.claudeCode == ClaudeCodeSelection(model: .sonnet5, effort: .ultracode))
}

@MainActor
@Test func legacyConfigurationMigratesOnceToChatGPTOnly() throws {
    let defaults = unconfiguredDefaults()
    let id = UUID()
    let legacy = LegacyShortcutConfiguration(entries: [
        LegacyShortcutEntry(
            id: id,
            shortcut: nil,
            selection: LegacyProfileSelection(model: .terra56, effort: .high)
        )
    ])
    defaults.set(try JSONEncoder().encode(legacy), forKey: ProfileStore.legacyStorageKey)

    let store = ProfileStore(defaults: defaults)

    #expect(store.entry(id: id)?.chatGPT == ChatGPTSelection(model: .terra56, effort: .high))
    #expect(store.entry(id: id)?.claudeCode == nil)
    #expect(store.entry(id: id)?.cursor == nil)
    #expect(defaults.data(forKey: ProfileStore.storageKey) != nil)
    #expect(defaults.object(forKey: ProfileStore.legacyStorageKey) == nil)
}

@MainActor
@Test func independentCursorAssignmentSurvivesRelaunch() throws {
    let defaults = isolatedDefaults()
    let store = ProfileStore(defaults: defaults)
    let id = try #require(store.addEntry())
    try store.setTarget(.cursor, enabled: true, for: id)
    store.setCursorModel(.composer25, for: id)
    store.setCursorEffort(.medium, for: id)

    let relaunched = ProfileStore(defaults: defaults)
    #expect(relaunched.entry(id: id)?.chatGPT == ChatGPTSelection(model: .sol56, effort: .extraHigh))
    #expect(relaunched.entry(id: id)?.cursor == CursorSelection(model: .composer25, effort: .medium))
}

@MainActor
@Test func rerecordingShortcutPreservesEveryTargetAssignment() throws {
    let store = ProfileStore(defaults: isolatedDefaults())
    let id = try #require(store.addEntry())
    try store.setTarget(.cursor, enabled: true, for: id)
    try store.setTarget(.antigravity, enabled: true, for: id)
    let shortcut = try KeyboardShortcut(keyCode: 19, keyLabel: "2", modifiers: [.command])

    try store.setShortcut(shortcut, for: id)

    let entry = try #require(store.entry(id: id))
    #expect(entry.shortcut == shortcut)
    #expect(entry.chatGPT != nil)
    #expect(entry.cursor != nil)
    #expect(entry.antigravity != nil)
}

@MainActor
@Test func invalidCurrentConfigurationNeverFallsBackToLegacy() throws {
    let defaults = isolatedDefaults()
    defaults.set(Data("invalid-v2".utf8), forKey: ProfileStore.storageKey)
    let legacy = LegacyShortcutConfiguration(entries: [
        LegacyShortcutEntry(
            id: UUID(),
            shortcut: nil,
            selection: LegacyProfileSelection(model: .sol56, effort: .extraHigh)
        )
    ])
    defaults.set(try JSONEncoder().encode(legacy), forKey: ProfileStore.legacyStorageKey)

    let store = ProfileStore(defaults: defaults)

    #expect(!store.isValid)
    #expect(store.entries.isEmpty)
}

@MainActor
@Test func lastApplicationAssignmentCannotBeDisabled() throws {
    let store = ProfileStore(defaults: isolatedDefaults())
    let id = try #require(store.addEntry())

    #expect(throws: ShortcutAssignmentError.lastAssignment) {
        try store.setTarget(.chatGPT, enabled: false, for: id)
    }
    #expect(store.entry(id: id)?.enabledTargets == [.chatGPT])
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
@Test func finishedSessionShortcutIsCreatedOnceAndPersists() throws {
    let defaults = isolatedDefaults()
    let store = ProfileStore(defaults: defaults)
    let id = try #require(store.ensureNavigationEntry())
    #expect(store.ensureNavigationEntry() == id)
    let shortcut = try KeyboardShortcut(keyCode: 0, keyLabel: "A", modifiers: [.command, .shift])

    try store.setShortcut(shortcut, for: id)

    let relaunched = ProfileStore(defaults: defaults)
    #expect(relaunched.ensureNavigationEntry() == id)
    #expect(relaunched.navigationEntries.count == 1)
    let entry = try #require(relaunched.entry(id: id))
    #expect(entry.shortcut == shortcut)
    #expect(entry.cursorNavigation == .nextUnreadSession)
    #expect(entry.cursor == nil)
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
    #expect(ProfileStore(defaults: defaults).entries.isEmpty)
}

@MainActor
@Test func persistedCursorModelAndNavigationConflictDisablesTheStore() throws {
    let defaults = isolatedDefaults()
    let payload: [String: Any] = [
        "version": 2,
        "configuration": ["entries": [[
            "id": UUID().uuidString,
            "shortcut": NSNull(),
            "chatGPT": NSNull(),
            "claudeCode": NSNull(),
            "cursor": ["model": "Grok 4.5", "effort": "High"],
            "cursorNavigation": "nextUnreadSession"
        ]]]
    ]
    defaults.set(try JSONSerialization.data(withJSONObject: payload), forKey: ProfileStore.storageKey)

    let store = ProfileStore(defaults: defaults)

    #expect(!store.isValid)
    #expect(store.entries.isEmpty)
}
