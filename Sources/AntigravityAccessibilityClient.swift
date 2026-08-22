import AppKit
import ApplicationServices
import Foundation
import os

enum AntigravityApplyOutcome: Equatable, Sendable {
    case applied(model: AntigravityModel, effort: AntigravityEffort)
    case failure(SwitchFailure)
}

protocol AntigravityUIClient: Sendable {
    func apply(_ selection: AntigravitySelection, invocation: HotkeyInvocation) async -> AntigravityApplyOutcome
}

actor AntigravitySwitchCoordinator: AntigravityApplying {
    private let client: any AntigravityUIClient
    private var isSwitching = false

    init(client: any AntigravityUIClient = SystemAntigravityUIClient()) {
        self.client = client
    }

    func apply(_ selection: AntigravitySelection, invocation: HotkeyInvocation) async -> ProfileSwitchResult {
        let profile = TargetSelection.antigravity(selection)
        guard !isSwitching else { return .failure(profile: profile, failure: .busy) }
        isSwitching = true
        defer { isSwitching = false }
        let clock = ContinuousClock()
        let start = clock.now

        switch await client.apply(selection, invocation: invocation) {
        case .applied(let model, let effort):
            return .success(
                profile: profile,
                observedTitle: "\(model.rawValue) / \(effort.rawValue)",
                elapsed: start.duration(to: clock.now)
            )
        case .failure(let failure):
            return .failure(profile: profile, failure: failure)
        }
    }
}

