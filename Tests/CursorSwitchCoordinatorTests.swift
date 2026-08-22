import Foundation
import Testing
@testable import ReasonDeck

private actor FakeCursorUIClient: CursorUIClient {
    let outcome: CursorApplyOutcome
    private(set) var calls = 0

    init(outcome: CursorApplyOutcome) {
        self.outcome = outcome
    }

    func apply(_ selection: CursorSelection, invocation: HotkeyInvocation) async -> CursorApplyOutcome {
        _ = (selection, invocation)
        calls += 1
        return outcome
    }
}

private let cursorInvocation = HotkeyInvocation(
    entryID: UUID(),
    target: .cursor,
    pid: 42,
    focusedWindowID: 7
)

@Test func effortFailurePreservesVerifiedCursorModelAsPartialSuccess() async {
    let client = FakeCursorUIClient(outcome: .partial(
        model: .grok45,
        failure: .cursorMenuItemMissing(CursorEffort.high.rawValue)
    ))
    let coordinator = CursorSwitchCoordinator(client: client)

    let result = await coordinator.apply(
        CursorSelection(model: .grok45, effort: .high),
        invocation: cursorInvocation
    )

    guard case .partialFailure(_, let observed, let failure) = result else {
        Issue.record("Expected a partial Cursor failure after model success")
        return
    }
    #expect(observed == CursorModel.grok45.rawValue)
    #expect(failure == .cursorMenuItemMissing(CursorEffort.high.rawValue))
    #expect(await client.calls == 1)
}

@Test func verifiedCursorModelAndEffortProduceObservedSuccess() async {
    let client = FakeCursorUIClient(outcome: .applied(model: .composer25, effort: .medium))
    let result = await CursorSwitchCoordinator(client: client).apply(
        CursorSelection(model: .composer25, effort: .medium),
        invocation: cursorInvocation
    )
    guard case .success(_, let title, _) = result else {
        Issue.record("Expected a verified Cursor success")
        return
    }
    #expect(title == "Composer 2.5 / Medium")
}

@Test func cursorModelUnavailableIsDistinctFromControlUnavailable() {
    #expect(SwitchFailure.cursorMenuItemMissing("Grok 4.5").message != SwitchFailure.cursorModelControlUnavailable.message)
    #expect(SwitchFailure.cursorPickerDidNotOpen.message != SwitchFailure.cursorModelControlUnavailable.message)
}

@Test func cursorAlreadyAppliedReportsDistinctOutcome() async {
    let client = FakeCursorUIClient(outcome: .alreadyApplied(model: .grok45, effort: .high))
    let result = await CursorSwitchCoordinator(client: client).apply(
        CursorSelection(model: .grok45, effort: .high),
        invocation: cursorInvocation
    )
    guard case .alreadyApplied(_, let title) = result else {
        Issue.record("Expected an already-applied Cursor outcome")
        return
    }
    #expect(title == "Grok 4.5 / High")
}

@Test func cursorRecognizesShortenedClaudeChipTitles() {
    #expect(CursorModelLabels.modelAlias(inChipTitle: "Opus 5 High") == "Opus 5")
    #expect(CursorModelLabels.chipShowsModel("Opus 5 High", model: CursorModel.claudeOpus5.rawValue))
    #expect(CursorModelLabels.chipShowsEffort("Opus 5 High", effort: CursorEffort.high.rawValue))
    #expect(CursorModelLabels.chipShowsModel("Fable 5 Low", model: CursorModel.claudeFable5.rawValue))
    #expect(CursorModelLabels.chipShowsModel("Sonnet 5 Medium", model: CursorModel.claudeSonnet5.rawValue))
    #expect(CursorModelLabels.chipShowsModel("Cursor Grok 4.5 High", model: CursorModel.grok45.rawValue))
}

@Test func cursorChipTitleNeverConfusesAModelWithItsLongerVariant() {
    #expect(CursorModelLabels.modelAlias(inChipTitle: "Composer 2.5 Fast High") == "Composer 2.5 Fast")
    #expect(!CursorModelLabels.chipShowsModel("Composer 2.5 Fast High", model: CursorModel.composer25.rawValue))
    #expect(CursorModelLabels.chipShowsModel("Composer 2.5 High", model: CursorModel.composer25.rawValue))
}

