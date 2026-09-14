import Foundation

enum ChatGPTModel: String, CaseIterable, Codable, Hashable, Sendable, Identifiable {
    case sol56 = "5.6 Sol"
    case terra56 = "5.6 Terra"
    case luna56 = "5.6 Luna"
    case model55 = "5.5"
    case model54 = "5.4"
    case mini54 = "5.4 Mini"
    case codexSpark53 = "5.3 Codex Spark"

    var id: String { rawValue }
}

enum ChatGPTReasoningEffort: String, CaseIterable, Codable, Hashable, Sendable, Identifiable {
    case extraHigh = "Extra High"
    case medium = "Medium"
    case none = "None"
    case light = "Light"
    case ultra = "Ultra"
    case high = "High"
    case max = "Max"

    var id: String { rawValue }

    /// Settings follow increasing reasoning intensity; declaration order remains
    /// independent because recognition code iterates every exact supported label.
    static let settingsOrder: [Self] = [.none, .light, .medium, .high, .extraHigh, .max, .ultra]
}

enum ApplicationTarget: String, CaseIterable, Codable, Hashable, Sendable, Identifiable {
    case chatGPT
    case claudeCode
    case cursor
    case antigravity

    var id: String { rawValue }
    var displayName: String {
        switch self {
        case .chatGPT: "ChatGPT"
        case .claudeCode: "Claude Desktop"
        case .cursor: "Cursor"
        case .antigravity: "Antigravity"
        }
    }

    var systemImage: String {
        switch self {
        case .chatGPT: "bubble.left.and.bubble.right"
        case .claudeCode: "terminal"
        case .cursor: "chevron.left.forwardslash.chevron.right"
        case .antigravity: "sparkles"
        }
    }

    var bundleIdentifier: String {
        switch self {
        case .chatGPT: AppConstants.chatGPTBundleID
        case .claudeCode: AppConstants.claudeDesktopBundleID
        case .cursor: AppConstants.cursorBundleID
        case .antigravity: AppConstants.antigravityBundleID
        }
    }
}

/// The single runtime support boundary. Persisted assignments remain intact when a
/// target is gated, but gated targets cannot be exposed through shortcuts or menu actions.
enum RuntimeCapabilities {
    static let releaseReadyModelTargets: Set<ApplicationTarget> = [.chatGPT, .claudeCode, .cursor, .antigravity]

    static func supports(_ target: ApplicationTarget) -> Bool {
        releaseReadyModelTargets.contains(target)
    }

    static func supports(_ entry: ShortcutEntry, target: ApplicationTarget) -> Bool {
        return entry.selection(for: target) != nil && supports(target)
    }

    static func runnableTargets(for entry: ShortcutEntry) -> Set<ApplicationTarget> {
        Set(entry.enabledTargets.filter { supports(entry, target: $0) })
    }

    static func unavailableMessage(for target: ApplicationTarget) -> String {
        "\(target.displayName) support is gated until its signed Accessibility reliability checks pass."
    }
}

enum ClaudeCodeModel: String, CaseIterable, Codable, Hashable, Sendable, Identifiable {
    case fable5 = "Fable 5"
    case opus5 = "Opus 5"
    case sonnet5 = "Sonnet 5"
    case haiku45 = "Haiku 4.5"

    var id: String { rawValue }
}

enum ClaudeCodeEffort: String, CaseIterable, Codable, Hashable, Sendable, Identifiable {
    case automatic = "Auto"
    case low = "Low"
    case medium = "Medium"
    case none = "None"
    case high = "High"
    case extraHigh = "Extra High"
    case max = "Max"
    case ultracode = "Ultracode"

    var id: String { rawValue }

    static let settingsOrder: [Self] = [
        .automatic, .none, .low, .medium, .high, .extraHigh, .max, .ultracode,
    ]
}

struct ShortcutModifiers: OptionSet, Codable, Hashable, Sendable {
    let rawValue: UInt64

