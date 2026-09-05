import AppKit
import ApplicationServices
import Foundation
import os

enum AntigravityPickerPlan: Equatable, Sendable {
    case alreadyApplied
    case pressMenuItem(titled: String)
    case failure(SwitchFailure)
}

enum AntigravityPickerState {
    static let currentTitlePrefix = "Select model, current: "
    private static let fastBadgeModels: Set<AntigravityModel> = [
        .gemini38Flash, .gemini37Flash, .gemini36Flash,
    ]

    static func menuItemTitle(for selection: AntigravitySelection) -> String {
        "\(selection.model.rawValue) \(selection.effort.rawValue)"
    }

    static func selection(fromCurrentTitle title: String) -> AntigravitySelection? {
        guard title.hasPrefix(currentTitlePrefix) else { return nil }
        return selection(fromCanonicalTitle: String(title.dropFirst(currentTitlePrefix.count)))
    }

    static func plan(
        currentTitle: String,
        menuItemTitles: [String],
        requested: AntigravitySelection
    ) -> AntigravityPickerPlan {
        if selection(fromCurrentTitle: currentTitle) == requested {
            return .alreadyApplied
        }

        let expected = menuItemTitle(for: requested)
        let acceptedRows = acceptedMenuItemTitles(for: requested)
        let exactMatches = menuItemTitles.filter(acceptedRows.contains)
        guard exactMatches.count <= 1 else {
            return .failure(.accessibility("Antigravity exposed multiple exact picker rows."))
        }
        guard exactMatches.count == 1 else {
            return .failure(.modelUnavailable(expected))
        }
        return .pressMenuItem(titled: exactMatches[0])
    }

    static func selection(fromMenuItemTitle title: String) -> AntigravitySelection? {
        for model in AntigravityModel.allCases {
            for effort in AntigravityEffort.allCases {
                let candidate = AntigravitySelection(model: model, effort: effort)
                if acceptedMenuItemTitles(for: candidate).contains(title) {
                    return candidate
                }
            }
        }
        return nil
    }

    private static func selection(fromCanonicalTitle title: String) -> AntigravitySelection? {
        for model in AntigravityModel.allCases {
            for effort in AntigravityEffort.allCases {
                let candidate = AntigravitySelection(model: model, effort: effort)
                if menuItemTitle(for: candidate) == title {
                    return candidate
                }
            }
        }
        return nil
    }

    /// Antigravity 2.8.1 appends an exact `Fast` badge to three Medium Flash rows,
    /// while its authoritative current-selection title omits that presentation badge.
    private static func acceptedMenuItemTitles(for selection: AntigravitySelection) -> Set<String> {
        let canonical = menuItemTitle(for: selection)
        guard selection.effort == .medium, fastBadgeModels.contains(selection.model) else {
            return [canonical]
        }
        return [canonical, "\(canonical) Fast"]
    }
}

enum AntigravityApplyOutcome: Equatable, Sendable {
    case applied(model: AntigravityModel, effort: AntigravityEffort)
    case failure(SwitchFailure)
}

struct AntigravityPickerObservation: Equatable, Sendable {
    let current: AntigravitySelection
    let available: [AntigravitySelection]
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
    private let pickerTimeout: Duration = .seconds(2)
    private let pollInterval: Duration = .milliseconds(50)

    func apply(_ selection: AntigravitySelection, invocation: HotkeyInvocation) async -> AntigravityApplyOutcome {
        do {
            let picker = try await openPicker(invocation: invocation)
            let menuTitles = picker.menuItems.map(\.title)
            switch AntigravityPickerState.plan(
                currentTitle: picker.currentTitle,
                menuItemTitles: menuTitles,
                requested: selection
            ) {
            case .alreadyApplied:
                let observed = try observedSelection(in: picker)
                try await dismissOpenPicker(invocation: invocation)
                return .applied(model: observed.model, effort: observed.effort)
            case .pressMenuItem(let title):
                let matches = picker.menuItems.filter { $0.title == title }
                guard matches.count == 1 else {
                    throw SwitchFailure.accessibility("Antigravity exact picker row became ambiguous.")
                }
                logger.info("Selecting Antigravity profile: \(title, privacy: .public)")
                try TrustedTargetAction.press(matches[0].element, invocation: invocation)
                try await waitForPickerToClose(invocation: invocation)
            case .failure(let failure):
                throw failure
            }

            // Reopening produces a fresh owned picker whose title proves both model and effort.
            let verificationPicker = try await openPicker(invocation: invocation)
            let observed = try observedSelection(in: verificationPicker)
            guard observed == selection else {
                try await dismissOpenPicker(invocation: invocation)
                throw SwitchFailure.verificationMismatch(
                    expected: AntigravityPickerState.menuItemTitle(for: selection),
                    observed: AntigravityPickerState.menuItemTitle(for: observed)
                )
            }
            try await dismissOpenPicker(invocation: invocation)
            return .applied(model: observed.model, effort: observed.effort)
        } catch let failure as SwitchFailure {
            try? await dismissVerifiedPickerIfNeeded(invocation: invocation)
            return .failure(failure)
        } catch {
            try? await dismissVerifiedPickerIfNeeded(invocation: invocation)
            return .failure(.accessibility(String(describing: error)))
        }
    }