@Test func cursorChipTitleRejectsUnknownAndTrailingText() {
    #expect(CursorModelLabels.modelAlias(inChipTitle: "Continue with ChatGPT") == nil)
    #expect(CursorModelLabels.modelAlias(inChipTitle: "Opus 5 Turbo") == nil)
    #expect(!CursorModelLabels.chipShowsEffort("Chat actions High", effort: CursorEffort.high.rawValue))
}

@Test func cursorUnknownModelChipCanStillExposeAnExactEffort() {
    #expect(CursorModelLabels.effort(inChipTitle: "Cursor Grok 4.6 High") == .high)
    #expect(CursorModelLabels.effort(inChipTitle: "High") == .high)
    #expect(CursorModelLabels.effort(inChipTitle: "Something Highlighted") == nil)
}

@Test func cursorRecognizesTheExactModelOnlyAutoChipAndMenu() {
    #expect(CursorModelLabels.modelOnlyChip(in: ["Auto"]) == .automatic)
    #expect(CursorModelLabels.modelOnlyChip(in: ["Automatic"]) == nil)
    #expect(CursorModelLabels.parameterMenuLabels(for: .automatic).contains("auto"))
}

@Test func cursorRecognizesCurrentGrok46LabelsExactly() {
    #expect(CursorModelLabels.model(inTitle: "Cursor Grok 4.6 High") == CursorModel.grok46.rawValue)
    #expect(CursorModelLabels.chipShows("Cursor Grok 4.6 High", model: "Grok 4.6", effort: "High"))
    #expect(!CursorModelLabels.chipShowsModel("Cursor Grok 4.6 High", model: "Grok 4.5"))
}

@Test func cursorStructuredPickerRowsResolveToClosedModels() {
    #expect(CursorModelLabels.model(inTitle: "Cursor Grok 4.5 High") == CursorModel.grok45.rawValue)
    #expect(CursorModelLabels.model(inTitle: "Opus 5 High") == CursorModel.claudeOpus5.rawValue)
    #expect(CursorModelLabels.model(inTitle: "GPT-5.6 Sol Medium") == CursorModel.gpt56Sol.rawValue)
    #expect(CursorModelLabels.model(inTitle: "Cursor Grok 4.6 Medium POPULAR") == CursorModel.grok46.rawValue)
    #expect(CursorModelLabels.model(inTitle: "Opus 5 Turbo") == nil)
}

@Test func cursorRecognizesOnlyClosedModelTriggerAndEffortRowLabels() {
    #expect(CursorModelLabels.isModelTriggerLabel("Model", for: .grok46))
    #expect(CursorModelLabels.isModelTriggerLabel("Model Cursor Grok 4.6", for: .grok46))
    #expect(!CursorModelLabels.isModelTriggerLabel("Model Cursor Grok 4.5", for: .grok46))
    #expect(!CursorModelLabels.isModelTriggerLabel("Model Unknown", for: .grok46))
    #expect(CursorModelLabels.effort(inParameterLabel: "Effort Medium") == .medium)
    #expect(CursorModelLabels.effort(inParameterLabel: "Medium") == .medium)
    #expect(CursorModelLabels.effort(inParameterLabel: "Effort Extreme") == nil)
}

@Test func cursorPickerRequiresMultipleDistinctKnownModels() {
    #expect(CursorModelLabels.distinctModels(in: ["GPT-5.6 Sol Medium"]).count == 1)
    #expect(CursorModelLabels.distinctModels(in: [
        "GPT-5.6 Sol Medium",
        "Cursor Grok 4.5 High",
        "Continue with ChatGPT",
    ]) == Set([CursorModel.gpt56Sol.rawValue, CursorModel.grok45.rawValue]))
}

