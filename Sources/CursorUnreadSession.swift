import AppKit
import ApplicationServices
import Foundation

enum CursorNavigationAction: String, CaseIterable, Codable, Hashable, Sendable, Identifiable {
    case nextUnreadSession

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .nextUnreadSession: "Next finished session"
        }
    }
}

enum CursorShortcutAction: Equatable, Hashable, Sendable {
    case switchModel(CursorSelection)
    case nextUnreadSession
}

enum NavigationSwitchResult: Equatable, Sendable {
    case success(title: String, elapsed: Duration)
    case failure(SwitchFailure)
}

/// Sidebar agent row discovered through Accessibility.
struct CursorAgentSessionRow: Equatable, Sendable {
    let title: String
    let isSelected: Bool
    let isUnread: Bool
    let isInProgress: Bool
}

enum CursorUnreadSessionPlanner {
    /// Returns the index of the next finished-unread row after the current selection, wrapping once.
    /// Never returns the already-selected row; if that is the only unread, returns nil.
    static func nextUnreadIndex(in rows: [CursorAgentSessionRow]) -> Int? {
        guard !rows.isEmpty else { return nil }
        let eligible = rows.indices.filter { rows[$0].isUnread && !rows[$0].isInProgress }
        guard !eligible.isEmpty else { return nil }
        guard let selected = rows.firstIndex(where: \.isSelected) else {
            return eligible.first
        }
        if let after = eligible.first(where: { $0 > selected }) {
            return after
        }
        if let wrap = eligible.first(where: { $0 != selected }) {
            return wrap
        }
        return nil
    }