    static let command = Self(rawValue: 1 << 0)
    static let option = Self(rawValue: 1 << 1)
    static let control = Self(rawValue: 1 << 2)
    static let shift = Self(rawValue: 1 << 3)
    static let allowed: Self = [.command, .option, .control, .shift]
    static let protective: Self = [.command, .option, .control]

    var displayName: String {
        var value = ""
        if contains(.control) { value += "⌃" }
        if contains(.option) { value += "⌥" }
        if contains(.shift) { value += "⇧" }
        if contains(.command) { value += "⌘" }
        return value
    }
}

struct KeyboardShortcut: Codable, Hashable, Sendable {
    enum ValidationError: Error, Equatable {
        case invalidModifiers
        case missingProtectiveModifier
        case invalidKeyLabel
    }

    let keyCode: UInt16
    let keyLabel: String
    let modifiers: ShortcutModifiers

    init(keyCode: UInt16, keyLabel: String, modifiers: ShortcutModifiers) throws {
        guard modifiers.subtracting(.allowed).isEmpty else { throw ValidationError.invalidModifiers }
        guard !modifiers.intersection(.protective).isEmpty else { throw ValidationError.missingProtectiveModifier }
        let label = keyLabel.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !label.isEmpty, label.count <= 12 else { throw ValidationError.invalidKeyLabel }
        self.keyCode = keyCode
        self.keyLabel = label
        self.modifiers = modifiers
    }

    var displayName: String { modifiers.displayName + keyLabel }
    var identity: ShortcutIdentity { ShortcutIdentity(keyCode: keyCode, modifiers: modifiers) }

    private enum CodingKeys: String, CodingKey { case keyCode, keyLabel, modifiers }

    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        try self.init(
            keyCode: container.decode(UInt16.self, forKey: .keyCode),
            keyLabel: container.decode(String.self, forKey: .keyLabel),
            modifiers: container.decode(ShortcutModifiers.self, forKey: .modifiers)
        )
    }
}

struct ShortcutIdentity: Hashable, Sendable {
    let keyCode: UInt16
    let modifiers: ShortcutModifiers
}

enum KeyboardKeyLabel {
    private static let labels: [UInt16: String] = [
        36: "↩", 48: "⇥", 49: "Space", 51: "⌫", 53: "⎋",
        64: "F17", 65: "Num .", 67: "Num *", 69: "Num +",
        71: "Num Clear", 75: "Num /", 76: "Num ↩", 78: "Num -", 79: "F18",
        80: "F19", 81: "Num =", 82: "Num 0", 83: "Num 1", 84: "Num 2",
        85: "Num 3", 86: "Num 4", 87: "Num 5", 88: "Num 6", 89: "Num 7",
        90: "F20", 91: "Num 8", 92: "Num 9", 96: "F5", 97: "F6", 98: "F7",
        99: "F3", 100: "F8", 101: "F9", 103: "F11", 105: "F13", 106: "F16",
        107: "F14", 109: "F10", 111: "F12", 113: "F15", 115: "Home",
        116: "Page Up", 117: "⌦", 118: "F4", 119: "End", 120: "F2",
        121: "Page Down", 122: "F1", 123: "←", 124: "→", 125: "↓", 126: "↑"
    ]

    static func label(for keyCode: UInt16, fallback: String?) -> String? {
        if let label = labels[keyCode] { return label }
        guard let fallback else { return nil }
        let normalized = fallback.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        return normalized.count == 1 ? normalized : nil
    }
}

struct ChatGPTSelection: Codable, Hashable, Sendable, Identifiable {
    let model: ChatGPTModel
    let effort: ChatGPTReasoningEffort

    var id: String { "\(model.rawValue)|\(effort.rawValue)" }
    var displayName: String { "\(model.rawValue) / \(effort.rawValue)" }
    var expectedTitle: String { "\(model.rawValue) \(effort.rawValue)" }