@Test func cursorCombinedChipTitleMatchesModelAndEffortTogether() {
    #expect(CursorModelLabels.chipShows("GPT-5.6 Sol High", model: "GPT-5.6 Sol", effort: "High"))
    #expect(CursorModelLabels.chipShows("Cursor Grok 4.5 High", model: "Grok 4.5", effort: "High"))
    #expect(!CursorModelLabels.chipShows("GPT-5.6 Sol Medium", model: "GPT-5.6 Sol", effort: "High"))
    #expect(!CursorModelLabels.chipShows("Opus 5 High", model: "GPT-5.6 Sol", effort: "High"))
}

@Test func cursorModelFailureDoesNotPretendEffortWasApplied() async {
    let client = FakeCursorUIClient(outcome: .failure(.cursorModelControlUnavailable))
    let result = await CursorSwitchCoordinator(client: client).apply(
        CursorSelection(model: .claudeOpus5, effort: .high),
        invocation: cursorInvocation
    )
    guard case .failure(_, let failure) = result else {
        Issue.record("Expected a Cursor model failure")
        return
    }
    #expect(failure == .cursorModelControlUnavailable)
}

@Test func CursorCoordinatorMapsOneLogicalTransactionFailure() async {
    let client = FakeCursorUIClient(outcome: .failure(.cursorPickerDidNotOpen))
    let result = await CursorSwitchCoordinator(client: client).apply(
        CursorSelection(model: .composer25, effort: .high),
        invocation: cursorInvocation
    )
    guard case .failure(_, let failure) = result else {
        Issue.record("Expected a Cursor transaction failure")
        return
    }
    #expect(failure == .cursorPickerDidNotOpen)
    #expect(await client.calls == 1)
}

private func cursorNode(
    _ id: Int,
    parent: Int? = nil,
    semantic: CursorAXSemantic = .container,
    actionable: Bool = false,
    showsMenu: Bool = false,
    visible: Bool = true,
    frame: CGRect? = nil
) -> CursorAXNode {
    CursorAXNode(
        id: id,
        parentID: parent,
        semantic: semantic,
        actionable: actionable,
        showsMenu: showsMenu,
        visible: visible,
        frame: frame
    )
}

@Test func cursorPlannerFindsOnlyComposerRelativeChip() throws {
    let snapshot = CursorAXSnapshot(nodes: [
        cursorNode(1),
        cursorNode(2, parent: 1),
        cursorNode(3, parent: 2, semantic: .composerInput),
        cursorNode(4, parent: 2, semantic: .modelChip(model: .gpt56Sol, effort: .high), actionable: true),
        cursorNode(8, parent: 2, semantic: .composerAccessory, actionable: true),
        cursorNode(5, parent: 1, semantic: .modelChip(model: .grok45, effort: .high), actionable: true),
    ])

    let composer = try CursorSurfacePlanner.composer(in: snapshot)
    #expect(composer.chipID == 4)
    #expect(composer.model == .gpt56Sol)
    #expect(composer.effort == .high)
}

@Test func cursorPlannerUsesGeometryForTheVerifiedComposerChip() throws {
    let snapshot = CursorAXSnapshot(nodes: [
        cursorNode(1),
        cursorNode(2, parent: 1),
        cursorNode(3, parent: 2, semantic: .composerInput),
        cursorNode(
            4,
            parent: 2,
            semantic: .modelChip(model: .gpt56Sol, effort: .high),
            actionable: true,
            showsMenu: true,
            frame: CGRect(x: 900, y: 700, width: 84, height: 24)
        ),
        cursorNode(5, parent: 2, semantic: .composerAccessory, actionable: true),
    ])
    let composer = try CursorSurfacePlanner.composer(in: snapshot)

    #expect(
        try CursorSurfacePlanner.composerChipTarget(
            in: snapshot,
            context: composer
        ) == .clickControl(4)
    )
}