    static func sessionName(fromAccessibilityTitle title: String) -> String {
        var value = title
        let prefixes = [
            "Completed, unread ",
            "Completed, Unread ",
            "Needs attention, unread ",
            "Needs Attention, unread ",
            "Needs attention ",
            "Needs Attention ",
            "In progress, unread ",
            "In Progress, unread ",
            "Completed ",
            "In progress ",
            "In Progress ",
            "Generating ",
            "Running ",
            "Draft ",
            "Waiting "
        ]
        for prefix in prefixes where value.hasPrefix(prefix) {
            value = String(value.dropFirst(prefix.count))
            break
        }
        if let regex = try? NSRegularExpression(pattern: #"\s+\d+[smhdw]$"#) {
            let range = NSRange(value.startIndex..<value.endIndex, in: value)
            value = regex.stringByReplacingMatches(in: value, range: range, withTemplate: "")
        }
        return value.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    static func openChatTitle(fromAccessibilityTitle title: String) -> String? {
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        for prefix in ["Chat title. ", "Chat title."] where trimmed.hasPrefix(prefix) {
            let value = String(trimmed.dropFirst(prefix.count))
                .trimmingCharacters(in: .whitespacesAndNewlines)
            return value.isEmpty ? nil : value
        }
        return nil
    }

    static func hasUnreadToken(_ title: String) -> Bool {
        isFinishedWaitingTitle(title)
    }

    /// Finished agent chats waiting for a reply: Cursor’s blue-dot / Needs attention rows.
    /// A finished session is actionable only when Accessibility exposes an
    /// explicit waiting marker. Plain `Completed` is not evidence that a
    /// reply is waiting.
    static func isFinishedWaitingTitle(_ title: String) -> Bool {
        let lowered = title.lowercased()
        return lowered.contains("unread")
            || lowered.contains("needs attention")
    }

    static func looksLikeAgentSessionTitle(_ title: String) -> Bool {
        let lowered = title.lowercased()
        let chrome = [
            "new chat", "search", "automations", "customize", "account menu",
            "connect slack", "no repo", "repositories", "open workspace", "next unread agent",
            "chat title", "next finished"
        ]
        if chrome.contains(where: {
            lowered == $0
                || lowered.hasPrefix($0 + " ")
                || lowered.hasPrefix($0 + "⌘")
                || lowered.hasPrefix($0 + ".")
        }) {
            return false
        }
        if lowered.hasPrefix("new chat") || lowered.hasPrefix("search") || lowered.hasPrefix("repositories") {
            return false
        }
        if isFinishedWaitingTitle(title) { return true }
        let statusTokens = [
            "completed", "unread", "needs attention", "in progress",
            "generating", "running", "draft", "waiting"
        ]
        if statusTokens.contains(where: { lowered.contains($0) }) { return true }
        // Nested agent rows often end with a relative age (`3m`, `16h`, `1d`).
        if let regex = try? NSRegularExpression(pattern: #"\s+\d+[smhdw]$"#) {
            let range = NSRange(title.startIndex..<title.endIndex, in: title)
            if regex.firstMatch(in: title, range: range) != nil { return true }
        }
        return false
    }
}

protocol CursorUnreadSessionClient: Sendable {
    func jumpToNextUnreadSession(invocation: HotkeyInvocation) async throws -> String
}

actor CursorNavigationCoordinator: CursorNavigating {
    private let client: any CursorUnreadSessionClient

    init(client: any CursorUnreadSessionClient = SystemCursorUnreadSessionClient()) {
        self.client = client
    }

    func apply(_ action: CursorNavigationAction, invocation: HotkeyInvocation) async -> NavigationSwitchResult {
        let clock = ContinuousClock()
        let start = clock.now
        do {
            let title = try await client.jumpToNextUnreadSession(invocation: invocation)
            return .success(title: title, elapsed: start.duration(to: clock.now))
        } catch let failure as SwitchFailure {
            return .failure(failure)
        } catch {
            return .failure(.accessibility(String(describing: error)))
        }
    }
}

actor SystemCursorUnreadSessionClient: CursorUnreadSessionClient {
    private let verifyTimeout: Duration = .milliseconds(1_200)

    func jumpToNextUnreadSession(invocation: HotkeyInvocation) async throws -> String {
        try validate(invocation)
        guard let window = agentsWindow(invocation: invocation) else {
            throw SwitchFailure.noFocusedWindow
        }
        let nodes = breadthFirst(root: window, maxDepth: 24, maxNodes: 8_000)
        let windowFrame = frame(window) ?? .zero
        let openTitle = discoverOpenChatTitle(in: nodes)
        let rows = discoverAgentRows(in: nodes, windowFrame: windowFrame, openChatTitle: openTitle)
        if !rows.isEmpty {
            let summaries = rows.map { row in
                CursorAgentSessionRow(
                    title: row.sessionName,
                    isSelected: row.isSelected,
                    isUnread: row.isUnread,
                    isInProgress: row.isInProgress
                )
            }
            if let targetIndex = CursorUnreadSessionPlanner.nextUnreadIndex(in: summaries) {
                let target = rows[targetIndex]
                try validate(invocation)
                try activate(target.element, invocation: invocation)
                guard try await waitForActivation(of: target, in: window, invocation: invocation) else {
                    throw SwitchFailure.verificationMismatch(
                        expected: target.sessionName,
                        observed: "Cursor did not open ‘\(target.sessionName)’"
                    )
                }
                return target.sessionName
            }
        }
        if rows.isEmpty {
            throw SwitchFailure.cursorUnreadNavigationUnavailable
        }
        guard rows.contains(where: \.isUnread) else {
            throw SwitchFailure.cursorUnreadStateNotObservable
        }
        throw SwitchFailure.cursorNoUnreadSessions
    }

    private struct DiscoveredRow {
        let element: AXUIElement
        let title: String
        let sessionName: String
        let isSelected: Bool
        let isUnread: Bool
        let isInProgress: Bool
    }

    private func discoverOpenChatTitle(in nodes: [AXUIElement]) -> String? {
        for element in nodes {
            for label in allLabels(element) {
                if let title = CursorUnreadSessionPlanner.openChatTitle(fromAccessibilityTitle: label) {
                    return title
                }
            }
        }
        return nil
    }

    private func discoverAgentRows(
        in nodes: [AXUIElement],
        windowFrame: CGRect,
        openChatTitle: String?
    ) -> [DiscoveredRow] {
        let sidebarMaxX = windowFrame.maxX > 0
            ? windowFrame.minX + min(windowFrame.width * 0.42, 380)
            : .greatestFiniteMagnitude
        var rows: [DiscoveredRow] = []
        for element in nodes {
            guard let rowFrame = frame(element),
                  rowFrame.minX <= sidebarMaxX,
                  rowFrame.width >= 120,
                  rowFrame.height >= 18,
                  rowFrame.height <= 48
            else { continue }
            guard isAgentRowCandidate(element) else { continue }
            let title = primaryTitle(element)
            let sessionName = CursorUnreadSessionPlanner.sessionName(fromAccessibilityTitle: title)
            guard !sessionName.isEmpty else { continue }
            let unread = CursorUnreadSessionPlanner.hasUnreadToken(title)
            let inProgress = Self.isInProgressTitle(title)
            let axSelected: Bool = value(element, kAXSelectedAttribute) ?? false
            let titleSelected = openChatTitle.map { open in
                sessionName.caseInsensitiveCompare(open) == .orderedSame
            } ?? false
            rows.append(DiscoveredRow(
                element: element,
                title: title,
                sessionName: sessionName,
                isSelected: axSelected || titleSelected,
                isUnread: unread,
                isInProgress: inProgress
            ))
        }
        let sorted = rows.sorted { (frame($0.element)?.midY ?? 0) < (frame($1.element)?.midY ?? 0) }
        let names = sorted.map(\.sessionName)
        return Set(names).count == names.count ? sorted : []
    }

    private func isAgentRowCandidate(_ element: AXUIElement) -> Bool {
        let role: String? = value(element, kAXRoleAttribute)
        guard role == kAXButtonRole as String else { return false }
        guard isActivatable(element) else { return false }
        let title = primaryTitle(element)
        guard title.count >= 3, title.count <= 200 else { return false }
        return CursorUnreadSessionPlanner.looksLikeAgentSessionTitle(title)
    }

    private static func isInProgressTitle(_ title: String) -> Bool {
        let lowered = title.lowercased()
        if lowered.contains("completed") { return false }
        return ["running", "generating", "working", "starting", "in progress", "thinking"]
            .contains { lowered.contains($0) }
    }

    private func waitForActivation(
        of target: DiscoveredRow,
        in window: AXUIElement,
        invocation: HotkeyInvocation
    ) async throws -> Bool {
        let clock = ContinuousClock()
        let end = clock.now.advanced(by: verifyTimeout)
        while clock.now < end {
            try validate(invocation)
            let nodes = breadthFirst(root: window, maxDepth: 24, maxNodes: 8_000)
            let windowFrame = frame(window) ?? .zero
            let openTitle = discoverOpenChatTitle(in: nodes)
            let rows = discoverAgentRows(in: nodes, windowFrame: windowFrame, openChatTitle: openTitle)
            if let match = rows.first(where: { $0.sessionName == target.sessionName }) {
                // Cursor marks the agent read on select; the AX title loses "unread".
                if target.isUnread, !match.isUnread {
                    return true
                }
                if match.isSelected {
                    return true
                }
            }
            if let openTitle,
               openTitle.caseInsensitiveCompare(target.sessionName) == .orderedSame {
                return true
            }
            try await Task.sleep(for: .milliseconds(40))
        }
        return false
    }

    private func validate(_ invocation: HotkeyInvocation) throws {
        guard AXIsProcessTrusted() else { throw SwitchFailure.permissionMissing }
        guard invocation.target == .cursor else {
            throw SwitchFailure.targetChanged(ApplicationTarget.cursor.displayName)
        }
        guard let running = NSRunningApplication(processIdentifier: invocation.pid),
              running.bundleIdentifier == AppConstants.cursorBundleID
        else {
            throw SwitchFailure.targetChanged(ApplicationTarget.cursor.displayName)
        }
        let front = NSWorkspace.shared.frontmostApplication
        guard front?.processIdentifier == invocation.pid else {
            throw SwitchFailure.targetChanged(ApplicationTarget.cursor.displayName)
        }
        let application = AXUIElementCreateApplication(invocation.pid)
        guard AXWindowIdentity.focusedWindowID(application: application, pid: invocation.pid)
            == invocation.focusedWindowID
        else { throw SwitchFailure.targetChanged(ApplicationTarget.cursor.displayName) }
    }

    private func agentsWindow(invocation: HotkeyInvocation) -> AXUIElement? {
        let application = AXUIElementCreateApplication(invocation.pid)
        guard let focused: AXUIElement = value(application, kAXFocusedWindowAttribute),
              AXWindowIdentity.focusedWindowID(application: application, pid: invocation.pid)
                == invocation.focusedWindowID
        else { return nil }
        return focused
    }

    private func focusedWindow(pid: pid_t) -> AXUIElement? {
        let application = AXUIElementCreateApplication(pid)
        return value(application, kAXFocusedWindowAttribute)
    }

    private func primaryTitle(_ element: AXUIElement) -> String {
        allLabels(element).first ?? ""
    }

    private func allLabels(_ element: AXUIElement) -> [String] {
        [kAXTitleAttribute, kAXDescriptionAttribute, kAXValueAttribute, kAXHelpAttribute]
            .compactMap { value(element, $0) as String? }
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
    }

    private func isActivatable(_ element: AXUIElement) -> Bool {
        let enabled = (value(element, kAXEnabledAttribute) as Bool?) != false
        guard enabled, frame(element) != nil else { return false }
        return actions(element).contains(kAXPressAction as String)
            || actions(element).contains("AXOpen")
    }

    private func activate(_ element: AXUIElement, invocation: HotkeyInvocation) throws {
        guard actions(element).contains(kAXPressAction as String) else {
            throw SwitchFailure.accessibility("Cursor agent row does not expose AXPress.")
        }
        try TrustedTargetAction.press(element, invocation: invocation)
    }

    private func breadthFirst(root: AXUIElement, maxDepth: Int, maxNodes: Int) -> [AXUIElement] {
        var queue: [(AXUIElement, Int)] = [(root, 0)]
        var output: [AXUIElement] = []
        var visited = Set<CFHashCode>()
        var index = 0
        while index < queue.count, output.count < maxNodes {
            let (element, depth) = queue[index]
            index += 1
            guard visited.insert(CFHash(element)).inserted else { continue }
            output.append(element)
            guard depth < maxDepth else { continue }
            let children: [AXUIElement] = value(element, kAXChildrenAttribute) ?? []
            let visible: [AXUIElement] = value(element, kAXVisibleChildrenAttribute) ?? []
            queue.append(contentsOf: (children + visible).map { ($0, depth + 1) })
        }
        return output
    }

    private func actions(_ element: AXUIElement) -> [String] {
        var result: CFArray?
        guard AXUIElementCopyActionNames(element, &result) == .success else { return [] }
        return result as? [String] ?? []
    }

    private func frame(_ element: AXUIElement) -> CGRect? {
        guard let positionValue: AXValue = value(element, kAXPositionAttribute),
              let sizeValue: AXValue = value(element, kAXSizeAttribute)
        else { return nil }
        var position = CGPoint.zero
        var size = CGSize.zero
        guard AXValueGetValue(positionValue, .cgPoint, &position),
              AXValueGetValue(sizeValue, .cgSize, &size)
        else { return nil }
        return CGRect(origin: position, size: size)
    }

    private func value<T>(_ element: AXUIElement, _ attribute: String) -> T? {
        var result: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, attribute as CFString, &result) == .success else { return nil }
        return result as? T
    }
}