    func matches(title: String) -> Bool {
        Self.normalize(title) == Self.normalize(expectedTitle)
    }

    func title(_ title: String, containsModel model: ChatGPTModel) -> Bool {
        Self.detectedModel(in: title) == model
    }

    func title(_ title: String, containsEffort effort: ChatGPTReasoningEffort) -> Bool {
        Self.detectedEffort(in: title) == effort
    }

    static func containsOrdered(_ title: String, _ value: String) -> Bool {
        normalize(title).contains(normalize(value))
    }

    static func detectedModel(in title: String) -> ChatGPTModel? {
        ChatGPTModel.allCases
            .sorted { $0.rawValue.count > $1.rawValue.count }
            .first { containsOrdered(title, $0.rawValue) }
    }

    static func detectedEffort(in title: String) -> ChatGPTReasoningEffort? {
        ChatGPTReasoningEffort.allCases
            .sorted { $0.rawValue.count > $1.rawValue.count }
            .first { containsOrdered(title, $0.rawValue) }
    }

    private static func normalize(_ value: String) -> String {
        value.split(whereSeparator: \.isWhitespace).joined(separator: " ")
    }
}

struct ClaudeCodeSelection: Codable, Hashable, Sendable, Identifiable {
    let model: ClaudeCodeModel
    let effort: ClaudeCodeEffort

    var id: String { "\(model.rawValue)|\(effort.rawValue)" }
    var displayName: String { "\(model.rawValue) / \(effort.rawValue)" }
}

enum CursorModel: String, CaseIterable, Codable, Hashable, Sendable, Identifiable {
    case automatic = "Auto"
    case grok45 = "Grok 4.5"
    case grok46 = "Grok 4.6"
    case composer25 = "Composer 2.5"
    case composer25Fast = "Composer 2.5 Fast"
    case claudeFable5 = "Claude Fable 5"
    case claudeOpus5 = "Claude Opus 5"
    case claudeSonnet5 = "Claude Sonnet 5"
    case gpt56Sol = "GPT-5.6 Sol"
    case gpt56Terra = "GPT-5.6 Terra"
    case gpt56Luna = "GPT-5.6 Luna"

    var id: String { rawValue }
}

enum CursorEffort: String, CaseIterable, Codable, Hashable, Sendable, Identifiable {
    case low = "Low"
    case medium = "Medium"
    case none = "None"
    case high = "High"

    var id: String { rawValue }

    static let settingsOrder: [Self] = [.none, .low, .medium, .high]
}

struct CursorSelection: Codable, Hashable, Sendable, Identifiable {
    let model: CursorModel
    let effort: CursorEffort

    var id: String { "\(model.rawValue)|\(effort.rawValue)" }
    var displayName: String { "\(model.rawValue) / \(effort.rawValue)" }
}


enum AntigravityModel: String, CaseIterable, Codable, Hashable, Sendable, Identifiable {
    case gemini38Flash = "Gemini 3.8 Flash"
    case gemini37Flash = "Gemini 3.7 Flash"
    case gemini36Flash = "Gemini 3.6 Flash"
    case gemini35Flash = "Gemini 3.5 Flash"
    case gemini31Pro = "Gemini 3.1 Pro"
    case claudeSonnet46 = "Claude Sonnet 4.6"
    case claudeOpus46 = "Claude Opus 4.6"
    case gptOSS120B = "GPT-OSS 120B"

    var id: String { rawValue }
}

enum AntigravityEffort: String, CaseIterable, Codable, Hashable, Sendable, Identifiable {
    case high = "High"
    case medium = "Medium"
    case low = "Low"
    case none = "None"
    case thinking = "(Thinking)"
    case mediumParen = "(Medium)"

    var id: String { rawValue }

    static let settingsOrder: [Self] = [.none, .low, .medium, .high, .mediumParen, .thinking]
}

struct AntigravitySelection: Codable, Hashable, Sendable, Identifiable {
    let model: AntigravityModel
    let effort: AntigravityEffort

