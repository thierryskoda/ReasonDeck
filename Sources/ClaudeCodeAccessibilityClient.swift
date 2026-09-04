import AppKit
import ApplicationServices
import Foundation
import os

enum ClaudeChatLabels {
    private static let composerEfforts: [(label: String, effort: ClaudeCodeEffort)] = [
        ("Low", .low),
        ("Medium", .medium),
        ("High", .high),
        ("Extra", .extraHigh),
        ("Max", .max),
        // Claude can repeat the cohort-specific usage copy in the closed composer
        // title. Allowlist the full observed title instead of accepting a prefix.
        ("Max 2.5× or more usage", .max),
        ("Max 3.5× or more usage", .max),
    ]

    private static let pickerModels: [String: ClaudeCodeModel] = [
        "Fable 5 Requires usage credits For your toughest challenges": .fable5,
        "Fable 5 Requires usage credits": .fable5,
        "Opus 5 For complex tasks": .opus5,
        "Opus 5": .opus5,
        "Sonnet 5 Most efficient for everyday tasks": .sonnet5,
        "Sonnet 5": .sonnet5,
        "Haiku 4.5 Fastest for quick answers": .haiku45,
        "Haiku 4.5": .haiku45,
    ]

    private static let pickerEfforts: [(label: String, effort: ClaudeCodeEffort)] = [
        ("Low", .low),
        ("Medium", .medium),
        ("Medium Default", .medium),
        ("High", .high),
        ("High Default", .high),
        ("Extra", .extraHigh),
        // Claude sometimes appends cohort-specific usage copy to Max. Keep each
        // observed full label allowlisted instead of weakening this to prefix matching.
        ("Max", .max),
        ("Max 2.5× or more usage", .max),
        ("Max 3.5× or more usage", .max),
    ]

    static func selection(inComposerTitle title: String) -> ClaudeCodeSelection? {
        for model in ClaudeCodeModel.allCases {
            for candidate in composerEfforts where title == "Model: \(model.rawValue) \(candidate.label)" {
                return ClaudeCodeSelection(model: model, effort: candidate.effort)
            }
        }
        return nil
    }

    static func model(inComposerTitle title: String) -> ClaudeCodeModel? {
        if let selection = selection(inComposerTitle: title) { return selection.model }
        return title == "Model: Haiku 4.5 Extended" ? .haiku45 : nil
    }

    static func effort(inComposerTitle title: String) -> ClaudeCodeEffort? {
        selection(inComposerTitle: title)?.effort
    }

    static func model(inPickerRow label: String) -> ClaudeCodeModel? {
        pickerModels[label]
    }

    static func effort(inPickerRow label: String) -> ClaudeCodeEffort? {
        pickerEfforts.first(where: { $0.label == label })?.effort
    }

    static func pickerLabel(for effort: ClaudeCodeEffort) -> String? {
        composerEfforts.first(where: { $0.effort == effort })?.label
    }

    static func pickerRowLabels(for effort: ClaudeCodeEffort) -> Set<String> {
        Set(pickerEfforts.filter { $0.effort == effort }.map(\.label))
    }
}

enum ClaudeChatModelLocation: Equatable {
    case root
    case moreModels
}

enum ClaudeChatModelRouting {
    static func location(
        for model: ClaudeCodeModel,
        rootModels: Set<ClaudeCodeModel>,
        hasMoreModels: Bool
    ) -> ClaudeChatModelLocation? {
        if rootModels.contains(model) { return .root }
        return hasMoreModels ? .moreModels : nil
    }
}

enum ClaudeCodeLabels {
    private static let pickerModels: [String: ClaudeCodeModel] = [
        "Fable 5 Requires usage credits": .fable5,
        "Opus 5": .opus5,
        "Sonnet 5": .sonnet5,
        "Haiku 4.5": .haiku45,
    ]

    private static let effortSteps: [(label: String, value: Int, effort: ClaudeCodeEffort)] = [
        ("Low", 0, .low),
        ("Medium", 1, .medium),
        ("High", 2, .high),
        ("Extra", 3, .extraHigh),
        ("Max", 4, .max),
    ]

    private static let composerModelPrefix = "Model: "

    // Claude Desktop 1.46388.2 renamed Code's closed model popup from the bare
    // model name to the "Model: <name>" form its effort popup already used.
    // Both exact forms stay allowlisted so pre-1.46388 layouts keep verifying,
    // and the qualified form is matched by exact prefix plus an exact closed-set
    // name — never by stripping an arbitrary prefix or by substring search,
    // which would let an unrelated Chromium label impersonate a model control.
    static func model(inComposerTitle title: String) -> ClaudeCodeModel? {
        if let model = ClaudeCodeModel(rawValue: title) { return model }
        guard title.hasPrefix(composerModelPrefix) else { return nil }
        return ClaudeCodeModel(rawValue: String(title.dropFirst(composerModelPrefix.count)))
    }

    // The opened Code picker keeps the closed popup's exact title on its menu
    // root. Search both verified version-specific forms so discovery and menu
    // ownership cannot disagree after the popup has visibly opened.
    static func modelControlTitles(for model: ClaudeCodeModel) -> Set<String> {
        [model.rawValue, "\(composerModelPrefix)\(model.rawValue)"]
    }

    static func model(inPickerRow label: String) -> ClaudeCodeModel? {
        pickerModels[label]
    }

    static func effort(inComposerTitle title: String) -> ClaudeCodeEffort? {
        guard title.hasPrefix("Effort: ") else { return nil }
        let label = String(title.dropFirst("Effort: ".count))
        return effortSteps.first(where: { $0.label == label })?.effort
    }

    static func sliderSelection(value: Int, description: String) -> ClaudeCodeEffort? {
        effortSteps.first(where: { $0.value == value && $0.label == description })?.effort
    }

    static func sliderValue(for effort: ClaudeCodeEffort) -> Int? {
        effortSteps.first(where: { $0.effort == effort })?.value
    }

