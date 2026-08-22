import AppKit
import ApplicationServices
import Foundation

enum ClaudeMenuSelection {
    static func isPersistent(
        role: String?,
        selected: Bool,
        mark: String?,
        numericValue: Int?
    ) -> Bool {
        if role == kAXMenuItemRole as String {
            return selected || !(mark ?? "").isEmpty
        }
        if role == kAXRadioButtonRole as String {
            return selected || numericValue == 1
        }
        if role == kAXButtonRole as String {
            return selected
        }
        return false
    }
}

protocol ClaudeCodeUIClient: Sendable {
    func selectModel(_ model: ClaudeCodeModel, invocation: HotkeyInvocation) async throws -> String
    func selectEffort(_ effort: ClaudeCodeEffort, invocation: HotkeyInvocation) async throws -> String
}

actor ClaudeCodeSwitchCoordinator: ClaudeCodeApplying {
    private let client: any ClaudeCodeUIClient
    private var isSwitching = false

    init(client: any ClaudeCodeUIClient = SystemClaudeCodeUIClient()) {
        self.client = client
    }

    func apply(_ selection: ClaudeCodeSelection, invocation: HotkeyInvocation) async -> ProfileSwitchResult {
        let profile = TargetSelection.claudeCode(selection)
        guard !isSwitching else {
            return .failure(profile: profile, failure: .busy)
        }
        isSwitching = true
        defer { isSwitching = false }
        let clock = ContinuousClock()
        let start = clock.now

        do {
            let observedModel = try await client.selectModel(selection.model, invocation: invocation)
            guard observedModel == selection.model.rawValue else {
                throw SwitchFailure.verificationMismatch(
                    expected: selection.model.rawValue,
                    observed: observedModel
                )
            }
            do {
                let observedEffort = try await client.selectEffort(selection.effort, invocation: invocation)
                guard observedEffort == selection.effort.rawValue else {
                    throw SwitchFailure.verificationMismatch(
                        expected: selection.effort.rawValue,
                        observed: observedEffort
                    )
                }
                return .success(
                    profile: profile,
                    observedTitle: "\(observedModel) / \(observedEffort)",
                    elapsed: start.duration(to: clock.now)
                )
            } catch let failure as SwitchFailure {
                return .partialFailure(profile: profile, observedTitle: observedModel, failure: failure)
            } catch {
                return .partialFailure(
                    profile: profile,
                    observedTitle: observedModel,
                    failure: .accessibility(String(describing: error))
                )
            }
        } catch let failure as SwitchFailure {
            return .failure(profile: profile, failure: failure)
        } catch {
            return .failure(profile: profile, failure: .accessibility(String(describing: error)))
        }
    }
}