    var id: String { "\(model.rawValue)|\(effort.rawValue)" }
    var displayName: String { "\(model.rawValue) / \(effort.rawValue)" }
}

enum TargetSelection: Codable, Hashable, Sendable {
    case chatGPT(ChatGPTSelection)
    case claudeCode(ClaudeCodeSelection)
    case cursor(CursorSelection)
    case antigravity(AntigravitySelection)

    var target: ApplicationTarget {
        switch self {
        case .chatGPT: .chatGPT
        case .claudeCode: .claudeCode
        case .cursor: .cursor
        case .antigravity: .antigravity
        }
    }

    var displayName: String {
        switch self {
        case .chatGPT(let selection): selection.displayName
        case .claudeCode(let selection): selection.displayName
        case .cursor(let selection): selection.displayName
        case .antigravity(let selection): selection.displayName
        }
    }

    var id: String { "\(target.rawValue)|\(displayName)" }
}

/// What one read of a saved configuration could not keep.
///
/// Rendered here rather than in the view so the exact wording is testable, and so the
/// only place that decides what counts as a loss is the place that observes it.
struct ConfigurationLosses: Equatable, Sendable {
    /// Shortcuts removed whole, because nothing in them was still usable.
    var removedShortcuts: [String] = []
    /// App assignments removed from shortcuts that were otherwise kept.
    var removedAssignments: [String] = []

    var isEmpty: Bool { removedShortcuts.isEmpty && removedAssignments.isEmpty }
}

/// Collects losses while a saved configuration is being read.
///
/// A `Decodable` initializer can only succeed or throw, so this travels in
/// `JSONDecoder.userInfo`. Without it, retiring a model or a whole feature would either
/// destroy the user's unrelated shortcuts or remove part of one without telling them.
/// `@unchecked` because the compiler cannot see that the lock below is what protects the
/// state. `JSONDecoder.userInfo` requires `Sendable`, and decoding being single threaded
/// today is not something this type should assume on the caller's behalf.
final class ConfigurationLossLog: @unchecked Sendable {
    static let userInfoKey = CodingUserInfoKey(rawValue: "com.thierryai.ReasonDeck.configurationLosses")!

    private let lock = NSLock()
    private var recorded = ConfigurationLosses()

    var losses: ConfigurationLosses { lock.withLock { recorded } }

    func recordRemovedShortcut(label: String?) {
        lock.withLock {
            recorded.removedShortcuts.append(
                "\(Self.subject(label)) was removed because nothing in it is still supported."
            )
        }
    }

    func recordRemovedAssignment(_ target: ApplicationTarget, shortcutLabel: String?) {
        lock.withLock {
            recorded.removedAssignments.append(
                "\(target.displayName) was removed from \(Self.subject(shortcutLabel).lowercasedFirstWhenDescriptive) "
                    + "because that model or effort is no longer supported."
            )
        }
    }

    private static func subject(_ label: String?) -> String {
        label ?? "A shortcut with no key combination"
    }
}

private extension String {
    /// "⇧⌘1" stays as it is; "A shortcut with no key combination" reads better mid-sentence.
    var lowercasedFirstWhenDescriptive: String {
        guard let first = first, first.isLetter else { return self }
        return first.lowercased() + dropFirst()
    }
}

/// Decodes one element of an array without letting its failure end the array.
struct RecoverableElement<Value: Decodable>: Decodable {
    let value: Value?

    init(from decoder: any Decoder) throws {
        value = try? Value(from: decoder)
    }
}

struct ShortcutEntry: Codable, Hashable, Sendable, Identifiable {
    let id: UUID
    let shortcut: KeyboardShortcut?
    let chatGPT: ChatGPTSelection?
    let claudeCode: ClaudeCodeSelection?
    let cursor: CursorSelection?
    let antigravity: AntigravitySelection?

