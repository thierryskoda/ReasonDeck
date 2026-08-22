import Foundation
import Testing
@testable import ReasonDeck

@Test func nextUnreadIndexWrapsAfterCurrentSelection() {
    let rows = [
        CursorAgentSessionRow(title: "A", isSelected: true, isUnread: true, isInProgress: false),
        CursorAgentSessionRow(title: "B", isSelected: false, isUnread: true, isInProgress: false),
        CursorAgentSessionRow(title: "C", isSelected: false, isUnread: false, isInProgress: false)
    ]
    #expect(CursorUnreadSessionPlanner.nextUnreadIndex(in: rows) == 1)
}

@Test func nextUnreadIndexWrapsToFirstUnread() {
    let rows = [
        CursorAgentSessionRow(title: "A", isSelected: false, isUnread: true, isInProgress: false),
        CursorAgentSessionRow(title: "B", isSelected: true, isUnread: false, isInProgress: false),
        CursorAgentSessionRow(title: "C", isSelected: false, isUnread: true, isInProgress: false)
    ]
    #expect(CursorUnreadSessionPlanner.nextUnreadIndex(in: rows) == 2)
    // After last unread, wrap to a different unread.
    let onLast = [
        CursorAgentSessionRow(title: "A", isSelected: false, isUnread: true, isInProgress: false),
        CursorAgentSessionRow(title: "B", isSelected: false, isUnread: false, isInProgress: false),
        CursorAgentSessionRow(title: "C", isSelected: true, isUnread: true, isInProgress: false)
    ]
    #expect(CursorUnreadSessionPlanner.nextUnreadIndex(in: onLast) == 0)
}

@Test func nextUnreadIndexReturnsNilWhenOnlyUnreadIsAlreadySelected() {
    let rows = [
        CursorAgentSessionRow(title: "A", isSelected: true, isUnread: true, isInProgress: false),
        CursorAgentSessionRow(title: "B", isSelected: false, isUnread: false, isInProgress: false)
    ]
    #expect(CursorUnreadSessionPlanner.nextUnreadIndex(in: rows) == nil)
}

@Test func nextUnreadIndexSkipsInProgressSessions() {
    let rows = [
        CursorAgentSessionRow(title: "A", isSelected: true, isUnread: true, isInProgress: false),
        CursorAgentSessionRow(title: "B", isSelected: false, isUnread: true, isInProgress: true),
        CursorAgentSessionRow(title: "C", isSelected: false, isUnread: true, isInProgress: false)
    ]
    #expect(CursorUnreadSessionPlanner.nextUnreadIndex(in: rows) == 2)
}

@Test func nextUnreadIndexReturnsNilWhenNoUnreadSessions() {
    let rows = [
        CursorAgentSessionRow(title: "A", isSelected: true, isUnread: false, isInProgress: false),
        CursorAgentSessionRow(title: "B", isSelected: false, isUnread: false, isInProgress: false)
    ]
    #expect(CursorUnreadSessionPlanner.nextUnreadIndex(in: rows) == nil)
}

@Test func nextUnreadIndexReturnsFirstWhenNothingSelected() {
    let rows = [
        CursorAgentSessionRow(title: "A", isSelected: false, isUnread: false, isInProgress: false),
        CursorAgentSessionRow(title: "B", isSelected: false, isUnread: true, isInProgress: false)
    ]
    #expect(CursorUnreadSessionPlanner.nextUnreadIndex(in: rows) == 1)
}

@Test func openChatTitleParsesAgentsHeader() {
    #expect(
        CursorUnreadSessionPlanner.openChatTitle(fromAccessibilityTitle: "Chat title. Push request clarification")
            == "Push request clarification"
    )
    #expect(CursorUnreadSessionPlanner.openChatTitle(fromAccessibilityTitle: "Completed, unread X 1m") == nil)
}

private final class StubUnreadSessionClient: CursorUnreadSessionClient, @unchecked Sendable {
    enum Behavior {
        case success(String)
        case failure(SwitchFailure)
    }

    let behavior: Behavior

    init(behavior: Behavior) {
        self.behavior = behavior
    }

    func jumpToNextUnreadSession(invocation: HotkeyInvocation) async throws -> String {
        switch behavior {
        case .success(let title): return title
        case .failure(let failure): throw failure
        }
    }
}

private let navigationInvocation = HotkeyInvocation(
    entryID: UUID(),
    target: .cursor,
    pid: 1,
    focusedWindowID: 42
)

