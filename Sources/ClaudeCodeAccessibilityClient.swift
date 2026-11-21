import AppKit
import ApplicationServices
import Foundation
import os

// Claude Desktop 6.6395.0 gives Chat, Cowork, and Code the same combined
// model-and-effort picker, so one closed label set serves every surface.
enum ClaudePickerLabels {
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

    // Claude appends an account-access badge to some models: " CVP" after the
    // effort in the closed composer title and " CVP: Defense Access" on the
    // picker row (both live-read on 6.6395.0). Each is one exact allowlisted
    // suffix on an exact closed-set name — never a prefix or substring match,
    // so an unrecognized badge still fails closed.
    private static let composerBadges = ["", " CVP"]
    private static let rowBadges = ["", " CVP: Defense Access"]

    // Row forms carrying marketing copy, observed on Claude Desktop 1.x Chat.
    // Kept so an older layout still verifies; the Fable 5.1 forms mirror the
    // observed Fable 5 forms and were never live-read.
    private static let describedRows: [String: ClaudeCodeModel] = [
        "Fable 5.1 Requires usage credits For your toughest challenges": .fable51,
        "Fable 5.1 Requires usage credits": .fable51,
        "Fable 5 Requires usage credits For your toughest challenges": .fable5,
        "Fable 5 Requires usage credits": .fable5,
        "Opus 5.5 Most capable for ambitious work": .opus55,
        "Opus 5 For complex tasks": .opus5,
        "Sonnet 5 Most efficient for everyday tasks": .sonnet5,
        "Haiku 4.5 Fastest for quick answers": .haiku45,
    ]

    private static let pickerModels: [String: ClaudeCodeModel] = {
        var rows = describedRows
        for model in ClaudeCodeModel.allCases {
            for badge in rowBadges { rows["\(model.rawValue)\(badge)"] = model }
        }
        return rows
    }()