    static func composerTitle(for effort: ClaudeCodeEffort) -> String? {
        effortSteps.first(where: { $0.effort == effort }).map { "Effort: \($0.label)" }
    }
}

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
    private let logger = Logger(
        subsystem: "com.thierryai.ReasonDeck",
        category: "claude-surface"
    )
    private let deadline: Duration = .seconds(2)
    private let pollInterval: Duration = .milliseconds(50)
    private var accessibilityPreparationAttemptedPID: pid_t?

    func selectModel(_ model: ClaudeCodeModel, invocation: HotkeyInvocation) async throws -> String {
        try await prepareWebAccessibility(invocation: invocation)
        switch try await surface(invocation: invocation) {
        case .chat:
            return try await chooseChatModel(model, invocation: invocation)
        case .code:
            return try await chooseCodeModel(model, invocation: invocation)
        }
    }

    func selectEffort(_ effort: ClaudeCodeEffort, invocation: HotkeyInvocation) async throws -> String {
        try await prepareWebAccessibility(invocation: invocation)
        switch try await surface(invocation: invocation) {
        case .chat:
            return try await chooseChatEffort(effort, invocation: invocation)
        case .code:
            return try await chooseCodeEffort(effort, invocation: invocation)
        }
    }

    private func prepareWebAccessibility(invocation: HotkeyInvocation) async throws {
        try validate(invocation, requiresCodeSurface: false)
        guard accessibilityPreparationAttemptedPID != invocation.pid else { return }
        let application = AXUIElementCreateApplication(invocation.pid)
        let manualResult = AXUIElementSetAttributeValue(
            application,
            "AXManualAccessibility" as CFString,
            kCFBooleanTrue
        )
        let enhancedResult: AXError = manualResult == .success ? .success : AXUIElementSetAttributeValue(
            application,
            "AXEnhancedUserInterface" as CFString,
            kCFBooleanTrue
        )
        accessibilityPreparationAttemptedPID = invocation.pid
        if enhancedResult == .success {
            try await Task.sleep(for: .milliseconds(500))
        } else {
            logger.error("Could not enable Claude web accessibility manualError=\(manualResult.rawValue, privacy: .public) enhancedError=\(enhancedResult.rawValue, privacy: .public)")
        }
        try validate(invocation, requiresCodeSurface: false)
    }

    private enum Surface {
        case chat
        case code
    }

    private struct ChatComposer {
        let popup: AXUIElement
        let title: String
        let model: ClaudeCodeModel
        let effort: ClaudeCodeEffort?
    }

    private struct CodeComposer {
        let modelPopup: AXUIElement
        let model: ClaudeCodeModel
        let effortPopup: AXUIElement
        let effort: ClaudeCodeEffort
    }

    private struct CodeEffortSlider {
        let node: RawNode
        let value: Int
        let effort: ClaudeCodeEffort
    }

    private struct RawNode {
        let id: CFHashCode
        let parentID: CFHashCode?
        let element: AXUIElement
        let role: String
        let actionable: Bool
        let showsMenu: Bool
        let visible: Bool
        let frame: CGRect?
    }

    private struct LiveMenu {
        let root: RawNode
        let nodes: [RawNode]
    }

    // Chromium's accessibility tree can briefly publish some composer elements
    // (e.g. the model/effort popups) before others (e.g. the prompt input),
    // right after a window gains focus or re-renders. A single-shot scan can
    // catch that half-published state and read it as an ambiguous surface.
    // Poll within the same deadline used elsewhere in this file instead of
    // failing on the first inconsistent snapshot.
    private func surface(invocation: HotkeyInvocation) async throws -> Surface {
        let clock = ContinuousClock()
        let end = clock.now.advanced(by: deadline)
        var lastError: Error = SwitchFailure.claudeCodeSurfaceNotFound
        while true {
            try validate(invocation, requiresCodeSurface: false)
            do {
                if try chatComposer(invocation: invocation) != nil { return .chat }
            } catch {
                lastError = error
            }
            do {
                if try codeComposer(invocation: invocation) != nil { return .code }
            } catch {
                lastError = error
            }
            guard clock.now < end else { throw lastError }
            try await Task.sleep(for: pollInterval)
        }
    }

    // Same rationale as `surface()`: don't fail an operation that already
    // knows which surface it's on just because one scan caught the AX tree
    // mid-sync.
    private func waitForInitialChatComposer(invocation: HotkeyInvocation) async throws -> ChatComposer {
        let clock = ContinuousClock()
        let end = clock.now.advanced(by: deadline)
        var lastError: Error = SwitchFailure.claudeCodeSurfaceNotFound
        while true {
            do {
                if let composer = try chatComposer(invocation: invocation) { return composer }
            } catch {
                lastError = error
            }
            guard clock.now < end else { throw lastError }
            try await Task.sleep(for: pollInterval)
        }
    }

    private func waitForInitialCodeComposer(invocation: HotkeyInvocation) async throws -> CodeComposer {
        let clock = ContinuousClock()
        let end = clock.now.advanced(by: deadline)
        var lastError: Error = SwitchFailure.claudeCodeSurfaceNotFound
        while true {
            do {
                if let composer = try codeComposer(invocation: invocation) { return composer }
            } catch {
                lastError = error
            }
            guard clock.now < end else { throw lastError }
            try await Task.sleep(for: pollInterval)
        }
    }

    private func chooseChatModel(
        _ model: ClaudeCodeModel,
        invocation: HotkeyInvocation
    ) async throws -> String {
        let initial = try await waitForInitialChatComposer(invocation: invocation)
        if initial.model == model { return model.rawValue }

        var originalPointer: CGPoint?
        var diagnosticPhase = "opening_root"
        defer { TrustedTargetAction.restorePointer(to: originalPointer) }
        do {
            _ = try await openChatModelMenu(invocation: invocation)
            // Claude replaces parts of the Chromium AX subtree shortly after
            // opening this verified menu. Refresh before targeting a model row.
            try await Task.sleep(for: .milliseconds(500))
            try validate(invocation, requiresCodeSurface: false)
            guard let rootMenu = try await waitForChatRootMenu(
                title: initial.title,
                currentModel: initial.model,
                timeout: deadline,
                invocation: invocation
            ) else {
                throw SwitchFailure.accessibility("Claude Chat model menu did not stabilize.")
            }
            let moreModels = rootMenu.nodes.filter {
                $0.visible
                    && isDescendant($0.id, of: rootMenu.root.id, in: rootMenu.nodes)
                    && controlLabels($0.element).contains("More models")
                    && validFrame($0.frame)
            }
            let rootRows = modelRows(in: rootMenu)
            guard let location = ClaudeChatModelRouting.location(
                for: model,
                rootModels: Set(rootRows.map(\.model)),
                hasMoreModels: uniqueRow(moreModels) != nil
            ) else { throw SwitchFailure.modelUnavailable(model.rawValue) }

            let menu: LiveMenu
            switch location {
            case .root:
                // Claude promotes current models into the primary picker. Prefer
                // that exact owned row instead of opening the legacy submenu.
                menu = rootMenu
            case .moreModels:
                diagnosticPhase = "opening_nested"
                guard let trigger = uniqueRow(moreModels) else {
                    throw SwitchFailure.accessibility("Claude Chat More models row was unavailable.")
                }
                // A standalone hover rebuilds this Chromium row before mouse-down.
                // Deliver directly to the snapshot-verified point instead.
                originalPointer = try clickMenuRow(
                    trigger,
                    in: rootMenu,
                    prepositionPointer: false,
                    invocation: invocation
                )
                // Paid Chromium focuses this exact submenu trigger without opening it.
                // Native Right Arrow performs the owned-menu transition deterministically.
                try TrustedTargetAction.postFocusedKey(
                    keyCode: 124,
                    flags: [],
                    invocation: invocation
                )
                guard let nestedMenu = try await waitForModelMenu(
                    title: "More models",
                    timeout: deadline,
                    invocation: invocation
                ) else {
                    throw SwitchFailure.accessibility("Claude Chat More models menu did not open.")
                }
                menu = nestedMenu
            }
            diagnosticPhase = "focusing_model"
            let rows = modelRows(in: menu)
            guard Set(rows.map(\.model)).count >= 2 else {
                throw SwitchFailure.accessibility("Claude Chat model menu could not be verified.")
            }
            guard let row = uniqueRow(rows.filter { $0.model == model }.map(\.node)) else {
                throw SwitchFailure.modelUnavailable(model.rawValue)
            }
            // Paid Chromium rows can advertise AXPress while treating it as a
            // focus-only no-op. This row is already exact-label, owned-menu,
            // and geometry verified, so use the same bounded click required by
            // the nested effort trigger.
            let selectionPointer = try clickMenuRow(
                row,
                in: menu,
                prepositionPointer: false,
                invocation: invocation
            )
            if originalPointer == nil { originalPointer = selectionPointer }
            try await Task.sleep(for: .milliseconds(500))
            diagnosticPhase = "activating_model"
            try validate(invocation, requiresCodeSurface: false)
            if !verifiedChatMenuRoots(invocation: invocation).isEmpty {
                let refreshedMenu: LiveMenu?
                switch location {
                case .root:
                    refreshedMenu = try await waitForChatRootMenu(
                        title: initial.title,
                        currentModel: initial.model,
                        timeout: .milliseconds(350),
                        invocation: invocation
                    )
                case .moreModels:
                    refreshedMenu = try await waitForModelMenu(
                        title: "More models",
                        timeout: .milliseconds(350),
                        invocation: invocation
                    )
                }
                guard let refreshedMenu, let refreshedRow = uniqueRow(
                    modelRows(in: refreshedMenu)
                        .filter { $0.model == model }
                        .map(\.node)
                ) else {
                    throw SwitchFailure.modelUnavailable(model.rawValue)
                }
                // Chromium uses the first click to focus a non-default nested row.
                // Reacquire it before the second click that activates selection.
                _ = try clickMenuRow(
                    refreshedRow,
                    in: refreshedMenu,
                    prepositionPointer: false,
                    invocation: invocation
                )
            }
            diagnosticPhase = "closing_menus"
            try await waitForChatMenusToClose(invocation: invocation)
            diagnosticPhase = "verifying_model"
            _ = try await waitForChatComposer(
                model: model,
                effort: nil,
                invocation: invocation
            )
            return model.rawValue
        } catch {
            logger.error("chat_model_failure phase=\(diagnosticPhase, privacy: .public)")
            try? await dismissVerifiedChatMenuIfNeeded(invocation: invocation)
            throw error
        }
    }

    private func chooseChatEffort(
        _ effort: ClaudeCodeEffort,
        invocation: HotkeyInvocation
    ) async throws -> String {
        let initial = try await waitForInitialChatComposer(invocation: invocation)
        if initial.effort == effort { return effort.rawValue }
        let desiredLabels = ClaudeChatLabels.pickerRowLabels(for: effort)
        guard !desiredLabels.isEmpty,
              let currentEffort = initial.effort,
              let currentLabel = ClaudeChatLabels.pickerLabel(for: currentEffort)
        else { throw SwitchFailure.effortUnavailable(effort.rawValue) }

        var originalPointer: CGPoint?
        defer { TrustedTargetAction.restorePointer(to: originalPointer) }
        do {
            _ = try await openChatModelMenu(invocation: invocation)
            // Claude publishes the verified menu before its nested-menu responder
            // is ready to accept focus, then replaces parts of the Chromium AX
            // subtree. Let it settle and refresh every element reference.
            try await Task.sleep(for: .milliseconds(500))
            try validate(invocation, requiresCodeSurface: false)
            guard let modelMenu = try await waitForChatRootMenu(
                title: initial.title,
                currentModel: initial.model,
                timeout: deadline,
                invocation: invocation
            ) else {
                throw SwitchFailure.accessibility("Claude Chat model menu did not stabilize.")
            }
            let triggerLabel = "Effort \(currentLabel)"
            let triggers = modelMenu.nodes.filter {
                $0.visible
                    && isDescendant($0.id, of: modelMenu.root.id, in: modelMenu.nodes)
                    && controlLabels($0.element).contains(triggerLabel)
                    && validFrame($0.frame)
            }
            guard let trigger = uniqueRow(triggers) else {
                throw SwitchFailure.effortUnavailable(effort.rawValue)
            }
            // Paid Chat/Cowork rows advertise AXPress but only take focus. A click on
            // the exact verified row geometry is the native action that opens this
            // nested Chromium menu; submenu and final-state checks remain mandatory.
            originalPointer = try clickMenuRow(trigger, in: modelMenu, invocation: invocation)
            let effortMenu = try await waitForEffortMenu(
                title: triggerLabel,
                timeout: deadline,
                invocation: invocation
            )
            guard let effortMenu else {
                throw SwitchFailure.accessibility("Claude Chat effort menu did not open.")
            }
            let rows = effortRows(in: effortMenu)
            guard Set(rows.map(\.effort)).count >= 3 else {
                throw SwitchFailure.accessibility("Claude Chat effort menu could not be verified.")
            }
            guard let row = uniqueRow(rows.filter { $0.effort == effort }.map(\.node)),
                  rows.contains(where: {
                      $0.node.id == row.id && desiredLabels.contains($0.label)
                  })
            else { throw SwitchFailure.effortUnavailable(effort.rawValue) }
            _ = try performMenuRow(row, in: effortMenu, invocation: invocation)
            try await waitForChatMenusToClose(invocation: invocation)
            _ = try await waitForChatComposer(
                model: initial.model,
                effort: effort,
                invocation: invocation
            )
            return effort.rawValue
        } catch {
            try? await dismissVerifiedChatMenuIfNeeded(invocation: invocation)
            throw error
        }
    }

    private func openChatModelMenu(invocation: HotkeyInvocation) async throws -> LiveMenu {
        guard verifiedChatMenuRoots(invocation: invocation).isEmpty,
              let composer = try chatComposer(invocation: invocation)
        else { throw SwitchFailure.accessibility("A Claude Chat model menu was already open.") }

        try TrustedTargetAction.press(composer.popup, invocation: invocation)
        if let menu = try await waitForChatRootMenu(
            title: composer.title,
            currentModel: composer.model,
            timeout: .milliseconds(350),
            invocation: invocation
        ) { return menu }

        // Chromium can publish the owned menu container before its exact rows.
        // Do not send another open action to that already-open control; let the
        // verified container finish populating within the normal deadline.
        if !verifiedChatMenuRoots(invocation: invocation).isEmpty {
            guard let menu = try await waitForChatRootMenu(
                title: composer.title,
                currentModel: composer.model,
                timeout: deadline,
                invocation: invocation
            ) else {
                throw SwitchFailure.accessibility("Claude Chat model menu did not stabilize.")
            }
            return menu
        }

        let actionComposer = try await waitForInitialChatComposer(invocation: invocation)
        guard actionComposer.title == composer.title else {
            throw SwitchFailure.verificationMismatch(
                expected: composer.title,
                observed: actionComposer.title
            )
        }
        let actionNames = actions(actionComposer.popup)
        if actionNames.contains(kAXShowMenuAction as String) {
            try TrustedTargetAction.showMenu(actionComposer.popup, invocation: invocation)
            if let menu = try await waitForChatRootMenu(
                title: composer.title,
                currentModel: composer.model,
                timeout: deadline,
                invocation: invocation
            ) { return menu }

            // Chromium can advertise successful AXPress and AXShowMenu actions
            // while leaving this exact popup closed. Use its fresh verified frame
            // only after both actions have produced no observable owned menu.
            guard verifiedChatMenuRoots(invocation: invocation).isEmpty else {
                throw SwitchFailure.accessibility("Claude Chat model menu did not stabilize.")
            }
        }
        let clickComposer = try await waitForInitialChatComposer(invocation: invocation)
        guard clickComposer.title == composer.title,
              let popupFrame = AXWindowIdentity.frame(clickComposer.popup)
        else {
            throw SwitchFailure.accessibility("Claude Chat model control geometry was unavailable.")
        }
        let pointer = try TrustedTargetAction.click(frame: popupFrame, invocation: invocation)
        TrustedTargetAction.restorePointer(to: pointer)
        guard let menu = try await waitForChatRootMenu(
            title: composer.title,
            currentModel: composer.model,
            timeout: deadline,
            invocation: invocation
        ) else { throw SwitchFailure.accessibility("Claude Chat model menu did not open.") }
        return menu
    }

    private func waitForModelMenu(
        title: String,
        timeout: Duration,
        invocation: HotkeyInvocation
    ) async throws -> LiveMenu? {
        try await waitForMenu(titles: [title], timeout: timeout, invocation: invocation) { menu in
            Set(self.modelRows(in: menu).map(\.model)).count >= 2
        }
    }

    private func waitForChatRootMenu(
        title: String,
        currentModel: ClaudeCodeModel,
        timeout: Duration,
        invocation: HotkeyInvocation
    ) async throws -> LiveMenu? {
        try await waitForMenu(titles: [title], timeout: timeout, invocation: invocation) { menu in
            let moreModels = menu.nodes.filter {
                $0.visible
                    && self.isDescendant($0.id, of: menu.root.id, in: menu.nodes)
                    && self.controlLabels($0.element).contains("More models")
                    && self.validFrame($0.frame)
            }
            return self.uniqueRow(moreModels) != nil
                && self.modelRows(in: menu).contains(where: { $0.model == currentModel })
        }
    }

    private func waitForEffortMenu(
        title: String,
        timeout: Duration,
        invocation: HotkeyInvocation
    ) async throws -> LiveMenu? {
        try await waitForMenu(titles: [title], timeout: timeout, invocation: invocation) { menu in
            Set(self.effortRows(in: menu).map(\.effort)).count >= 3
        }
    }

    private func waitForMenu(
        titles: Set<String>,
        timeout: Duration,
        invocation: HotkeyInvocation,
        verifying predicate: (LiveMenu) -> Bool
    ) async throws -> LiveMenu? {
        let clock = ContinuousClock()
        let end = clock.now.advanced(by: timeout)
        while clock.now < end {
            let matches = try menus(titledAnyOf: titles, invocation: invocation).filter(predicate)
            if matches.count == 1 { return matches[0] }
            if matches.count > 1 {
                throw SwitchFailure.accessibility("Claude Chat menu was ambiguous.")
            }
            try await Task.sleep(for: pollInterval)
        }
        return nil
    }

    private func waitForChatComposer(
        model: ClaudeCodeModel,
        effort: ClaudeCodeEffort?,
        invocation: HotkeyInvocation
    ) async throws -> ChatComposer {
        let clock = ContinuousClock()
        let end = clock.now.advanced(by: deadline)
        var lastTitle = "unexposed"
        while clock.now < end {
            if let current = try chatComposer(invocation: invocation) {
                lastTitle = current.title
                if current.model == model, effort == nil || current.effort == effort {
                    return current
                }
            }
            try await Task.sleep(for: pollInterval)
        }
        let expected = effort.map { "Model: \(model.rawValue) \(ClaudeChatLabels.pickerLabel(for: $0) ?? $0.rawValue)" }
            ?? model.rawValue
        throw SwitchFailure.verificationMismatch(expected: expected, observed: lastTitle)
    }

    private func waitForChatMenusToClose(invocation: HotkeyInvocation) async throws {
        let clock = ContinuousClock()
        let end = clock.now.advanced(by: deadline)
        while clock.now < end {
            try validate(invocation, requiresCodeSurface: false)
            if verifiedChatMenuRoots(invocation: invocation).isEmpty { return }
            try await Task.sleep(for: pollInterval)
        }
        throw SwitchFailure.deadlineExceeded("waiting for Claude Chat’s verified model menu to close")
    }

    private func dismissVerifiedChatMenuIfNeeded(invocation: HotkeyInvocation) async throws {
        try validate(invocation, requiresCodeSurface: false)
        guard !verifiedChatMenuRoots(invocation: invocation).isEmpty else { return }
        try TrustedTargetAction.postFocusedKey(keyCode: 53, flags: [], invocation: invocation)
        try await waitForChatMenusToClose(invocation: invocation)
    }

    private func chatComposer(invocation: HotkeyInvocation) throws -> ChatComposer? {
        try validate(invocation, requiresCodeSurface: false)
        let nodes = try windowNodes(invocation: invocation)
        let inputs = nodes.filter { node in
            node.visible
                && [kAXTextAreaRole as String, kAXTextFieldRole as String].contains(node.role)
                && controlLabels(node.element).contains("Write your prompt to Claude")
        }
        let popups = nodes.compactMap { node -> (RawNode, String, ClaudeCodeModel, ClaudeCodeEffort?)? in
            guard node.visible,
                  node.role == kAXPopUpButtonRole as String,
                  node.actionable || node.showsMenu,
                  let title = controlLabels(node.element).first(where: {
                      ClaudeChatLabels.model(inComposerTitle: $0) != nil
                  }),
                  let model = ClaudeChatLabels.model(inComposerTitle: title),
                  validFrame(node.frame)
            else { return nil }
            return (node, title, model, ClaudeChatLabels.effort(inComposerTitle: title))
        }
        guard inputs.count == 1 else {
            logger.error("chat_surface_missing phase=input inputs=\(inputs.count, privacy: .public) popups=\(popups.count, privacy: .public)")
            if inputs.isEmpty, popups.isEmpty { return nil }
            throw SwitchFailure.accessibility("Claude Chat composer was ambiguous.")
        }
        let candidates = popups.filter {
            sharesBoundedAncestor(
                [inputs[0].id, $0.0.id],
                in: nodes,
                maxDistance: 12
            )
        }
        guard candidates.count == 1 else {
            logger.error("chat_surface_missing phase=relationship candidates=\(candidates.count, privacy: .public) popups=\(popups.count, privacy: .public)")
            if candidates.isEmpty { return nil }
            throw SwitchFailure.accessibility("Claude Chat model control was ambiguous.")
        }
        let candidate = candidates[0]
        return ChatComposer(
            popup: candidate.0.element,
            title: candidate.1,
            model: candidate.2,
            effort: candidate.3
        )
    }

    private func codeComposer(invocation: HotkeyInvocation) throws -> CodeComposer? {
        try validate(invocation, requiresCodeSurface: false)
        let application = AXUIElementCreateApplication(invocation.pid)
        guard let window: AXUIElement = value(application, kAXFocusedWindowAttribute),
              containsCodeSurface(in: window)
        else { return nil }

        let nodes = try windowNodes(invocation: invocation)
        let inputs = nodes.filter { node in
            node.visible
                && [kAXTextAreaRole as String, kAXTextFieldRole as String].contains(node.role)
                && controlLabels(node.element).contains("Prompt")
        }
        let models = nodes.compactMap { node -> (RawNode, ClaudeCodeModel)? in
            guard node.visible,
                  node.role == kAXPopUpButtonRole as String,
                  node.actionable || node.showsMenu,
                  let model = controlLabels(node.element).compactMap(ClaudeCodeLabels.model(inComposerTitle:)).first,
                  validFrame(node.frame)
            else { return nil }
            return (node, model)
        }
        let efforts = nodes.compactMap { node -> (RawNode, ClaudeCodeEffort)? in
            guard node.visible,
                  node.role == kAXPopUpButtonRole as String,
                  node.actionable || node.showsMenu,
                  let effort = controlLabels(node.element).compactMap(ClaudeCodeLabels.effort(inComposerTitle:)).first,
                  validFrame(node.frame)
            else { return nil }
            return (node, effort)
        }
        guard inputs.count == 1 else {
            logger.error("code_surface_missing phase=input inputs=\(inputs.count, privacy: .public) models=\(models.count, privacy: .public) efforts=\(efforts.count, privacy: .public)")
            if inputs.isEmpty, models.isEmpty, efforts.isEmpty { return nil }
            throw SwitchFailure.accessibility("Claude Code composer was ambiguous.")
        }
        let modelCandidates = models.filter {
            sharesBoundedAncestor([inputs[0].id, $0.0.id], in: nodes, maxDistance: 12)
        }
        let effortCandidates = efforts.filter {
            sharesBoundedAncestor([inputs[0].id, $0.0.id], in: nodes, maxDistance: 12)
        }
        guard modelCandidates.count == 1, effortCandidates.count == 1,
              sharesBoundedAncestor(
                [inputs[0].id, modelCandidates[0].0.id, effortCandidates[0].0.id],
                in: nodes,
                maxDistance: 12
              )
        else {
            logger.error("code_surface_missing phase=relationship models=\(modelCandidates.count, privacy: .public) efforts=\(effortCandidates.count, privacy: .public)")
            if modelCandidates.isEmpty, effortCandidates.isEmpty { return nil }
            throw SwitchFailure.accessibility("Claude Code controls were ambiguous.")
        }
        return CodeComposer(
            modelPopup: modelCandidates[0].0.element,
            model: modelCandidates[0].1,
            effortPopup: effortCandidates[0].0.element,
            effort: effortCandidates[0].1
        )
    }

    private func menus(titledAnyOf titles: Set<String>, invocation: HotkeyInvocation) throws -> [LiveMenu] {
        let nodes = try windowNodes(invocation: invocation)
        return nodes.compactMap { node in
            guard node.visible,
                  node.role == kAXMenuRole as String,
                  controlLabels(node.element).contains(where: titles.contains),
                  validFrame(node.frame)
            else { return nil }
            // Chromium can expose the same nested-menu rows through both the
            // window overlay and the menu. The window-wide breadth-first scan
            // may encounter the overlay path first, which makes a genuinely
            // owned row look unrelated. Re-root the bounded snapshot at the
            // exact verified menu so descendant checks retain menu ownership.
            let menuNodes = rawNodes(root: node.element, maxDepth: 12, maxNodes: 500)
            return LiveMenu(root: node, nodes: menuNodes)
        }
    }

    private func openCodeModelMenu(invocation: HotkeyInvocation) async throws -> LiveMenu {
        guard verifiedCodeModelMenuRoots(invocation: invocation).isEmpty,
              try codeEffortSliders(invocation: invocation).isEmpty,
              let composer = try codeComposer(invocation: invocation)
        else { throw SwitchFailure.accessibility("A Claude Code control was already open.") }

        try TrustedTargetAction.press(composer.modelPopup, invocation: invocation)
        if let menu = try await waitForCodeModelMenu(
            model: composer.model,
            timeout: .milliseconds(350),
            invocation: invocation
        ) { return menu }

        let actionNames = actions(composer.modelPopup)
        if actionNames.contains(kAXShowMenuAction as String) {
            try TrustedTargetAction.showMenu(composer.modelPopup, invocation: invocation)
        } else if let popupFrame = AXWindowIdentity.frame(composer.modelPopup) {
            let pointer = try TrustedTargetAction.click(frame: popupFrame, invocation: invocation)
            TrustedTargetAction.restorePointer(to: pointer)
        }
        guard let menu = try await waitForCodeModelMenu(
            model: composer.model,
            timeout: deadline,
            invocation: invocation
        ) else { throw SwitchFailure.accessibility("Claude Code model menu did not open.") }
        return menu
    }

    private func waitForCodeModelMenu(
        model: ClaudeCodeModel,
        timeout: Duration,
        invocation: HotkeyInvocation
    ) async throws -> LiveMenu? {
        try await waitForMenu(
            titles: ClaudeCodeLabels.modelControlTitles(for: model),
            timeout: timeout,
            invocation: invocation
        ) { menu in
            Set(self.codeModelRows(in: menu).map(\.model)).count >= 3
        }
    }

    private func openCodeEffortSlider(invocation: HotkeyInvocation) async throws -> CodeEffortSlider {
        guard verifiedCodeModelMenuRoots(invocation: invocation).isEmpty,
              try codeEffortSliders(invocation: invocation).isEmpty,
              let composer = try codeComposer(invocation: invocation)
        else { throw SwitchFailure.accessibility("A Claude Code control was already open.") }

        try TrustedTargetAction.press(composer.effortPopup, invocation: invocation)
        guard let slider = try await waitForCodeEffortSlider(
            value: ClaudeCodeLabels.sliderValue(for: composer.effort),
            timeout: deadline,
            invocation: invocation
        ) else { throw SwitchFailure.accessibility("Claude Code effort slider did not open.") }
        return slider
    }

    private func waitForCodeEffortSlider(
        value expectedValue: Int?,
        timeout: Duration,
        invocation: HotkeyInvocation
    ) async throws -> CodeEffortSlider? {
        let clock = ContinuousClock()
        let end = clock.now.advanced(by: timeout)
        while clock.now < end {
            let sliders = try codeEffortSliders(invocation: invocation)
            if sliders.count > 1 {
                throw SwitchFailure.accessibility("Claude Code effort slider was ambiguous.")
            }
            if let slider = sliders.first, expectedValue == nil || slider.value == expectedValue {
                return slider
            }
            try await Task.sleep(for: pollInterval)
        }
        return nil
    }

    private func waitForCodeComposer(
        model: ClaudeCodeModel?,
        effort: ClaudeCodeEffort?,
        invocation: HotkeyInvocation
    ) async throws -> CodeComposer {
        let clock = ContinuousClock()
        let end = clock.now.advanced(by: deadline)
        var last = "unexposed"
        while clock.now < end {
            if let composer = try codeComposer(invocation: invocation) {
                last = "\(composer.model.rawValue) / \(composer.effort.rawValue)"
                if (model == nil || composer.model == model),
                   (effort == nil || composer.effort == effort) {
                    return composer
                }
            }
            try await Task.sleep(for: pollInterval)
        }
        let expected = "\(model?.rawValue ?? "current model") / \(effort?.rawValue ?? "current effort")"
        throw SwitchFailure.verificationMismatch(expected: expected, observed: last)
    }

    private func waitForCodeControlsToClose(invocation: HotkeyInvocation) async throws {
        let clock = ContinuousClock()
        let end = clock.now.advanced(by: deadline)
        while clock.now < end {
            try validate(invocation, requiresCodeSurface: true)
            if verifiedCodeModelMenuRoots(invocation: invocation).isEmpty,
               try codeEffortSliders(invocation: invocation).isEmpty {
                return
            }
            try await Task.sleep(for: pollInterval)
        }
        throw SwitchFailure.deadlineExceeded("waiting for Claude Code’s verified control to close")
    }

    private func dismissVerifiedCodeControlIfNeeded(invocation: HotkeyInvocation) async throws {
        try validate(invocation, requiresCodeSurface: true)
        let hasModelMenu = !verifiedCodeModelMenuRoots(invocation: invocation).isEmpty
        let hasEffortSlider = try !codeEffortSliders(invocation: invocation).isEmpty
        guard hasModelMenu || hasEffortSlider else { return }
        try TrustedTargetAction.postFocusedKey(keyCode: 53, flags: [], invocation: invocation)
        try await waitForCodeControlsToClose(invocation: invocation)
    }

    private func verifiedCodeModelMenuRoots(invocation: HotkeyInvocation) -> [RawNode] {
        guard let nodes = try? windowNodes(invocation: invocation) else { return [] }
        return nodes.filter { node in
            node.visible
                && node.role == kAXMenuRole as String
                && controlLabels(node.element).contains(where: { ClaudeCodeLabels.model(inComposerTitle: $0) != nil })
                && validFrame(node.frame)
        }
    }

    private func codeModelRows(in menu: LiveMenu) -> [(node: RawNode, model: ClaudeCodeModel)] {
        menu.nodes.compactMap { node in
            guard node.visible,
                  isDescendant(node.id, of: menu.root.id, in: menu.nodes),
                  let model = controlLabels(node.element).compactMap(ClaudeCodeLabels.model(inPickerRow:)).first,
                  validFrame(node.frame)
            else { return nil }
            return (node, model)
        }
    }

    private func codeEffortSliders(invocation: HotkeyInvocation) throws -> [CodeEffortSlider] {
        guard let composer = try codeComposer(invocation: invocation) else { return [] }
        let nodes = try windowNodes(invocation: invocation)
        return nodes.compactMap { node in
            guard node.visible,
                  node.role == kAXSliderRole as String,
                  controlLabels(node.element).contains("Effort"),
                  node.showsMenu,
                  actions(node.element).contains(kAXIncrementAction as String),
                  actions(node.element).contains(kAXDecrementAction as String),
                  let number: NSNumber = value(node.element, kAXValueAttribute),
                  let description: String = value(node.element, kAXValueDescriptionAttribute),
                  let effort = ClaudeCodeLabels.sliderSelection(
                    value: number.intValue,
                    description: description
                  ),
                  sharesBoundedAncestor(
                    [CFHash(composer.effortPopup), node.id],
                    in: nodes,
                    maxDistance: 12
                  ),
                  validFrame(node.frame)
            else { return nil }
            return CodeEffortSlider(node: node, value: number.intValue, effort: effort)
        }
    }

    private func verifiedChatMenuRoots(invocation: HotkeyInvocation) -> [RawNode] {
        guard let nodes = try? windowNodes(invocation: invocation) else { return [] }
        return nodes.filter { node in
            guard node.visible, node.role == kAXMenuRole as String else { return false }
            return controlLabels(node.element).contains { label in
                ClaudeChatLabels.model(inComposerTitle: label) != nil
                    || label == "More models"
                    || ClaudeChatLabels.pickerLabel(for: .low).map { label == "Effort \($0)" } == true
                    || ClaudeChatLabels.pickerLabel(for: .medium).map { label == "Effort \($0)" } == true
                    || ClaudeChatLabels.pickerLabel(for: .high).map { label == "Effort \($0)" } == true
                    || ClaudeChatLabels.pickerLabel(for: .extraHigh).map { label == "Effort \($0)" } == true
                    || ClaudeChatLabels.pickerLabel(for: .max).map { label == "Effort \($0)" } == true
            }
        }
    }

    private func modelRows(in menu: LiveMenu) -> [(node: RawNode, model: ClaudeCodeModel)] {
        menu.nodes.compactMap { node in
            guard node.visible,
                  isDescendant(node.id, of: menu.root.id, in: menu.nodes),
                  let model = controlLabels(node.element).compactMap(ClaudeChatLabels.model(inPickerRow:)).first,
                  validFrame(node.frame)
            else { return nil }
            return (node, model)
        }
    }

    private func effortRows(in menu: LiveMenu) -> [(node: RawNode, effort: ClaudeCodeEffort, label: String)] {
        menu.nodes.compactMap { node in
            guard node.visible,
                  isDescendant(node.id, of: menu.root.id, in: menu.nodes),
                  let pair = controlLabels(node.element).compactMap({ label in
                      ClaudeChatLabels.effort(inPickerRow: label).map { (effort: $0, label: label) }
                  }).first,
                  validFrame(node.frame)
            else { return nil }
            return (node, pair.effort, pair.label)
        }
    }

    private func performMenuRow(
        _ row: RawNode,
        in menu: LiveMenu,
        invocation: HotkeyInvocation
    ) throws -> CGPoint? {
        if row.actionable {
            try TrustedTargetAction.press(row.element, invocation: invocation)
            return nil
        }
        return try clickMenuRow(row, in: menu, invocation: invocation)
    }

    private func clickMenuRow(
        _ row: RawNode,
        in menu: LiveMenu,
        prepositionPointer: Bool = true,
        invocation: HotkeyInvocation
    ) throws -> CGPoint? {
        guard let rowFrame = row.frame,
              let menuFrame = menu.root.frame,
              menuFrame.width > 0, menuFrame.height > 0,
              menuFrame.width <= 1_000, menuFrame.height <= 1_000
        else { throw SwitchFailure.accessibility("Claude Chat menu geometry was unavailable.") }
        let point = CGPoint(x: rowFrame.midX, y: rowFrame.midY)
        guard menuFrame.contains(point) else {
            throw SwitchFailure.accessibility("Claude Chat menu row geometry was invalid.")
        }
        return try TrustedTargetAction.click(
            frame: CGRect(x: point.x - 1, y: point.y - 1, width: 2, height: 2),
            invocation: invocation,
            prepositionPointer: prepositionPointer
        )
    }

    private func uniqueRow(_ rows: [RawNode]) -> RawNode? {
        let unique = Dictionary(grouping: rows, by: \.id).compactMap(\.value.first)
        return unique.count == 1 ? unique[0] : nil
    }

    private func windowNodes(invocation: HotkeyInvocation) throws -> [RawNode] {
        try validate(invocation, requiresCodeSurface: false)
        let application = AXUIElementCreateApplication(invocation.pid)
        guard let window: AXUIElement = value(application, kAXFocusedWindowAttribute),
              AXWindowIdentity.focusedWindowID(application: application, pid: invocation.pid)
                == invocation.focusedWindowID
        else { throw SwitchFailure.targetChanged(ApplicationTarget.claudeCode.displayName) }
        // Claude Desktop nests the Chat/Cowork composer controls below several
        // Chromium wrapper groups. Keep this bounded, but deep enough to reach
        // the exact prompt field, model popup, and owned menu rows.
        let nodes = rawNodes(root: window, maxDepth: 36, maxNodes: 8_000)
        try validate(invocation, requiresCodeSurface: false)
        return nodes
    }

    private func rawNodes(root: AXUIElement, maxDepth: Int, maxNodes: Int) -> [RawNode] {
        var queue: [(AXUIElement, CFHashCode?, Int)] = [(root, nil, 0)]
        var output: [RawNode] = []
        var visited = Set<CFHashCode>()
        var index = 0
        while index < queue.count, output.count < maxNodes {
            let (element, parentID, depth) = queue[index]
            index += 1
            let id = CFHash(element)
            guard visited.insert(id).inserted else { continue }
            let role: String = value(element, kAXRoleAttribute) ?? ""
            let hidden: Bool = value(element, "AXHidden") ?? false
            let actionNames = actions(element)
            output.append(RawNode(
                id: id,
                parentID: parentID,
                element: element,
                role: role,
                actionable: actionNames.contains(kAXPressAction as String),
                showsMenu: actionNames.contains(kAXShowMenuAction as String),
                visible: !hidden,
                frame: AXWindowIdentity.frame(element)
            ))
            guard depth < maxDepth else { continue }
            let children: [AXUIElement] = value(element, kAXChildrenAttribute) ?? []
            let visibleChildren: [AXUIElement] = value(element, kAXVisibleChildrenAttribute) ?? []
            queue.append(contentsOf: (children + visibleChildren).map { ($0, id, depth + 1) })
        }
        return output
    }

    private func sharesBoundedAncestor(
        _ ids: [CFHashCode],
        in nodes: [RawNode],
        maxDistance: Int
    ) -> Bool {
        guard let first = ids.first else { return false }
        let index = Dictionary(uniqueKeysWithValues: nodes.map { ($0.id, $0) })
        func ancestors(of id: CFHashCode) -> Set<CFHashCode> {
            var result: Set<CFHashCode> = [id]
            var current = index[id]?.parentID
            var distance = 1
            while let value = current, distance <= maxDistance, result.insert(value).inserted {
                current = index[value]?.parentID
                distance += 1
            }
            return result
        }
        var common = ancestors(of: first)
        for id in ids.dropFirst() { common.formIntersection(ancestors(of: id)) }
        return !common.isEmpty
    }

    private func isDescendant(
        _ nodeID: CFHashCode,
        of ancestorID: CFHashCode,
        in nodes: [RawNode]
    ) -> Bool {
        let index = Dictionary(uniqueKeysWithValues: nodes.map { ($0.id, $0) })
        var current = index[nodeID]?.parentID
        var visited = Set<CFHashCode>()
        while let id = current, visited.insert(id).inserted {
            if id == ancestorID { return true }
            current = index[id]?.parentID
        }
        return false
    }

    private func controlLabels(_ element: AXUIElement) -> [String] {
        [kAXTitleAttribute, kAXDescriptionAttribute, kAXHelpAttribute]
            .compactMap { value(element, $0) as String? }
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
    }

    private func validFrame(_ frame: CGRect?) -> Bool {
        guard let frame else { return false }
        return frame.width > 0 && frame.height > 0
            && frame.width <= 1_000 && frame.height <= 1_000
            && frame.minX.isFinite && frame.minY.isFinite
            && frame.maxX.isFinite && frame.maxY.isFinite
    }

    private func chooseCodeModel(
        _ model: ClaudeCodeModel,
        invocation: HotkeyInvocation
    ) async throws -> String {
        let initial = try await waitForInitialCodeComposer(invocation: invocation)
        if initial.model == model { return model.rawValue }

        var originalPointer: CGPoint?
        defer { TrustedTargetAction.restorePointer(to: originalPointer) }
        do {
            let menu = try await openCodeModelMenu(invocation: invocation)
            let rows = codeModelRows(in: menu)
            guard Set(rows.map(\.model)).count >= 3 else {
                throw SwitchFailure.accessibility("Claude Code model menu could not be verified.")
            }
            guard let row = uniqueRow(rows.filter { $0.model == model }.map(\.node)) else {
                throw SwitchFailure.modelUnavailable(model.rawValue)
            }
            originalPointer = try performMenuRow(row, in: menu, invocation: invocation)
            try await waitForCodeControlsToClose(invocation: invocation)
            _ = try await waitForCodeComposer(
                model: model,
                effort: nil,
                invocation: invocation
            )
            return model.rawValue
        } catch {
            try? await dismissVerifiedCodeControlIfNeeded(invocation: invocation)
            throw error
        }
    }

    private func chooseCodeEffort(
        _ effort: ClaudeCodeEffort,
        invocation: HotkeyInvocation
    ) async throws -> String {
        guard let targetValue = ClaudeCodeLabels.sliderValue(for: effort) else {
            throw SwitchFailure.effortUnavailable(effort.rawValue)
        }
        let initial = try await waitForInitialCodeComposer(invocation: invocation)
        if initial.effort == effort { return effort.rawValue }

        do {
            let initialSlider = try await openCodeEffortSlider(invocation: invocation)
            var observed = initialSlider
            for _ in 0..<4 where observed.value != targetValue {
                let increment = observed.value < targetValue
                try TrustedTargetAction.stepSlider(
                    observed.node.element,
                    increment: increment,
                    invocation: invocation
                )
                let expectedValue = observed.value + (increment ? 1 : -1)
                guard let refreshed = try await waitForCodeEffortSlider(
                    value: expectedValue,
                    timeout: deadline,
                    invocation: invocation
                ) else {
                    throw SwitchFailure.verificationMismatch(
                        expected: "Claude Code effort step \(expectedValue)",
                        observed: "unexposed"
                    )
                }
                observed = refreshed
            }
            guard observed.value == targetValue, observed.effort == effort else {
                throw SwitchFailure.verificationMismatch(
                    expected: effort.rawValue,
                    observed: observed.effort.rawValue
                )
            }
            try TrustedTargetAction.postFocusedKey(keyCode: 53, flags: [], invocation: invocation)
            try await waitForCodeControlsToClose(invocation: invocation)
            _ = try await waitForCodeComposer(
                model: initial.model,
                effort: effort,
                invocation: invocation
            )
            return effort.rawValue
        } catch {
            try? await dismissVerifiedCodeControlIfNeeded(invocation: invocation)
            throw error
        }
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
            let mark: String? = value(element, kAXMenuItemMarkCharAttribute)
            let numericValue: NSNumber? = value(element, kAXValueAttribute)
            let allowedRoles = [kAXButtonRole as String, kAXRadioButtonRole as String]
            return allowedRoles.contains(role ?? "")
                && exactLabels(element).contains("Code")
                && ClaudeMenuSelection.isPersistent(
                    role: role,
                    selected: selected,
                    mark: mark,
                    numericValue: numericValue?.intValue
                )
        }
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
