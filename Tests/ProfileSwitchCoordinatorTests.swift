import Testing
@testable import ReasonDeck

actor FakeAccessibilityClient: AccessibilityClient {
    var title: String
    var unavailableModel: String?
    var unavailableEffort: String?
    var modelSelections = 0
    var effortSelections = 0
    init(title: String) { self.title = title }
    func currentPickerTitle() async throws -> String { title }
    func selectModel(_ model: ChatGPTModel) async throws -> String {
        if unavailableModel == model.rawValue { throw SwitchFailure.modelUnavailable(model.rawValue) }
        modelSelections += 1; title = model.rawValue
        return model.rawValue
    }
    func selectEffort(_ effort: ReasoningEffort) async throws -> String {
        if unavailableEffort == effort.rawValue { throw SwitchFailure.effortUnavailable(effort.rawValue) }
        effortSelections += 1; title += " \(effort.rawValue)"
        return title
    }
}

@Test func alreadySelectedProfileIsIdempotent() async {
    let fake = FakeAccessibilityClient(title: "5.6 Sol   Extra High")
    let result = await ProfileSwitchCoordinator(client: fake).apply(ProfileSelection(model: .sol56, effort: .extraHigh))
    if case .success = result {} else { Issue.record("Expected success") }
    #expect(await fake.modelSelections == 0)
    #expect(await fake.effortSelections == 0)
}

@Test func appliesModelBeforeEffortAndVerifies() async {
    let fake = FakeAccessibilityClient(title: "5.6 Terra High")
    let result = await ProfileSwitchCoordinator(client: fake).apply(ProfileSelection(model: .sol56, effort: .extraHigh))
    if case .success(_, let observed, _) = result { #expect(observed == "5.6 Sol Extra High") } else { Issue.record("Expected success") }
}

@Test func unavailableModelFailsWithoutEffortChange() async {
    let fake = FakeAccessibilityClient(title: "5.6 Terra High")
    await fake.setUnavailableModel("5.6 Sol")
    let result = await ProfileSwitchCoordinator(client: fake).apply(ProfileSelection(model: .sol56, effort: .extraHigh))
    if case .failure(_, .modelUnavailable("5.6 Sol")) = result {} else { Issue.record("Expected unavailable model") }
    #expect(await fake.effortSelections == 0)
}

@Test func unavailableEffortReportsPartialFailure() async {
    let fake = FakeAccessibilityClient(title: "5.6 Terra High")
    await fake.setUnavailableEffort("Extra High")
    let result = await ProfileSwitchCoordinator(client: fake).apply(ProfileSelection(model: .sol56, effort: .extraHigh))
    if case .partialFailure(_, let observed, .effortUnavailable("Extra High")) = result { #expect(observed == "5.6 Sol") } else { Issue.record("Expected partial failure") }
}

@Test func deadlineFailureRemainsTyped() async {
    let fake = ThrowingAccessibilityClient(failure: .deadlineExceeded("finding picker"))
    let result = await ProfileSwitchCoordinator(client: fake).apply(ProfileSelection(model: .sol56, effort: .extraHigh))
    if case .failure(_, .deadlineExceeded("finding picker")) = result {} else { Issue.record("Expected typed deadline failure") }
}

@Test func overlappingRequestIsRejectedWhileFirstSwitchIsSuspended() async throws {
    let coordinator = ProfileSwitchCoordinator(client: SlowAccessibilityClient())
    async let first = coordinator.apply(ProfileSelection(model: .sol56, effort: .extraHigh))
    try await Task.sleep(for: .milliseconds(20))
    let overlapping = await coordinator.apply(ProfileSelection(model: .terra56, effort: .high))
    if case .failure(_, .accessibility(let detail)) = overlapping {
        #expect(detail.contains("already running"))
    } else {
        Issue.record("Expected overlapping request failure")
    }
    _ = await first
}

struct ThrowingAccessibilityClient: AccessibilityClient {
    let failure: SwitchFailure
    func currentPickerTitle() async throws -> String { throw failure }
    func selectModel(_ model: ChatGPTModel) async throws -> String { throw failure }
    func selectEffort(_ effort: ReasoningEffort) async throws -> String { throw failure }
}

struct SlowAccessibilityClient: AccessibilityClient {
    func currentPickerTitle() async throws -> String {
        try await Task.sleep(for: .milliseconds(200))
        return "5.6 Sol Extra High"
    }
    func selectModel(_ model: ChatGPTModel) async throws -> String { model.rawValue }
    func selectEffort(_ effort: ReasoningEffort) async throws -> String { effort.rawValue }
}

extension FakeAccessibilityClient {
    func setUnavailableModel(_ value: String) { unavailableModel = value }
    func setUnavailableEffort(_ value: String) { unavailableEffort = value }
}
