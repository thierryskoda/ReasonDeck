import Foundation
import ApplicationServices
import Testing
@testable import ReasonDeck

private struct UnexpectedClaudeEffortFailure: Error {}

private actor FakeClaudeCodeUIClient: ClaudeCodeUIClient {
    let modelResult: Result<String, Error>
    let effortResult: Result<String, Error>

    init(modelResult: Result<String, Error>, effortResult: Result<String, Error>) {
        self.modelResult = modelResult
        self.effortResult = effortResult
    }

    func selectModel(_ model: ClaudeCodeModel, invocation: HotkeyInvocation) async throws -> String {
        try modelResult.get()
    }

    func selectEffort(_ effort: ClaudeCodeEffort, invocation: HotkeyInvocation) async throws -> String {
        try effortResult.get()
    }
}

private let claudeInvocation = HotkeyInvocation(
    entryID: UUID(),
    target: .claudeCode,
    pid: 42,
    focusedWindowID: 99
)

@Test func unexpectedEffortFailurePreservesVerifiedClaudeModelAsPartialSuccess() async {
    let client = FakeClaudeCodeUIClient(
        modelResult: .success("Opus 5"),
        effortResult: .failure(UnexpectedClaudeEffortFailure())
    )
    let coordinator = ClaudeCodeSwitchCoordinator(client: client)

    let result = await coordinator.apply(
        ClaudeCodeSelection(model: .opus5, effort: .high),
        invocation: claudeInvocation
    )

    guard case .partialFailure(_, let observed, .accessibility(let detail)) = result else {
        Issue.record("Expected a partial failure after the verified model change")
        return
    }
    #expect(observed == "Opus 5")
    #expect(detail.contains("UnexpectedClaudeEffortFailure"))
}

@Test func verifiedClaudeModelAndEffortProduceObservedSuccess() async {
    let client = FakeClaudeCodeUIClient(
        modelResult: .success("Sonnet 5"),
        effortResult: .success("High")
    )

    let result = await ClaudeCodeSwitchCoordinator(client: client).apply(
        ClaudeCodeSelection(model: .sonnet5, effort: .high),
        invocation: claudeInvocation
    )

    guard case .success(_, let observed, _) = result else {
        Issue.record("Expected a verified Claude success")
        return
    }
    #expect(observed == "Sonnet 5 / High")
}

@Test func claudeModelFailureDoesNotPretendEffortWasApplied() async {
    let client = FakeClaudeCodeUIClient(
        modelResult: .failure(SwitchFailure.modelUnavailable("Fable 5")),
        effortResult: .success("High")
    )

    let result = await ClaudeCodeSwitchCoordinator(client: client).apply(
        ClaudeCodeSelection(model: .fable5, effort: .high),
        invocation: claudeInvocation
    )

    if case .failure(_, .modelUnavailable("Fable 5")) = result {
        return
    }
    Issue.record("Expected the typed model failure")
}

@Test func mismatchedClaudeModelObservationFailsBeforeEffort() async {
    let client = FakeClaudeCodeUIClient(
        modelResult: .success("Sonnet 5"),
        effortResult: .success("High")
    )

    let result = await ClaudeCodeSwitchCoordinator(client: client).apply(
        ClaudeCodeSelection(model: .opus5, effort: .high),
        invocation: claudeInvocation
    )

    if case .failure(_, .verificationMismatch(expected: "Opus 5", observed: "Sonnet 5")) = result {
        return
    }
    Issue.record("Expected an exact model observation mismatch")
}

@Test func mismatchedClaudeEffortObservationIsPartial() async {
    let client = FakeClaudeCodeUIClient(
        modelResult: .success("Opus 5"),
        effortResult: .success("Medium")
    )

    let result = await ClaudeCodeSwitchCoordinator(client: client).apply(
        ClaudeCodeSelection(model: .opus5, effort: .high),
        invocation: claudeInvocation
    )

    if case .partialFailure(_, "Opus 5", .verificationMismatch(expected: "High", observed: "Medium")) = result {
        return
    }
    Issue.record("Expected an exact effort observation mismatch")
}