enum CursorUnreadSessionDiagnostics {
    /// Kept as a compatibility no-op. Diagnostics must not activate arbitrary
    /// workspace controls outside the trusted target-action boundary.
    @discardableResult
    static func openWorkspaceNamed(_ name: String, pid: pid_t) -> Bool {
        _ = name
        _ = pid
        return false
    }

    static func dump(pid: pid_t) -> String {
        _ = pid
        return "Cursor diagnostics are disabled in distributable builds."

        /*
        let application = AXUIElementCreateApplication(pid)
        let windows: [AXUIElement] = value(application, kAXWindowsAttribute) ?? []
        var lines: [String] = ["diagnostics: windows=\(windows.count)"]
        let targets: [(Int, AXUIElement)]
        if windows.isEmpty {
            if let focused: AXUIElement = value(application, kAXFocusedWindowAttribute) {
                targets = [(0, focused)]
            } else {
                targets = []
            }
        } else {
            targets = windows.enumerated().map { ($0.offset, $0.element) }
        }
        for (idx, window) in targets {
            let windowTitle = (value(window, kAXTitleAttribute) as String?)
                ?? allLabels(window).first
                ?? "(untitled)"
            let windowFrame = frame(window) ?? .zero
            lines.append("--- window[\(idx)] \(Int(windowFrame.width))x\(Int(windowFrame.height)) \(windowTitle.prefix(60))")
            let nodes = breadthFirst(root: window, maxDepth: 26, maxNodes: 10_000)
            lines.append("nodes=\(nodes.count)")
            let sidebarMaxX = windowFrame.maxX > 0
                ? windowFrame.minX + min(windowFrame.width * 0.42, 420)
                : .greatestFiniteMagnitude
            var leftTitles: [String] = []
            for element in nodes {
                guard let rowFrame = frame(element),
                      rowFrame.minX <= sidebarMaxX,
                      rowFrame.width >= 60,
                      rowFrame.height >= 14,
                      rowFrame.height <= 72
                else { continue }
                let role: String = value(element, kAXRoleAttribute) ?? "?"
                guard role == kAXButtonRole as String
                    || role == kAXRadioButtonRole as String
                    || role == kAXStaticTextRole as String
                    || role == kAXGroupRole as String
                    || role == "AXCell"
                    || role == "AXRow"
                else { continue }
                let labels = allLabels(element)
                guard let title = labels.first, title.count >= 2, title.count <= 200 else { continue }
                let selected: Bool = value(element, kAXSelectedAttribute) ?? false
                let press = actions(element).contains(kAXPressAction as String)
                let leading = leadingTinyChildren(in: element, rowFrame: rowFrame).count
                let trailing = trailingTinyChildren(in: element, rowFrame: rowFrame).count
                leftTitles.append(
                    "\(role) press=\(press) sel=\(selected) leadTiny=\(leading) trailTiny=\(trailing) \(Int(rowFrame.width))x\(Int(rowFrame.height))@\(Int(rowFrame.minX)),\(Int(rowFrame.minY)) \(title.prefix(80))"
                )
            }
            lines.append("leftSizedElements=\(leftTitles.count)")
            lines.append(contentsOf: leftTitles.prefix(120))
        }
        return lines.joined(separator: "\n")
        */
    }