actor SystemClaudeCodeUIClient: ClaudeCodeUIClient {
    private let deadline: Duration = .seconds(2)

    func selectModel(_ model: ClaudeCodeModel, invocation: HotkeyInvocation) async throws -> String {
        try await choose(model.rawValue, shortcutKeyCode: 34, invocation: invocation)
    }

    func selectEffort(_ effort: ClaudeCodeEffort, invocation: HotkeyInvocation) async throws -> String {
        try await choose(effort.rawValue, shortcutKeyCode: 14, invocation: invocation)
    }

    private func choose(_ label: String, shortcutKeyCode: CGKeyCode, invocation: HotkeyInvocation) async throws -> String {
        try validate(invocation, requiresCodeSurface: true)
        let application = AXUIElementCreateApplication(invocation.pid)
        let existing = elementIdentities(in: application)
        try postShortcut(keyCode: shortcutKeyCode, invocation: invocation)
        guard let item = try await waitForExactActionable(label, invocation: invocation, excluding: existing) else {
            try await dismissOpenMenus(invocation: invocation, excluding: existing)
            if ClaudeCodeModel.allCases.contains(where: { $0.rawValue == label }) {
                throw SwitchFailure.modelUnavailable(label)
            }
            throw SwitchFailure.effortUnavailable(label)
        }
        try validate(invocation, requiresCodeSurface: true)
        let openedMenus = transientMenuRoots(invocation: invocation, excluding: existing)
        guard !openedMenus.isEmpty else {
            throw SwitchFailure.accessibility("Claude menu root could not be verified.")
        }
        do {
            try TrustedTargetAction.press(item, invocation: invocation)
        } catch {
            try await dismissAndVerify(openedMenus, invocation: invocation)
            throw error
        }
        try await waitForMenusToClose(openedMenus, invocation: invocation)
        try validate(invocation, requiresCodeSurface: true)
        return try await verifySelected(label, shortcutKeyCode: shortcutKeyCode, invocation: invocation)
    }

    private func verifySelected(_ label: String, shortcutKeyCode: CGKeyCode, invocation: HotkeyInvocation) async throws -> String {
        let application = AXUIElementCreateApplication(invocation.pid)
        let existing = elementIdentities(in: application)
        try postShortcut(keyCode: shortcutKeyCode, invocation: invocation)
        guard let item = try await waitForExactActionable(label, invocation: invocation, excluding: existing),
              isSelected(item)
        else {
            try await dismissOpenMenus(invocation: invocation, excluding: existing)
            throw SwitchFailure.verificationMismatch(expected: label, observed: "Claude did not expose the item as selected")
        }
        let openedMenus = transientMenuRoots(invocation: invocation, excluding: existing)
        guard !openedMenus.isEmpty else {
            throw SwitchFailure.accessibility("Claude verification menu root could not be verified.")
        }
        try await dismissAndVerify(openedMenus, invocation: invocation)
        return label
    }

    private func validate(_ invocation: HotkeyInvocation, requiresCodeSurface: Bool) throws {
        guard AXIsProcessTrusted() else { throw SwitchFailure.permissionMissing }
        guard invocation.target == .claudeCode,
              let running = NSWorkspace.shared.frontmostApplication,
              running.bundleIdentifier == AppConstants.claudeDesktopBundleID,
              running.processIdentifier == invocation.pid
        else { throw SwitchFailure.targetChanged(ApplicationTarget.claudeCode.displayName) }

        let application = AXUIElementCreateApplication(invocation.pid)
        guard let window: AXUIElement = value(application, kAXFocusedWindowAttribute),
              AXWindowIdentity.focusedWindowID(application: application, pid: invocation.pid)
                == invocation.focusedWindowID
        else { throw SwitchFailure.targetChanged(ApplicationTarget.claudeCode.displayName) }
        if requiresCodeSurface, !containsCodeSurface(in: window) {
            throw SwitchFailure.claudeCodeSurfaceNotFound
        }
    }

    private func containsCodeSurface(in window: AXUIElement) -> Bool {
        return breadthFirst(root: window, maxDepth: 18, maxNodes: 4_000).contains { element in
            let selected: Bool = value(element, kAXSelectedAttribute) ?? false
            let role: String? = value(element, kAXRoleAttribute)
            let allowedRoles = [kAXButtonRole as String, kAXRadioButtonRole as String, kAXTabGroupRole as String]
            return selected && allowedRoles.contains(role ?? "") && exactLabels(element).contains("Code")
        }
    }

    private func waitForExactActionable(
        _ label: String,
        invocation: HotkeyInvocation,
        excluding existing: Set<CFHashCode>
    ) async throws -> AXUIElement? {
        let clock = ContinuousClock()
        let end = clock.now.advanced(by: deadline)
        let application = AXUIElementCreateApplication(invocation.pid)
        while clock.now < end {
            try validate(invocation, requiresCodeSurface: true)
            let focusedWindow: AXUIElement? = value(application, kAXFocusedWindowAttribute)
            if let focusedWindow, let item = breadthFirst(root: focusedWindow, maxDepth: 20, maxNodes: 5_000).first(where: {
                !existing.contains(CFHash($0))
                    && exactLabels($0).contains(label)
                    && actions($0).contains(kAXPressAction as String)
                    && (value($0, kAXEnabledAttribute) as Bool?) == true
                    && frame($0) != nil
                    && isInsideMenu($0)
            }) { return item }
            try await Task.sleep(for: .milliseconds(50))
        }
        return nil
    }

    private func isInsideMenu(_ element: AXUIElement) -> Bool {
        var current: AXUIElement? = element
        for _ in 0..<10 {
            guard let node = current else { return false }
            let role: String? = value(node, kAXRoleAttribute)
            if role == kAXMenuRole as String || role == kAXMenuItemRole as String {
                return true
            }
            let subrole: String? = value(node, kAXSubroleAttribute)
            if subrole?.localizedCaseInsensitiveContains("popover") == true {
                return true
            }
            current = value(node, kAXParentAttribute)
        }
        return false
    }

    private func elementIdentities(in root: AXUIElement) -> Set<CFHashCode> {
        Set(breadthFirst(root: root, maxDepth: 20, maxNodes: 5_000).map(CFHash))
    }

    private func isSelected(_ element: AXUIElement) -> Bool {
        let role: String? = value(element, kAXRoleAttribute)
        let selected: Bool = value(element, kAXSelectedAttribute) ?? false
        let mark: String? = value(element, kAXMenuItemMarkCharAttribute)
        let numericValue: NSNumber? = value(element, kAXValueAttribute)
        return ClaudeMenuSelection.isPersistent(
            role: role,
            selected: selected,
            mark: mark,
            numericValue: numericValue?.intValue
        )
    }

    private func postShortcut(keyCode: CGKeyCode, invocation: HotkeyInvocation) throws {
        try postKey(keyCode: keyCode, flags: [.maskCommand, .maskShift], invocation: invocation)
    }

    private func dismissMenu(invocation: HotkeyInvocation) throws {
        try postKey(keyCode: 53, flags: [], invocation: invocation)
    }

    private func dismissOpenMenus(
        invocation: HotkeyInvocation,
        excluding existing: Set<CFHashCode>
    ) async throws {
        let menus = transientMenuRoots(invocation: invocation, excluding: existing)
        try dismissMenu(invocation: invocation)
        guard !menus.isEmpty else {
            throw SwitchFailure.accessibility("Claude menu cleanup could not identify the open menu.")
        }
        try await waitForMenusToClose(menus, invocation: invocation)
    }

    private func dismissAndVerify(
        _ menus: [AXUIElement],
        invocation: HotkeyInvocation
    ) async throws {
        try dismissMenu(invocation: invocation)
        try await waitForMenusToClose(menus, invocation: invocation)
    }

    private func transientMenuRoots(
        invocation: HotkeyInvocation,
        excluding existing: Set<CFHashCode>
    ) -> [AXUIElement] {
        let application = AXUIElementCreateApplication(invocation.pid)
        guard let window: AXUIElement = value(application, kAXFocusedWindowAttribute) else { return [] }
        return breadthFirst(root: window, maxDepth: 20, maxNodes: 5_000).filter { element in
            guard !existing.contains(CFHash(element)) else { return false }
            let role: String? = value(element, kAXRoleAttribute)
            let subrole: String? = value(element, kAXSubroleAttribute)
            return role == kAXMenuRole as String
                || subrole?.localizedCaseInsensitiveContains("popover") == true
        }
    }

    private func waitForMenusToClose(
        _ menus: [AXUIElement],
        invocation: HotkeyInvocation
    ) async throws {
        let clock = ContinuousClock()
        let end = clock.now.advanced(by: deadline)
        while clock.now < end {
            try validate(invocation, requiresCodeSurface: true)
            if menus.allSatisfy({ !isAlive($0) }) { return }
            try await Task.sleep(for: .milliseconds(50))
        }
        throw SwitchFailure.deadlineExceeded("waiting for the Claude menu to close")
    }

    private func isAlive(_ element: AXUIElement) -> Bool {
        var role: CFTypeRef?
        return AXUIElementCopyAttributeValue(element, kAXRoleAttribute as CFString, &role) == .success
    }

    private func postKey(keyCode: CGKeyCode, flags: CGEventFlags, invocation: HotkeyInvocation) throws {
        try validate(invocation, requiresCodeSurface: true)
        try TrustedTargetAction.postKey(keyCode: keyCode, flags: flags, invocation: invocation)
        try validate(invocation, requiresCodeSurface: true)
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

    private func exactLabels(_ element: AXUIElement) -> [String] {
        [kAXTitleAttribute, kAXDescriptionAttribute, kAXValueAttribute]
            .compactMap { value(element, $0) as String? }
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
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