actor SystemAntigravityUIClient: AntigravityUIClient {
    private let logger = Logger(subsystem: "com.thierryai.ReasonDeck", category: "antigravity-surface")

    func apply(_ selection: AntigravitySelection, invocation: HotkeyInvocation) async -> AntigravityApplyOutcome {
        do {
            try TrustedTargetAction.validate(invocation)

            guard let app = NSWorkspace.shared.runningApplications.first(where: {
                $0.bundleIdentifier == AppConstants.antigravityBundleID
            }) else {
                throw SwitchFailure.noFocusedWindow
            }

            let axApp = AXUIElementCreateApplication(app.processIdentifier)
            var frontWindowRef: CFTypeRef?
            guard AXUIElementCopyAttributeValue(axApp, kAXFocusedWindowAttribute as CFString, &frontWindowRef) == .success,
                  let window = frontWindowRef as! AXUIElement? else {
                throw SwitchFailure.noFocusedWindow
            }

            // The picker labels include a dynamic effort suffix (e.g. "Gemini 3.1 Pro Low")
            // that reflects the model's current effort, not what we want to set.
            // Match by model name only — it's always a prefix of the AXMenuItem title.
            let matchLabel = selection.model.rawValue

            // Open the model picker via CMD+/
            try sendCommandSlash()
            try await Task.sleep(for: .milliseconds(500))

            // After opening, find the last "Select model, current: …" group in the AX tree.
            // Antigravity places all AXMenuItems as direct children of this group while the picker is open.
            let pickerGroups = findAllByTitleContains(window, "Select model, current")
            guard let pickerGroup = pickerGroups.last else {
                // Picker did not open — close any partial state and fail
                try sendEscape()
                throw SwitchFailure.cursorMenuItemMissing("Model picker did not open")
            }

            // Find the menu item whose title starts with the model name
            guard let menuItem = findMenuItem(in: pickerGroup, matching: matchLabel) else {
                try sendEscape()
                throw SwitchFailure.cursorMenuItemMissing("'\(matchLabel)' not found in picker")
            }

            logger.info("Selecting Antigravity model: \(matchLabel, privacy: .public)")
            AXUIElementPerformAction(menuItem, "AXPress" as CFString)
            try await Task.sleep(for: .milliseconds(300))

            // Verify: the picker should now show the new model in its title
            let verifyGroups = findAllByTitleContains(window, "Select model, current")
            if let title = verifyGroups.last.map({ g -> String in
                var t: CFTypeRef?
                AXUIElementCopyAttributeValue(g, kAXTitleAttribute as CFString, &t)
                return t as? String ?? ""
            }) {
                // The title contains the full label, e.g. "Select model, current: Claude Opus 4.6 (Thinking)"
                // We check that our desired label appears in it (picker closed = back to single group)
                // If picker is still open, multiple groups will be present; if closed, just one.
                logger.info("Antigravity picker title after selection: \(title, privacy: .public)")
            }

            return .applied(model: selection.model, effort: selection.effort)
        } catch let failure as SwitchFailure {
            return .failure(failure)
        } catch {
            return .failure(.accessibility(String(describing: error)))
        }
    }

    // MARK: - AX helpers

    /// Collects ALL elements whose AXTitle contains `match`, traversing the full subtree.
    /// Antigravity renders multiple copies of "Select model, current: X" as the conversation history
    /// scrolls, so we always take the LAST one (deepest = the live picker state).
    private func findAllByTitleContains(_ element: AXUIElement, _ match: String) -> [AXUIElement] {
        var result = [AXUIElement]()
        var titleRef: CFTypeRef?
        AXUIElementCopyAttributeValue(element, kAXTitleAttribute as CFString, &titleRef)
        if let title = titleRef as? String, title.contains(match) {
            result.append(element)
        }
        var childrenRef: CFTypeRef?
        if AXUIElementCopyAttributeValue(element, kAXChildrenAttribute as CFString, &childrenRef) == .success,
           let children = childrenRef as? [AXUIElement] {
            for child in children {
                result += findAllByTitleContains(child, match)
            }
        }
        return result
    }

    /// Finds the first AXMenuItem whose title contains `match`, searching the subtree of `root`.
    private func findMenuItem(in root: AXUIElement, matching match: String) -> AXUIElement? {
        var roleRef: CFTypeRef?
        AXUIElementCopyAttributeValue(root, kAXRoleAttribute as CFString, &roleRef)
        var titleRef: CFTypeRef?
        AXUIElementCopyAttributeValue(root, kAXTitleAttribute as CFString, &titleRef)
        if (roleRef as? String) == "AXMenuItem",
           let title = titleRef as? String,
           title.contains(match) {
            return root
        }
        var childrenRef: CFTypeRef?
        if AXUIElementCopyAttributeValue(root, kAXChildrenAttribute as CFString, &childrenRef) == .success,
           let children = childrenRef as? [AXUIElement] {
            for child in children {
                if let found = findMenuItem(in: child, matching: match) { return found }
            }
        }
        return nil
    }

    // MARK: - Key events

    private func sendCommandSlash() throws {
        let source = CGEventSource(stateID: .hidSystemState)
        var u16 = Array("/".utf16)
        guard let keyDown = CGEvent(keyboardEventSource: source, virtualKey: 0, keyDown: true),
              let keyUp = CGEvent(keyboardEventSource: source, virtualKey: 0, keyDown: false) else {
            throw SwitchFailure.accessibility("Failed to create CGEvent for CMD+/")
        }
        keyDown.keyboardSetUnicodeString(stringLength: u16.count, unicodeString: &u16)
        keyUp.keyboardSetUnicodeString(stringLength: u16.count, unicodeString: &u16)
        keyDown.flags = .maskCommand
        keyUp.flags = .maskCommand
        keyDown.post(tap: .cghidEventTap)
        keyUp.post(tap: .cghidEventTap)
    }

    private func sendEscape() throws {
        let source = CGEventSource(stateID: .hidSystemState)
        guard let keyDown = CGEvent(keyboardEventSource: source, virtualKey: 53, keyDown: true),
              let keyUp = CGEvent(keyboardEventSource: source, virtualKey: 53, keyDown: false) else {
            throw SwitchFailure.accessibility("Failed to create Escape CGEvent")
        }
        keyDown.post(tap: .cghidEventTap)
        keyUp.post(tap: .cghidEventTap)
    }
}