    init(
        id: UUID = UUID(),
        shortcut: KeyboardShortcut?,
        chatGPT: ChatGPTSelection?,
        claudeCode: ClaudeCodeSelection?,
        cursor: CursorSelection? = nil,
        antigravity: AntigravitySelection? = nil
    ) {
        self.id = id
        self.shortcut = shortcut
        self.chatGPT = chatGPT
        self.claudeCode = claudeCode
        self.cursor = cursor
        self.antigravity = antigravity
    }

    var enabledTargets: Set<ApplicationTarget> {
        var targets = Set<ApplicationTarget>()
        if chatGPT != nil { targets.insert(.chatGPT) }
        if claudeCode != nil { targets.insert(.claudeCode) }
        if cursor != nil { targets.insert(.cursor) }
        if antigravity != nil { targets.insert(.antigravity) }
        return targets
    }

    func selection(for target: ApplicationTarget) -> TargetSelection? {
        switch target {
        case .chatGPT: chatGPT.map(TargetSelection.chatGPT)
        case .claudeCode: claudeCode.map(TargetSelection.claudeCode)
        case .cursor: cursor.map(TargetSelection.cursor)
        case .antigravity: antigravity.map(TargetSelection.antigravity)
        }
    }

    private enum CodingKeys: String, CodingKey {
        case id, shortcut, chatGPT, claudeCode, cursor, antigravity
    }

    /// Reads each part of a saved shortcut on its own.
    ///
    /// A model or effort this build has retired removes only that app from this shortcut. It
    /// does not invalidate the shortcut's other apps, and it does not invalidate neighbouring
    /// shortcuts. Keys this build no longer knows are ignored outright, which is why retiring
    /// a feature needs no migration code. Dropping is never substitution: an unreadable
    /// assignment is removed and reported, never replaced with a different model or effort.
    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        // A shortcut that no longer satisfies the modifier rules leaves the entry unassigned
        // rather than discarding its selections; the empty key field is visible in Settings.
        shortcut = (try? container.decodeIfPresent(KeyboardShortcut.self, forKey: .shortcut)) ?? nil

        let log = decoder.userInfo[ConfigurationLossLog.userInfoKey] as? ConfigurationLossLog
        let label = shortcut?.displayName

        chatGPT = Self.assignment(ChatGPTSelection.self, .chatGPT, .chatGPT, container, label, log)
        claudeCode = Self.assignment(ClaudeCodeSelection.self, .claudeCode, .claudeCode, container, label, log)
        cursor = Self.assignment(CursorSelection.self, .cursor, .cursor, container, label, log)
        antigravity = Self.assignment(AntigravitySelection.self, .antigravity, .antigravity, container, label, log)
    }

    /// Absent means the user never enabled that app; present but unreadable means this build
    /// retired the stored model or effort, which is a loss the user has to be told about.
    private static func assignment<Selection: Decodable>(
        _ type: Selection.Type,
        _ key: CodingKeys,
        _ target: ApplicationTarget,
        _ container: KeyedDecodingContainer<CodingKeys>,
        _ shortcutLabel: String?,
        _ log: ConfigurationLossLog?
    ) -> Selection? {
        guard container.contains(key) else { return nil }
        guard let decoded = try? container.decodeIfPresent(type, forKey: key) else {
            log?.recordRemovedAssignment(target, shortcutLabel: shortcutLabel)
            return nil
        }
        return decoded
    }
}

struct ShortcutConfiguration: Codable, Equatable, Sendable {
    enum ValidationError: Error, Equatable {
        case duplicateIdentifier
        case duplicateShortcut
        case missingAssignment
    }

    let entries: [ShortcutEntry]

    private init(validatedEntries: [ShortcutEntry]) {
        entries = validatedEntries
    }