@Test func cursorPlannerAcceptsComposerRelativeEffortOnlyChipWithoutInventingModel() throws {
    let snapshot = CursorAXSnapshot(nodes: [
        cursorNode(1),
        cursorNode(2, parent: 1),
        cursorNode(3, parent: 2, semantic: .composerInput),
        cursorNode(4, parent: 2, semantic: .modelChip(model: nil, effort: .high), actionable: true),
        cursorNode(8, parent: 2, semantic: .composerAccessory, actionable: true),
    ])

    let composer = try CursorSurfacePlanner.composer(in: snapshot)
    #expect(composer.chipID == 4)
    #expect(composer.model == nil)
    #expect(composer.effort == .high)
}

@Test func cursorPlannerAcceptsComposerRelativeModelOnlyAutoChipWithoutInventingEffort() throws {
    let snapshot = CursorAXSnapshot(nodes: [
        cursorNode(1),
        cursorNode(2, parent: 1),
        cursorNode(3, parent: 2, semantic: .composerInput),
        cursorNode(4, parent: 2, semantic: .modelChip(model: .automatic, effort: nil), actionable: true),
        cursorNode(8, parent: 2, semantic: .composerAccessory, actionable: true),
    ])

    let composer = try CursorSurfacePlanner.composer(in: snapshot)
    #expect(composer.model == .automatic)
    #expect(composer.effort == nil)
}

@Test func cursorPlannerRejectsAmbiguousComposerSurfaces() {
    let snapshot = CursorAXSnapshot(nodes: [
        cursorNode(1),
        cursorNode(2, parent: 1),
        cursorNode(3, parent: 2, semantic: .composerInput),
        cursorNode(4, parent: 2, semantic: .modelChip(model: .gpt56Sol, effort: .high), actionable: true),
        cursorNode(8, parent: 2, semantic: .composerAccessory, actionable: true),
        cursorNode(5, parent: 1),
        cursorNode(6, parent: 5, semantic: .composerInput),
        cursorNode(7, parent: 5, semantic: .modelChip(model: .grok45, effort: .medium), actionable: true),
        cursorNode(9, parent: 5, semantic: .composerAccessory, actionable: true),
    ])

    #expect(throws: CursorSurfaceFailure.ambiguousComposer) {
        try CursorSurfacePlanner.composer(in: snapshot)
    }
}

@Test func cursorPlannerRejectsInputAndChipWithoutExactComposerAccessory() {
    let snapshot = CursorAXSnapshot(nodes: [
        cursorNode(1),
        cursorNode(2, parent: 1),
        cursorNode(3, parent: 2, semantic: .composerInput),
        cursorNode(4, parent: 2, semantic: .modelChip(model: .gpt56Sol, effort: .high), actionable: true),
    ])

    #expect(throws: CursorSurfaceFailure.composerUnavailable) {
        try CursorSurfacePlanner.composer(in: snapshot)
    }
}

@Test func cursorPlannerScopesRowsToVerifiedTwoStageMenus() throws {
    let snapshot = CursorAXSnapshot(nodes: [
        cursorNode(1),
        cursorNode(10, parent: 1, semantic: .parametersMenu(model: .gpt56Sol)),
        cursorNode(11, parent: 10, semantic: .effortItem(.high), actionable: true),
        cursorNode(12, parent: 10, semantic: .modelTrigger, actionable: true),
        cursorNode(20, parent: 1, semantic: .modelSelectionMenu),
        cursorNode(21, parent: 20, semantic: .modelItem(.automatic), actionable: true),
        cursorNode(22, parent: 20, semantic: .modelItem(.grok45), actionable: true),
        cursorNode(23, parent: 20, semantic: .modelItem(.gpt56Sol), actionable: true),
        cursorNode(30, parent: 1, semantic: .effortItem(.high), actionable: true),
    ])

    #expect(try CursorSurfacePlanner.parametersMenu(in: snapshot, for: .gpt56Sol).id == 10)
    #expect(try CursorSurfacePlanner.modelTrigger(in: snapshot, menuID: 10) == .press(12))
    #expect(try CursorSurfacePlanner.effortItem(in: snapshot, menuID: 10, effort: .high) == .press(11))
    let modelMenu = try CursorSurfacePlanner.modelMenu(in: snapshot)
    #expect(modelMenu == 20)
    #expect(try CursorSurfacePlanner.modelItem(in: snapshot, menuID: modelMenu, model: .grok45) == .press(22))
}