    private static func leadingTinyChildren(in element: AXUIElement, rowFrame: CGRect) -> [String] {
        tinyChildren(in: element, rowFrame: rowFrame, trailing: false)
    }

    private static func trailingTinyChildren(in element: AXUIElement, rowFrame: CGRect) -> [String] {
        tinyChildren(in: element, rowFrame: rowFrame, trailing: true)
    }

    private static func tinyChildren(in element: AXUIElement, rowFrame: CGRect, trailing: Bool) -> [String] {
        let edgeX = trailing
            ? rowFrame.minX + rowFrame.width * 0.55
            : rowFrame.minX + max(28, rowFrame.width * 0.28)
        var out: [String] = []
        var queue: [(AXUIElement, Int)] = [(element, 0)]
        var index = 0
        while index < queue.count {
            let (node, depth) = queue[index]
            index += 1
            if depth > 6 { continue }
            if let rect = frame(node), rect.width > 0, rect.height > 0 {
                let tiny = rect.width <= 16 && rect.height <= 16
                let labels = allLabels(node)
                let unnamed = labels.isEmpty || labels.allSatisfy { $0.count <= 1 }
                let onSide = trailing ? rect.midX >= edgeX : rect.midX <= edgeX
                if tiny && unnamed && onSide {
                    out.append("\(Int(rect.width))x\(Int(rect.height))@\(Int(rect.midX)),\(Int(rect.midY))")
                }
            }
            let children: [AXUIElement] = value(node, kAXChildrenAttribute) ?? []
            let visible: [AXUIElement] = value(node, kAXVisibleChildrenAttribute) ?? []
            queue.append(contentsOf: (children + visible).map { ($0, depth + 1) })
        }
        return out
    }

