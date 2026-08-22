import Foundation
import Testing
@testable import ReasonDeck

private actor FakeChatGPTClient: ChatGPTUIClient {
    let outcome: ChatGPTApplyOutcome
    private(set) var calls = 0

    init(_ outcome: ChatGPTApplyOutcome) { self.outcome = outcome }

    func apply(_ selection: ChatGPTSelection, invocation: HotkeyInvocation) async -> ChatGPTApplyOutcome {
        calls += 1
        return outcome
    }
}

private actor FakeChatGPTPickerTransport: ChatGPTPickerTransport {
    private var observedTitles: [String]
    private let modelTitle: String
    private let effortTitle: String
    private(set) var observationCalls = 0
    private(set) var modelCalls = 0
    private(set) var effortCalls = 0
    private(set) var focusRestorationCalls = 0

    init(observedTitles: [String], modelTitle: String, effortTitle: String) {
        self.observedTitles = observedTitles
        self.modelTitle = modelTitle
        self.effortTitle = effortTitle
    }

    func observeSelectionTitle(invocation: HotkeyInvocation) throws -> String {
        observationCalls += 1
        guard !observedTitles.isEmpty else {
            throw SwitchFailure.accessibility("Unexpected duplicate observation")
        }
        return observedTitles.removeFirst()
    }

    func selectModel(_ model: ChatGPTModel, invocation: HotkeyInvocation) -> String {
        modelCalls += 1
        return modelTitle
    }

    func selectEffort(_ effort: ChatGPTReasoningEffort, invocation: HotkeyInvocation) -> String {
        effortCalls += 1
        return effortTitle
    }

    func restoreComposerFocus(invocation: HotkeyInvocation) -> Bool {
        focusRestorationCalls += 1
        return true
    }
}

private let chatGPTInvocation = HotkeyInvocation(
    entryID: UUID(), target: .chatGPT, pid: 42, focusedWindowID: 99
)

@Test func alreadySelectedProfileIsIdempotent() async {
    let client = FakeChatGPTClient(.alreadyApplied(observedTitle: "5.6 Sol Extra High"))
    let result = await ChatGPTSwitchCoordinator(client: client).apply(
        ChatGPTSelection(model: .sol56, effort: .extraHigh), invocation: chatGPTInvocation
    )
    if case .alreadyApplied(_, "5.6 Sol Extra High") = result {} else { Issue.record("Expected already applied") }
    #expect(await client.calls == 1)
}

@Test func verifiedChatGPTTransactionReportsSuccess() async {
    let client = FakeChatGPTClient(.applied(model: .sol56, effort: .extraHigh, observedTitle: "5.6 Sol Extra High"))
    let result = await ChatGPTSwitchCoordinator(client: client).apply(
        ChatGPTSelection(model: .sol56, effort: .extraHigh), invocation: chatGPTInvocation
    )
    if case .success(_, "5.6 Sol Extra High", _) = result {} else { Issue.record("Expected success") }
}

@Test func chatGPTTransactionReusesTheModelSelectionVerification() async {
    let transport = FakeChatGPTPickerTransport(
        observedTitles: ["5.6 Terra High"],
        modelTitle: "5.6 Sol High",
        effortTitle: "5.6 Sol High"
    )
    let selection = ChatGPTSelection(model: .sol56, effort: .high)

    let outcome = await ChatGPTTransaction.apply(
        selection,
        invocation: chatGPTInvocation,
        using: transport
    )

    #expect(outcome == .applied(model: .sol56, effort: .high, observedTitle: "5.6 Sol High"))
    #expect(await transport.observationCalls == 1)
    #expect(await transport.modelCalls == 1)
    #expect(await transport.effortCalls == 0)
    #expect(await transport.focusRestorationCalls == 1)
}

@Test func chatGPTTransactionAttemptsFocusRestorationAfterPickerFailure() async {
    let transport = FakeChatGPTPickerTransport(
        observedTitles: [],
        modelTitle: "5.6 Sol High",
        effortTitle: "5.6 Sol High"
    )

    let outcome = await ChatGPTTransaction.apply(
        ChatGPTSelection(model: .sol56, effort: .high),
        invocation: chatGPTInvocation,
        using: transport
    )

    guard case .failure(.accessibility("Unexpected duplicate observation")) = outcome else {
        Issue.record("Expected the picker failure to remain unchanged")
        return
    }
    #expect(await transport.focusRestorationCalls == 1)
}

@Test func modelChangeWithEffortFailureIsPartial() async {
    let client = FakeChatGPTClient(.partial(model: .sol56, observedTitle: "5.6 Sol High", failure: .effortUnavailable("Extra High")))
    let result = await ChatGPTSwitchCoordinator(client: client).apply(
        ChatGPTSelection(model: .sol56, effort: .extraHigh), invocation: chatGPTInvocation
    )
    if case .partialFailure(_, "5.6 Sol High", .effortUnavailable("Extra High")) = result {} else { Issue.record("Expected partial failure") }
}

@Test func typedChatGPTFailureIsPreserved() async {
    let client = FakeChatGPTClient(.failure(.pickerNotFound))
    let result = await ChatGPTSwitchCoordinator(client: client).apply(
        ChatGPTSelection(model: .sol56, effort: .extraHigh), invocation: chatGPTInvocation
    )
    if case .failure(_, .pickerNotFound) = result {} else { Issue.record("Expected typed picker failure") }
}
