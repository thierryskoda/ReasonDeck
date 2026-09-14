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
@Test func anUnreadableSupersededPayloadStillFailsClosed() {
    // Recovery applies to a configuration this build partly understands. Data that is not a
    // configuration at all is still refused rather than guessed at.
    let defaults = unconfiguredDefaults()
    defaults.set(Data("obsolete".utf8), forKey: ProfileStore.supersededStorageKey)

    let store = ProfileStore(defaults: defaults)

    #expect(!store.isValid)
    #expect(store.entries.isEmpty)

    store.reset()
    #expect(store.isValid)
    #expect(defaults.object(forKey: ProfileStore.supersededStorageKey) == nil)
    #expect(ProfileStore(defaults: defaults).entries.isEmpty)
}

/// A version 2 payload as shipped before Cursor session navigation was retired: two ordinary
/// model shortcuts either side of a navigation-only entry this build no longer knows.
private let supersededPayloadWithRetiredFeature = """
{"configuration":{"entries":[
 {"id":"68EBCE6E-00D7-46C9-A1E3-0023955AE256",
  "shortcut":{"keyCode":18,"keyLabel":"1","modifiers":9},
  "chatGPT":{"model":"5.6 Terra","effort":"Medium"},
  "claudeCode":{"model":"Sonnet 5","effort":"High"}},
 {"id":"1A8B6EB6-F7CC-4452-BA30-242365F7560D","cursorNavigation":"nextUnreadSession"},
 {"id":"72413D4A-2083-4902-A6BB-E109C02E9D66",
  "shortcut":{"keyCode":19,"keyLabel":"2","modifiers":9},
  "chatGPT":{"model":"5.6 Sol","effort":"High"},
  "claudeCode":{"model":"Opus 5","effort":"High"}}
]},"version":2}
"""

@MainActor
@Test func aRetiredFeatureNoLongerDestroysTheShortcutsBesideIt() throws {
    // Regression: retiring Cursor session navigation invalidated the whole saved file, so
    // upgrading wiped every unrelated model shortcut with no way to get them back.
    let defaults = unconfiguredDefaults()
    defaults.set(Data(supersededPayloadWithRetiredFeature.utf8), forKey: ProfileStore.supersededStorageKey)

    let store = ProfileStore(defaults: defaults)

    #expect(store.isValid)
    #expect(store.entries.count == 2)
    #expect(store.entries.map { $0.shortcut?.displayName } == ["\u{21e7}\u{2318}1", "\u{21e7}\u{2318}2"])
    #expect(store.entries[0].claudeCode == ClaudeCodeSelection(model: .sonnet5, effort: .high))
    #expect(store.entries[1].chatGPT == ChatGPTSelection(model: .sol56, effort: .high))
}

@MainActor
@Test func aSupersededPayloadIsNormalizedSoItIsNotReReadEveryLaunch() {
    let defaults = unconfiguredDefaults()
    defaults.set(Data(supersededPayloadWithRetiredFeature.utf8), forKey: ProfileStore.supersededStorageKey)

    _ = ProfileStore(defaults: defaults)

    #expect(defaults.object(forKey: ProfileStore.supersededStorageKey) == nil)
    #expect(defaults.object(forKey: ProfileStore.storageKey) != nil)
    #expect(ProfileStore(defaults: defaults).entries.count == 2)
}

@MainActor
@Test func anUnchangedConfigurationKeepsEveryShortcut() {
    // The ordinary upgrade: nothing the user saved was retired, so nothing changes.
    let defaults = isolatedDefaults()
    let store = ProfileStore(defaults: defaults)
    let id = try! #require(store.addEntry())
    store.setClaudeCodeModel(.opus5, for: id)

    let reopened = ProfileStore(defaults: defaults)
    #expect(reopened.entries.count == store.entries.count)
}

@MainActor
@Test func aRetiredModelRemovesOnlyThatAppFromTheShortcut() throws {
    let defaults = unconfiguredDefaults()
    let payload = """
    {"configuration":{"entries":[
     {"id":"68EBCE6E-00D7-46C9-A1E3-0023955AE256",
      "shortcut":{"keyCode":18,"keyLabel":"1","modifiers":9},
      "chatGPT":{"model":"A Model ReasonDeck Retired","effort":"High"},
      "claudeCode":{"model":"Sonnet 5","effort":"High"}}
    ]},"version":3}
    """
    defaults.set(Data(payload.utf8), forKey: ProfileStore.storageKey)

    let store = ProfileStore(defaults: defaults)

    #expect(store.entries.count == 1)
    #expect(store.entries[0].chatGPT == nil)
    #expect(store.entries[0].claudeCode == ClaudeCodeSelection(model: .sonnet5, effort: .high))
}

