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

@Test func claudeComposerTitleParsesOnlyClosedModelAndEffortLabels() {
    #expect(
        ClaudePickerLabels.selection(inComposerTitle: "Model: Sonnet 5 Medium")
            == ClaudeCodeSelection(model: .sonnet5, effort: .medium)
    )
    #expect(
        ClaudePickerLabels.selection(inComposerTitle: "Model: Sonnet 5 Extra")
            == ClaudeCodeSelection(model: .sonnet5, effort: .extraHigh)
    )
    #expect(
        ClaudePickerLabels.selection(inComposerTitle: "Model: Opus 5.5 Medium")
            == ClaudeCodeSelection(model: .opus55, effort: .medium)
    )
    #expect(ClaudePickerLabels.selection(inComposerTitle: "Sonnet 5 Medium") == nil)
    #expect(ClaudePickerLabels.selection(inComposerTitle: "Model: Sonnet 5 Turbo") == nil)
    #expect(ClaudePickerLabels.model(inComposerTitle: "Model: Haiku 4.5 Extended") == .haiku45)
    #expect(ClaudePickerLabels.effort(inComposerTitle: "Model: Haiku 4.5 Extended") == nil)
}

@Test func claudePickerRowsUseExactClosedLabelsAndRejectUpgradeRows() {
    #expect(
        ClaudePickerLabels.model(
            inPickerRow: "Fable 5 Requires usage credits For your toughest challenges"
        ) == .fable5
    )
    #expect(ClaudePickerLabels.model(inPickerRow: "Opus 5 For complex tasks") == .opus5)
    #expect(ClaudePickerLabels.model(inPickerRow: "Opus 5.5 Most capable for ambitious work") == .opus55)
    #expect(
        ClaudePickerLabels.model(
            inPickerRow: "Sonnet 5 Most efficient for everyday tasks"
        ) == .sonnet5
    )
    #expect(
        ClaudePickerLabels.model(
            inPickerRow: "Haiku 4.5 Fastest for quick answers"
        ) == .haiku45
    )
    #expect(
        ClaudePickerLabels.model(inPickerRow: "Fable 5 Requires usage credits") == .fable5
    )
    #expect(ClaudePickerLabels.model(inPickerRow: "Opus 5") == .opus5)
    #expect(ClaudePickerLabels.model(inPickerRow: "Sonnet 5") == .sonnet5)
    #expect(ClaudePickerLabels.model(inPickerRow: "Haiku 4.5") == .haiku45)
    #expect(
        ClaudePickerLabels.model(
            inPickerRow: "Opus 5 Pro For complex tasks Upgrade"
        ) == nil
    )
    #expect(ClaudePickerLabels.model(inPickerRow: "Sonnet 5 experimental") == nil)
    #expect(ClaudePickerLabels.model(inPickerRow: "Opus 5.5 experimental") == nil)
}

@Test func claudeModelRoutingPrefersTheVerifiedRootMenu() {
    #expect(
        ClaudePickerModelRouting.location(
            for: .sonnet5,
            rootModels: [.opus5, .sonnet5, .haiku45],
            hasMoreModels: true
        ) == .root
    )
    #expect(
        ClaudePickerModelRouting.location(
            for: .sonnet5,
            rootModels: [.opus5],
            hasMoreModels: true
        ) == .moreModels
    )
    #expect(
        ClaudePickerModelRouting.location(
            for: .sonnet5,
            rootModels: [.opus5],
            hasMoreModels: false
        ) == nil
    )
}

