import Foundation
import Testing
@testable import ReasonDeck

@Test func configurationStartsEmpty() {
    #expect(ShortcutConfiguration.empty.entries.isEmpty)
}

@Test func supportedLabelsHaveOneTypedSourceOfTruth() {
    #expect(ChatGPTModel.allCases.map(\.rawValue) == ["5.6 Sol", "5.6 Terra", "5.6 Luna", "5.5", "5.4", "5.4 Mini", "5.3 Codex Spark"])
    #expect(ChatGPTReasoningEffort.allCases.map(\.rawValue) == ["Extra High", "Medium", "None", "Light", "Ultra", "High", "Max"])
    #expect(ClaudeCodeModel.allCases.map(\.rawValue) == ["Fable 5", "Opus 5", "Sonnet 5", "Haiku 4.5"])
    #expect(ClaudeCodeEffort.allCases.map(\.rawValue) == ["Auto", "Low", "Medium", "None", "High", "Extra High", "Max", "Ultracode"])
    #expect(CursorModel.allCases.map(\.rawValue) == [
        "Auto", "Grok 4.5", "Grok 4.6", "Composer 2.5", "Composer 2.5 Fast",
        "Claude Fable 5", "Claude Opus 5", "Claude Sonnet 5",
        "GPT-5.6 Sol", "GPT-5.6 Terra", "GPT-5.6 Luna"
    ])
    #expect(CursorEffort.allCases.map(\.rawValue) == ["Low", "Medium", "None", "High"])
    #expect(AntigravityModel.allCases.map(\.rawValue) == [
        "Gemini 3.7 Flash", "Gemini 3.6 Flash", "Gemini 3.5 Flash", "Gemini 3.1 Pro",
        "Claude Sonnet 4.6", "Claude Opus 4.6", "GPT-OSS 120B"
    ])
    #expect(AntigravityEffort.allCases.map(\.rawValue) == ["High", "Medium", "None", "(Thinking)", "(Medium)"])
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
    let first = ShortcutEntry(shortcut: shortcut, chatGPT: ChatGPTSelection(model: .sol56, effort: .extraHigh), claudeCode: nil)
    let second = ShortcutEntry(shortcut: shortcut, chatGPT: ChatGPTSelection(model: .terra56, effort: .high), claudeCode: nil)
    #expect(throws: ShortcutConfiguration.ValidationError.duplicateShortcut) {
        try ShortcutConfiguration(entries: [first, second])
    }
    #expect(throws: ShortcutConfiguration.ValidationError.duplicateIdentifier) {
        try ShortcutConfiguration(entries: [first, ShortcutEntry(id: first.id, shortcut: nil, chatGPT: second.chatGPT, claudeCode: nil)])
    }
}

@Test func configurationRejectsTheSamePhysicalShortcutWithDifferentLabels() throws {
    let numericLabel = try KeyboardShortcut(keyCode: 18, keyLabel: "1", modifiers: [.command])
    let alternateLabel = try KeyboardShortcut(keyCode: 18, keyLabel: "!", modifiers: [.command])
    let first = ShortcutEntry(shortcut: numericLabel, chatGPT: ChatGPTSelection(model: .sol56, effort: .extraHigh), claudeCode: nil)
    let second = ShortcutEntry(shortcut: alternateLabel, chatGPT: ChatGPTSelection(model: .terra56, effort: .high), claudeCode: nil)

    #expect(throws: ShortcutConfiguration.ValidationError.duplicateShortcut) {
        try ShortcutConfiguration(entries: [first, second])
    }
}

@Test func configurationRejectsMultipleFinishedSessionActions() {
    let first = ShortcutEntry(
        shortcut: nil,
        chatGPT: nil,
        claudeCode: nil,
        cursorNavigation: .nextUnreadSession
    )
    let second = ShortcutEntry(
        shortcut: nil,
        chatGPT: nil,
        claudeCode: nil,
        cursorNavigation: .nextUnreadSession
    )

    #expect(throws: ShortcutConfiguration.ValidationError.duplicateNavigationAction) {
        try ShortcutConfiguration(entries: [first, second])
    }
}