    /// Supports the opt-in signed live check without trusting the apply result or leaving
    /// the user's original Antigravity selection unrestored after the test.
    func observePickerState(invocation: HotkeyInvocation) async throws -> AntigravityPickerObservation {
        do {
            let picker = try await openPicker(invocation: invocation)
            let observation = AntigravityPickerObservation(
                current: try observedSelection(in: picker),
                available: picker.menuItems.compactMap {
                    AntigravityPickerState.selection(fromMenuItemTitle: $0.title)
                }
            )
            try await dismissOpenPicker(invocation: invocation)
            return observation
        } catch {
            try? await dismissVerifiedPickerIfNeeded(invocation: invocation)
            throw error
        }
    }

    private struct PickerMenuItem {
        let title: String
        let element: AXUIElement
    }

    private struct OpenPicker {
        let currentTitle: String
        let menuItems: [PickerMenuItem]
    }

    private struct RawNode {
        let id: CFHashCode
        let parentID: CFHashCode?
        let element: AXUIElement
        let role: String
        let title: String?
        let actionable: Bool
        let visible: Bool
    }

    private func openPicker(invocation: HotkeyInvocation) async throws -> OpenPicker {
        if let picker = try openPickerSnapshot(invocation: invocation) { return picker }
        try TrustedTargetAction.postFocusedCommandSlash(invocation: invocation)

        let clock = ContinuousClock()
        let end = clock.now.advanced(by: pickerTimeout)
        while clock.now < end {
            if let picker = try openPickerSnapshot(invocation: invocation) { return picker }
            try await Task.sleep(for: pollInterval)
        }
        throw SwitchFailure.pickerNotFound
    }

    private func waitForPickerToClose(invocation: HotkeyInvocation) async throws {
        let clock = ContinuousClock()
        let end = clock.now.advanced(by: pickerTimeout)
        while clock.now < end {
            if try openPickerSnapshot(invocation: invocation) == nil { return }
            try await Task.sleep(for: pollInterval)
        }
        throw SwitchFailure.deadlineExceeded("waiting for Antigravity’s verified model picker to close")
    }

    private func dismissOpenPicker(invocation: HotkeyInvocation) async throws {
        // Antigravity may close the verified picker itself after its current title is read.
        // An already-closed picker is the desired terminal UI state; never send Escape blindly.
        guard try openPickerSnapshot(invocation: invocation) != nil else { return }
        try TrustedTargetAction.postFocusedKey(keyCode: 53, flags: [], invocation: invocation)
        try await waitForPickerToClose(invocation: invocation)
    }

    /// Cleanup sends Escape only while a fresh snapshot still proves ownership of Antigravity's picker.
    private func dismissVerifiedPickerIfNeeded(invocation: HotkeyInvocation) async throws {
        guard try openPickerSnapshot(invocation: invocation) != nil else { return }
        try TrustedTargetAction.postFocusedKey(keyCode: 53, flags: [], invocation: invocation)
    }

    private func observedSelection(in picker: OpenPicker) throws -> AntigravitySelection {
        guard let selection = AntigravityPickerState.selection(fromCurrentTitle: picker.currentTitle) else {
            throw SwitchFailure.verificationMismatch(
                expected: "exact Antigravity model and effort",
                observed: "unrecognized picker state"
            )
        }
        return selection
    }