    private static let pickerEfforts: [(label: String, effort: ClaudeCodeEffort)] = {
        // 6.28899.2 tags whichever effort it recommends for the current model
        // with "Recommended" — High for Sonnet 5, Medium for Fable 5.2 — so
        // every effort needs that exact suffixed form, not only Medium.
        let base: [(label: String, effort: ClaudeCodeEffort)] = [
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
        let recommended = Set(["Low", "Medium", "High", "Extra", "Max"])
            .map { label -> (label: String, effort: ClaudeCodeEffort) in
                (label: "\(label) Recommended", effort: base.first(where: { $0.label == label })!.effort)
            }
        return base + recommended
    }()

    static func selection(inComposerTitle title: String) -> ClaudeCodeSelection? {
        for model in ClaudeCodeModel.allCases {
            for candidate in composerEfforts {
                for badge in composerBadges
                where title == "Model: \(model.rawValue) \(candidate.label)\(badge)" {
                    return ClaudeCodeSelection(model: model, effort: candidate.effort)
                }
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

    // The nested effort menu is titled by its trigger row, "Effort <label>".
    static let effortMenuTitles: Set<String> = Set(composerEfforts.map { "Effort \($0.label)" })
}

enum ClaudePickerModelLocation: Equatable {
    case root
    case moreModels
}

enum ClaudePickerModelRouting {
    static func location(
        for model: ClaudeCodeModel,
        rootModels: Set<ClaudeCodeModel>,
        hasMoreModels: Bool
    ) -> ClaudePickerModelLocation? {
        if rootModels.contains(model) { return .root }
        return hasMoreModels ? .moreModels : nil
    }
}

// Which prompt field proves the surface. The two are mutually exclusive: Code's
// generic "Prompt" label counts only while the Code tab is the selected one.
enum ClaudeComposerSurface {
    static func promptLabel(codeTabSelected: Bool) -> String {
        codeTabSelected ? "Prompt" : "Write your prompt to Claude"
    }
}

// Claude Desktop 1.x published an opened picker as an AXMenu. 6.6395.0
// publishes the same picker as an AXGroup carrying the identical exact title,
// with AXMenuItem rows. The exact closed-set title is the proof either way;
// the role only bounds which containers are worth reading.
enum ClaudeMenuContainer {
    static func isCandidate(role: String) -> Bool {
        role == kAXMenuRole as String || role == kAXGroupRole as String
    }
}

// Bounded breadth-first walk that identifies each node by its position in the
// walk. Never deduplicate by CFHash(AXUIElement): distinct Chromium elements
// share hashes (21 of 459 in one Claude Desktop 6.28899.2 window), so a
// hash-keyed visited set silently drops whole subtrees — including the
// composer — and the shortcut fails with "surface not found" depending on
// which session is open. Walk kAXChildren only; adding kAXVisibleChildren
// revisits the same elements and is what made deduplication look necessary.
enum ClaudeTreeScan {
    struct Visit<Element> {
        let element: Element
        let id: Int
        let parentID: Int?
        let depth: Int
    }

    static func breadthFirst<Element>(
        root: Element,
        maxDepth: Int,
        maxNodes: Int,
        children: (Element) -> [Element]
    ) -> [Visit<Element>] {
        var output = [Visit(element: root, id: 0, parentID: nil, depth: 0)]
        var index = 0
        while index < output.count {
            let visit = output[index]
            index += 1
            guard visit.depth < maxDepth, output.count < maxNodes else { continue }
            for child in children(visit.element).prefix(maxNodes - output.count) {
                output.append(Visit(
                    element: child,
                    id: output.count,
                    parentID: visit.id,
                    depth: visit.depth + 1
                ))
            }
        }
        return output
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

enum ClaudeAccessibilityPreparationPolicy {
    enum WindowState: Equatable {
        case awaitingRepublish
        case ready
        case changed
    }

    static func shouldPrepare(after failure: SwitchFailure) -> Bool {
        if case .claudeCodeSurfaceNotFound = failure { return true }
        return false
    }

    struct Attempt: Equatable, Sendable {
        let pid: pid_t
        let instant: ContinuousClock.Instant
    }

    // Chromium can drop and rebuild Claude's web Accessibility tree many times
    // within one process lifetime, so this cannot be a once-per-process latch:
    // one spent attempt left every later shortcut polling an empty tree until
    // Claude happened to republish on its own. Re-assert it, but at most once
    // per cooldown, because each attempt can rebuild Chromium's focused window
    // and costs a bounded republish wait.
    static let retryCooldown: Duration = .seconds(30)

    static func shouldAttempt(
        pid: pid_t,
        lastAttempt: Attempt?,
        now: ContinuousClock.Instant,
        cooldown: Duration = retryCooldown
    ) -> Bool {
        guard let lastAttempt, lastAttempt.pid == pid else { return true }
        return lastAttempt.instant.duration(to: now) >= cooldown
    }

    static func windowState(
        capturedWindowID: CGWindowID,
        observedWindowID: CGWindowID?
    ) -> WindowState {
        guard let observedWindowID else { return .awaitingRepublish }
        return observedWindowID == capturedWindowID ? .ready : .changed
    }
}

enum ClaudeAccessibilityBootstrapPolicy {
    static func shouldPrepare(
        pid: pid_t,
        lastPreparedPID: pid_t?,
        accessibilityTrusted: Bool
    ) -> Bool {
        accessibilityTrusted && pid != lastPreparedPID
    }
}

actor ClaudeAccessibilityBootstrapper {
    private let logger = Logger(
        subsystem: "com.thierryai.ReasonDeck",
        category: "claude-accessibility"
    )
    private var lastPreparedPID: pid_t?

    func prepare(pid: pid_t) {
        guard ClaudeAccessibilityBootstrapPolicy.shouldPrepare(
            pid: pid,
            lastPreparedPID: lastPreparedPID,
            accessibilityTrusted: AXIsProcessTrusted()
        ) else { return }

        let application = AXUIElementCreateApplication(pid)
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
        guard enhancedResult == .success else {
            logger.error("Claude Accessibility bootstrap failed pid=\(pid, privacy: .public) manualError=\(manualResult.rawValue, privacy: .public) enhancedError=\(enhancedResult.rawValue, privacy: .public)")
            return
        }
        lastPreparedPID = pid
        logger.info("Claude Accessibility bootstrap completed pid=\(pid, privacy: .public)")
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
    private var lastPreparationAttempt: ClaudeAccessibilityPreparationPolicy.Attempt?

    func selectModel(_ model: ClaudeCodeModel, invocation: HotkeyInvocation) async throws -> String {
        try await ensureComposer(invocation: invocation)
        return try await chooseModel(model, invocation: invocation)
    }

    func selectEffort(_ effort: ClaudeCodeEffort, invocation: HotkeyInvocation) async throws -> String {
        try await ensureComposer(invocation: invocation)
        return try await chooseEffort(effort, invocation: invocation)
    }

    /// The verified current selection, read without opening the picker.
    func observeSelection(invocation: HotkeyInvocation) async throws -> (model: ClaudeCodeModel, effort: ClaudeCodeEffort?) {
        try await ensureComposer(invocation: invocation)
        let composer = try await initialComposer(invocation: invocation)
        return (composer.model, composer.effort)
    }

    private func ensureComposer(invocation: HotkeyInvocation) async throws {
        do {
            _ = try await initialComposer(invocation: invocation)
        } catch let failure as SwitchFailure
            where ClaudeAccessibilityPreparationPolicy.shouldPrepare(after: failure) {
            // Current Claude builds often expose the complete composer tree
            // without manual preparation. Setting this attribute eagerly can
            // rebuild Chromium's AX window identity after shortcut capture, so
            // use it only when bounded discovery proved the tree is absent.
            try await prepareWebAccessibility(invocation: invocation)
            _ = try await initialComposer(invocation: invocation)
        }
    }

    private func prepareWebAccessibility(invocation: HotkeyInvocation) async throws {
        try validate(invocation)
        let now = ContinuousClock().now
        guard ClaudeAccessibilityPreparationPolicy.shouldAttempt(
            pid: invocation.pid,
            lastAttempt: lastPreparationAttempt,
            now: now
        ) else { return }
        // Record before acting so a throw below still counts toward the cooldown.
        lastPreparationAttempt = .init(pid: invocation.pid, instant: now)
        logger.info("Re-enabling Claude web accessibility pid=\(invocation.pid, privacy: .public)")
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
        if enhancedResult == .success {
            try await waitForCapturedWindowAfterPreparation(invocation: invocation)
        } else {
            logger.error("Could not enable Claude web accessibility manualError=\(manualResult.rawValue, privacy: .public) enhancedError=\(enhancedResult.rawValue, privacy: .public)")
        }
        try validate(invocation)
    }

    private func waitForCapturedWindowAfterPreparation(
        invocation: HotkeyInvocation
    ) async throws {
        let clock = ContinuousClock()
        let end = clock.now.advanced(by: deadline)
        while true {
            guard AXIsProcessTrusted() else { throw SwitchFailure.permissionMissing }
            guard let running = NSWorkspace.shared.frontmostApplication,
                  running.bundleIdentifier == AppConstants.claudeDesktopBundleID,
                  running.processIdentifier == invocation.pid
            else { throw SwitchFailure.targetChanged(ApplicationTarget.claudeCode.displayName) }

            let application = AXUIElementCreateApplication(invocation.pid)
            let observedWindowID = AXWindowIdentity.focusedWindowID(
                application: application,
                pid: invocation.pid
            )
            switch ClaudeAccessibilityPreparationPolicy.windowState(
                capturedWindowID: invocation.focusedWindowID,
                observedWindowID: observedWindowID
            ) {
            case .ready:
                return
            case .changed:
                throw SwitchFailure.targetChanged(ApplicationTarget.claudeCode.displayName)
            case .awaitingRepublish:
                guard clock.now < end else {
                    throw SwitchFailure.targetChanged(ApplicationTarget.claudeCode.displayName)
                }
                // Enabling Chromium Accessibility can temporarily unpublish the
                // focused AX window. Wait only for the captured native window ID;
                // a different window still aborts immediately.
                try await Task.sleep(for: pollInterval)
            }
        }
    }

    private struct Composer {
        let popup: AXUIElement
        let title: String
        let model: ClaudeCodeModel
        let effort: ClaudeCodeEffort?
        let isCodeTab: Bool
    }

    private struct RawNode {
        let id: Int
        let parentID: Int?
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
    // (e.g. the model popup) before others (e.g. the prompt input), right
    // after a window gains focus or re-renders. A single-shot scan can catch
    // that half-published state and read it as an ambiguous surface. Poll
    // within the same deadline used elsewhere in this file instead of failing
    // on the first inconsistent snapshot.
    private func initialComposer(invocation: HotkeyInvocation) async throws -> Composer {
        let clock = ContinuousClock()
        let end = clock.now.advanced(by: deadline)
        var lastError: Error = SwitchFailure.claudeCodeSurfaceNotFound
        while true {
            do {
                if let composer = try composer(invocation: invocation) { return composer }
            } catch {
                lastError = error
            }
            guard clock.now < end else { throw lastError }
            try await Task.sleep(for: pollInterval)
        }
    }

    private func chooseModel(
        _ model: ClaudeCodeModel,
        invocation: HotkeyInvocation
    ) async throws -> String {
        let initial = try await initialComposer(invocation: invocation)
        if initial.model == model { return model.rawValue }

        var originalPointer: CGPoint?
        var diagnosticPhase = "opening_root"
        defer { TrustedTargetAction.restorePointer(to: originalPointer) }
        do {
            _ = try await openModelMenu(invocation: invocation)
            // Claude replaces parts of the Chromium AX subtree shortly after
            // opening this verified menu. Refresh before targeting a model row.
            try await Task.sleep(for: .milliseconds(500))
            try validate(invocation)
            guard let rootMenu = try await waitForRootMenu(
                title: initial.title,
                timeout: deadline,
                invocation: invocation
            ) else {
                throw SwitchFailure.accessibility("Claude model menu did not stabilize.")
            }
            let moreModels = rootMenu.nodes.filter {
                $0.visible
                    && isDescendant($0.id, of: rootMenu.root.id, in: rootMenu.nodes)
                    && controlLabels($0.element).contains("More models")
                    && validFrame($0.frame)
            }
            let rootRows = modelRows(in: rootMenu)
            guard let location = ClaudePickerModelRouting.location(
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
                    throw SwitchFailure.accessibility("Claude More models row was unavailable.")
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
                    throw SwitchFailure.accessibility("Claude More models menu did not open.")
                }
                menu = nestedMenu
            }
            diagnosticPhase = "focusing_model"
            let rows = modelRows(in: menu)
            guard Set(rows.map(\.model)).count >= 2 else {
                throw SwitchFailure.accessibility("Claude model menu could not be verified.")
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
            try validate(invocation)
            if !verifiedMenuRoots(invocation: invocation).isEmpty {
                let refreshedMenu: LiveMenu?
                switch location {
                case .root:
                    refreshedMenu = try await waitForRootMenu(
                        title: initial.title,
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
            try await waitForMenusToClose(invocation: invocation)
            diagnosticPhase = "verifying_model"
            _ = try await waitForComposer(
                model: model,
                effort: nil,
                invocation: invocation
            )
            return model.rawValue
        } catch {
            logger.error("model_failure phase=\(diagnosticPhase, privacy: .public)")
            try? await dismissVerifiedMenuIfNeeded(invocation: invocation)
            throw error
        }
    }

    private func chooseEffort(
        _ effort: ClaudeCodeEffort,
        invocation: HotkeyInvocation
    ) async throws -> String {
        let initial = try await initialComposer(invocation: invocation)
        if initial.effort == effort { return effort.rawValue }
        let desiredLabels = ClaudePickerLabels.pickerRowLabels(for: effort)
        guard !desiredLabels.isEmpty,
              let currentEffort = initial.effort,
              let currentLabel = ClaudePickerLabels.pickerLabel(for: currentEffort)
        else { throw SwitchFailure.effortUnavailable(effort.rawValue) }

        var originalPointer: CGPoint?
        defer { TrustedTargetAction.restorePointer(to: originalPointer) }
        do {
            _ = try await openModelMenu(invocation: invocation)
            // Claude publishes the verified menu before its nested-menu responder
            // is ready to accept focus, then replaces parts of the Chromium AX
            // subtree. Let it settle and refresh every element reference.
            try await Task.sleep(for: .milliseconds(500))
            try validate(invocation)
            guard let modelMenu = try await waitForRootMenu(
                title: initial.title,
                timeout: deadline,
                invocation: invocation
            ) else {
                throw SwitchFailure.accessibility("Claude model menu did not stabilize.")
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
            // Paid Claude rows advertise AXPress but only take focus. A click on
            // the exact verified row geometry is the native action that opens this
            // nested Chromium menu; submenu and final-state checks remain mandatory.
            originalPointer = try clickMenuRow(trigger, in: modelMenu, invocation: invocation)
            let effortMenu = try await waitForEffortMenu(
                title: triggerLabel,
                timeout: deadline,
                invocation: invocation
            )
            guard let effortMenu else {
                throw SwitchFailure.accessibility("Claude effort menu did not open.")
            }
            let rows = effortRows(in: effortMenu)
            guard Set(rows.map(\.effort)).count >= 3 else {
                throw SwitchFailure.accessibility("Claude effort menu could not be verified.")
            }
            guard let row = uniqueRow(rows.filter { $0.effort == effort }.map(\.node)),
                  rows.contains(where: {
                      $0.node.id == row.id && desiredLabels.contains($0.label)
                  })
            else { throw SwitchFailure.effortUnavailable(effort.rawValue) }
            _ = try performMenuRow(row, in: effortMenu, invocation: invocation)
            try await waitForMenusToClose(invocation: invocation)
            _ = try await waitForComposer(
                model: initial.model,
                effort: effort,
                invocation: invocation
            )
            return effort.rawValue
        } catch {
            try? await dismissVerifiedMenuIfNeeded(invocation: invocation)
            throw error
        }
    }

    private func openModelMenu(invocation: HotkeyInvocation) async throws -> LiveMenu {
        guard verifiedMenuRoots(invocation: invocation).isEmpty,
              let composer = try composer(invocation: invocation)
        else { throw SwitchFailure.accessibility("A Claude model menu was already open.") }

        try TrustedTargetAction.press(composer.popup, invocation: invocation)
        if let menu = try await waitForRootMenu(
            title: composer.title,
            timeout: .milliseconds(350),
            invocation: invocation
        ) { return menu }

        // Chromium can publish the owned menu container before its exact rows.
        // Do not send another open action to that already-open control; let the
        // verified container finish populating within the normal deadline.
        if !verifiedMenuRoots(invocation: invocation).isEmpty {
            guard let menu = try await waitForRootMenu(
                title: composer.title,
                timeout: deadline,
                invocation: invocation
            ) else {
                throw SwitchFailure.accessibility("Claude model menu did not stabilize.")
            }
            return menu
        }

        let actionComposer = try await initialComposer(invocation: invocation)
        guard actionComposer.title == composer.title else {
            throw SwitchFailure.verificationMismatch(
                expected: composer.title,
                observed: actionComposer.title
            )
        }
        let actionNames = actions(actionComposer.popup)
        // On Code's 1.x popups AXShowMenu reported success while opening
        // Chromium's text context menu, and cancelling it stepped the live
        // effort down. Never send it on the Code tab; go straight to the click.
        if !actionComposer.isCodeTab, actionNames.contains(kAXShowMenuAction as String) {
            try TrustedTargetAction.showMenu(actionComposer.popup, invocation: invocation)
            if let menu = try await waitForRootMenu(
                title: composer.title,
                timeout: deadline,
                invocation: invocation
            ) { return menu }

            // Chromium can advertise successful AXPress and AXShowMenu actions
            // while leaving this exact popup closed. Use its fresh verified frame
            // only after both actions have produced no observable owned menu.
            guard verifiedMenuRoots(invocation: invocation).isEmpty else {
                throw SwitchFailure.accessibility("Claude model menu did not stabilize.")
            }
        }
        let clickComposer = try await initialComposer(invocation: invocation)
        guard clickComposer.title == composer.title,
              let popupFrame = AXWindowIdentity.frame(clickComposer.popup)
        else {
            throw SwitchFailure.accessibility("Claude model control geometry was unavailable.")
        }
        let pointer = try TrustedTargetAction.click(frame: popupFrame, invocation: invocation)
        TrustedTargetAction.restorePointer(to: pointer)
        guard let menu = try await waitForRootMenu(
            title: composer.title,
            timeout: deadline,
            invocation: invocation
        ) else { throw SwitchFailure.accessibility("Claude model menu did not open.") }
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

    // The root menu is owned by its exact title, which already encodes the
    // current model and effort. Do not also require the current model's row:
    // a model chosen from More models (for example Sonnet 5) has no root row,
    // and requiring one made it impossible to switch away from such a model.
    private func waitForRootMenu(
        title: String,
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
                && Set(self.modelRows(in: menu).map(\.model)).count >= 2
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
                throw SwitchFailure.accessibility("Claude menu was ambiguous.")
            }
            try await Task.sleep(for: pollInterval)
        }
        return nil
    }

    private func waitForComposer(
        model: ClaudeCodeModel,
        effort: ClaudeCodeEffort?,
        invocation: HotkeyInvocation
    ) async throws -> Composer {
        let clock = ContinuousClock()
        let end = clock.now.advanced(by: deadline)
        var lastTitle = "unexposed"
        while clock.now < end {
            if let current = try composer(invocation: invocation) {
                lastTitle = current.title
                if current.model == model, effort == nil || current.effort == effort {
                    return current
                }
            }
            try await Task.sleep(for: pollInterval)
        }
        let expected = effort.map { "Model: \(model.rawValue) \(ClaudePickerLabels.pickerLabel(for: $0) ?? $0.rawValue)" }
            ?? model.rawValue
        throw SwitchFailure.verificationMismatch(expected: expected, observed: lastTitle)
    }

    private func waitForMenusToClose(invocation: HotkeyInvocation) async throws {
        let clock = ContinuousClock()
        let end = clock.now.advanced(by: deadline)
        while clock.now < end {
            try validate(invocation)
            if verifiedMenuRoots(invocation: invocation).isEmpty { return }
            try await Task.sleep(for: pollInterval)
        }
        throw SwitchFailure.deadlineExceeded("waiting for Claude’s verified model menu to close")
    }

    private func dismissVerifiedMenuIfNeeded(invocation: HotkeyInvocation) async throws {
        try validate(invocation)
        guard !verifiedMenuRoots(invocation: invocation).isEmpty else { return }
        try TrustedTargetAction.postFocusedKey(keyCode: 53, flags: [], invocation: invocation)
        try await waitForMenusToClose(invocation: invocation)
    }

    private func composer(invocation: HotkeyInvocation) throws -> Composer? {
        try validate(invocation)
        let application = AXUIElementCreateApplication(invocation.pid)
        guard let window: AXUIElement = value(application, kAXFocusedWindowAttribute) else {
            throw SwitchFailure.targetChanged(ApplicationTarget.claudeCode.displayName)
        }
        let codeTabSelected = containsCodeSurface(in: window)
        let promptLabel = ClaudeComposerSurface.promptLabel(codeTabSelected: codeTabSelected)
        let nodes = try windowNodes(invocation: invocation)
        let inputs = nodes.filter { node in
            node.visible
                && [kAXTextAreaRole as String, kAXTextFieldRole as String].contains(node.role)
                && controlLabels(node.element).contains(promptLabel)
        }
        let popups = nodes.compactMap { node -> (RawNode, String, ClaudeCodeModel, ClaudeCodeEffort?)? in
            guard node.visible,
                  node.role == kAXPopUpButtonRole as String,
                  node.actionable || node.showsMenu,
                  let title = controlLabels(node.element).first(where: {
                      ClaudePickerLabels.model(inComposerTitle: $0) != nil
                  }),
                  let model = ClaudePickerLabels.model(inComposerTitle: title),
                  validFrame(node.frame)
            else { return nil }
            return (node, title, model, ClaudePickerLabels.effort(inComposerTitle: title))
        }
        guard inputs.count == 1 else {
            logger.error("surface_missing phase=input code=\(codeTabSelected, privacy: .public) inputs=\(inputs.count, privacy: .public) popups=\(popups.count, privacy: .public)")
            if inputs.isEmpty, popups.isEmpty { return nil }
            throw SwitchFailure.accessibility("Claude composer was ambiguous.")
        }
        let candidates = popups.filter {
            sharesBoundedAncestor(
                [inputs[0].id, $0.0.id],
                in: nodes,
                maxDistance: 12
            )
        }
        guard candidates.count == 1 else {
            // popups=0 with a visible prompt usually means Claude renamed the
            // model control or shipped a model outside the closed set. Re-read
            // the live popup title before widening any matcher.
            logger.error("surface_missing phase=relationship code=\(codeTabSelected, privacy: .public) candidates=\(candidates.count, privacy: .public) popups=\(popups.count, privacy: .public)")
            if candidates.isEmpty { return nil }
            throw SwitchFailure.accessibility("Claude model control was ambiguous.")
        }
        let candidate = candidates[0]
        return Composer(
            popup: candidate.0.element,
            title: candidate.1,
            model: candidate.2,
            effort: candidate.3,
            isCodeTab: codeTabSelected
        )
    }

    private func menus(titledAnyOf titles: Set<String>, invocation: HotkeyInvocation) throws -> [LiveMenu] {
        let nodes = try windowNodes(invocation: invocation)
        return nodes.compactMap { node in
            guard node.visible,
                  ClaudeMenuContainer.isCandidate(role: node.role),
                  menuContainerLabels(node).contains(where: titles.contains),
                  validFrame(node.frame)
            else { return nil }
            // Chromium can expose the same nested-menu rows through both the
            // window overlay and the menu. The window-wide breadth-first scan
            // may encounter the overlay path first, which makes a genuinely
            // owned row look unrelated. Re-root the bounded snapshot at the
            // exact verified menu so descendant checks retain menu ownership.
            // Node IDs are positions within one scan, so the menu's root must
            // come from this re-rooted scan for descendant checks to line up.
            let menuNodes = rawNodes(root: node.element, maxDepth: 12, maxNodes: 500)
            guard let root = menuNodes.first else { return nil }
            return LiveMenu(root: root, nodes: menuNodes)
        }
    }

    private func verifiedMenuRoots(invocation: HotkeyInvocation) -> [RawNode] {
        guard let nodes = try? windowNodes(invocation: invocation) else { return [] }
        return nodes.filter { node in
            guard node.visible, ClaudeMenuContainer.isCandidate(role: node.role) else { return false }
            return menuContainerLabels(node).contains { label in
                ClaudePickerLabels.model(inComposerTitle: label) != nil
                    || label == "More models"
                    || ClaudePickerLabels.effortMenuTitles.contains(label)
            }
        }
    }

    // Groups are the bulk of Claude's tree and the 6.x picker container names
    // itself through its title alone, so read one attribute per group instead
    // of three.
    private func menuContainerLabels(_ node: RawNode) -> [String] {
        guard node.role == kAXGroupRole as String else { return controlLabels(node.element) }
        let title: String? = value(node.element, kAXTitleAttribute)
        return title.map { [$0.trimmingCharacters(in: .whitespacesAndNewlines)] } ?? []
    }

    private func modelRows(in menu: LiveMenu) -> [(node: RawNode, model: ClaudeCodeModel)] {
        menu.nodes.compactMap { node in
            guard node.visible,
                  isDescendant(node.id, of: menu.root.id, in: menu.nodes),
                  let model = controlLabels(node.element).compactMap(ClaudePickerLabels.model(inPickerRow:)).first,
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
                      ClaudePickerLabels.effort(inPickerRow: label).map { (effort: $0, label: label) }
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
        else { throw SwitchFailure.accessibility("Claude menu geometry was unavailable.") }
        let point = CGPoint(x: rowFrame.midX, y: rowFrame.midY)
        guard menuFrame.contains(point) else {
            throw SwitchFailure.accessibility("Claude menu row geometry was invalid.")
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
        try validate(invocation)
        let application = AXUIElementCreateApplication(invocation.pid)
        guard let window: AXUIElement = value(application, kAXFocusedWindowAttribute),
              AXWindowIdentity.focusedWindowID(application: application, pid: invocation.pid)
                == invocation.focusedWindowID
        else { throw SwitchFailure.targetChanged(ApplicationTarget.claudeCode.displayName) }
        // Claude Desktop nests the composer controls below several Chromium
        // wrapper groups. Keep this bounded, but deep enough to reach the exact
        // prompt field, model popup, and owned menus: on 6.6395.0 the Code
        // popup sits at depth 31 and its nested effort and More models
        // containers at depth 39.
        let nodes = rawNodes(root: window, maxDepth: 44, maxNodes: 8_000)
        try validate(invocation)
        return nodes
    }

    private func rawNodes(root: AXUIElement, maxDepth: Int, maxNodes: Int) -> [RawNode] {
        ClaudeTreeScan.breadthFirst(root: root, maxDepth: maxDepth, maxNodes: maxNodes) { element in
            value(element, kAXChildrenAttribute) ?? []
        }.map { visit in
            let role: String = value(visit.element, kAXRoleAttribute) ?? ""
            let hidden: Bool = value(visit.element, "AXHidden") ?? false
            let actionNames = actions(visit.element)
            return RawNode(
                id: visit.id,
                parentID: visit.parentID,
                element: visit.element,
                role: role,
                actionable: actionNames.contains(kAXPressAction as String),
                showsMenu: actionNames.contains(kAXShowMenuAction as String),
                visible: !hidden,
                frame: AXWindowIdentity.frame(visit.element)
            )
        }
    }

    private func sharesBoundedAncestor(
        _ ids: [Int],
        in nodes: [RawNode],
        maxDistance: Int
    ) -> Bool {
        guard let first = ids.first else { return false }
        let index = Dictionary(uniqueKeysWithValues: nodes.map { ($0.id, $0) })
        func ancestors(of id: Int) -> Set<Int> {
            var result: Set<Int> = [id]
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
        _ nodeID: Int,
        of ancestorID: Int,
        in nodes: [RawNode]
    ) -> Bool {
        let index = Dictionary(uniqueKeysWithValues: nodes.map { ($0.id, $0) })
        var current = index[nodeID]?.parentID
        var visited = Set<Int>()
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

    private func validate(_ invocation: HotkeyInvocation) throws {
        guard AXIsProcessTrusted() else { throw SwitchFailure.permissionMissing }
        guard invocation.target == .claudeCode,
              let running = NSWorkspace.shared.frontmostApplication,
              running.bundleIdentifier == AppConstants.claudeDesktopBundleID,
              running.processIdentifier == invocation.pid
        else { throw SwitchFailure.targetChanged(ApplicationTarget.claudeCode.displayName) }

        let application = AXUIElementCreateApplication(invocation.pid)
        guard AXWindowIdentity.focusedWindowID(application: application, pid: invocation.pid)
                == invocation.focusedWindowID
        else { throw SwitchFailure.targetChanged(ApplicationTarget.claudeCode.displayName) }
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
        ClaudeTreeScan.breadthFirst(root: root, maxDepth: maxDepth, maxNodes: maxNodes) { element in
            value(element, kAXChildrenAttribute) ?? []
        }.map(\.element)
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

    private func value<T>(_ element: AXUIElement, _ attribute: String) -> T? {
        var result: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, attribute as CFString, &result) == .success else { return nil }
        return result as? T
    }
}