@Test func profileSelectionOwnsDisplayAndExactTitleMatching() {
    let selection = ChatGPTSelection(model: .mini54, effort: .extraHigh)
    #expect(selection.displayName == "5.4 Mini / Extra High")
    #expect(selection.matches(title: "  5.4 Mini   Extra High "))
    #expect(selection.title("5.4 Mini Extra High", containsModel: .mini54))
    #expect(!selection.title("5.4 Mini Extra High", containsModel: .model54))
    #expect(!selection.title("5.4 Mini Extra High", containsEffort: .high))
}

@Test func oneShortcutCanOwnIndependentAssignmentsForSupportedApplications() {
    let chatGPT = ChatGPTSelection(model: .sol56, effort: .extraHigh)
    let claudeCode = ClaudeCodeSelection(model: .opus5, effort: .high)
    let cursor = CursorSelection(model: .grok45, effort: .high)
    let entry = ShortcutEntry(shortcut: nil, chatGPT: chatGPT, claudeCode: claudeCode, cursor: cursor)

    #expect(entry.selection(for: .chatGPT) == .chatGPT(chatGPT))
    #expect(entry.selection(for: .claudeCode) == .claudeCode(claudeCode))
    #expect(entry.selection(for: .cursor) == .cursor(cursor))
    #expect(entry.enabledTargets == [.chatGPT, .claudeCode, .cursor])
}

@Test func configuredModelAdaptersAreRunnableForEverySupportedApplication() throws {
    let shortcut = try KeyboardShortcut(keyCode: 18, keyLabel: "1", modifiers: [.command])
    let entry = ShortcutEntry(
        shortcut: shortcut,
        chatGPT: ChatGPTSelection(model: .sol56, effort: .extraHigh),
        claudeCode: ClaudeCodeSelection(model: .opus5, effort: .high),
        cursor: CursorSelection(model: .grok45, effort: .high)
    )

    #expect(entry.enabledTargets == [.chatGPT, .claudeCode, .cursor])
    #expect(RuntimeCapabilities.runnableTargets(for: entry) == [.chatGPT, .claudeCode, .cursor])
}

@Test func cursorModelAndFinishedNavigationAreBothRunnable() throws {
    let shortcut = try KeyboardShortcut(keyCode: 18, keyLabel: "1", modifiers: [.command])
    let modelEntry = ShortcutEntry(
        shortcut: shortcut,
        chatGPT: nil,
        claudeCode: nil,
        cursor: CursorSelection(model: .gpt56Sol, effort: .high)
    )
    let navigationEntry = ShortcutEntry(
        shortcut: shortcut,
        chatGPT: nil,
        claudeCode: nil,
        cursor: nil,
        cursorNavigation: .nextUnreadSession
    )

    #expect(RuntimeCapabilities.runnableTargets(for: modelEntry) == [.cursor])
    #expect(RuntimeCapabilities.runnableTargets(for: navigationEntry) == [.cursor])
}

@Test func persistedCursorModelAndNavigationConflictFailsClosed() throws {
    let payload: [String: Any] = [
        "entries": [[
            "id": UUID().uuidString,
            "shortcut": NSNull(),
            "chatGPT": NSNull(),
            "claudeCode": NSNull(),
            "cursor": ["model": "Grok 4.5", "effort": "High"],
            "cursorNavigation": "nextUnreadSession"
        ]]
    ]
    let data = try JSONSerialization.data(withJSONObject: payload)

    #expect(throws: ShortcutConfiguration.ValidationError.conflictingCursorActions) {
        _ = try JSONDecoder().decode(ShortcutConfiguration.self, from: data)
    }
}

@Test func operationStatesRemainDistinctAndHumanReadable() {
    #expect(OperationStatus.switching("A").message.contains("Applying"))
    #expect(OperationStatus.success("A").systemImage.contains("checkmark"))
    #expect(OperationStatus.already("A").message == "Already A")
    #expect(OperationStatus.partial(title: "A", message: "B").message.contains("Partially"))
    #expect(OperationStatus.failure("B").systemImage.contains("xmark"))
    #expect(OperationStatus.invalidConfiguration("Reset").message == "Reset")
}