    init(entries: [ShortcutEntry]) throws {
        guard Set(entries.map(\.id)).count == entries.count else {
            throw ValidationError.duplicateIdentifier
        }
        let shortcuts = entries.compactMap(\.shortcut).map(\.identity)
        guard Set(shortcuts).count == shortcuts.count else {
            throw ValidationError.duplicateShortcut
        }
        guard entries.allSatisfy({ !$0.enabledTargets.isEmpty }) else {
            throw ValidationError.missingAssignment
        }
        self.entries = entries
    }

    static let empty = ShortcutConfiguration(validatedEntries: [])

    func entry(id: UUID) -> ShortcutEntry? {
        entries.first { $0.id == id }
    }

    func addingEntry(chatGPT: ChatGPTSelection) -> (configuration: ShortcutConfiguration, id: UUID) {
        var id = UUID()
        while entry(id: id) != nil { id = UUID() }
        let entry = ShortcutEntry(id: id, shortcut: nil, chatGPT: chatGPT, claudeCode: nil, cursor: nil, antigravity: nil)
        return (ShortcutConfiguration(validatedEntries: entries + [entry]), id)
    }

    func replacing(_ entry: ShortcutEntry) throws -> ShortcutConfiguration {
        try ShortcutConfiguration(entries: entries.map { $0.id == entry.id ? entry : $0 })
    }

    func deleting(_ id: UUID) -> ShortcutConfiguration {
        ShortcutConfiguration(validatedEntries: entries.filter { $0.id != id })
    }

    private enum CodingKeys: String, CodingKey { case entries }

    /// Reads a saved configuration, keeping every shortcut this build can still honor.
    ///
    /// Each entry is decoded independently, so one shortcut this build cannot read never
    /// takes its readable neighbours with it. Reading therefore fails only when the stored
    /// data is not a configuration at all, not because part of it is out of date.
    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let decoded = try container.decode([RecoverableElement<ShortcutEntry>].self, forKey: .entries)
        let log = decoder.userInfo[ConfigurationLossLog.userInfoKey] as? ConfigurationLossLog

        for element in decoded where element.value == nil {
            log?.recordRemovedShortcut(label: nil)
        }

        self = Self.recovered(from: decoded.compactMap(\.value), log: log)
    }

    /// Reduces entries read from storage to the ones this build can honor.
    ///
    /// An entry with no assignments left has nothing to run, and a duplicate of one already
    /// kept cannot be told apart at dispatch. Both are removed and reported. Nothing is ever
    /// rewritten into something else: the invariant is that ReasonDeck drops what it cannot
    /// honor and says so, never that it guesses a replacement. See ADR-001.
    static func recovered(
        from entries: [ShortcutEntry],
        log: ConfigurationLossLog?
    ) -> ShortcutConfiguration {
        var kept: [ShortcutEntry] = []
        var seenIdentifiers: Set<UUID> = []
        var seenShortcuts: Set<ShortcutIdentity> = []

        for entry in entries {
            let label = entry.shortcut?.displayName

            guard !entry.enabledTargets.isEmpty else {
                log?.recordRemovedShortcut(label: label)
                continue
            }
            guard seenIdentifiers.insert(entry.id).inserted else {
                log?.recordRemovedShortcut(label: label)
                continue
            }
            if let identity = entry.shortcut?.identity, !seenShortcuts.insert(identity).inserted {
                log?.recordRemovedShortcut(label: label)
                continue
            }
            kept.append(entry)
        }

        return ShortcutConfiguration(validatedEntries: kept)
    }
}

enum ShortcutAssignmentError: Error, Equatable {
    case duplicate
    case lastAssignment

    var message: String {
        switch self {
        case .duplicate: "That keyboard shortcut is already assigned."
        case .lastAssignment: "Each shortcut must remain enabled for at least one application."
        }
    }
}

enum SwitchFailure: Error, Equatable, Sendable {
    case busy, capabilityGated, invalidConfiguration, permissionMissing, chatGPTNotFrontmost, targetChanged(String), noFocusedWindow
    case claudeCodeSurfaceNotFound, cursorModelControlUnavailable, cursorPickerDidNotOpen
    case cursorMenuItemMissing(String)
    case pickerNotFound, modelRowNotActionable, modelUnavailable(String)
    case effortRowNotActionable, effortUnavailable(String), deadlineExceeded(String)
    case verificationMismatch(expected: String, observed: String), accessibility(String)

