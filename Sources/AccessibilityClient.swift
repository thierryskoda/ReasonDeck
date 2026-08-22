import Foundation

enum ChatGPTApplyOutcome: Equatable, Sendable {
    case applied(model: ChatGPTModel, effort: ChatGPTReasoningEffort, observedTitle: String)
    case alreadyApplied(observedTitle: String)
    case partial(model: ChatGPTModel, observedTitle: String, failure: SwitchFailure)
    case failure(SwitchFailure)
}

/// ChatGPT has one atomic operation.  The caller cannot retain an AX element,
/// cache a picker, or interleave the model and effort phases.
protocol ChatGPTUIClient: Sendable {
    func apply(_ selection: ChatGPTSelection, invocation: HotkeyInvocation) async -> ChatGPTApplyOutcome
}

/// The live Accessibility adapter owns these operations. Keeping transaction
/// orchestration separate makes the number and order of visible picker
/// interactions deterministic and testable.
protocol ChatGPTPickerTransport: Sendable {
    func observeSelectionTitle(invocation: HotkeyInvocation) async throws -> String
    func selectModel(_ model: ChatGPTModel, invocation: HotkeyInvocation) async throws -> String
    func selectEffort(_ effort: ChatGPTReasoningEffort, invocation: HotkeyInvocation) async throws -> String
    func restoreComposerFocus(invocation: HotkeyInvocation) async -> Bool
}

enum ChatGPTTransaction {
    static func apply(
        _ selection: ChatGPTSelection,
        invocation: HotkeyInvocation,
        using transport: any ChatGPTPickerTransport
    ) async -> ChatGPTApplyOutcome {
        let outcome = await applySelection(selection, invocation: invocation, using: transport)
        _ = await transport.restoreComposerFocus(invocation: invocation)
        return outcome
    }

    private static func applySelection(
        _ selection: ChatGPTSelection,
        invocation: HotkeyInvocation,
        using transport: any ChatGPTPickerTransport
    ) async -> ChatGPTApplyOutcome {
        do {
            let initial = try await transport.observeSelectionTitle(invocation: invocation)
            if selection.matches(title: initial) { return .alreadyApplied(observedTitle: initial) }

            let afterModel: String
            if !selection.title(initial, containsModel: selection.model) {
                afterModel = try await transport.selectModel(selection.model, invocation: invocation)
                guard selection.title(afterModel, containsModel: selection.model) else {
                    return .failure(.verificationMismatch(expected: selection.model.rawValue, observed: afterModel))
                }
            } else {
                afterModel = initial
            }

            guard selection.title(afterModel, containsModel: selection.model) else {
                return .failure(.verificationMismatch(expected: selection.model.rawValue, observed: afterModel))
            }
            if selection.title(afterModel, containsEffort: selection.effort) {
                return selection.matches(title: afterModel)
                    ? .applied(model: selection.model, effort: selection.effort, observedTitle: afterModel)
                    : .failure(.verificationMismatch(expected: selection.expectedTitle, observed: afterModel))
            }

            do {
                let final = try await transport.selectEffort(selection.effort, invocation: invocation)
                guard selection.matches(title: final) else {
                    return .partial(
                        model: selection.model,
                        observedTitle: afterModel,
                        failure: .verificationMismatch(expected: selection.expectedTitle, observed: final)
                    )
                }
                return .applied(model: selection.model, effort: selection.effort, observedTitle: final)
            } catch let failure as SwitchFailure {
                return .partial(model: selection.model, observedTitle: afterModel, failure: failure)
            }
        } catch let failure as SwitchFailure {
            return .failure(failure)
        } catch {
            return .failure(.accessibility(String(describing: error)))
        }
    }
}

actor ChatGPTSwitchCoordinator: ChatGPTApplying {
    private let client: any ChatGPTUIClient

    init(client: any ChatGPTUIClient = SystemAccessibilityClient()) {
        self.client = client
    }

    func apply(_ selection: ChatGPTSelection, invocation: HotkeyInvocation) async -> ProfileSwitchResult {
        let clock = ContinuousClock()
        let start = clock.now
        switch await client.apply(selection, invocation: invocation) {
        case .applied(_, _, let title):
            return .success(profile: .chatGPT(selection), observedTitle: title, elapsed: start.duration(to: clock.now))
        case .alreadyApplied(let title):
            return .alreadyApplied(profile: .chatGPT(selection), observedTitle: title)
        case .partial(_, let title, let failure):
            return .partialFailure(profile: .chatGPT(selection), observedTitle: title, failure: failure)
        case .failure(let failure):
            return .failure(profile: .chatGPT(selection), failure: failure)
        }
    }
}
