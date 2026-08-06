import Testing
@testable import ReasonDeck

@Test func configurationStartsEmpty() {
    #expect(ShortcutConfiguration.empty.entries.isEmpty)
}

@Test func supportedLabelsHaveOneTypedSourceOfTruth() {
    #expect(ChatGPTModel.allCases.map(\.rawValue) == ["5.6 Sol", "5.6 Terra", "5.6 Luna", "5.5", "5.4", "5.4 Mini", "5.3 Codex Spark"])
    #expect(ReasoningEffort.allCases.map(\.rawValue) == ["Extra High", "Medium", "Light", "Ultra", "High", "Max"])
}

@Test func keyboardShortcutsRequireAProtectiveModifier() throws {
    #expect(throws: KeyboardShortcut.ValidationError.missingProtectiveModifier) {
        try KeyboardShortcut(keyCode: 18, keyLabel: "1", modifiers: [.shift])
    }
    let shortcut = try KeyboardShortcut(keyCode: 18, keyLabel: "1", modifiers: [.command, .shift])
    #expect(shortcut.displayName == "⇧⌘1")
}

@Test func keyLabelsUseTheUnmodifiedKeyboardLayoutValue() {
    #expect(KeyboardKeyLabel.label(for: 18, fallback: "1") == "1")
    #expect(KeyboardKeyLabel.label(for: 0, fallback: "A") == "A")
    #expect(KeyboardKeyLabel.label(for: 122, fallback: nil) == "F1")
}

@Test func configurationRejectsDuplicateShortcutsAndIdentifiers() throws {
    let shortcut = try KeyboardShortcut(keyCode: 18, keyLabel: "1", modifiers: [.command])
    let first = ShortcutEntry(shortcut: shortcut, selection: ProfileSelection(model: .sol56, effort: .extraHigh))
    let second = ShortcutEntry(shortcut: shortcut, selection: ProfileSelection(model: .terra56, effort: .high))
    #expect(throws: ShortcutConfiguration.ValidationError.duplicateShortcut) {
        try ShortcutConfiguration(entries: [first, second])
    }
    #expect(throws: ShortcutConfiguration.ValidationError.duplicateIdentifier) {
        try ShortcutConfiguration(entries: [first, ShortcutEntry(id: first.id, shortcut: nil, selection: second.selection)])
    }
}

@Test func profileSelectionOwnsDisplayAndExactTitleMatching() {
    let selection = ProfileSelection(model: .mini54, effort: .extraHigh)
    #expect(selection.displayName == "5.4 Mini / Extra High")
    #expect(selection.matches(title: "  5.4 Mini   Extra High "))
    #expect(selection.title("5.4 Mini Extra High", containsModel: .mini54))
    #expect(!selection.title("5.4 Mini Extra High", containsModel: .model54))
    #expect(!selection.title("5.4 Mini Extra High", containsEffort: .high))
}

@Test func operationStatesRemainDistinctAndHumanReadable() {
    #expect(OperationStatus.switching("A").message.contains("Applying"))
    #expect(OperationStatus.success("A").systemImage.contains("checkmark"))
    #expect(OperationStatus.partial(title: "A", message: "B").message.contains("Partially"))
    #expect(OperationStatus.failure("B").systemImage.contains("xmark"))
    #expect(OperationStatus.invalidConfiguration("Reset").message == "Reset")
}