@Test func claudeEffortRowsMapExactChatLabelsToTypedEfforts() {
    #expect(ClaudePickerLabels.effort(inPickerRow: "Low") == .low)
    #expect(ClaudePickerLabels.effort(inPickerRow: "Medium") == .medium)
    #expect(ClaudePickerLabels.effort(inPickerRow: "Medium Default") == .medium)
    #expect(ClaudePickerLabels.effort(inPickerRow: "High Default") == .high)
    #expect(ClaudePickerLabels.effort(inPickerRow: "Extra") == .extraHigh)
    #expect(ClaudePickerLabels.pickerLabel(for: .medium) == "Medium")
    #expect(ClaudePickerLabels.pickerRowLabels(for: .medium) == ["Medium", "Medium Default", "Medium Recommended"])
    #expect(ClaudePickerLabels.pickerLabel(for: .extraHigh) == "Extra")
    #expect(ClaudePickerLabels.pickerRowLabels(for: .ultracode).isEmpty)
    #expect(ClaudePickerLabels.pickerLabel(for: .ultracode) == nil)
    #expect(ClaudePickerLabels.effort(inPickerRow: "Extended") == nil)
}

@Test func claudeMaxEffortAcceptsOnlyKnownExactRowVariants() {
    let expectedLabels: Set<String> = [
        "Max",
        "Max 2.5× or more usage",
        "Max 3.5× or more usage",
    ]

    #expect(
        ClaudePickerLabels.selection(inComposerTitle: "Model: Sonnet 5 Max 3.5× or more usage")
            == ClaudeCodeSelection(model: .sonnet5, effort: .max)
    )
    #expect(
        ClaudePickerLabels.selection(inComposerTitle: "Model: Opus 5 Max 2.5× or more usage")
            == ClaudeCodeSelection(model: .opus5, effort: .max)
    )
    #expect(ClaudePickerLabels.effort(inPickerRow: "Max") == .max)
    #expect(ClaudePickerLabels.effort(inPickerRow: "Max 2.5× or more usage") == .max)
    #expect(ClaudePickerLabels.effort(inPickerRow: "Max 3.5× or more usage") == .max)
    #expect(ClaudePickerLabels.pickerRowLabels(for: .max) == expectedLabels)
    #expect(ClaudePickerLabels.selection(inComposerTitle: "Model: Sonnet 5 Max 2× usage") == nil)
    #expect(ClaudePickerLabels.effort(inPickerRow: "Max 2× usage") == nil)
}

@Test func claudeWebAccessibilityPreparationIsAMissingSurfaceFallbackOnly() {
    #expect(
        ClaudeAccessibilityPreparationPolicy.shouldPrepare(
            after: .claudeCodeSurfaceNotFound
        )
    )
    #expect(
        !ClaudeAccessibilityPreparationPolicy.shouldPrepare(
            after: .targetChanged("Claude Desktop")
        )
    )
    #expect(
        !ClaudeAccessibilityPreparationPolicy.shouldPrepare(
            after: .accessibility("ambiguous controls")
        )
    )
}

@Test func claudePreparationWaitsOnlyForTheCapturedWindowToRepublish() {
    #expect(
        ClaudeAccessibilityPreparationPolicy.windowState(
            capturedWindowID: 42,
            observedWindowID: nil
        ) == .awaitingRepublish
    )
    #expect(
        ClaudeAccessibilityPreparationPolicy.windowState(
            capturedWindowID: 42,
            observedWindowID: 42
        ) == .ready
    )
    #expect(
        ClaudeAccessibilityPreparationPolicy.windowState(
            capturedWindowID: 42,
            observedWindowID: 99
        ) == .changed
    )
}

@Test func claudeAccessibilityBootstrapRunsOncePerTrustedProcess() {
    #expect(
        ClaudeAccessibilityBootstrapPolicy.shouldPrepare(
            pid: 42,
            lastPreparedPID: nil,
            accessibilityTrusted: true
        )
    )
    #expect(
        !ClaudeAccessibilityBootstrapPolicy.shouldPrepare(
            pid: 42,
            lastPreparedPID: 42,
            accessibilityTrusted: true
        )
    )
    #expect(
        ClaudeAccessibilityBootstrapPolicy.shouldPrepare(
            pid: 99,
            lastPreparedPID: 42,
            accessibilityTrusted: true
        )
    )
    #expect(
        !ClaudeAccessibilityBootstrapPolicy.shouldPrepare(
            pid: 99,
            lastPreparedPID: nil,
            accessibilityTrusted: false
        )
    )
}