@MainActor
@Test func aShortcutWhoseEveryAppWasRetiredIsRemovedWhole() throws {
    let defaults = unconfiguredDefaults()
    let payload = """
    {"configuration":{"entries":[
     {"id":"68EBCE6E-00D7-46C9-A1E3-0023955AE256",
      "shortcut":{"keyCode":18,"keyLabel":"1","modifiers":9},
      "chatGPT":{"model":"Retired","effort":"High"}},
     {"id":"72413D4A-2083-4902-A6BB-E109C02E9D66",
      "shortcut":{"keyCode":19,"keyLabel":"2","modifiers":9},
      "claudeCode":{"model":"Sonnet 5","effort":"High"}}
    ]},"version":3}
    """
    defaults.set(Data(payload.utf8), forKey: ProfileStore.storageKey)

    let store = ProfileStore(defaults: defaults)

    #expect(store.entries.count == 1)
    #expect(store.entries[0].shortcut?.displayName == "\u{21e7}\u{2318}2")
}

@MainActor
@Test func aConfigurationFromANewerBuildIsRefusedRatherThanMisread() {
    // Leniency runs one way only. A newer format may mean something this build would get
    // wrong, and switching the wrong model is worse than asking for a reset.
    let defaults = unconfiguredDefaults()
    let payload = """
    {"configuration":{"entries":[]},"version":99}
    """
    defaults.set(Data(payload.utf8), forKey: ProfileStore.storageKey)

    let store = ProfileStore(defaults: defaults)
    #expect(!store.isValid)
}

@MainActor
@Test func aDuplicateKeyCombinationIsDroppedRatherThanInvalidatingTheFile() {
    // Two entries claiming the same keys cannot be told apart at dispatch. The first is kept
    // and the second reported, instead of the pair invalidating every other shortcut.
    let defaults = unconfiguredDefaults()
    let payload = """
    {"configuration":{"entries":[
     {"id":"68EBCE6E-00D7-46C9-A1E3-0023955AE256",
      "shortcut":{"keyCode":18,"keyLabel":"1","modifiers":9},
      "claudeCode":{"model":"Sonnet 5","effort":"High"}},
     {"id":"72413D4A-2083-4902-A6BB-E109C02E9D66",
      "shortcut":{"keyCode":18,"keyLabel":"1","modifiers":9},
      "claudeCode":{"model":"Opus 5","effort":"High"}},
     {"id":"9A8B6EB6-F7CC-4452-BA30-242365F7560D",
      "shortcut":{"keyCode":19,"keyLabel":"2","modifiers":9},
      "chatGPT":{"model":"5.6 Sol","effort":"High"}}
    ]},"version":3}
    """
    defaults.set(Data(payload.utf8), forKey: ProfileStore.storageKey)

    let store = ProfileStore(defaults: defaults)

    #expect(store.entries.count == 2)
    #expect(store.entries[0].claudeCode == ClaudeCodeSelection(model: .sonnet5, effort: .high))
    #expect(store.entries[1].chatGPT == ChatGPTSelection(model: .sol56, effort: .high))
}

@MainActor
@Test func aRepeatedIdentifierIsDroppedRatherThanInvalidatingTheFile() {
    let defaults = unconfiguredDefaults()
    let payload = """
    {"configuration":{"entries":[
     {"id":"68EBCE6E-00D7-46C9-A1E3-0023955AE256",
      "shortcut":{"keyCode":18,"keyLabel":"1","modifiers":9},
      "claudeCode":{"model":"Sonnet 5","effort":"High"}},
     {"id":"68EBCE6E-00D7-46C9-A1E3-0023955AE256",
      "shortcut":{"keyCode":19,"keyLabel":"2","modifiers":9},
      "claudeCode":{"model":"Opus 5","effort":"High"}}
    ]},"version":3}
    """
    defaults.set(Data(payload.utf8), forKey: ProfileStore.storageKey)

    let store = ProfileStore(defaults: defaults)

    #expect(store.entries.count == 1)
    #expect(store.entries[0].claudeCode == ClaudeCodeSelection(model: .sonnet5, effort: .high))
}

@MainActor
@Test func anEntryTooDamagedToReadDoesNotEndTheArray() {
    // The array-level guard: an element that is not an object at all is skipped, not fatal.
    let defaults = unconfiguredDefaults()
    let payload = """
    {"configuration":{"entries":[
     "not-an-entry",
     {"id":"72413D4A-2083-4902-A6BB-E109C02E9D66",
      "shortcut":{"keyCode":19,"keyLabel":"2","modifiers":9},
      "chatGPT":{"model":"5.6 Sol","effort":"High"}}
    ]},"version":3}
    """
    defaults.set(Data(payload.utf8), forKey: ProfileStore.storageKey)

    let store = ProfileStore(defaults: defaults)

    #expect(store.entries.count == 1)
    #expect(store.entries[0].chatGPT == ChatGPTSelection(model: .sol56, effort: .high))
}
