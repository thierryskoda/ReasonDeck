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

enum ReasoningEffort: String, CaseIterable, Codable, Hashable, Sendable, Identifiable {
    case extraHigh = "Extra High"
    case medium = "Medium"
    case light = "Light"
    case ultra = "Ultra"
    case high = "High"
    case max = "Max"

    var id: String { rawValue }
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

struct ProfileSelection: Codable, Hashable, Sendable, Identifiable {
    let model: ChatGPTModel
    let effort: ReasoningEffort

    var id: String { "\(model.rawValue)|\(effort.rawValue)" }
    var displayName: String { "\(model.rawValue) / \(effort.rawValue)" }
    var expectedTitle: String { "\(model.rawValue) \(effort.rawValue)" }

    func matches(title: String) -> Bool {
        Self.normalize(title) == Self.normalize(expectedTitle)
    }

    func title(_ title: String, containsModel model: ChatGPTModel) -> Bool {
        Self.detectedModel(in: title) == model
    }

    func title(_ title: String, containsEffort effort: ReasoningEffort) -> Bool {
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

    static func detectedEffort(in title: String) -> ReasoningEffort? {
        ReasoningEffort.allCases
            .sorted { $0.rawValue.count > $1.rawValue.count }
            .first { containsOrdered(title, $0.rawValue) }
    }

    private static func normalize(_ value: String) -> String {
        value.split(whereSeparator: \.isWhitespace).joined(separator: " ")
    }
}

struct ShortcutEntry: Codable, Hashable, Sendable, Identifiable {
    let id: UUID
    let shortcut: KeyboardShortcut?
    let selection: ProfileSelection

    init(id: UUID = UUID(), shortcut: KeyboardShortcut?, selection: ProfileSelection) {
        self.id = id
        self.shortcut = shortcut
        self.selection = selection
    }
}

struct ShortcutConfiguration: Codable, Equatable, Sendable {
    enum ValidationError: Error, Equatable {
        case duplicateIdentifier
        case duplicateShortcut
    }

    let entries: [ShortcutEntry]

    private init(validatedEntries: [ShortcutEntry]) {
        entries = validatedEntries
    }

    init(entries: [ShortcutEntry]) throws {
        guard Set(entries.map(\.id)).count == entries.count else {
            throw ValidationError.duplicateIdentifier
        }
        let shortcuts = entries.compactMap(\.shortcut)
        guard Set(shortcuts).count == shortcuts.count else {
            throw ValidationError.duplicateShortcut
        }
        self.entries = entries
    }

    static let empty = ShortcutConfiguration(validatedEntries: [])

    func entry(id: UUID) -> ShortcutEntry? {
        entries.first { $0.id == id }
    }

    func addingEntry(selection: ProfileSelection) -> (configuration: ShortcutConfiguration, id: UUID) {
        var id = UUID()
        while entry(id: id) != nil { id = UUID() }
        let entry = ShortcutEntry(id: id, shortcut: nil, selection: selection)
        return (ShortcutConfiguration(validatedEntries: entries + [entry]), id)
    }

    func replacing(_ entry: ShortcutEntry) throws -> ShortcutConfiguration {
        try ShortcutConfiguration(entries: entries.map { $0.id == entry.id ? entry : $0 })
    }

    func replacingSelection(_ selection: ProfileSelection, for id: UUID) -> ShortcutConfiguration {
        ShortcutConfiguration(validatedEntries: entries.map { entry in
            guard entry.id == id else { return entry }
            return ShortcutEntry(id: id, shortcut: entry.shortcut, selection: selection)
        })
    }

    func deleting(_ id: UUID) -> ShortcutConfiguration {
        ShortcutConfiguration(validatedEntries: entries.filter { $0.id != id })
    }

    private enum CodingKeys: String, CodingKey { case entries }

    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        try self.init(entries: container.decode([ShortcutEntry].self, forKey: .entries))
    }
}

enum ShortcutAssignmentError: Error, Equatable {
    case duplicate

    var message: String { "That keyboard shortcut is already assigned." }
}

enum SwitchFailure: Error, Equatable, Sendable {
    case permissionMissing, chatGPTNotFrontmost, noFocusedWindow
    case pickerNotFound, modelRowNotActionable, modelUnavailable(String)
    case effortRowNotActionable, effortUnavailable(String), deadlineExceeded(String)
    case verificationMismatch(expected: String, observed: String), accessibility(String)

    var message: String {
        switch self {
        case .permissionMissing: "Accessibility permission is required."
        case .chatGPTNotFrontmost: "Bring ChatGPT to the front first."
        case .noFocusedWindow: "No focused ChatGPT window was found."
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
}

enum ProfileSwitchResult: Equatable, Sendable {
    case success(profile: ProfileSelection, observedTitle: String, elapsed: Duration)
    case partialFailure(profile: ProfileSelection, observedTitle: String, failure: SwitchFailure)
    case failure(profile: ProfileSelection, failure: SwitchFailure)
}

enum OperationStatus: Equatable, Sendable {
    case ready
    case switching(String)
    case success(String)
    case partial(title: String, message: String)
    case failure(String)
    case invalidConfiguration(String)

    var message: String {
        switch self {
        case .ready: "Ready"
        case .switching(let profile): "Applying \(profile)…"
        case .success(let title): "Applied \(title)"
        case .partial(let title, let message): "Partially applied \(title). \(message)"
        case .failure(let message), .invalidConfiguration(let message): message
        }
    }

    var systemImage: String {
        switch self {
        case .ready: "circle"
        case .switching: "arrow.triangle.2.circlepath"
        case .success: "checkmark.circle.fill"
        case .partial: "exclamationmark.circle.fill"
        case .failure, .invalidConfiguration: "xmark.circle.fill"
        }
    }
}