@Test func cursorPlannerRejectsDuplicateModelTriggersInsideParametersMenu() throws {
    let snapshot = CursorAXSnapshot(nodes: [
        cursorNode(1),
        cursorNode(10, parent: 1, semantic: .parametersMenu(model: .gpt56Sol)),
        cursorNode(11, parent: 10, semantic: .modelTrigger, actionable: true),
        cursorNode(12, parent: 10, semantic: .modelTrigger, actionable: true),
    ])

    #expect(throws: CursorSurfaceFailure.ambiguousItem) {
        try CursorSurfacePlanner.modelTrigger(in: snapshot, menuID: 10)
    }
}

@Test func cursorPlannerRejectsDuplicateExactRowsInsideVerifiedMenu() throws {
    let snapshot = CursorAXSnapshot(nodes: [
        cursorNode(1),
        cursorNode(20, parent: 1, semantic: .modelSelectionMenu),
        cursorNode(21, parent: 20, semantic: .modelItem(.automatic), actionable: true),
        cursorNode(22, parent: 20, semantic: .modelItem(.grok45), actionable: true),
        cursorNode(23, parent: 20, semantic: .modelItem(.grok45), actionable: true),
    ])
    let menu = try CursorSurfacePlanner.modelMenu(in: snapshot)

    #expect(throws: CursorSurfaceFailure.ambiguousItem) {
        try CursorSurfacePlanner.modelItem(in: snapshot, menuID: menu, model: .grok45)
    }
}

@Test func cursorPlannerLiftsExactMenuLabelToNearestActionableRow() throws {
    let snapshot = CursorAXSnapshot(nodes: [
        cursorNode(1),
        cursorNode(20, parent: 1, semantic: .modelSelectionMenu),
        cursorNode(21, parent: 20, actionable: true),
        cursorNode(22, parent: 21, semantic: .modelItem(.automatic)),
        cursorNode(23, parent: 20, actionable: true),
        cursorNode(24, parent: 23, semantic: .modelItem(.grok46)),
    ])

    let menu = try CursorSurfacePlanner.modelMenu(in: snapshot)
    #expect(try CursorSurfacePlanner.modelItem(in: snapshot, menuID: menu, model: .grok46) == .press(23))
}

@Test func cursorPlannerUsesFramedExactLabelWhenElectronExposesNoPressAction() throws {
    let snapshot = CursorAXSnapshot(nodes: [
        cursorNode(1),
        cursorNode(10, parent: 1, semantic: .parametersMenu(model: .gpt56Sol)),
        cursorNode(
            11,
            parent: 10,
            semantic: .modelTrigger,
            frame: CGRect(x: 400, y: 500, width: 240, height: 28)
        ),
        cursorNode(
            12,
            parent: 11,
            semantic: .modelTrigger,
            frame: CGRect(x: 420, y: 505, width: 50, height: 18)
        ),
    ])

    #expect(
        try CursorSurfacePlanner.modelTrigger(in: snapshot, menuID: 10)
            == .click(rowID: 12, menuID: 10)
    )
}

@Test func cursorPlannerClicksAFramedExactRowWhenElectronPressIsANoOp() throws {
    let snapshot = CursorAXSnapshot(nodes: [
        cursorNode(
            10,
            semantic: .parametersMenu(model: .grok46),
            frame: CGRect(x: 979, y: 944, width: 230, height: 96)
        ),
        cursorNode(
            11,
            parent: 10,
            semantic: .modelTrigger,
            actionable: true,
            showsMenu: true,
            frame: CGRect(x: 983, y: 1010, width: 222, height: 26)
        ),
    ])

    #expect(
        try CursorSurfacePlanner.modelTrigger(in: snapshot, menuID: 10)
            == .click(rowID: 11, menuID: 10)
    )
}

