import Foundation
import Observation

private struct StoredShortcutConfiguration: Codable {
    static let currentVersion = 3

    let version: Int
    let configuration: ShortcutConfiguration

    init(configuration: ShortcutConfiguration) {
        version = Self.currentVersion
        self.configuration = configuration
    }

    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        version = try container.decode(Int.self, forKey: .version)
        // Older formats are readable: every field this build still understands decodes, and
        // the rest is reported as a loss. Only a format written by a newer build is refused,
        // because its meaning is genuinely unknown and guessing at it could switch the wrong
        // model. Refusing an older one instead would discard shortcuts that are still valid.
        guard version <= Self.currentVersion else {
            throw DecodingError.dataCorruptedError(
                forKey: .version,
                in: container,
                debugDescription: "Shortcut configuration was written by a newer ReasonDeck."
            )
        }
        configuration = try container.decode(ShortcutConfiguration.self, forKey: .configuration)
    }
}

struct LegacyProfileSelection: Codable, Hashable, Sendable {
    let model: ChatGPTModel
    let effort: ChatGPTReasoningEffort
}

struct LegacyShortcutEntry: Codable, Hashable, Sendable {
    let id: UUID
    let shortcut: KeyboardShortcut?
    let selection: LegacyProfileSelection
}

struct LegacyShortcutConfiguration: Codable, Sendable {
    let entries: [LegacyShortcutEntry]

    func migrated() throws -> ShortcutConfiguration {
        try ShortcutConfiguration(entries: entries.map { entry in
            ShortcutEntry(
                id: entry.id,
                shortcut: entry.shortcut,
                chatGPT: ChatGPTSelection(
                    model: entry.selection.model,
                    effort: entry.selection.effort
                ),
                claudeCode: nil,
                cursor: nil
            )
        })
    }
}

@MainActor
@Observable
final class ProfileStore {
    /// The `v3` suffix is historical and does not change again. The stored payload carries
    /// its own version and the reader accepts every version it understands, so a schema
    /// change no longer needs a new key, a new decoder, or a migration.
    static let storageKey = "com.thierryai.ReasonDeck.shortcutConfiguration.v3"
    /// Same payload shape as the current key, written before that rule existed.
    static let supersededStorageKey = "com.thierryai.ReasonDeck.shortcutConfiguration.v2"
    /// A genuinely different shape: ChatGPT-only entries with no version marker.
    static let legacyStorageKey = "com.thierryai.ReasonDeck.shortcutConfiguration.v1"
    static let didOpenInitialSettingsKey = "com.thierryai.ReasonDeck.didOpenInitialSettings.v1"

    private(set) var configuration: ShortcutConfiguration?
    private(set) var invalidReason: String?
    /// What the last read could not keep. Cleared once the user accepts it or saves over it.
    private(set) var losses = ConfigurationLosses()
    @ObservationIgnored private let defaults: UserDefaults
    @ObservationIgnored var onChange: (@MainActor () -> Void)?

    var isValid: Bool { configuration != nil }
    var entries: [ShortcutEntry] { configuration?.entries ?? [] }

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults

        if defaults.object(forKey: Self.storageKey) != nil {
            loadStoredConfiguration(forKey: Self.storageKey)
            return
        }

        if defaults.object(forKey: Self.supersededStorageKey) != nil {
            loadStoredConfiguration(forKey: Self.supersededStorageKey)
            return
        }

        if defaults.object(forKey: Self.legacyStorageKey) != nil {
            migrateLegacyConfiguration()
            return
        }

        if defaults.bool(forKey: Self.didOpenInitialSettingsKey) {
            configuration = .empty
            save(.empty)
            return
        }