@Test func claudeWebAccessibilityPreparationRetriesAfterCooldownNotOncePerProcess() {
    let now = ContinuousClock().now
    let spent = ClaudeAccessibilityPreparationPolicy.Attempt(pid: 42, instant: now)
    #expect(ClaudeAccessibilityPreparationPolicy.shouldAttempt(pid: 42, lastAttempt: nil, now: now))
    #expect(
        !ClaudeAccessibilityPreparationPolicy.shouldAttempt(
            pid: 42,
            lastAttempt: spent,
            now: now.advanced(by: .seconds(29))
        )
    )
    #expect(
        ClaudeAccessibilityPreparationPolicy.shouldAttempt(
            pid: 42,
            lastAttempt: spent,
            now: now.advanced(by: .seconds(30))
        )
    )
    #expect(ClaudeAccessibilityPreparationPolicy.shouldAttempt(pid: 99, lastAttempt: spent, now: now))
}

// Labels live-read from Claude Desktop 6.6395.0's Code composer and its opened
// picker, Effort menu, and More models menu.
@Test func claudeDesktop6ComposerTitleCarriesModelEffortAndOptionalAccessBadge() {
    #expect(
        ClaudePickerLabels.selection(inComposerTitle: "Model: Fable 5.2 Medium")
            == ClaudeCodeSelection(model: .fable52, effort: .medium)
    )
    #expect(
        ClaudePickerLabels.selection(inComposerTitle: "Model: Sonnet 5.5 Medium CVP")
            == ClaudeCodeSelection(model: .sonnet55, effort: .medium)
    )
    #expect(ClaudePickerLabels.selection(inComposerTitle: "Model: Fable 5.1 High")?.model == .fable51)
    // The pre-6 Code forms carried no effort and no longer identify a composer.
    #expect(ClaudePickerLabels.model(inComposerTitle: "Model: Fable 5.2") == nil)
    #expect(ClaudePickerLabels.model(inComposerTitle: "Fable 5.2") == nil)
    #expect(ClaudePickerLabels.model(inComposerTitle: "Effort: Medium") == nil)
    // Badges stay exact: no other suffix, order, or unknown model may pass.
    #expect(ClaudePickerLabels.selection(inComposerTitle: "Model: Sonnet 5.5 Medium CVP: Defense Access") == nil)
    #expect(ClaudePickerLabels.selection(inComposerTitle: "Model: Sonnet 5.5 CVP Medium") == nil)
    #expect(ClaudePickerLabels.selection(inComposerTitle: "Model: Sonnet 5.5 Medium Pro") == nil)
    #expect(ClaudePickerLabels.selection(inComposerTitle: "Model: Fable 5.3 Medium") == nil)
}

@Test func claudeDesktop6PickerRowsAreBareNamesWithOptionalExactAccessBadge() {
    #expect(ClaudePickerLabels.model(inPickerRow: "Fable 5.2") == .fable52)
    #expect(ClaudePickerLabels.model(inPickerRow: "Haiku 5.5") == .haiku55)
    #expect(ClaudePickerLabels.model(inPickerRow: "Opus 5.5 CVP: Defense Access") == .opus55)
    #expect(ClaudePickerLabels.model(inPickerRow: "Sonnet 5.5 CVP: Defense Access") == .sonnet55)
    #expect(ClaudePickerLabels.model(inPickerRow: "Fable 5") == .fable5)
    #expect(ClaudePickerLabels.model(inPickerRow: "Fable 5.1") == .fable51)
    #expect(ClaudePickerLabels.model(inPickerRow: "Opus 4.8 CVP: Defense Access") == .opus48)
    #expect(ClaudePickerLabels.model(inPickerRow: "Opus 4.7 CVP: Defense Access") == .opus47)
    #expect(ClaudePickerLabels.model(inPickerRow: "Opus 4.6") == .opus46)
    #expect(ClaudePickerLabels.model(inPickerRow: "Sonnet 4.6") == .sonnet46)
    #expect(ClaudePickerLabels.model(inPickerRow: "Opus 5.5 CVP") == nil)
    #expect(ClaudePickerLabels.model(inPickerRow: "Opus 5.5 CVP: Other Access") == nil)
    #expect(ClaudePickerLabels.model(inPickerRow: "Fable 5.3") == nil)
    #expect(ClaudePickerLabels.model(inPickerRow: "More models") == nil)
    #expect(ClaudePickerLabels.model(inPickerRow: "Effort Medium") == nil)
}