    var message: String {
        switch self {
        case .busy: "Another switch is already running."
        case .capabilityGated: "This target is gated until its signed Accessibility reliability checks pass."
        case .invalidConfiguration: "Saved shortcuts are invalid. Reset them before switching."
        case .permissionMissing: "Accessibility permission is required."
        case .chatGPTNotFrontmost: "Bring ChatGPT to the front first."
        case .targetChanged(let app): "The active \(app) window changed before switching finished."
        case .noFocusedWindow: "No focused app window was found."
        case .claudeCodeSurfaceNotFound: "Open Claude Desktop with a visible Chat/Cowork composer or an idle Code Prompt composer."
        case .cursorModelControlUnavailable: "Cursor model chip isn’t visible. Click the model name, then retry."
        case .cursorPickerDidNotOpen: "Cursor’s model menu didn’t open. Click the model chip, then retry."
        case .cursorMenuItemMissing(let value): "‘\(value)’ isn’t in Cursor’s open model menu."
        case .pickerNotFound: "The composer model picker was not found."
        case .modelRowNotActionable: "The Model row is not actionable."
        case .modelUnavailable(let value): "Model ‘\(value)’ is unavailable."
        case .effortRowNotActionable: "The Effort row is not actionable."
        case .effortUnavailable(let value): "Effort ‘\(value)’ is unavailable."
        case .deadlineExceeded(let phase): "Timed out while \(phase)."
        case .verificationMismatch(let expected, let observed): "Expected ‘\(expected)’, observed ‘\(observed)’."
        case .accessibility(let detail): "Accessibility failed: \(detail)"
        }
    }

    /// Safe for diagnostics: never exposes Accessibility text or error details.
    var diagnosticCode: AttemptFailureCode {
        switch self {
        case .busy: .busy
        case .capabilityGated: .capabilityGated
        case .invalidConfiguration: .invalidConfiguration
        case .permissionMissing: .permissionMissing
        case .chatGPTNotFrontmost: .chatGPTNotFrontmost
        case .targetChanged: .targetChanged
        case .noFocusedWindow: .noFocusedWindow
        case .claudeCodeSurfaceNotFound: .claudeCodeSurfaceNotFound
        case .cursorModelControlUnavailable: .cursorModelControlUnavailable
        case .cursorPickerDidNotOpen: .cursorPickerDidNotOpen
        case .cursorMenuItemMissing: .cursorMenuItemMissing
        case .pickerNotFound: .pickerNotFound
        case .modelRowNotActionable: .modelRowNotActionable
        case .modelUnavailable: .modelUnavailable
        case .effortRowNotActionable: .effortRowNotActionable
        case .effortUnavailable: .effortUnavailable
        case .deadlineExceeded: .deadlineExceeded
        case .verificationMismatch: .verificationMismatch
        case .accessibility: .accessibilityError
        }
    }
}

enum AttemptFailureCode: String, Equatable, Sendable {
    case busy
    case capabilityGated = "capability_gated"
    case installationRequired = "installation_required"
    case invalidConfiguration = "invalid_configuration"
    case missingAssignment = "missing_assignment"
    case permissionMissing = "permission_missing"
    case chatGPTNotFrontmost = "chatgpt_not_frontmost"
    case targetChanged = "target_changed"
    case noFocusedWindow = "no_focused_window"
    case claudeCodeSurfaceNotFound = "claude_code_surface_not_found"
    case cursorModelControlUnavailable = "cursor_model_control_unavailable"
    case cursorPickerDidNotOpen = "cursor_picker_did_not_open"
    case cursorMenuItemMissing = "cursor_menu_item_missing"
    case pickerNotFound = "picker_not_found"
    case modelRowNotActionable = "model_row_not_actionable"
    case modelUnavailable = "model_unavailable"
    case effortRowNotActionable = "effort_row_not_actionable"
    case effortUnavailable = "effort_unavailable"
    case deadlineExceeded = "deadline_exceeded"
    case verificationMismatch = "verification_mismatch"
    case accessibilityError = "accessibility_error"
}