@Test func cursorPlannerPrefersDirectShowMenuOnExactModelTrigger() throws {
    let snapshot = CursorAXSnapshot(nodes: [
        cursorNode(1),
        cursorNode(10, parent: 1, semantic: .parametersMenu(model: .gpt56Sol)),
        cursorNode(11, parent: 10, semantic: .modelTrigger, showsMenu: true),
        cursorNode(12, parent: 11, semantic: .modelTrigger, showsMenu: true),
    ])

    #expect(try CursorSurfacePlanner.modelTrigger(in: snapshot, menuID: 10) == .showMenu(11))
}

@Test func cursorPlannerUsesExactFramedLabelInsteadOfNoOpActionableSibling() throws {
    let snapshot = CursorAXSnapshot(nodes: [
        cursorNode(1),
        cursorNode(
            10,
            parent: 1,
            semantic: .parametersMenu(model: .gpt56Sol),
            frame: CGRect(x: 350, y: 450, width: 300, height: 300)
        ),
        cursorNode(
            11,
            parent: 10,
            actionable: true,
            frame: CGRect(x: 360, y: 500, width: 280, height: 28)
        ),
        cursorNode(
            12,
            parent: 10,
            semantic: .modelTrigger,
            frame: CGRect(x: 390, y: 506, width: 50, height: 16)
        ),
    ])

    #expect(
        try CursorSurfacePlanner.modelTrigger(in: snapshot, menuID: 10)
            == .click(rowID: 12, menuID: 10)
    )
}

@Test func cursorPlannerResolvesUniqueActionAcrossBoundedStructuralRow() throws {
    let snapshot = CursorAXSnapshot(nodes: [
        cursorNode(1),
        cursorNode(10, parent: 1, semantic: .parametersMenu(model: .gpt56Sol)),
        cursorNode(11, parent: 10),
        cursorNode(12, parent: 11, semantic: .modelTrigger, showsMenu: true),
        cursorNode(13, parent: 12, semantic: .modelTrigger, showsMenu: true),
        cursorNode(14, parent: 11, actionable: true),
    ])

    #expect(try CursorSurfacePlanner.modelTrigger(in: snapshot, menuID: 10) == .press(14))
}

@Test func cursorPlannerIgnoresHiddenPickerRoots() throws {
    let snapshot = CursorAXSnapshot(nodes: [
        cursorNode(1),
        cursorNode(10, parent: 1, semantic: .parametersMenu(model: .gpt56Sol), visible: false),
        cursorNode(20, parent: 1, semantic: .parametersMenu(model: .gpt56Sol)),
    ])

    #expect(try CursorSurfacePlanner.parametersMenu(in: snapshot, for: .gpt56Sol).id == 20)
}

@Test func cursorModelTransitionWaitsForTwoStableRequestedModelObservations() {
    var latch = CursorModelTransitionLatch(selectedModel: .grok46)

    let oldModel = latch.observe(.gpt56Sol)
    let firstMatch = latch.observe(.grok46)
    let secondMatch = latch.observe(.grok46)
    #expect(!oldModel)
    #expect(!firstMatch)
    #expect(secondMatch)
}

@Test func cursorModelTransitionAllowsOnlyABoundedStableUnexposedFallback() {
    var latch = CursorModelTransitionLatch(selectedModel: .grok46)

    for _ in 0..<5 {
        let ready = latch.observe(nil)
        #expect(!ready)
    }
    let stableUnexposed = latch.observe(nil)
    let oldModel = latch.observe(.gpt56Sol)
    #expect(stableUnexposed)
    #expect(!oldModel)
}

@Test func cursorTraversalIdentityKeepsDistinctElementsWhenHashesCollide() {
    var identities = CursorAXIdentityRegistry<Int>(
        hash: { _ in 7 },
        equal: ==
    )

    let first = identities.insert(11)
    let colliding = identities.insert(22)
    let duplicate = identities.insert(11)

    #expect(first.isNew)
    #expect(colliding.isNew)
    #expect(first.id != colliding.id)
    #expect(!duplicate.isNew)
    #expect(duplicate.id == first.id)
}