@Test func attemptDiagnosticsAllowOnlyClosedFields() {
    let event = AttemptEvent(
        attemptID: UUID(),
        target: .chatGPT,
        phase: .captured,
        outcome: nil,
        failure: nil,
        elapsed: .zero
    )

    #expect(event.target == .chatGPT)
    #expect(event.phase == .captured)
    #expect(event.failure == nil)
}

@Test func busyIsATypedOutcomeRatherThanFreeFormAccessibilityFailure() {
    #expect(SwitchFailure.busy.message.contains("already running"))
    #expect(SwitchFailure.busy.diagnosticCode == .busy)
}

@Test func targetContextRejectsPidAndWindowDrift() {
    let invocation = HotkeyInvocation(
        entryID: UUID(),
        target: .chatGPT,
        pid: 101,
        focusedWindowID: 202
    )
    #expect(TargetContextValidator.matches(
        invocation,
        observed: ObservedTargetContext(target: .chatGPT, pid: 101, focusedWindowID: 202)
    ))
    #expect(!TargetContextValidator.matches(
        invocation,
        observed: ObservedTargetContext(target: .chatGPT, pid: 102, focusedWindowID: 202)
    ))
    #expect(!TargetContextValidator.matches(
        invocation,
        observed: ObservedTargetContext(target: .chatGPT, pid: 101, focusedWindowID: 203)
    ))
}

@Test func deferredHotkeyCaptureBindsOnlyTheSameTargetProcessAndObservedWindow() {
    let entryID = UUID()
    let capture = HotkeyCapture(entryID: entryID, target: .cursor, pid: 101)
    let identity = FocusedWindowIdentity(id: 202, source: .correlatedWindowGeometry)

    #expect(HotkeyInvocationFactory.make(
        capture: capture,
        observedTarget: .cursor,
        observedPID: 101,
        identity: identity
    ) == HotkeyInvocation(
        entryID: entryID,
        target: .cursor,
        pid: 101,
        focusedWindowID: 202,
        identitySource: .correlatedWindowGeometry
    ))
    #expect(HotkeyInvocationFactory.make(
        capture: capture,
        observedTarget: .chatGPT,
        observedPID: 101,
        identity: identity
    ) == nil)
    #expect(HotkeyInvocationFactory.make(
        capture: capture,
        observedTarget: .cursor,
        observedPID: 102,
        identity: identity
    ) == nil)
}

@Test func focusedAXGeometryCorrelatesOnlyOneSamePidLayerZeroWindow() {
    let frame = CGRect(x: 100, y: 50, width: 1200, height: 800)
    let candidates = [
        AXWindowIdentity.GeometryCandidate(id: 7, pid: 42, bounds: frame, layer: 0, isOnscreen: true),
        AXWindowIdentity.GeometryCandidate(id: 8, pid: 99, bounds: frame, layer: 0, isOnscreen: true),
        AXWindowIdentity.GeometryCandidate(id: 9, pid: 42, bounds: frame, layer: 1, isOnscreen: true),
    ]

    #expect(AXWindowIdentity.correlatedWindowID(
        pid: 42,
        focusedAXFrame: frame,
        candidates: candidates
    ) == 7)
}

@Test func focusedAXGeometryFailsClosedOnAmbiguityOrDrift() {
    let frame = CGRect(x: 100, y: 50, width: 1200, height: 800)
    let duplicateMatches = [
        AXWindowIdentity.GeometryCandidate(id: 7, pid: 42, bounds: frame, layer: 0, isOnscreen: true),
        AXWindowIdentity.GeometryCandidate(id: 8, pid: 42, bounds: frame, layer: 0, isOnscreen: true),
    ]
    let drifted = [
        AXWindowIdentity.GeometryCandidate(
            id: 9,
            pid: 42,
            bounds: CGRect(x: 104, y: 50, width: 1200, height: 800),
            layer: 0,
            isOnscreen: true
        ),
    ]

    #expect(AXWindowIdentity.correlatedWindowID(pid: 42, focusedAXFrame: frame, candidates: duplicateMatches) == nil)
    #expect(AXWindowIdentity.correlatedWindowID(pid: 42, focusedAXFrame: frame, candidates: drifted) == nil)
}