enum AttemptPhase: String, Equatable, Sendable {
    case captured, dispatched, completed
}

enum AttemptOutcome: String, Equatable, Sendable {
    case success, alreadyApplied, partialFailure, failure, busy, contextAborted
}

/// Values requested by a shortcut. These are source-owned closed enums, never
/// labels obtained from an Accessibility tree.
enum AttemptRequest: Equatable, Sendable {
    case profile(TargetSelection)

    var diagnosticValue: String {
        switch self {
        case .profile(let selection): selection.id
        }
    }
}

/// A bounded local diagnostic record. Its types intentionally prohibit arbitrary UI text.
struct AttemptEvent: Equatable, Sendable {
    let attemptID: UUID
    let target: ApplicationTarget
    let request: AttemptRequest?
    let identitySource: WindowIdentitySource
    let phase: AttemptPhase
    let outcome: AttemptOutcome?
    let failure: AttemptFailureCode?
    let elapsed: Duration

    init(
        attemptID: UUID,
        target: ApplicationTarget,
        request: AttemptRequest? = nil,
        identitySource: WindowIdentitySource = .axWindowNumber,
        phase: AttemptPhase,
        outcome: AttemptOutcome?,
        failure: AttemptFailureCode?,
        elapsed: Duration
    ) {
        self.attemptID = attemptID
        self.target = target
        self.request = request
        self.identitySource = identitySource
        self.phase = phase
        self.outcome = outcome
        self.failure = failure
        self.elapsed = elapsed
    }
}

/// Clipboard-safe failure details for issue reports. The type deliberately has
/// no field for Accessibility labels, window text, or the free-form error message.
struct FailureDiagnostic: Equatable, Sendable {
    let reasonDeckVersion: String
    let reasonDeckBuild: String
    let macOSVersion: String
    let target: ApplicationTarget
    let targetVersion: String
    let failure: AttemptFailureCode

    var clipboardText: String {
        """
        ReasonDeck failure report
        ReasonDeck: \(reasonDeckVersion) (\(reasonDeckBuild))
        macOS: \(macOSVersion)
        App: \(target.displayName) \(targetVersion)
        Failure: \(failure.rawValue)
        """
    }
}

enum ProfileSwitchResult: Equatable, Sendable {
    case success(profile: TargetSelection, observedTitle: String, elapsed: Duration)
    case alreadyApplied(profile: TargetSelection, observedTitle: String)
    case partialFailure(profile: TargetSelection, observedTitle: String, failure: SwitchFailure)
    case failure(profile: TargetSelection, failure: SwitchFailure)
}

enum OperationStatus: Equatable, Sendable {
    case ready
    case switching(String)
    case success(String)
    case already(String)
    case partial(title: String, message: String)
    case busy
    case failure(String)
    case invalidConfiguration(String)

    var message: String {
        switch self {
        case .ready: "Ready"
        case .switching(let profile): "Applying \(profile)…"
        case .success(let title): "Applied \(title)"
        case .already(let title): "Already \(title)"
        case .partial(let title, let message): "Partially applied \(title). \(message)"
        case .busy: SwitchFailure.busy.message
        case .failure(let message), .invalidConfiguration(let message): message
        }
    }

    var systemImage: String {
        switch self {
        case .ready: "circle"
        case .switching: "arrow.triangle.2.circlepath"
        case .success, .already: "checkmark.circle.fill"
        case .partial: "exclamationmark.circle.fill"
        case .busy: "pause.circle.fill"
        case .failure, .invalidConfiguration: "xmark.circle.fill"
        }
    }
}
