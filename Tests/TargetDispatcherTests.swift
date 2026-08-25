import Foundation
import Testing
@testable import ReasonDeck

private actor ChatGPTSpy: ChatGPTApplying {
    private(set) var calls = 0
    func apply(_ selection: ChatGPTSelection, invocation: HotkeyInvocation) async -> ProfileSwitchResult {
        calls += 1
        return .alreadyApplied(profile: .chatGPT(selection), observedTitle: selection.expectedTitle)
    }
}

private actor CursorSpy: CursorApplying {
    private(set) var calls = 0
    func apply(_ selection: CursorSelection, invocation: HotkeyInvocation) async -> ProfileSwitchResult {
        calls += 1
        return .alreadyApplied(profile: .cursor(selection), observedTitle: selection.displayName)
    }
}

private actor ClaudeSpy: ClaudeCodeApplying {
    private(set) var calls = 0
    func apply(_ selection: ClaudeCodeSelection, invocation: HotkeyInvocation) async -> ProfileSwitchResult {
        calls += 1
        return .failure(profile: .claudeCode(selection), failure: .claudeCodeSurfaceNotFound)
    }
}

private actor NavigationSpy: CursorNavigating {
    private(set) var calls = 0
    func apply(_ action: CursorNavigationAction, invocation: HotkeyInvocation) async -> NavigationSwitchResult {
        calls += 1
        return .failure(.cursorUnreadNavigationUnavailable)
    }
}

@Test func dispatcherCallsOnlyTheCapturedTargetsAdapter() async {
    let chatGPT = ChatGPTSpy()
    let cursor = CursorSpy()
    let claude = ClaudeSpy()
    let navigation = NavigationSpy()
    let entry = ShortcutEntry(
        shortcut: nil,
        chatGPT: ChatGPTSelection(model: .sol56, effort: .extraHigh),
        claudeCode: ClaudeCodeSelection(model: .opus5, effort: .high),
        cursor: CursorSelection(model: .grok45, effort: .high)
    )
    let dispatcher = TargetDispatcher(chatGPT: chatGPT, claudeCode: claude, cursor: cursor, cursorNavigation: navigation)
    let invocation = HotkeyInvocation(entryID: entry.id, target: .chatGPT, pid: 42, focusedWindowID: 9)

    let result = await dispatcher.apply(entry: entry, invocation: invocation)
    if case .profile(.alreadyApplied(.chatGPT, _)) = result {} else { Issue.record("Expected ChatGPT result") }
    #expect(await chatGPT.calls == 1)
    #expect(await cursor.calls == 0)
    #expect(await claude.calls == 0)
    #expect(await navigation.calls == 0)
}

@Test func claudeAdapterIsCalledByTheDispatcher() async {
    let chatGPT = ChatGPTSpy()
    let cursor = CursorSpy()
    let claude = ClaudeSpy()
    let navigation = NavigationSpy()
    let entry = ShortcutEntry(
        shortcut: nil,
        chatGPT: nil,
        claudeCode: ClaudeCodeSelection(model: .opus5, effort: .high),
        cursor: nil
    )
    let dispatcher = TargetDispatcher(chatGPT: chatGPT, claudeCode: claude, cursor: cursor, cursorNavigation: navigation)
    let invocation = HotkeyInvocation(entryID: entry.id, target: .claudeCode, pid: 42, focusedWindowID: 9)

    let result = await dispatcher.apply(entry: entry, invocation: invocation)
    if case .profile(.failure(_, .claudeCodeSurfaceNotFound)) = result {} else { Issue.record("Expected Claude adapter result") }
    #expect(await claude.calls == 1)
    #expect(await chatGPT.calls == 0)
    #expect(await cursor.calls == 0)
    #expect(await navigation.calls == 0)
}

@Test func dispatcherRejectsAnEntryDifferentFromTheCapturedInvocation() async {
    let chatGPT = ChatGPTSpy()
    let cursor = CursorSpy()
    let claude = ClaudeSpy()
    let navigation = NavigationSpy()
    let entry = ShortcutEntry(
        shortcut: nil,
        chatGPT: ChatGPTSelection(model: .sol56, effort: .extraHigh),
        claudeCode: nil,
        cursor: nil
    )
    let dispatcher = TargetDispatcher(chatGPT: chatGPT, claudeCode: claude, cursor: cursor, cursorNavigation: navigation)
    let invocation = HotkeyInvocation(entryID: UUID(), target: .chatGPT, pid: 42, focusedWindowID: 9)

    let result = await dispatcher.apply(entry: entry, invocation: invocation)
    if case .profile(.failure(_, .invalidConfiguration)) = result {} else { Issue.record("Expected entry identity failure") }
    #expect(await chatGPT.calls == 0)
}