@Test func claudeDesktop6EffortMenuAcceptsTheRecommendedTagAndLeavesUltracodeUnavailable() {
    #expect(ClaudePickerLabels.effort(inPickerRow: "Medium Recommended") == .medium)
    #expect(ClaudePickerLabels.effort(inPickerRow: "High Recommended") == nil)
    #expect(ClaudePickerLabels.effort(inPickerRow: "Ultracode") == nil)
    #expect(ClaudePickerLabels.effortMenuTitles == [
        "Effort Low", "Effort Medium", "Effort High", "Effort Extra", "Effort Max",
        "Effort Max 2.5× or more usage", "Effort Max 3.5× or more usage",
    ])
}

@Test func claudeCodeTabIsProvenByItsOwnPromptLabelOnly() {
    #expect(ClaudeComposerSurface.promptLabel(codeTabSelected: true) == "Prompt")
    #expect(ClaudeComposerSurface.promptLabel(codeTabSelected: false) == "Write your prompt to Claude")
}

@Test func claudeOpenedPickerMayBeAMenuOrATitledGroupButNothingElse() {
    #expect(ClaudeMenuContainer.isCandidate(role: kAXMenuRole as String))
    #expect(ClaudeMenuContainer.isCandidate(role: kAXGroupRole as String))
    #expect(!ClaudeMenuContainer.isCandidate(role: kAXPopUpButtonRole as String))
    #expect(!ClaudeMenuContainer.isCandidate(role: kAXMenuItemRole as String))
}

// Regression: distinct Chromium elements can share a CFHash, and a hash-keyed
// visited set used to drop the composer's whole subtree. These stand-in
// elements all hash and compare equal, as colliding AX elements do.
private struct CollidingElement: Hashable {
    let name: String
    static func == (lhs: Self, rhs: Self) -> Bool { true }
    func hash(into hasher: inout Hasher) {}
}

@Test func claudeTreeScanVisitsEveryNodeEvenWhenElementsAreIndistinguishable() {
    let tree: [String: [String]] = ["window": ["sidebar", "main"], "main": ["composer"], "composer": ["prompt", "model"]]
    let visits = ClaudeTreeScan.breadthFirst(
        root: CollidingElement(name: "window"),
        maxDepth: 10,
        maxNodes: 100
    ) { element in (tree[element.name] ?? []).map(CollidingElement.init(name:)) }

    #expect(visits.map(\.element.name) == ["window", "sidebar", "main", "composer", "prompt", "model"])
    #expect(visits.map(\.id) == [0, 1, 2, 3, 4, 5])
    #expect(visits.map(\.parentID) == [nil, 0, 0, 2, 3, 3])
    #expect(visits.map(\.depth) == [0, 1, 1, 2, 3, 3])
}

@Test func claudeTreeScanStaysWithinItsDepthAndNodeBounds() {
    let children: (Int) -> [Int] = { [$0 * 2 + 1, $0 * 2 + 2] }
    #expect(ClaudeTreeScan.breadthFirst(root: 0, maxDepth: 2, maxNodes: 100, children: children).map(\.element) == [0, 1, 2, 3, 4, 5, 6])
    #expect(ClaudeTreeScan.breadthFirst(root: 0, maxDepth: 10, maxNodes: 4, children: children).map(\.element) == [0, 1, 2, 3])
}
