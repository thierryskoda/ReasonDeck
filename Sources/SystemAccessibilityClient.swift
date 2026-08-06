import AppKit
import ApplicationServices
import Foundation
import os

enum AppConstants {
    static let chatGPTBundleID = "com.openai.codex"
    static let modelLabel = "Model"
    static let effortLabel = "Effort"
}

private final class AXBox: @unchecked Sendable {
    let value: AXUIElement
    init(_ value: AXUIElement) { self.value = value }
}

actor SystemAccessibilityClient: AccessibilityClient {
    private let logger = Logger(subsystem: "com.thierryai.ChatGPTProfileKeys", category: "switching")
    private let deadline: Duration = .seconds(2)
    private let cacheLifetime: Duration = .seconds(1)
    private var cachedContext: (context: Context, expiresAt: ContinuousClock.Instant)?

    func currentPickerTitle() async throws -> String {
        let context = try resolveContext(allowCached: false)
        cache(context)
        return context.picker.title
    }

    func selectModel(_ model: ChatGPTModel) async throws -> String {
        let context = try resolveContext(allowCached: true)
        let row = try await open(context.picker, window: context.window.value, pid: context.pid, expectedRow: AppConstants.modelLabel)
        try press(row, pid: context.pid)
        let item = try await waitForMenuItem(named: model.rawValue, in: context.application.value)
        guard let item else { throw SwitchFailure.modelUnavailable(model.rawValue) }
        try press(item, pid: context.pid)
        cachedContext = nil
        try? await Task.sleep(for: .milliseconds(50))
        dismissMenus(pid: context.pid)
        let picker = try await waitForPicker(containing: model.rawValue, in: context.window.value, phase: "verifying model")
        let updated = Context(application: context.application, window: context.window, picker: picker, pid: context.pid)
        cache(updated)
        return picker.title
    }

    func selectEffort(_ effort: ReasoningEffort) async throws -> String {
        let context = try resolveContext(allowCached: true)
        let row = try await open(context.picker, window: context.window.value, pid: context.pid, expectedRow: AppConstants.effortLabel)
        try press(row, pid: context.pid)
        let item = try await waitForMenuItem(named: effort.rawValue, in: context.application.value)
        guard let item else { throw SwitchFailure.effortUnavailable(effort.rawValue) }
        try press(item, pid: context.pid)
        cachedContext = nil
        try? await Task.sleep(for: .milliseconds(50))
        dismissMenus(pid: context.pid)
        let picker = try await waitForPicker(containing: effort.rawValue, in: context.window.value, phase: "verifying effort")
        let updated = Context(application: context.application, window: context.window, picker: picker, pid: context.pid)
        cache(updated)
        return picker.title
    }

    private struct Context { let application: AXBox; let window: AXBox; let picker: Picker; let pid: pid_t }
    private struct Picker { let element: AXUIElement; let title: String; let clickPoint: CGPoint? }

    private func resolveContext(allowCached: Bool) throws -> Context {
        guard AXIsProcessTrusted() else { throw SwitchFailure.permissionMissing }
        guard let running = NSWorkspace.shared.frontmostApplication,
              running.bundleIdentifier == AppConstants.chatGPTBundleID
        else { throw SwitchFailure.chatGPTNotFrontmost }
        let clock = ContinuousClock()
        if allowCached,
           let cachedContext,
           cachedContext.context.pid == running.processIdentifier,
           clock.now < cachedContext.expiresAt,
           !(value(cachedContext.context.window.value, kAXMinimizedAttribute) as Bool? ?? false) {
            return cachedContext.context
        }
        let application = AXUIElementCreateApplication(running.processIdentifier)
        let focused: AXUIElement? = value(application, kAXFocusedWindowAttribute)
        let windows: [AXUIElement] = value(application, kAXWindowsAttribute) ?? []
        if let focused, let picker = findPicker(in: focused, logFailure: false) {
            return Context(application: AXBox(application), window: AXBox(focused), picker: picker, pid: running.processIdentifier)
        }
        let viable = windows.compactMap { window -> (AXUIElement, Picker)? in
            let minimized: Bool = value(window, kAXMinimizedAttribute) ?? false
            guard !minimized, let picker = findPicker(in: window, logFailure: false) else { return nil }
            return (window, picker)
        }
        logger.debug("Window resolution total=\(windows.count) viable=\(viable.count) focusedHadPicker=false")
        if viable.count == 1, let (window, picker) = viable.first {
            return Context(application: AXBox(application), window: AXBox(window), picker: picker, pid: running.processIdentifier)
        }
        if windows.count == 1, let only = windows.first {
            _ = findPicker(in: only, logFailure: true)
            throw SwitchFailure.pickerNotFound
        }
        throw SwitchFailure.noFocusedWindow
    }

    private func cache(_ context: Context) {
        cachedContext = (context, ContinuousClock().now.advanced(by: cacheLifetime))
    }

    private func findPicker(in root: AXUIElement, logFailure: Bool) -> Picker? {
        let elements = breadthFirst(root: root, maxDepth: 24, maxNodes: 10_000, newestFirst: true)
        for element in elements {
            let role = string(element, kAXRoleAttribute)
            guard role == kAXPopUpButtonRole as String || role == kAXButtonRole as String else { continue }
            let controlLabels = breadthFirst(root: element, maxDepth: 4, maxNodes: 80)
                .flatMap { labels($0) }
            guard ChatGPTModel.allCases.contains(where: { model in
                controlLabels.contains(where: { ProfileSelection.containsOrdered($0, model.rawValue) })
            })
            else { continue }
            logger.debug("Composer picker found role=\(role ?? "unknown", privacy: .public) nodes=\(elements.count)")
            return Picker(element: element, title: controlLabels.joined(separator: " "), clickPoint: nil)
        }
        if let windowFrame = frame(root) {
            let candidates = elements.compactMap { element -> (AXUIElement, CGRect)? in
                guard string(element, kAXRoleAttribute) == kAXGroupRole as String,
                      let candidateFrame = frame(element),
                      candidateFrame.width >= 350,
                      candidateFrame.width <= min(1_200, windowFrame.width * 0.8),
                      candidateFrame.height >= 50,
                      candidateFrame.height <= 200,
                      candidateFrame.minY > windowFrame.maxY - 250
                else { return nil }
                return (element, candidateFrame)
            }.sorted { $0.1.width < $1.1.width }
            for (element, composerFrame) in candidates {
                let title = profileTitle(in: element)
                guard !title.isEmpty else { continue }
                let point = CGPoint(x: composerFrame.maxX - 120, y: composerFrame.maxY - 20)
                logger.debug("Composer picker found by geometry composerWidth=\(Int(composerFrame.width))")
                return Picker(element: element, title: title, clickPoint: point)
            }
        }
        if logFailure {
            let controlCandidates = elements.reduce(into: 0) { count, element in
                let role = string(element, kAXRoleAttribute)
                if role == kAXPopUpButtonRole as String || role == kAXButtonRole as String { count += 1 }
            }
            logger.error("Composer picker missing nodes=\(elements.count) buttonCandidates=\(controlCandidates)")
        }
        return nil
    }

    private func open(_ picker: Picker, window: AXUIElement, pid: pid_t, expectedRow: String) async throws -> AXUIElement {
        if picker.clickPoint == nil {
            _ = AXUIElementPerformAction(picker.element, kAXPressAction as CFString)
            if let row = await waitForActionable(named: expectedRow, in: window, timeout: .milliseconds(350)) { return row }
        }
        let point: CGPoint
        if let clickPoint = picker.clickPoint {
            point = clickPoint
        } else {
            guard let pickerFrame = frame(picker.element) else { throw SwitchFailure.accessibility("Picker has no usable frame.") }
            point = CGPoint(x: pickerFrame.midX, y: pickerFrame.midY)
        }
        click(point, pid: pid)
        guard let row = await waitForActionable(named: expectedRow, in: window, timeout: deadline) else {
            if expectedRow == AppConstants.modelLabel { throw SwitchFailure.modelRowNotActionable }
            if expectedRow == AppConstants.effortLabel { throw SwitchFailure.effortRowNotActionable }
            throw SwitchFailure.deadlineExceeded("opening the profile menu")
        }
        return row
    }

    private func click(_ point: CGPoint, pid _: pid_t) {
        // Chromium ignored process-targeted mouse delivery for this control in live tests.
        // Use the validated composer-relative point at HID level, then restore the pointer.
        let originalCursorPosition = CGEvent(source: nil)?.location
        guard let down = CGEvent(mouseEventSource: nil, mouseType: .leftMouseDown, mouseCursorPosition: point, mouseButton: .left),
              let up = CGEvent(mouseEventSource: nil, mouseType: .leftMouseUp, mouseCursorPosition: point, mouseButton: .left)
        else { return }
        down.flags = []; up.flags = []; down.post(tap: .cghidEventTap); up.post(tap: .cghidEventTap)
        if let originalCursorPosition { CGWarpMouseCursorPosition(originalCursorPosition) }
    }

    private func dismissMenus(pid: pid_t) {
        guard let down = CGEvent(keyboardEventSource: nil, virtualKey: 53, keyDown: true),
              let up = CGEvent(keyboardEventSource: nil, virtualKey: 53, keyDown: false)
        else { return }
        down.flags = []; up.flags = []; down.postToPid(pid); up.postToPid(pid)
    }

    private func findActionable(named name: String, in root: AXUIElement) -> AXUIElement? {
        for element in breadthFirst(root: root, maxDepth: 18, maxNodes: 3_500) where labels(element).contains(name) {
            var candidate: AXUIElement? = element
            var nearestFramedAncestor: AXUIElement?
            for _ in 0..<12 {
                guard let current = candidate else { break }
                if nearestFramedAncestor == nil, frame(current) != nil { nearestFramedAncestor = current }
                if actions(current).contains(kAXPressAction as String), (value(current, kAXEnabledAttribute) as Bool? ?? true) { return current }
                candidate = value(current, kAXParentAttribute)
            }
            if let nearestFramedAncestor { return nearestFramedAncestor }
        }
        return nil
    }

    private func waitForActionable(named name: String, in root: AXUIElement, timeout: Duration) async -> AXUIElement? {
        let clock = ContinuousClock(); let end = clock.now.advanced(by: timeout)
        while clock.now < end {
            if let element = findActionable(named: name, in: root) { return element }
            try? await Task.sleep(for: .milliseconds(50))
        }
        return nil
    }

    private func waitForMenuItem(named name: String, in root: AXUIElement) async throws -> AXUIElement? {
        let clock = ContinuousClock(); let end = clock.now.advanced(by: deadline)
        while clock.now < end {
            let candidates = breadthFirst(root: root, maxDepth: 18, maxNodes: 3_500).filter {
                labels($0).contains(name) && frame($0) != nil && (value($0, kAXEnabledAttribute) as Bool? ?? true)
            }
            if let item = candidates.max(by: { (frame($0)?.minX ?? 0) < (frame($1)?.minX ?? 0) }) { return item }
            try await Task.sleep(for: .milliseconds(50))
        }
        return nil
    }

    private func waitForPicker(containing value: String, in root: AXUIElement, phase: String) async throws -> Picker {
        let clock = ContinuousClock(); let end = clock.now.advanced(by: deadline)
        while clock.now < end {
            if let picker = findPicker(in: root, logFailure: false),
               ProfileSelection.containsOrdered(picker.title, value) {
                return picker
            }
            try await Task.sleep(for: .milliseconds(50))
        }
        throw SwitchFailure.deadlineExceeded(phase)
    }

    private func press(_ element: AXUIElement, pid: pid_t) throws {
        let error = AXUIElementPerformAction(element, kAXPressAction as CFString)
        if error == .success { return }
        guard let elementFrame = frame(element) else { throw SwitchFailure.accessibility("AXPress error \(error.rawValue)") }
        click(CGPoint(x: elementFrame.midX, y: elementFrame.midY), pid: pid)
    }

    private func breadthFirst(root: AXUIElement, maxDepth: Int, maxNodes: Int, newestFirst: Bool = false) -> [AXUIElement] {
        var queue: [(AXUIElement, Int)] = [(root, 0)], output: [AXUIElement] = [], index = 0
        var visited = Set<CFHashCode>()
        while index < queue.count && output.count < maxNodes {
            let (element, depth) = queue[index]; index += 1
            let identity = CFHash(element)
            guard visited.insert(identity).inserted else { continue }
            output.append(element)
            guard depth < maxDepth else { continue }
            let children: [AXUIElement] = value(element, kAXChildrenAttribute) ?? []
            let visibleChildren: [AXUIElement] = value(element, kAXVisibleChildrenAttribute) ?? []
            let contents: [AXUIElement] = value(element, kAXContentsAttribute) ?? []
            let related = children + visibleChildren + contents
            let orderedChildren = newestFirst ? Array(related.reversed()) : related
            queue.append(contentsOf: orderedChildren.map { ($0, depth + 1) })
        }
        return output
    }

    private func profileTitle(in root: AXUIElement) -> String {
        let text = breadthFirst(root: root, maxDepth: 12, maxNodes: 600)
            .flatMap { labels($0) }
            .joined(separator: " ")
        let model = ProfileSelection.detectedModel(in: text)?.rawValue
        let effort = ProfileSelection.detectedEffort(in: text)?.rawValue
        return [model, effort].compactMap { $0 }.joined(separator: " ")
    }
    private func labels(_ element: AXUIElement) -> [String] {
        [kAXTitleAttribute, kAXDescriptionAttribute, kAXValueAttribute]
            .compactMap { string(element, $0) }
            .filter { !$0.isEmpty }
    }
    private func string(_ element: AXUIElement, _ attribute: String) -> String? { value(element, attribute) }
    private func actions(_ element: AXUIElement) -> [String] { var result: CFArray?; guard AXUIElementCopyActionNames(element, &result) == .success else { return [] }; return result as? [String] ?? [] }
    private func value<T>(_ element: AXUIElement, _ attribute: String) -> T? { var result: CFTypeRef?; guard AXUIElementCopyAttributeValue(element, attribute as CFString, &result) == .success else { return nil }; return result as? T }
    private func frame(_ element: AXUIElement) -> CGRect? {
        guard let positionValue: AXValue = value(element, kAXPositionAttribute),
              let sizeValue: AXValue = value(element, kAXSizeAttribute) else { return nil }
        var position = CGPoint.zero, size = CGSize.zero
        guard AXValueGetValue(positionValue, .cgPoint, &position), AXValueGetValue(sizeValue, .cgSize, &size) else { return nil }
        return CGRect(origin: position, size: size)
    }
}