@Test func navigationCoordinatorReportsSuccess() async {
    let coordinator = CursorNavigationCoordinator(
        client: StubUnreadSessionClient(behavior: .success("Fix OAuth integration"))
    )
    let result = await coordinator.apply(.nextUnreadSession, invocation: navigationInvocation)
    guard case .success(let title, _) = result else {
        Issue.record("Expected success")
        return
    }
    #expect(title == "Fix OAuth integration")
}

@Test func navigationCoordinatorReportsNoUnreadFailure() async {
    let coordinator = CursorNavigationCoordinator(
        client: StubUnreadSessionClient(behavior: .failure(.cursorNoUnreadSessions))
    )
    let result = await coordinator.apply(.nextUnreadSession, invocation: navigationInvocation)
    guard case .failure(.cursorNoUnreadSessions) = result else {
        Issue.record("Expected cursorNoUnreadSessions failure")
        return
    }
}

@Test func shortcutEntrySupportsCursorNavigationAssignment() throws {
    let entry = ShortcutEntry(
        shortcut: try KeyboardShortcut(keyCode: 20, keyLabel: "3", modifiers: [.command, .control]),
        chatGPT: nil,
        claudeCode: nil,
        cursor: nil,
        cursorNavigation: .nextUnreadSession
    )
    #expect(entry.enabledTargets == [.cursor])
    #expect(entry.navigation(for: .cursor) == .nextUnreadSession)
    #expect(entry.selection(for: .cursor) == nil)
}

@Test func configurationSeparatesModelAndNavigationEntries() throws {
    let model = ShortcutEntry(
        shortcut: try KeyboardShortcut(keyCode: 18, keyLabel: "1", modifiers: [.command, .shift]),
        chatGPT: ChatGPTSelection(model: .sol56, effort: .extraHigh),
        claudeCode: nil,
        cursor: CursorSelection(model: .grok45, effort: .high)
    )
    var configuration = try ShortcutConfiguration(entries: [model])
    let addition = configuration.addingNavigationEntry()
    configuration = addition.configuration
    #expect(configuration.entries.count == 2)
    #expect(configuration.entries.filter { $0.cursorNavigation == nil }.count == 1)
    #expect(configuration.entries.filter { $0.cursorNavigation != nil }.count == 1)
    #expect(addition.configuration.entry(id: addition.id)?.cursorNavigation == .nextUnreadSession)
    #expect(addition.configuration.entry(id: addition.id)?.chatGPT == nil)
}

@Test func cursorNavigationFailureMessagesAreDistinct() {
    #expect(SwitchFailure.cursorNoUnreadSessions.message.contains("finished"))
    #expect(SwitchFailure.cursorUnreadNavigationUnavailable.message.contains("Agents"))
    #expect(SwitchFailure.cursorUnreadStateNotObservable.message.contains("finished"))
}

@Test func accessibilityTitlesParseSessionNameAndUnreadToken() {
    let unread = "Completed, unread Event strategy for run clubs 5m"
    #expect(CursorUnreadSessionPlanner.hasUnreadToken(unread))
    #expect(CursorUnreadSessionPlanner.sessionName(fromAccessibilityTitle: unread) == "Event strategy for run clubs")
    #expect(CursorUnreadSessionPlanner.looksLikeAgentSessionTitle(unread))

    let attention = "Needs attention Cursor functionality issue 30m"
    #expect(CursorUnreadSessionPlanner.hasUnreadToken(attention))
    #expect(CursorUnreadSessionPlanner.sessionName(fromAccessibilityTitle: attention) == "Cursor functionality issue")

    let completedWithoutMarker = "Completed Concrete minimal version examples 3m"
    #expect(!CursorUnreadSessionPlanner.isFinishedWaitingTitle(completedWithoutMarker))
    #expect(!CursorUnreadSessionPlanner.hasUnreadToken(completedWithoutMarker))
    #expect(
        CursorUnreadSessionPlanner.sessionName(fromAccessibilityTitle: completedWithoutMarker)
            == "Concrete minimal version examples"
    )

    let read = "Completed Event prioritization logic 50m"
    #expect(!CursorUnreadSessionPlanner.hasUnreadToken(read))
    #expect(CursorUnreadSessionPlanner.sessionName(fromAccessibilityTitle: read) == "Event prioritization logic")
    #expect(!CursorUnreadSessionPlanner.looksLikeAgentSessionTitle("New Chat ⌘N"))
    #expect(!CursorUnreadSessionPlanner.looksLikeAgentSessionTitle("montreal-map"))
    #expect(!CursorUnreadSessionPlanner.isFinishedWaitingTitle("In progress Drafting README 1m"))
}