    private static func actions(_ element: AXUIElement) -> [String] {
        var result: CFArray?
        guard AXUIElementCopyActionNames(element, &result) == .success else { return [] }
        return result as? [String] ?? []
    }

    private static func allLabels(_ element: AXUIElement) -> [String] {
        [kAXTitleAttribute, kAXDescriptionAttribute, kAXValueAttribute, kAXHelpAttribute]
            .compactMap { value(element, $0) as String? }
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
    }

    private static func breadthFirst(root: AXUIElement, maxDepth: Int, maxNodes: Int) -> [AXUIElement] {
        var queue: [(AXUIElement, Int)] = [(root, 0)]
        var output: [AXUIElement] = []
        var visited = Set<CFHashCode>()
        var index = 0
        while index < queue.count, output.count < maxNodes {
            let (element, depth) = queue[index]
            index += 1
            guard visited.insert(CFHash(element)).inserted else { continue }
            output.append(element)
            guard depth < maxDepth else { continue }
            let children: [AXUIElement] = value(element, kAXChildrenAttribute) ?? []
            let visible: [AXUIElement] = value(element, kAXVisibleChildrenAttribute) ?? []
            queue.append(contentsOf: (children + visible).map { ($0, depth + 1) })
        }
        return output
    }

    private static func frame(_ element: AXUIElement) -> CGRect? {
        guard let positionValue: AXValue = value(element, kAXPositionAttribute),
              let sizeValue: AXValue = value(element, kAXSizeAttribute)
        else { return nil }
        var position = CGPoint.zero
        var size = CGSize.zero
        guard AXValueGetValue(positionValue, .cgPoint, &position),
              AXValueGetValue(sizeValue, .cgSize, &size)
        else { return nil }
        return CGRect(origin: position, size: size)
    }

    private static func value<T>(_ element: AXUIElement, _ attribute: String) -> T? {
        var result: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, attribute as CFString, &result) == .success else { return nil }
        return result as? T
    }
}
