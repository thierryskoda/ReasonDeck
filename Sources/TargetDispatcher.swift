import Foundation

/// Concrete platform operations intentionally stay separate.  This type owns
/// routing only; it never opens a picker or interprets a platform selection.
protocol ChatGPTApplying: Sendable {
    func apply(_ selection: ChatGPTSelection, invocation: HotkeyInvocation) async -> ProfileSwitchResult
}

protocol ClaudeCodeApplying: Sendable {
    func apply(_ selection: ClaudeCodeSelection, invocation: HotkeyInvocation) async -> ProfileSwitchResult
}

protocol CursorApplying: Sendable {
    func apply(_ selection: CursorSelection, invocation: HotkeyInvocation) async -> ProfileSwitchResult
}

protocol AntigravityApplying: Sendable {
    func apply(_ selection: AntigravitySelection, invocation: HotkeyInvocation) async -> ProfileSwitchResult
}

actor TargetDispatcher {
    private let chatGPT: any ChatGPTApplying
    private let claudeCode: any ClaudeCodeApplying
    private let cursor: any CursorApplying
    private let antigravity: any AntigravityApplying

    init(
        chatGPT: any ChatGPTApplying = ChatGPTSwitchCoordinator(),
        claudeCode: any ClaudeCodeApplying = ClaudeCodeSwitchCoordinator(),
        cursor: any CursorApplying = CursorSwitchCoordinator(),
        antigravity: any AntigravityApplying = AntigravitySwitchCoordinator()
    ) {
        self.chatGPT = chatGPT
        self.claudeCode = claudeCode
        self.cursor = cursor
        self.antigravity = antigravity
    }

    func apply(
        entry: ShortcutEntry,
        invocation: HotkeyInvocation
    ) async -> ProfileSwitchResult {
        guard entry.id == invocation.entryID else {
            return .failure(
                profile: missingProfile(for: invocation.target),
                failure: .invalidConfiguration
            )
        }
        guard RuntimeCapabilities.supports(entry, target: invocation.target) else {
            return .failure(
                profile: missingProfile(for: invocation.target),
                failure: .capabilityGated
            )
        }

        guard let selection = entry.selection(for: invocation.target), selection.target == invocation.target else {
            return .failure(
                profile: missingProfile(for: invocation.target),
                failure: .invalidConfiguration
            )
        }

        switch selection {
        case .chatGPT(let value):
            return await chatGPT.apply(value, invocation: invocation)
        case .claudeCode(let value):
            return await claudeCode.apply(value, invocation: invocation)
        case .cursor(let value):
            return await cursor.apply(value, invocation: invocation)
        case .antigravity(let value):
            return await antigravity.apply(value, invocation: invocation)
        }
    }

    private func missingProfile(for target: ApplicationTarget) -> TargetSelection {
        switch target {
        case .chatGPT:
            .chatGPT(ChatGPTSelection(model: .sol56, effort: .medium))
        case .claudeCode:
            .claudeCode(ClaudeCodeSelection(model: .sonnet5, effort: .medium))
        case .cursor:
            .cursor(CursorSelection(model: .automatic, effort: .medium))
        case .antigravity:
            .antigravity(AntigravitySelection(model: .gemini31Pro, effort: .low))
        }
    }
}
