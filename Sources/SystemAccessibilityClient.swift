import AppKit
import ApplicationServices
import CoreGraphics
import Foundation
import os

enum AppConstants {
    static let chatGPTBundleID = "com.openai.codex"
    static let claudeDesktopBundleID = "com.anthropic.claudefordesktop"
    static let cursorBundleID = "com.todesktop.230313mzl4w4u92"
    static let antigravityBundleID = "com.google.antigravity"
    static let modelLabel = "Model"
    static let effortLabel = "Effort"
}

actor SystemAccessibilityClient: ChatGPTUIClient, ChatGPTPickerTransport {
    private let logger = Logger(subsystem: "com.thierryai.ReasonDeck", category: "switching")
    private let deadline: Duration = .seconds(2)
    private let nativeModelPickerKey: CGKeyCode = 46 // M, Control-Shift-M in ChatGPT.
    private var accessibilityPreparationAttemptedPID: pid_t?
    private var composerFocusTarget: ComposerFocusTarget?
    private var modernTransaction = false

    func apply(_ selection: ChatGPTSelection, invocation: HotkeyInvocation) async -> ChatGPTApplyOutcome {
        composerFocusTarget = await captureComposerFocus(invocation: invocation)
        modernTransaction = false
        if let context = try? await resolveContext(invocation: invocation) {
            let snapshot = chatGPTSnapshot(window: context.window)
            modernTransaction = (try? ChatGPTModernPlanner.composer(in: snapshot.snapshot)) != nil
        }
        let outcome = await ChatGPTTransaction.apply(selection, invocation: invocation, using: self)
        composerFocusTarget = nil
        return outcome
    }

    func observeSelectionTitleLeavingPickerOpen(invocation: HotkeyInvocation) async throws -> String {
        let start = ContinuousClock().now
        defer { logElapsed("observe-picker", since: start) }
        if modernTransaction { return try await modernSelection(invocation: invocation).expectedTitle }
        let context = try await openNativePicker(invocation: invocation)
        return "\(context.picker.model.rawValue) \(context.picker.effort.rawValue)"
    }

    func selectModel(_ model: ChatGPTModel, invocation: HotkeyInvocation) async throws -> String {
        let start = ContinuousClock().now
        defer { logElapsed("select-model-total", since: start) }
        if modernTransaction { return try await selectModernModel(model, invocation: invocation).expectedTitle }
        let context = try await openNativePicker(invocation: invocation)
        let row = try element(for: context.picker.modelRow, in: context.live)
        let pickerMenu = owningMenu(of: row)
        try execute(context.picker.modelRow, element: row, invocation: invocation)
        guard let menu = await waitForOwnedMenu(
            containing: model.rawValue,
            in: context.window,
            excluding: pickerMenu,
            timeout: deadline
        ), let item = uniqueActionable(named: model.rawValue, in: menu) else {
            throw SwitchFailure.modelUnavailable(model.rawValue)
        }
        try TrustedTargetAction.press(item, invocation: invocation)
        try? await Task.sleep(for: .milliseconds(50))
        return try await observeSelectionTitleLeavingPickerOpen(invocation: invocation)
    }

    func selectEffort(_ effort: ChatGPTReasoningEffort, invocation: HotkeyInvocation) async throws -> String {
        let start = ContinuousClock().now
        defer { logElapsed("select-effort-total", since: start) }
        if modernTransaction { return try await selectModernEffort(effort, invocation: invocation).expectedTitle }
        let context = try await openNativePicker(invocation: invocation)
        let row = try element(for: context.picker.effortRow, in: context.live)
        let pickerMenu = owningMenu(of: row)
        try execute(context.picker.effortRow, element: row, invocation: invocation)
        guard let menu = await waitForOwnedMenu(
            containing: effort.rawValue,
            in: context.window,
            excluding: pickerMenu,
            timeout: deadline
        ), let item = uniqueActionable(named: effort.rawValue, in: menu) else {
            throw SwitchFailure.effortUnavailable(effort.rawValue)
        }
        try TrustedTargetAction.press(item, invocation: invocation)
        try? await Task.sleep(for: .milliseconds(50))
        return try await observeSelectionTitleLeavingPickerOpen(invocation: invocation)
    }

    func restoreComposerFocus(invocation: HotkeyInvocation) async -> Bool {
        let start = ContinuousClock().now
        defer { logElapsed("restore-composer-focus", since: start) }
        do {
            var context = try await resolveContext(invocation: invocation)
            if modernTransaction {
                try await dismissModernPicker(invocation: invocation)
                context = try await resolveContext(invocation: invocation)
            }
            if let picker = nativePicker(in: context.window) {
                try dismissNativePicker(picker, invocation: invocation)
                try await Task.sleep(for: .milliseconds(50))
                context = try await resolveContext(invocation: invocation)
            }

            guard let target = composerFocusTarget else {
                logger.info("Composer focus was not captured before the ChatGPT transaction")
                return false
            }
            guard isDescendant(target.element, of: context.window) else {
                logger.info("Captured composer focus target changed before focus restoration")
                return false
            }

            try TrustedTargetAction.validate(invocation)
            let error = AXUIElementSetAttributeValue(
                target.element,
                kAXFocusedAttribute as CFString,
                kCFBooleanTrue
            )
            guard error == .success else {
                logger.error("Could not restore ChatGPT composer focus error=\(error.rawValue)")
                return false
            }

            let clock = ContinuousClock()
            let end = clock.now.advanced(by: .milliseconds(500))
            while clock.now < end {
                try TrustedTargetAction.validate(invocation)
                context = try await resolveContext(invocation: invocation)
                let focused: AXUIElement? = value(context.application, kAXFocusedUIElementAttribute)
                if focused.map({ CFEqual($0, target.element) }) == true {
                    return true
                }
                try await Task.sleep(for: .milliseconds(25))
            }
            logger.error("ChatGPT did not verify the restored composer focus")
            return false
        } catch {
            logger.error("Could not restore ChatGPT composer focus: \(String(describing: error), privacy: .public)")
            return false
        }
    }

    private struct Context {
        let application: AXUIElement
        let window: AXUIElement
    }
    private struct ComposerFocusTarget { let element: AXUIElement }
    private struct LiveChatGPTSnapshot {
        let snapshot: ChatGPTAXSnapshot
        let elements: [Int: AXUIElement]
    }
    private struct NativePickerContext {
        let window: AXUIElement
        let live: LiveChatGPTSnapshot
        let picker: ChatGPTNativePicker
    }

    private func resolveContext(invocation: HotkeyInvocation) async throws -> Context {
        guard AXIsProcessTrusted() else { throw SwitchFailure.permissionMissing }
        guard let running = NSWorkspace.shared.frontmostApplication,
              running.bundleIdentifier == AppConstants.chatGPTBundleID
        else { throw SwitchFailure.chatGPTNotFrontmost }
        guard invocation.target == .chatGPT, invocation.pid == running.processIdentifier else {
            throw SwitchFailure.targetChanged(ApplicationTarget.chatGPT.displayName)
        }
        let application = AXUIElementCreateApplication(running.processIdentifier)
        guard AXWindowIdentity.focusedWindowID(application: application, pid: running.processIdentifier) == invocation.focusedWindowID else {
            throw SwitchFailure.targetChanged(ApplicationTarget.chatGPT.displayName)
        }
        if accessibilityPreparationAttemptedPID != running.processIdentifier {
            let manualResult = AXUIElementSetAttributeValue(application, "AXManualAccessibility" as CFString, kCFBooleanTrue)
            let enhancedResult: AXError = manualResult == .success ? .success : AXUIElementSetAttributeValue(
                application,
                "AXEnhancedUserInterface" as CFString,
                kCFBooleanTrue
            )
            accessibilityPreparationAttemptedPID = running.processIdentifier
            if enhancedResult == .success {
                try await Task.sleep(for: .milliseconds(150))
            } else {
                logger.error("Could not enable ChatGPT web accessibility manualError=\(manualResult.rawValue) enhancedError=\(enhancedResult.rawValue)")
            }
        }
        guard let window: AXUIElement = value(application, kAXFocusedWindowAttribute) else {
            throw SwitchFailure.noFocusedWindow
        }
        return Context(application: application, window: window)
    }

    private func captureComposerFocus(invocation: HotkeyInvocation) async -> ComposerFocusTarget? {
        guard let context = try? await resolveContext(invocation: invocation),
              let focused: AXUIElement = value(context.application, kAXFocusedUIElementAttribute),
              string(focused, kAXRoleAttribute) == "AXTextArea",
              isDescendant(focused, of: context.window)
        else { return nil }
        return ComposerFocusTarget(element: focused)
    }

    private func modernContext(invocation: HotkeyInvocation) async throws -> (Context, LiveChatGPTSnapshot, ChatGPTModernComposer) {
        let context = try await resolveContext(invocation: invocation)
        let live = chatGPTSnapshot(window: context.window)
        guard let composer = try? ChatGPTModernPlanner.composer(in: live.snapshot) else { throw SwitchFailure.pickerNotFound }
        return (context, live, composer)
    }

    private func modernSelection(invocation: HotkeyInvocation) async throws -> ChatGPTSelection {
        let (_, live, composer) = try await modernContext(invocation: invocation)
        if let power = try? ChatGPTModernPlanner.powerPicker(in: live.snapshot) {
            return power.status.selection
        }
        guard let selection = composer.selection else { throw SwitchFailure.pickerNotFound }
        return selection
    }

    private func waitForModernSelection(
        model: ChatGPTModel, effort: ChatGPTReasoningEffort? = nil, invocation: HotkeyInvocation
    ) async throws -> ChatGPTSelection {
        let end = ContinuousClock().now.advanced(by: deadline)
        while ContinuousClock().now < end {
            try TrustedTargetAction.validate(invocation)
            if let selection = try? await modernSelection(invocation: invocation),
               selection.model == model, effort == nil || selection.effort == effort { return selection }
            try await Task.sleep(for: .milliseconds(50))
        }
        throw SwitchFailure.pickerNotFound
    }

    private func openPowerPicker(invocation: HotkeyInvocation) async throws -> (LiveChatGPTSnapshot, ChatGPTPowerPicker) {
        var (_, live, composer) = try await modernContext(invocation: invocation)
        if let power = try? ChatGPTModernPlanner.powerPicker(in: live.snapshot) { return (live, power) }
        if live.snapshot.byID[composer.controlID]?.expanded == true {
            try await dismissModernPicker(invocation: invocation)
            (_, live, composer) = try await modernContext(invocation: invocation)
        }
        guard let control = live.elements[composer.controlID] else { throw SwitchFailure.pickerNotFound }
        try TrustedTargetAction.press(control, invocation: invocation)
        let end = ContinuousClock().now.advanced(by: deadline)
        while ContinuousClock().now < end {
            let (_, fresh, _) = try await modernContext(invocation: invocation)
            if let power = try? ChatGPTModernPlanner.powerPicker(in: fresh.snapshot) { return (fresh, power) }
            try await Task.sleep(for: .milliseconds(50))
        }
        throw SwitchFailure.pickerNotFound
    }

    private func selectModernModel(_ model: ChatGPTModel, invocation: HotkeyInvocation) async throws -> ChatGPTSelection {
        var (_, live, composer) = try await modernContext(invocation: invocation)
        var items = try? ChatGPTModernPlanner.modelList(in: live.snapshot, composer: composer)
        if items == nil {
            let (powerLive, power) = try await openPowerPicker(invocation: invocation)
            guard let row = powerLive.elements[power.modelActionID] else { throw SwitchFailure.modelRowNotActionable }
            try TrustedTargetAction.press(row, invocation: invocation)
            let end = ContinuousClock().now.advanced(by: deadline)
            while ContinuousClock().now < end {
                (_, live, composer) = try await modernContext(invocation: invocation)
                items = try? ChatGPTModernPlanner.modelList(in: live.snapshot, composer: composer)
                if items != nil { break }
                try await Task.sleep(for: .milliseconds(50))
            }
        }
        guard let id = items?[model], let row = live.elements[id] else { throw SwitchFailure.modelUnavailable(model.rawValue) }
        try TrustedTargetAction.press(row, invocation: invocation)
        return try await waitForModernSelection(model: model, invocation: invocation)
    }

    private func selectModernEffort(_ effort: ChatGPTReasoningEffort, invocation: HotkeyInvocation) async throws -> ChatGPTSelection {
        var (live, power) = try await openPowerPicker(invocation: invocation)
        let model = power.status.selection.model
        var visited = Set<ChatGPTPowerStatus>()
        // Each arrow is a documented semantic Power adjustment, not positional menu
        // navigation. Reacquire and verify its announced model, effort, and bounds each time.
        for _ in 0..<8 {
            if power.status.selection.effort == effort { return power.status.selection }
            guard visited.insert(power.status).inserted,
                  let increase = try? power.status.direction(toward: effort),
                  let control = live.elements[power.powerID] else { throw SwitchFailure.effortUnavailable(effort.rawValue) }
            try TrustedTargetAction.validate(invocation)
            guard AXUIElementSetAttributeValue(control, kAXFocusedAttribute as CFString, kCFBooleanTrue) == .success else {
                throw SwitchFailure.effortRowNotActionable
            }
            // Chromium acknowledges AXFocused before its focused-element reference changes.
            let focusEnd = ContinuousClock().now.advanced(by: .milliseconds(500))
            var focused = false
            while ContinuousClock().now < focusEnd {
                let context = try await resolveContext(invocation: invocation)
                let target: AXUIElement? = value(context.application, kAXFocusedUIElementAttribute)
                if target.map({ CFEqual($0, control) }) == true { focused = true; break }
                try await Task.sleep(for: .milliseconds(25))
            }
            guard focused else { throw SwitchFailure.effortRowNotActionable }
            try TrustedTargetAction.postFocusedKey(keyCode: increase ? 124 : 123, flags: [], invocation: invocation)
            let previous = power.status
            let end = ContinuousClock().now.advanced(by: deadline)
            var changed = false
            while ContinuousClock().now < end {
                let (_, fresh, _) = try await modernContext(invocation: invocation)
                if let observed = try? ChatGPTModernPlanner.powerPicker(in: fresh.snapshot), observed.status != previous {
                    guard observed.status.selection.model == model,
                          observed.status.total == previous.total,
                          observed.status.position == previous.position + (increase ? 1 : -1) else {
                        throw SwitchFailure.effortUnavailable(effort.rawValue)
                    }
                    // A missing intermediate effort must not cause oscillation past the target.
                    if observed.status.selection.effort != effort,
                       (try? observed.status.direction(toward: effort)) != increase {
                        throw SwitchFailure.effortUnavailable(effort.rawValue)
                    }
                    live = fresh; power = observed; changed = true; break
                }
                try await Task.sleep(for: .milliseconds(50))
            }
            guard changed else { throw SwitchFailure.effortUnavailable(effort.rawValue) }
        }
        throw SwitchFailure.effortUnavailable(effort.rawValue)
    }

    private func dismissModernPicker(invocation: HotkeyInvocation) async throws {
        for _ in 0..<3 {
            let (_, live, composer) = try await modernContext(invocation: invocation)
            let powerOpen = (try? ChatGPTModernPlanner.powerPicker(in: live.snapshot)) != nil
            let listOpen = (try? ChatGPTModernPlanner.modelList(in: live.snapshot, composer: composer)) != nil
            guard powerOpen || listOpen else { return }
            try TrustedTargetAction.postFocusedKey(keyCode: 53, flags: [], invocation: invocation)
            try await Task.sleep(for: .milliseconds(100))
        }
        let (_, live, composer) = try await modernContext(invocation: invocation)
        guard (try? ChatGPTModernPlanner.powerPicker(in: live.snapshot)) == nil,
              (try? ChatGPTModernPlanner.modelList(in: live.snapshot, composer: composer)) == nil else {
            throw SwitchFailure.pickerNotFound
        }
    }

    private func openNativePicker(invocation: HotkeyInvocation) async throws -> NativePickerContext {
        let context = try await resolveContext(invocation: invocation)
        if let picker = nativePicker(in: context.window) {
            return picker
        }
        try TrustedTargetAction.postKey(
            keyCode: nativeModelPickerKey,
            flags: [.maskControl, .maskShift],
            invocation: invocation
        )
        let clock = ContinuousClock(); let end = clock.now.advanced(by: deadline)
        while clock.now < end {
            try TrustedTargetAction.validate(invocation)
            let fresh = try await resolveContext(invocation: invocation)
            if let picker = nativePicker(in: fresh.window) { return picker }
            try await Task.sleep(for: .milliseconds(50))
        }
        throw SwitchFailure.pickerNotFound
    }

    private func nativePicker(in window: AXUIElement) -> NativePickerContext? {
        let live = chatGPTSnapshot(window: window)
        guard let picker = try? ChatGPTSurfacePlanner.nativePicker(in: live.snapshot) else { return nil }
        return NativePickerContext(window: window, live: live, picker: picker)
    }

    /// `context` is the fresh snapshot that proved this exact native picker;
    /// delivery still revalidates the captured frontmost window immediately.
    private func dismissNativePicker(_ context: NativePickerContext, invocation: HotkeyInvocation) throws {
        guard AXWindowIdentity.windowID(context.window).map({ $0 == invocation.focusedWindowID }) ?? true else {
            throw SwitchFailure.targetChanged(ApplicationTarget.chatGPT.displayName)
        }
        try TrustedTargetAction.postKey(keyCode: 53, flags: [], invocation: invocation)
    }

    private func execute(_ action: ChatGPTActionTarget, element: AXUIElement, invocation: HotkeyInvocation) throws {
        switch action {
        case .press:
            try TrustedTargetAction.press(element, invocation: invocation)
        case .showMenu:
            try TrustedTargetAction.showMenu(element, invocation: invocation)
        case .click:
            throw SwitchFailure.accessibility("Native picker exposed a non-AX action target.")
        }
    }

    private func element(for action: ChatGPTActionTarget, in live: LiveChatGPTSnapshot) throws -> AXUIElement {
        let id: Int
        switch action {
        case .press(let value), .showMenu(let value), .click(let value): id = value
        }
        guard let element = live.elements[id] else {
            throw SwitchFailure.accessibility("Native picker target disappeared from its snapshot.")
        }
        return element
    }

    private func waitForOwnedMenu(
        containing name: String,
        in root: AXUIElement,
        excluding excluded: AXUIElement?,
        timeout: Duration
    ) async -> AXUIElement? {
        let clock = ContinuousClock(); let end = clock.now.advanced(by: timeout)
        while clock.now < end {
            let candidates = breadthFirst(root: root, maxDepth: 40, maxNodes: 3_500).filter { element in
                guard frame(element) != nil, CFHash(element) != excluded.map(CFHash) else { return false }
                let role = string(element, kAXRoleAttribute)
                let subrole = string(element, kAXSubroleAttribute)
                guard role == kAXMenuRole as String || subrole?.localizedCaseInsensitiveContains("popover") == true else { return false }
                return breadthFirst(root: element, maxDepth: 8, maxNodes: 300).contains { labels($0).contains(name) }
            }
            if candidates.count == 1 { return candidates[0] }
            try? await Task.sleep(for: .milliseconds(50))
        }
        return nil
    }

    private func uniqueActionable(named name: String, in root: AXUIElement) -> AXUIElement? {
        var candidates: [AXUIElement] = []
        var seen = Set<CFHashCode>()
        for element in breadthFirst(root: root, maxDepth: 12, maxNodes: 1_000) where labels(element).contains(name) {
            var candidate: AXUIElement? = element
            for _ in 0..<12 {
                guard let current = candidate else { break }
                if actions(current).contains(kAXPressAction as String),
                   value(current, kAXEnabledAttribute) as Bool? ?? true,
                   seen.insert(CFHash(current)).inserted {
                    candidates.append(current)
                    break
                }
                candidate = value(current, kAXParentAttribute)
            }
        }
        return candidates.count == 1 ? candidates[0] : nil
    }

    private func owningMenu(of element: AXUIElement) -> AXUIElement? {
        var current: AXUIElement? = element
        var visited = Set<CFHashCode>()
        while let value = current, visited.insert(CFHash(value)).inserted {
            if string(value, kAXRoleAttribute) == kAXMenuRole as String { return value }
            current = self.value(value, kAXParentAttribute)
        }
        return nil
    }

    private func isDescendant(_ element: AXUIElement, of ancestor: AXUIElement) -> Bool {
        var current: AXUIElement? = element
        var visited = Set<CFHashCode>()
        for _ in 0..<32 {
            guard let value = current, visited.insert(CFHash(value)).inserted else { return false }
            if CFEqual(value, ancestor) { return true }
            current = self.value(value, kAXParentAttribute)
        }
        return false
    }

    private func logElapsed(_ phase: String, since start: ContinuousClock.Instant) {
        logger.info("phase=\(phase, privacy: .public) elapsed=\(String(describing: start.duration(to: ContinuousClock().now)), privacy: .public)")
    }

    private func chatGPTSnapshot(window: AXUIElement) -> LiveChatGPTSnapshot {
        // Modern task composers occur 28 levels below the window. Bound breadth and
        // depth independently, and preserve traversal edges: AXParent can be unstable.
        var queue: [(AXUIElement, Int?, Int)] = [(window, nil, 0)]
        var elements: [Int: AXUIElement] = [:]
        var nodes: [ChatGPTAXNode] = []
        var visited = Set<CFHashCode>()
        var index = 0
        while index < queue.count && nodes.count < 3_500 {
            let (element, parent, depth) = queue[index]; index += 1
            guard visited.insert(CFHash(element)).inserted else { continue }
            let id = nodes.count
            let role = string(element, kAXRoleAttribute) ?? "AXUnknown"
            let actionNames = actions(element)
            var actionSet = Set<ChatGPTAXAction>()
            if actionNames.contains(kAXPressAction as String) { actionSet.insert(.press) }
            if actionNames.contains(kAXShowMenuAction as String) { actionSet.insert(.showMenu) }
            let control = ["AXMenuItem", "AXPopUpButton", "AXButton"].contains(role)
            let typed = control ? typedLabels(labels(element)) : []
            nodes.append(ChatGPTAXNode(id: id, parentID: parent, role: role, labels: typed,
                actions: actionSet, visible: frame(element) != nil && (value(element, kAXEnabledAttribute) as Bool? ?? true),
                frame: frame(element), expanded: value(element, kAXExpandedAttribute)))
            elements[id] = element
            // Input values and their text descendants are never needed for targeting.
            guard depth < 40, role != "AXTextArea", role != "AXTextField" else { continue }
            let children: [AXUIElement] = value(element, kAXChildrenAttribute) ?? []
            let contents: [AXUIElement] = value(element, kAXContentsAttribute) ?? []
            queue.append(contentsOf: (children + contents).map { ($0, id, depth + 1) })
        }
        let powerRoots = Set(nodes.filter { $0.labels.contains(.power) }.compactMap(\.parentID))
        for index in nodes.indices where nodes[index].role == "AXStaticText" {
            var parent = nodes[index].parentID
            var isPickerText = false
            for _ in 0..<5 {
                guard let id = parent else { break }
                if powerRoots.contains(id) || nodes[id].role == "AXMenuItem" { isPickerText = true; break }
                parent = nodes[id].parentID
            }
            guard isPickerText, let element = elements[index] else { continue }
            let old = nodes[index]
            nodes[index] = ChatGPTAXNode(id: old.id, parentID: old.parentID, role: old.role,
                labels: typedLabels(labels(element)), actions: old.actions, visible: old.visible, frame: old.frame)
        }
        // Legacy native rows may expose their closed labels only on text children.
        for index in nodes.indices where nodes[index].role == "AXMenuItem" {
            var labels = nodes[index].labels
            for child in nodes where child.role == "AXStaticText" {
                var parent = child.parentID
                for _ in 0..<4 {
                    guard let id = parent else { break }
                    if id == index { labels.formUnion(child.labels); break }
                    parent = nodes[id].parentID
                }
            }
            let old = nodes[index]
            nodes[index] = ChatGPTAXNode(id: old.id, parentID: old.parentID, role: old.role,
                labels: labels.subtracting([.unknownText]), actions: old.actions, visible: old.visible, frame: old.frame)
        }
        return LiveChatGPTSnapshot(snapshot: .init(windowFrame: frame(window) ?? .zero, nodes: nodes), elements: elements)
    }

    private func typedLabels(_ values: [String]) -> Set<ChatGPTAXLabel> {
        let labels = values.reduce(into: Set<ChatGPTAXLabel>()) { $0.formUnion(ChatGPTControlLabels.classify($1)) }
        return labels.count > 1 ? labels.subtracting([.unknownText]) : labels
    }

    private func breadthFirst(root: AXUIElement, maxDepth: Int, maxNodes: Int) -> [AXUIElement] {
        var queue: [(AXUIElement, Int)] = [(root, 0)], output: [AXUIElement] = [], index = 0
        var visited = Set<CFHashCode>()
        while index < queue.count && output.count < maxNodes {
            let (element, depth) = queue[index]; index += 1
            guard visited.insert(CFHash(element)).inserted else { continue }
            output.append(element)
            guard depth < maxDepth else { continue }
            let children: [AXUIElement] = value(element, kAXChildrenAttribute) ?? []
            let visibleChildren: [AXUIElement] = value(element, kAXVisibleChildrenAttribute) ?? []
            let contents: [AXUIElement] = value(element, kAXContentsAttribute) ?? []
            queue.append(contentsOf: (children + visibleChildren + contents).map { ($0, depth + 1) })
        }
        return output
    }

    private func labels(_ element: AXUIElement) -> [String] {
        let role = string(element, kAXRoleAttribute)
        guard role != "AXTextArea", role != "AXTextField" else { return [] }
        let attributes = [kAXTitleAttribute, kAXDescriptionAttribute]
            + (role == "AXStaticText" ? [kAXValueAttribute] : [])
        return attributes.compactMap { string(element, $0) }
            .filter { !$0.isEmpty }
    }

    private func string(_ element: AXUIElement, _ attribute: String) -> String? { value(element, attribute) }
    private func actions(_ element: AXUIElement) -> [String] {
        var result: CFArray?
        guard AXUIElementCopyActionNames(element, &result) == .success else { return [] }
        return result as? [String] ?? []
    }
    private func value<T>(_ element: AXUIElement, _ attribute: String) -> T? {
        var result: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, attribute as CFString, &result) == .success else { return nil }
        return result as? T
    }
    private func frame(_ element: AXUIElement) -> CGRect? {
        guard let positionValue: AXValue = value(element, kAXPositionAttribute),
              let sizeValue: AXValue = value(element, kAXSizeAttribute) else { return nil }
        var position = CGPoint.zero, size = CGSize.zero
        guard AXValueGetValue(positionValue, .cgPoint, &position), AXValueGetValue(sizeValue, .cgSize, &size) else { return nil }
        return CGRect(origin: position, size: size)
    }
}