@Test func claudeMenuSelectionRequiresRoleSpecificPersistentState() {
    #expect(ClaudeMenuSelection.isPersistent(
        role: kAXMenuItemRole as String,
        selected: false,
        mark: "✓",
        numericValue: nil
    ))
    #expect(ClaudeMenuSelection.isPersistent(
        role: kAXRadioButtonRole as String,
        selected: false,
        mark: nil,
        numericValue: 1
    ))
    #expect(!ClaudeMenuSelection.isPersistent(
        role: kAXStaticTextRole as String,
        selected: true,
        mark: nil,
        numericValue: 1
    ))
}

@Test func claudeChatComposerTitleParsesOnlyClosedModelAndEffortLabels() {
    #expect(
        ClaudeChatLabels.selection(inComposerTitle: "Model: Sonnet 5 Medium")
            == ClaudeCodeSelection(model: .sonnet5, effort: .medium)
    )
    #expect(
        ClaudeChatLabels.selection(inComposerTitle: "Model: Sonnet 5 Extra")
            == ClaudeCodeSelection(model: .sonnet5, effort: .extraHigh)
    )
    #expect(ClaudeChatLabels.selection(inComposerTitle: "Sonnet 5 Medium") == nil)
    #expect(ClaudeChatLabels.selection(inComposerTitle: "Model: Sonnet 5 Turbo") == nil)
    #expect(ClaudeChatLabels.model(inComposerTitle: "Model: Haiku 4.5 Extended") == .haiku45)
    #expect(ClaudeChatLabels.effort(inComposerTitle: "Model: Haiku 4.5 Extended") == nil)
}

@Test func claudeChatPickerRowsUseExactClosedLabelsAndRejectUpgradeRows() {
    #expect(
        ClaudeChatLabels.model(
            inPickerRow: "Fable 5 Requires usage credits For your toughest challenges"
        ) == .fable5
    )
    #expect(ClaudeChatLabels.model(inPickerRow: "Opus 5 For complex tasks") == .opus5)
    #expect(
        ClaudeChatLabels.model(
            inPickerRow: "Sonnet 5 Most efficient for everyday tasks"
        ) == .sonnet5
    )
    #expect(
        ClaudeChatLabels.model(
            inPickerRow: "Haiku 4.5 Fastest for quick answers"
        ) == .haiku45
    )
    #expect(
        ClaudeChatLabels.model(inPickerRow: "Fable 5 Requires usage credits") == .fable5
    )
    #expect(ClaudeChatLabels.model(inPickerRow: "Opus 5") == .opus5)
    #expect(ClaudeChatLabels.model(inPickerRow: "Sonnet 5") == .sonnet5)
    #expect(ClaudeChatLabels.model(inPickerRow: "Haiku 4.5") == .haiku45)
    #expect(
        ClaudeChatLabels.model(
            inPickerRow: "Opus 5 Pro For complex tasks Upgrade"
        ) == nil
    )
    #expect(ClaudeChatLabels.model(inPickerRow: "Sonnet 5 experimental") == nil)
}

@Test func claudeChatModelRoutingPrefersTheVerifiedRootMenu() {
    #expect(
        ClaudeChatModelRouting.location(
            for: .sonnet5,
            rootModels: [.opus5, .sonnet5, .haiku45],
            hasMoreModels: true
        ) == .root
    )
    #expect(
        ClaudeChatModelRouting.location(
            for: .sonnet5,
            rootModels: [.opus5],
            hasMoreModels: true
        ) == .moreModels
    )
    #expect(
        ClaudeChatModelRouting.location(
            for: .sonnet5,
            rootModels: [.opus5],
            hasMoreModels: false
        ) == nil
    )
}