        do {
            let initialConfiguration = try Self.makeFirstInstallConfiguration()
            defaults.set(
                try JSONEncoder().encode(StoredShortcutConfiguration(configuration: initialConfiguration)),
                forKey: Self.storageKey
            )
            configuration = initialConfiguration
        } catch {
            configuration = nil
            invalidReason = "Default shortcuts could not be created. Reset to empty to continue."
        }
    }

    func entry(id: UUID) -> ShortcutEntry? {
        configuration?.entry(id: id)
    }

    @discardableResult
    func addEntry() -> UUID? {
        guard let configuration else { return nil }
        let addition = configuration.addingEntry(
            chatGPT: ChatGPTSelection(model: .sol56, effort: .extraHigh)
        )
        save(addition.configuration)
        return addition.id
    }

    func deleteEntry(_ id: UUID) {
        guard let configuration else { return }
        save(configuration.deleting(id))
    }

    func setShortcut(_ shortcut: KeyboardShortcut?, for id: UUID) throws {
        guard let configuration, let current = configuration.entry(id: id) else { return }
        let updated = ShortcutEntry(
            id: id,
            shortcut: shortcut,
            chatGPT: current.chatGPT,
            claudeCode: current.claudeCode,
            cursor: current.cursor,
            antigravity: current.antigravity
        )
        do {
            save(try configuration.replacing(updated))
        } catch ShortcutConfiguration.ValidationError.duplicateShortcut {
            throw ShortcutAssignmentError.duplicate
        }
    }

    func setTarget(_ target: ApplicationTarget, enabled: Bool, for id: UUID) throws {
        guard let configuration, let current = configuration.entry(id: id) else { return }
        var chatGPT = current.chatGPT
        var claudeCode = current.claudeCode
        var cursor = current.cursor
        var antigravity = current.antigravity

        switch target {
        case .antigravity:
            antigravity = enabled
                ? AntigravitySelection(model: .gemini31Pro, effort: .low)
                : nil
        case .chatGPT:
            chatGPT = enabled
                ? current.chatGPT ?? ChatGPTSelection(model: .sol56, effort: .extraHigh)
                : nil
        case .claudeCode:
            claudeCode = enabled
                ? current.claudeCode ?? ClaudeCodeSelection(model: .sonnet5, effort: .medium)
                : nil
        case .cursor:
            cursor = enabled
                ? current.cursor ?? CursorSelection(model: .grok45, effort: .high)
                : nil
        }

        do {
            save(try configuration.replacing(ShortcutEntry(
                id: id,
                shortcut: current.shortcut,
                chatGPT: chatGPT,
                claudeCode: claudeCode,
                cursor: cursor,
                antigravity: antigravity
            )))
        } catch ShortcutConfiguration.ValidationError.missingAssignment {
            throw ShortcutAssignmentError.lastAssignment
        }
    }

    func setChatGPTModel(_ model: ChatGPTModel, for id: UUID) {
        update(id) { entry in
            guard let selection = entry.chatGPT else { return entry }
            return ShortcutEntry(
                id: entry.id,
                shortcut: entry.shortcut,
                chatGPT: ChatGPTSelection(model: model, effort: selection.effort),
                claudeCode: entry.claudeCode,
                cursor: entry.cursor,
                antigravity: entry.antigravity
            )
        }
    }

    func setChatGPTEffort(_ effort: ChatGPTReasoningEffort, for id: UUID) {
        update(id) { entry in
            guard let selection = entry.chatGPT else { return entry }
            return ShortcutEntry(
                id: entry.id,
                shortcut: entry.shortcut,
                chatGPT: ChatGPTSelection(model: selection.model, effort: effort),
                claudeCode: entry.claudeCode,
                cursor: entry.cursor,
                antigravity: entry.antigravity
            )
        }
    }

    func setClaudeCodeModel(_ model: ClaudeCodeModel, for id: UUID) {
        update(id) { entry in
            guard let selection = entry.claudeCode else { return entry }
            return ShortcutEntry(
                id: entry.id,
                shortcut: entry.shortcut,
                chatGPT: entry.chatGPT,
                claudeCode: ClaudeCodeSelection(model: model, effort: selection.effort),
                cursor: entry.cursor,
                antigravity: entry.antigravity
            )
        }
    }

    func setClaudeCodeEffort(_ effort: ClaudeCodeEffort, for id: UUID) {
        update(id) { entry in
            guard let selection = entry.claudeCode else { return entry }
            return ShortcutEntry(
                id: entry.id,
                shortcut: entry.shortcut,
                chatGPT: entry.chatGPT,
                claudeCode: ClaudeCodeSelection(model: selection.model, effort: effort),
                cursor: entry.cursor,
                antigravity: entry.antigravity
            )
        }
    }

    func setCursorModel(_ model: CursorModel, for id: UUID) {
        update(id) { entry in
            guard let selection = entry.cursor else { return entry }
            return ShortcutEntry(
                id: entry.id,
                shortcut: entry.shortcut,
                chatGPT: entry.chatGPT,
                claudeCode: entry.claudeCode,
                cursor: CursorSelection(model: model, effort: selection.effort),
                antigravity: entry.antigravity
            )
        }
    }

    func setCursorEffort(_ effort: CursorEffort, for id: UUID) {
        update(id) { entry in
            guard let selection = entry.cursor else { return entry }
            return ShortcutEntry(
                id: entry.id,
                shortcut: entry.shortcut,
                chatGPT: entry.chatGPT,
                claudeCode: entry.claudeCode,
                cursor: CursorSelection(model: selection.model, effort: effort),
                antigravity: entry.antigravity
            )
        }
    }

    func setAntigravityModel(_ model: AntigravityModel, for id: UUID) {
        update(id) { entry in
            guard let selection = entry.antigravity else { return entry }
            return ShortcutEntry(
                id: entry.id,
                shortcut: entry.shortcut,
                chatGPT: entry.chatGPT,
                claudeCode: entry.claudeCode,
                cursor: entry.cursor,
                antigravity: AntigravitySelection(model: model, effort: selection.effort)
            )
        }
    }

    func setAntigravityEffort(_ effort: AntigravityEffort, for id: UUID) {
        update(id) { entry in
            guard let selection = entry.antigravity else { return entry }
            return ShortcutEntry(
                id: entry.id,
                shortcut: entry.shortcut,
                chatGPT: entry.chatGPT,
                claudeCode: entry.claudeCode,
                cursor: entry.cursor,
                antigravity: AntigravitySelection(model: selection.model, effort: effort)
            )
        }
    }

    func reset() {
        save(.empty)
    }

    private func update(_ id: UUID, transform: (ShortcutEntry) -> ShortcutEntry) {
        guard let configuration, let current = configuration.entry(id: id) else { return }
        guard let updated = try? configuration.replacing(transform(current)) else {
            invalidate("Profiles could not be saved. Reset to continue.")
            return
        }
        save(updated)
    }

    /// Reads a stored configuration, keeping whatever this build can still honor.
    ///
    /// What survived is deliberately not written back here. Leaving the stored data alone
    /// means the loss is reported again on every launch until the user accepts it, instead
    /// of a first launch quietly rewriting their shortcuts while they are not looking.
    private func loadStoredConfiguration(forKey key: String) {
        guard let data = defaults.data(forKey: key) else {
            invalidateSavedConfiguration()
            return
        }

        let log = ConfigurationLossLog()
        let decoder = JSONDecoder()
        decoder.userInfo[ConfigurationLossLog.userInfoKey] = log

        do {
            configuration = try decoder.decode(StoredShortcutConfiguration.self, from: data).configuration
            losses = log.losses
        } catch {
            invalidateSavedConfiguration()
        }
    }

    /// Commit what survived a read, which also clears the superseded keys.
    ///
    /// Explicit because the user is agreeing to the loss. Nothing about a recovered read is
    /// applied to storage until they do.
    func acceptRecoveredConfiguration() {
        guard let configuration else { return }
        save(configuration)
    }

    private func migrateLegacyConfiguration() {
        guard let data = defaults.data(forKey: Self.legacyStorageKey) else {
            invalidateSavedConfiguration()
            return
        }
        do {
            let legacy = try JSONDecoder().decode(LegacyShortcutConfiguration.self, from: data)
            let migrated = try legacy.migrated()
            let encoded = try JSONEncoder().encode(StoredShortcutConfiguration(configuration: migrated))
            defaults.set(encoded, forKey: Self.storageKey)
            defaults.removeObject(forKey: Self.supersededStorageKey)
            defaults.removeObject(forKey: Self.legacyStorageKey)
            configuration = migrated
        } catch {
            invalidateSavedConfiguration()
        }
    }

    private func save(_ configuration: ShortcutConfiguration) {
        do {
            defaults.set(
                try JSONEncoder().encode(StoredShortcutConfiguration(configuration: configuration)),
                forKey: Self.storageKey
            )
            defaults.removeObject(forKey: Self.supersededStorageKey)
            defaults.removeObject(forKey: Self.legacyStorageKey)
            self.configuration = configuration
            invalidReason = nil
            losses = ConfigurationLosses()
            onChange?()
        } catch {
            invalidate("Profiles could not be saved. Reset to continue.")
        }
    }

    private func invalidateSavedConfiguration() {
        invalidate("Saved shortcuts are invalid. Reset to empty to continue.")
    }

    private func invalidate(_ reason: String) {
        configuration = nil
        invalidReason = reason
        onChange?()
    }

    private static func makeFirstInstallConfiguration() throws -> ShortcutConfiguration {
        try ShortcutConfiguration(entries: [
            ShortcutEntry(
                shortcut: KeyboardShortcut(
                    keyCode: 18,
                    keyLabel: "1",
                    modifiers: [.command, .shift]
                ),
                chatGPT: ChatGPTSelection(model: .luna56, effort: .high),
                claudeCode: ClaudeCodeSelection(model: .sonnet5, effort: .medium),
                cursor: CursorSelection(model: .composer25Fast, effort: .high),
                antigravity: AntigravitySelection(model: .gemini37Flash, effort: .medium)
            ),
            ShortcutEntry(
                shortcut: KeyboardShortcut(
                    keyCode: 19,
                    keyLabel: "2",
                    modifiers: [.command, .shift]
                ),
                chatGPT: ChatGPTSelection(model: .sol56, effort: .high),
                claudeCode: ClaudeCodeSelection(model: .sonnet5, effort: .high),
                cursor: CursorSelection(model: .gpt56Sol, effort: .high),
                antigravity: AntigravitySelection(model: .claudeOpus46, effort: .thinking)
            )
        ])
    }
}