    private func openPickerSnapshot(invocation: HotkeyInvocation) throws -> OpenPicker? {
        try TrustedTargetAction.validate(invocation)
        let application = AXUIElementCreateApplication(invocation.pid)
        guard let window: AXUIElement = value(application, kAXFocusedWindowAttribute),
              AXWindowIdentity.focusedWindowID(application: application, pid: invocation.pid)
                == invocation.focusedWindowID
        else { throw SwitchFailure.targetChanged(ApplicationTarget.antigravity.displayName) }

        // Antigravity 2.8.1 nests the owned picker group 23 levels below the focused window.
        // Keep the scan bounded while leaving a small structural-drift margin.
        let nodes = rawNodes(root: window, maxDepth: 32, maxNodes: 5_000)
        let currentNodes = nodes.filter {
            $0.visible && $0.title.flatMap(AntigravityPickerState.selection(fromCurrentTitle:)) != nil
        }
        let menuNodes = nodes.filter {
            $0.role == kAXMenuItemRole as String && $0.visible && $0.actionable
                && $0.title.flatMap(AntigravityPickerState.selection(fromMenuItemTitle:)) != nil
        }
        let contexts = currentNodes.compactMap { current -> OpenPicker? in
            let descendants = menuNodes.filter { isDescendant($0.id, of: current.id, in: nodes) }
            let distinctModels = Set(descendants.compactMap {
                $0.title.flatMap(AntigravityPickerState.selection(fromMenuItemTitle:))?.model
            })
            guard distinctModels.count >= 2, let currentTitle = current.title else { return nil }
            return OpenPicker(
                currentTitle: currentTitle,
                menuItems: descendants.compactMap { node in
                    node.title.map { PickerMenuItem(title: $0, element: node.element) }
                }
            )
        }
        guard contexts.count <= 1 else {
            throw SwitchFailure.accessibility("Antigravity exposed multiple verified model pickers.")
        }
        return contexts.first
    }

    /// Reads titles only from allowlisted control roles and retains only closed model/effort labels.
    /// Editor and transcript text nodes are never inspected or collected.
    private func rawNodes(root: AXUIElement, maxDepth: Int, maxNodes: Int) -> [RawNode] {
        var queue: [(AXUIElement, CFHashCode?, Int)] = [(root, nil, 0)]
        var output: [RawNode] = []
        var visited = Set<CFHashCode>()
        var index = 0
        let titledRoles = Set([
            kAXGroupRole as String,
            kAXButtonRole as String,
            kAXPopUpButtonRole as String,
            kAXMenuItemRole as String,
        ])

        while index < queue.count, output.count < maxNodes {
            let (element, parentID, depth) = queue[index]
            index += 1
            let id = CFHash(element)
            guard visited.insert(id).inserted else { continue }
            let role: String = value(element, kAXRoleAttribute) ?? ""
            let hidden: Bool = value(element, "AXHidden") ?? false
            let enabled: Bool = value(element, kAXEnabledAttribute) ?? true
            let actionNames = actions(element)
            let candidateTitle: String? = titledRoles.contains(role)
                ? value(element, kAXTitleAttribute) : nil
            let title: String?
            if let candidateTitle,
               AntigravityPickerState.selection(fromCurrentTitle: candidateTitle) != nil
                || AntigravityPickerState.selection(fromMenuItemTitle: candidateTitle) != nil {
                title = candidateTitle
            } else {
                title = nil
            }
            output.append(RawNode(
                id: id,
                parentID: parentID,
                element: element,
                role: role,
                title: title,
                actionable: actionNames.contains(kAXPressAction as String),
                visible: !hidden && enabled
            ))
            guard depth < maxDepth else { continue }
            let children: [AXUIElement] = value(element, kAXChildrenAttribute) ?? []
            let visibleChildren: [AXUIElement] = value(element, kAXVisibleChildrenAttribute) ?? []
            queue.append(contentsOf: (children + visibleChildren).map { ($0, id, depth + 1) })
        }
        return output
    }

    private func isDescendant(_ nodeID: CFHashCode, of ancestorID: CFHashCode, in nodes: [RawNode]) -> Bool {
        let byID = Dictionary(uniqueKeysWithValues: nodes.map { ($0.id, $0) })
        var current = byID[nodeID]?.parentID
        var visited = Set<CFHashCode>()
        while let id = current, visited.insert(id).inserted {
            if id == ancestorID { return true }
            current = byID[id]?.parentID
        }
        return false
    }

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
}