@Test func claudeChatEffortRowsMapExactChatLabelsToTypedEfforts() {
    #expect(ClaudeChatLabels.effort(inPickerRow: "Low") == .low)
    #expect(ClaudeChatLabels.effort(inPickerRow: "Medium") == .medium)
    #expect(ClaudeChatLabels.effort(inPickerRow: "Medium Default") == .medium)
    #expect(ClaudeChatLabels.effort(inPickerRow: "High Default") == .high)
    #expect(ClaudeChatLabels.effort(inPickerRow: "Extra") == .extraHigh)
    #expect(ClaudeChatLabels.pickerLabel(for: .medium) == "Medium")
    #expect(ClaudeChatLabels.pickerRowLabels(for: .medium) == ["Medium", "Medium Default"])
    #expect(ClaudeChatLabels.pickerLabel(for: .extraHigh) == "Extra")
    #expect(ClaudeChatLabels.pickerRowLabels(for: .ultracode).isEmpty)
    #expect(ClaudeChatLabels.pickerLabel(for: .ultracode) == nil)
    #expect(ClaudeChatLabels.effort(inPickerRow: "Extended") == nil)
}

@Test func claudeChatMaxEffortAcceptsOnlyKnownExactRowVariants() {
    let expectedLabels: Set<String> = [
        "Max",
        "Max 2.5× or more usage",
        "Max 3.5× or more usage",
    ]

    #expect(
        ClaudeChatLabels.selection(inComposerTitle: "Model: Sonnet 5 Max 3.5× or more usage")
            == ClaudeCodeSelection(model: .sonnet5, effort: .max)
    )
    #expect(
        ClaudeChatLabels.selection(inComposerTitle: "Model: Opus 5 Max 2.5× or more usage")
            == ClaudeCodeSelection(model: .opus5, effort: .max)
    )
    #expect(ClaudeChatLabels.effort(inPickerRow: "Max") == .max)
    #expect(ClaudeChatLabels.effort(inPickerRow: "Max 2.5× or more usage") == .max)
    #expect(ClaudeChatLabels.effort(inPickerRow: "Max 3.5× or more usage") == .max)
    #expect(ClaudeChatLabels.pickerRowLabels(for: .max) == expectedLabels)
    #expect(ClaudeChatLabels.selection(inComposerTitle: "Model: Sonnet 5 Max 2× usage") == nil)
    #expect(ClaudeChatLabels.effort(inPickerRow: "Max 2× usage") == nil)
}

@Test func claudeCodePaidModelRowsRemainExactAndClosed() {
    #expect(ClaudeCodeLabels.model(inComposerTitle: "Opus 5") == .opus5)
    #expect(ClaudeCodeLabels.model(inPickerRow: "Fable 5 Requires usage credits") == .fable5)
    #expect(ClaudeCodeLabels.model(inPickerRow: "Sonnet 5") == .sonnet5)
    #expect(ClaudeCodeLabels.model(inPickerRow: "Fable 5") == nil)
    #expect(ClaudeCodeLabels.model(inPickerRow: "Sonnet 5 experimental") == nil)
}

@Test func claudeCodePaidEffortSliderRequiresMatchingValueAndDescription() {
    #expect(ClaudeCodeLabels.effort(inComposerTitle: "Effort: Low") == .low)
    #expect(ClaudeCodeLabels.effort(inComposerTitle: "Effort: Extra") == .extraHigh)
    #expect(ClaudeCodeLabels.effort(inComposerTitle: "Effort: Auto") == nil)
    #expect(ClaudeCodeLabels.sliderSelection(value: 0, description: "Low") == .low)
    #expect(ClaudeCodeLabels.sliderSelection(value: 2, description: "High") == .high)
    #expect(ClaudeCodeLabels.sliderSelection(value: 4, description: "Max") == .max)
    #expect(ClaudeCodeLabels.sliderSelection(value: 4, description: "High") == nil)
    #expect(ClaudeCodeLabels.sliderValue(for: .extraHigh) == 3)
    #expect(ClaudeCodeLabels.sliderValue(for: .automatic) == nil)
    #expect(ClaudeCodeLabels.composerTitle(for: .medium) == "Effort: Medium")
}
