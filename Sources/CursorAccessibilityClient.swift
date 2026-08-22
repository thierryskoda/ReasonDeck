import AppKit
import ApplicationServices
import Foundation
import os

enum CursorApplyOutcome: Equatable, Sendable {
    case applied(model: CursorModel, effort: CursorEffort)
    case alreadyApplied(model: CursorModel, effort: CursorEffort)
    case partial(model: CursorModel, failure: SwitchFailure)
    case failure(SwitchFailure)
}

protocol CursorUIClient: Sendable {
    func apply(_ selection: CursorSelection, invocation: HotkeyInvocation) async -> CursorApplyOutcome
}

/// Cursor renders some models under a shorter display name than the configured label
/// (`Claude Opus 5` appears as `Opus 5`, Grok models gain a `Cursor` prefix).
/// These aliases stay closed to exact strings typed here; no substring guessing.
enum CursorModelLabels {
    static func aliases(for model: String) -> [String] {
        switch model {
        case "Grok 4.5": ["Grok 4.5", "Cursor Grok 4.5"]
        case "Grok 4.6": ["Grok 4.6", "Cursor Grok 4.6"]
        case "Claude Fable 5": ["Claude Fable 5", "Fable 5"]
        case "Claude Opus 5": ["Claude Opus 5", "Opus 5"]
        case "Claude Sonnet 5": ["Claude Sonnet 5", "Sonnet 5"]
        default: [model]
        }
    }

    static var allAliases: [String] {
        CursorModel.allCases.flatMap { aliases(for: $0.rawValue) }
    }

    static func modelAlias(inChipTitle title: String) -> String? {
        allAliases
            .filter { alias in title == alias || remainderIsEffort(title: title, alias: alias) }
            .max(by: { $0.count < $1.count })
    }

    static func chipShowsModel(_ title: String, model: String) -> Bool {
        guard let alias = modelAlias(inChipTitle: title) else { return false }
        return aliases(for: model).contains(alias)
    }

    static func chipShowsEffort(_ title: String, effort: String) -> Bool {
        guard modelAlias(inChipTitle: title) != nil else { return false }
        return title.hasSuffix(" " + effort)
    }

    static func chipShows(_ title: String, model: String, effort: String) -> Bool {
        chipShowsModel(title, model: model) && chipShowsEffort(title, effort: effort)
    }

    static func model(inTitle title: String) -> String? {
        let normalizedTitle = title.hasSuffix(" POPULAR")
            ? String(title.dropLast(" POPULAR".count))
            : title
        guard let alias = modelAlias(inChipTitle: normalizedTitle) else { return nil }
        return CursorModel.allCases
            .map(\.rawValue)
            .first { aliases(for: $0).contains(alias) }
    }

    static func isModelTriggerLabel(_ label: String, for model: CursorModel) -> Bool {
        label == "Model" || aliases(for: model.rawValue).contains { label == "Model " + $0 }
    }

    static func effort(inParameterLabel label: String) -> CursorEffort? {
        CursorEffort.allCases.first { effort in
            label == effort.rawValue || label == "Effort " + effort.rawValue
        }
    }

    static func modelOnlyChip(in labels: [String]) -> CursorModel? {
        labels.contains(CursorModel.automatic.rawValue) ? .automatic : nil
    }

    static func distinctModels(in titles: [String]) -> Set<String> {
        Set(titles.compactMap(model(inTitle:)))
    }

    static func parsedChipTitle(_ title: String) -> (model: CursorModel, effort: CursorEffort)? {
        guard let modelValue = model(inTitle: title),
              let model = CursorModel(rawValue: modelValue),
              let effort = CursorEffort.allCases.first(where: {
                  chipShowsEffort(title, effort: $0.rawValue)
              })
        else { return nil }
        return (model, effort)
    }

    static func effort(inChipTitle title: String) -> CursorEffort? {
        CursorEffort.allCases.first { effort in
            title == effort.rawValue || title.hasSuffix(" " + effort.rawValue)
        }
    }

    static func parameterMenuLabels(for model: CursorModel) -> Set<String> {
        var labels = Set(aliases(for: model.rawValue).flatMap { alias in
            let lower = alias.lowercased()
            return [
                lower + " parameters",
                lower.replacingOccurrences(of: " ", with: "-") + " parameters",
            ]
        })
        if model == .automatic { labels.insert("auto") }
        return labels
    }

    private static func remainderIsEffort(title: String, alias: String) -> Bool {
        guard title.hasPrefix(alias + " ") else { return false }
        let remainder = String(title.dropFirst(alias.count + 1))
        return CursorEffort.allCases.map(\.rawValue).contains(remainder)
    }
}

enum CursorAXSemantic: Equatable, Sendable {
    case container
    case composerInput
    case composerAccessory
    case modelChip(model: CursorModel?, effort: CursorEffort?)
    case parametersMenu(model: CursorModel)
    case modelTrigger
    case modelSelectionMenu
    case modelItem(CursorModel)
    case effortItem(CursorEffort)
}

struct CursorAXNode: Equatable, Sendable {
    let id: Int
    let parentID: Int?
    let semantic: CursorAXSemantic
    let actionable: Bool
    let showsMenu: Bool
    let visible: Bool
    let frame: CGRect?
}

enum CursorActionTarget: Equatable, Sendable {
    case press(Int)
    case showMenu(Int)
    case clickControl(Int)
    case click(rowID: Int, menuID: Int)
}

struct CursorAXSnapshot: Equatable, Sendable {
    let nodes: [CursorAXNode]

    var byID: [Int: CursorAXNode] {
        Dictionary(uniqueKeysWithValues: nodes.map { ($0.id, $0) })
    }

    func isDescendant(_ nodeID: Int, of ancestorID: Int) -> Bool {
        let index = byID
        var current = index[nodeID]?.parentID
        var visited = Set<Int>()
        while let id = current, visited.insert(id).inserted {
            if id == ancestorID { return true }
            current = index[id]?.parentID
        }
        return false
    }
}

struct CursorComposerContext: Equatable, Sendable {
    let rootID: Int
    let inputID: Int
    let chipID: Int
    let model: CursorModel?
    let effort: CursorEffort?
}

struct CursorModelTransitionLatch: Sendable {
    private let selectedModel: CursorModel
    private var matchingObservations = 0
    private var unexposedObservations = 0

    init(selectedModel: CursorModel) {
        self.selectedModel = selectedModel
    }

    mutating func observe(_ model: CursorModel?) -> Bool {
        if model == selectedModel {
            matchingObservations += 1
            unexposedObservations = 0
            return matchingObservations >= 2
        }
        matchingObservations = 0
        if model == nil {
            unexposedObservations += 1
            return unexposedObservations >= 6
        }
        unexposedObservations = 0
        return false
    }
}

enum CursorSurfaceFailure: Error, Equatable, Sendable {
    case composerUnavailable
    case ambiguousComposer
    case pickerUnavailable
    case ambiguousPicker
    case itemMissing
    case ambiguousItem
}

enum CursorSurfacePlanner {
    static func composer(in snapshot: CursorAXSnapshot) throws -> CursorComposerContext {
        let inputs = snapshot.nodes.filter {
            $0.visible && $0.semantic == .composerInput
        }
        let chips = snapshot.nodes.compactMap { node -> (CursorAXNode, CursorModel?, CursorEffort?)? in
            guard node.visible, node.actionable,
                  case .modelChip(let model, let effort) = node.semantic
            else { return nil }
            return (node, model, effort)
        }
        let accessories = snapshot.nodes.filter {
            $0.visible && $0.semantic == .composerAccessory
        }

        var candidates: [(context: CursorComposerContext, distance: Int)] = []
        for input in inputs {
            for (chip, model, effort) in chips {
                guard let common = nearestCommonAncestor(
                    input.id,
                    chip.id,
                    snapshot: snapshot,
                    maxDistance: 6
                ) else { continue }
                guard accessories.contains(where: {
                    $0.id == common.id || snapshot.isDescendant($0.id, of: common.id)
                }) else { continue }
                candidates.append((
                    CursorComposerContext(
                        rootID: common.id,
                        inputID: input.id,
                        chipID: chip.id,
                        model: model,
                        effort: effort
                    ),
                    common.distance
                ))
            }
        }

        guard let minimum = candidates.map(\.distance).min() else {
            throw CursorSurfaceFailure.composerUnavailable
        }
        let best = candidates.filter { $0.distance == minimum }
        guard best.count == 1 else { throw CursorSurfaceFailure.ambiguousComposer }
        return best[0].context
    }

    static func composerChipTarget(
        in snapshot: CursorAXSnapshot,
        context: CursorComposerContext
    ) throws -> CursorActionTarget {
        guard let chip = snapshot.byID[context.chipID],
              chip.visible,
              chip.id == context.rootID || snapshot.isDescendant(chip.id, of: context.rootID),
              case .modelChip = chip.semantic,
              let frame = chip.frame,
              frame.width > 0,
              frame.height > 0
        else { throw CursorSurfaceFailure.itemMissing }
        return .clickControl(chip.id)
    }

    static func parametersMenu(
        in snapshot: CursorAXSnapshot,
        for model: CursorModel? = nil
    ) throws -> (id: Int, model: CursorModel) {
        let matches = snapshot.nodes.compactMap { node -> (Int, CursorModel)? in
            guard node.visible, case .parametersMenu(let observed) = node.semantic,
                  model == nil || observed == model
            else { return nil }
            return (node.id, observed)
        }
        guard !matches.isEmpty else { throw CursorSurfaceFailure.pickerUnavailable }
        guard matches.count == 1 else { throw CursorSurfaceFailure.ambiguousPicker }
        return matches[0]
    }

    static func modelMenu(in snapshot: CursorAXSnapshot) throws -> Int {
        let menus = snapshot.nodes.filter { node in
            guard node.visible, node.semantic == .modelSelectionMenu else { return false }
            let models = Set(snapshot.nodes.compactMap { item -> CursorModel? in
                guard item.visible,
                      snapshot.isDescendant(item.id, of: node.id),
                      case .modelItem(let model) = item.semantic,
                      actionableTarget(
                          from: item.id,
                          menuID: node.id,
                          snapshot: snapshot
                      ) != nil || item.frame.map({ $0.width > 0 && $0.height > 0 }) == true
                else { return nil }
                return model
            })
            return models.count >= 2
        }
        guard !menus.isEmpty else { throw CursorSurfaceFailure.pickerUnavailable }
        guard menus.count == 1 else { throw CursorSurfaceFailure.ambiguousPicker }
        return menus[0].id
    }

    static func modelTrigger(
        in snapshot: CursorAXSnapshot,
        menuID: Int
    ) throws -> CursorActionTarget {
        try item(
            in: snapshot,
            menuID: menuID,
            semantic: .modelTrigger
        )
    }

    static func modelItem(
        in snapshot: CursorAXSnapshot,
        menuID: Int,
        model: CursorModel
    ) throws -> CursorActionTarget {
        try item(
            in: snapshot,
            menuID: menuID,
            semantic: .modelItem(model)
        )
    }

    static func effortItem(
        in snapshot: CursorAXSnapshot,
        menuID: Int,
        effort: CursorEffort
    ) throws -> CursorActionTarget {
        try item(
            in: snapshot,
            menuID: menuID,
            semantic: .effortItem(effort)
        )
    }

    static func openMenuIDs(in snapshot: CursorAXSnapshot) -> [Int] {
        snapshot.nodes.compactMap { node in
            guard node.visible else { return nil }
            switch node.semantic {
            case .parametersMenu, .modelSelectionMenu: return node.id
            default: return nil
            }
        }
    }

    private static func item(
        in snapshot: CursorAXSnapshot,
        menuID: Int,
        semantic: CursorAXSemantic
    ) throws -> CursorActionTarget {
        let markers = snapshot.nodes.filter { marker in
            marker.visible
                && marker.semantic == semantic
                && snapshot.isDescendant(marker.id, of: menuID)
        }
        let framedMarkers = markers.filter { marker in
            guard let frame = marker.frame else { return false }
            return frame.width > 0 && frame.height > 0
        }
        let clickLeaves = framedMarkers.filter { candidate in
            framedMarkers.allSatisfy { other in
                other.id == candidate.id || snapshot.isDescendant(candidate.id, of: other.id)
            }
        }
        if clickLeaves.count == 1 {
            return .click(rowID: clickLeaves[0].id, menuID: menuID)
        }
        if clickLeaves.count > 1 { throw CursorSurfaceFailure.ambiguousItem }

        let presses = Set(markers.compactMap { marker -> Int? in
            guard marker.visible,
                  marker.semantic == semantic,
                  snapshot.isDescendant(marker.id, of: menuID)
            else { return nil }
            return actionableTarget(
                from: marker.id,
                menuID: menuID,
                snapshot: snapshot
            )
        })
        if presses.count == 1, let press = presses.first { return .press(press) }
        if presses.count > 1 { throw CursorSurfaceFailure.ambiguousItem }

        let rowPresses = Set(markers.compactMap {
            rowScopedActionTarget(
                from: $0.id,
                menuID: menuID,
                snapshot: snapshot,
                maxAncestorDistance: 4
            )
        })
        if rowPresses.count == 1, let press = rowPresses.first { return .press(press) }
        if rowPresses.count > 1 { throw CursorSurfaceFailure.ambiguousItem }

        let showMenuMarkers = markers.filter(\.showsMenu)
        let showMenuRoots = showMenuMarkers.filter { candidate in
            showMenuMarkers.allSatisfy { other in
                other.id == candidate.id || snapshot.isDescendant(other.id, of: candidate.id)
            }
        }
        if showMenuRoots.count == 1 { return .showMenu(showMenuRoots[0].id) }
        if showMenuRoots.count > 1 || (!showMenuMarkers.isEmpty && showMenuRoots.isEmpty) {
            throw CursorSurfaceFailure.ambiguousItem
        }

        let markerMidYs = framedMarkers.compactMap { $0.frame?.midY }
        if let minimumY = markerMidYs.min(), let maximumY = markerMidYs.max(),
           maximumY - minimumY <= 4 {
            let rowY = (minimumY + maximumY) / 2
            let rowActions = snapshot.nodes.filter { candidate in
                guard candidate.visible, candidate.actionable,
                      snapshot.isDescendant(candidate.id, of: menuID),
                      let frame = candidate.frame,
                      frame.width > 0, frame.height > 0, frame.height <= 80
                else { return false }
                return rowY >= frame.minY - 2 && rowY <= frame.maxY + 2
            }
            if rowActions.count == 1 { return .press(rowActions[0].id) }
            if rowActions.count > 1 { throw CursorSurfaceFailure.ambiguousItem }
        }
        guard !clickLeaves.isEmpty else { throw CursorSurfaceFailure.itemMissing }
        throw CursorSurfaceFailure.ambiguousItem
    }

    private static func actionableTarget(
        from markerID: Int,
        menuID: Int,
        snapshot: CursorAXSnapshot
    ) -> Int? {
        let index = snapshot.byID
        var current: Int? = markerID
        var visited = Set<Int>()
        while let id = current, id != menuID, visited.insert(id).inserted {
            guard let node = index[id], node.visible else { return nil }
            if node.actionable { return id }
            current = node.parentID
        }
        return nil
    }

    private static func rowScopedActionTarget(
        from markerID: Int,
        menuID: Int,
        snapshot: CursorAXSnapshot,
        maxAncestorDistance: Int
    ) -> Int? {
        let index = snapshot.byID
        var current = index[markerID]?.parentID
        var distance = 1
        var visited = Set<Int>()
        while let ancestorID = current,
              ancestorID != menuID,
              distance <= maxAncestorDistance,
              visited.insert(ancestorID).inserted {
            let actions = snapshot.nodes.filter {
                $0.visible
                    && $0.actionable
                    && ($0.parentID == ancestorID || snapshot.isDescendant($0.id, of: ancestorID))
            }
            if actions.count == 1 { return actions[0].id }
            current = index[ancestorID]?.parentID
            distance += 1
        }
        return nil
    }

    private static func uniqueNode(
        in snapshot: CursorAXSnapshot,
        matching predicate: (CursorAXNode) -> Bool,
        missing: CursorSurfaceFailure,
        ambiguous: CursorSurfaceFailure
    ) throws -> CursorAXNode {
        let matches = snapshot.nodes.filter { $0.visible && predicate($0) }
        guard !matches.isEmpty else { throw missing }
        guard matches.count == 1 else { throw ambiguous }
        return matches[0]
    }

    private static func nearestCommonAncestor(
        _ firstID: Int,
        _ secondID: Int,
        snapshot: CursorAXSnapshot,
        maxDistance: Int
    ) -> (id: Int, distance: Int)? {
        let index = snapshot.byID
        func ancestors(of id: Int) -> [Int: Int] {
            var output: [Int: Int] = [:]
            var current = index[id]?.parentID
            var distance = 1
            while let value = current, distance <= maxDistance, output[value] == nil {
                output[value] = distance
                current = index[value]?.parentID
                distance += 1
            }
            return output
        }
        let first = ancestors(of: firstID)
        let second = ancestors(of: secondID)
        return first.compactMap { id, firstDistance -> (Int, Int)? in
            guard let secondDistance = second[id] else { return nil }
            let total = firstDistance + secondDistance
            return total <= maxDistance ? (id, total) : nil
        }.min(by: { $0.1 < $1.1 })
    }
}

actor CursorSwitchCoordinator: CursorApplying {
    private let client: any CursorUIClient
    private var isSwitching = false

    init(client: any CursorUIClient = SystemCursorUIClient()) {
        self.client = client
    }

    func apply(_ selection: CursorSelection, invocation: HotkeyInvocation) async -> ProfileSwitchResult {
        let profile = TargetSelection.cursor(selection)
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
        case .alreadyApplied(let model, let effort):
            return .alreadyApplied(
                profile: profile,
                observedTitle: "\(model.rawValue) / \(effort.rawValue)"
            )
        case .partial(let model, let failure):
            return .partialFailure(profile: profile, observedTitle: model.rawValue, failure: failure)
        case .failure(let failure):
            return .failure(profile: profile, failure: failure)
        }
    }
}

struct CursorAXIdentityRegistry<Element> {
    struct Insertion {
        let id: Int
        let isNew: Bool
    }

    private struct Entry {
        let element: Element
        let id: Int
    }

    private let hash: (Element) -> Int
    private let equal: (Element, Element) -> Bool
    private var buckets: [Int: [Entry]] = [:]
    private var nextID = 1

    init(
        hash: @escaping (Element) -> Int,
        equal: @escaping (Element, Element) -> Bool
    ) {
        self.hash = hash
        self.equal = equal
    }

    mutating func insert(_ element: Element) -> Insertion {
        let hashValue = hash(element)
        if let existing = buckets[hashValue]?.first(where: {
            equal($0.element, element)
        }) {
            return Insertion(id: existing.id, isNew: false)
        }

        let id = nextID
        nextID += 1
        buckets[hashValue, default: []].append(Entry(element: element, id: id))
        return Insertion(id: id, isNew: true)
    }
}

actor SystemCursorUIClient: CursorUIClient {
    private let logger = Logger(
        subsystem: "com.thierryai.ReasonDeck",
        category: "cursor-surface"
    )
    private let transitionTimeout: Duration = .seconds(2.5)
    private let verificationTimeout: Duration = .seconds(1.5)
    private let pollInterval: Duration = .milliseconds(40)

    func apply(_ selection: CursorSelection, invocation: HotkeyInvocation) async -> CursorApplyOutcome {
        var verifiedModel: CursorModel?
        do {
            try TrustedTargetAction.validate(invocation)
            let initial = try composer(invocation: invocation)
            if initial.context.model == selection.model,
               initial.context.effort == selection.effort
            {
                return .alreadyApplied(model: selection.model, effort: selection.effort)
            }
            var changed = false
            var currentComposer = initial
            var parameters = try await openParameters(
                from: currentComposer,
                expectedModel: currentComposer.context.model,
                invocation: invocation
            )

            if parameters.model != selection.model {
                try await selectModel(
                    selection.model,
                    from: parameters,
                    invocation: invocation
                )
                changed = true
                currentComposer = try await waitForComposerAfterModelSelection(
                    selection.model,
                    invocation: invocation
                )
                parameters = try await openParameters(
                    from: currentComposer,
                    expectedModel: selection.model,
                    invocation: invocation
                )
            }
            guard parameters.model == selection.model else {
                throw SwitchFailure.verificationMismatch(
                    expected: selection.model.rawValue,
                    observed: parameters.model.rawValue
                )
            }
            verifiedModel = selection.model

            if currentComposer.context.effort != selection.effort {
                try await selectEffort(selection.effort, from: parameters, invocation: invocation)
                changed = true
                currentComposer = try await waitForComposer(
                    model: nil,
                    effort: selection.effort,
                    invocation: invocation
                )
                parameters = try await openParameters(
                    from: currentComposer,
                    expectedModel: selection.model,
                    invocation: invocation
                )
            }

            guard parameters.model == selection.model,
                  currentComposer.context.effort == selection.effort
            else {
                throw SwitchFailure.verificationMismatch(
                    expected: selection.displayName,
                    observed: "\(parameters.model.rawValue) / \(currentComposer.context.effort?.rawValue ?? "unexposed")"
                )
            }
            try await closeVerifiedMenu(invocation: invocation)
            return changed
                ? .applied(model: selection.model, effort: selection.effort)
                : .alreadyApplied(model: selection.model, effort: selection.effort)
        } catch let failure as SwitchFailure {
            try? await dismissVerifiedMenuIfNeeded(invocation: invocation)
            if let verifiedModel {
                return .partial(model: verifiedModel, failure: failure)
            }
            return .failure(failure)
        } catch {
            try? await dismissVerifiedMenuIfNeeded(invocation: invocation)
            let failure = SwitchFailure.accessibility(String(describing: error))
            if let verifiedModel {
                return .partial(model: verifiedModel, failure: failure)
            }
            return .failure(failure)
        }
    }

    private func selectModel(
        _ model: CursorModel,
        from parameters: VerifiedParameters,
        invocation: HotkeyInvocation
    ) async throws {
        let trigger: CursorActionTarget
        do {
            trigger = try CursorSurfacePlanner.modelTrigger(
                in: parameters.snapshot,
                menuID: parameters.menuID
            )
        } catch CursorSurfaceFailure.itemMissing {
            logger.error("item_missing phase=model_trigger")
            throw SwitchFailure.cursorMenuItemMissing(parameters.model.rawValue)
        }
        let originalPointer = try perform(trigger, in: parameters.live, invocation: invocation)
        defer { TrustedTargetAction.restorePointer(to: originalPointer) }

        let models = try await waitForModelMenu(invocation: invocation)
        let item: CursorActionTarget
        do {
            item = try CursorSurfacePlanner.modelItem(
                in: models.snapshot,
                menuID: models.menuID,
                model: model
            )
        } catch CursorSurfaceFailure.itemMissing {
            logger.error("item_missing phase=model_selection")
            throw SwitchFailure.cursorMenuItemMissing(model.rawValue)
        }
        _ = try perform(item, in: models.live, invocation: invocation)
        try await waitForMenusToClose(invocation: invocation)
    }

    private func selectEffort(
        _ effort: CursorEffort,
        from parameters: VerifiedParameters,
        invocation: HotkeyInvocation
    ) async throws {
        let item: CursorActionTarget
        do {
            item = try CursorSurfacePlanner.effortItem(
                in: parameters.snapshot,
                menuID: parameters.menuID,
                effort: effort
            )
        } catch CursorSurfaceFailure.itemMissing {
            logger.error("item_missing phase=effort_selection")
            throw SwitchFailure.cursorMenuItemMissing(effort.rawValue)
        }
        let originalPointer = try perform(item, in: parameters.live, invocation: invocation)
        defer { TrustedTargetAction.restorePointer(to: originalPointer) }
        try await waitForMenusToClose(invocation: invocation)
    }

    private func openParameters(
        from composer: VerifiedComposer,
        expectedModel: CursorModel?,
        invocation: HotkeyInvocation
    ) async throws -> VerifiedParameters {
        try TrustedTargetAction.validate(invocation)
        guard CursorSurfacePlanner.openMenuIDs(in: composer.live.snapshot).isEmpty else {
            throw SwitchFailure.accessibility("A Cursor model menu was already open.")
        }
        let trigger: CursorActionTarget
        do {
            trigger = try CursorSurfacePlanner.composerChipTarget(
                in: composer.live.snapshot,
                context: composer.context
            )
        } catch CursorSurfaceFailure.itemMissing {
            throw SwitchFailure.cursorModelControlUnavailable
        }
        let originalPointer = try perform(
            trigger,
            in: composer.live,
            invocation: invocation
        )
        defer { TrustedTargetAction.restorePointer(to: originalPointer) }
        _ = try await waitForParametersMenu(model: expectedModel, invocation: invocation)
        try await Task.sleep(for: .milliseconds(120))
        return try await waitForParametersMenu(model: expectedModel, invocation: invocation)
    }

    private struct VerifiedComposer {
        let live: LiveCursorSnapshot
        let context: CursorComposerContext
    }

    private func composer(invocation: HotkeyInvocation) throws -> VerifiedComposer {
        let live = try liveSnapshot(invocation: invocation)
        do {
            return VerifiedComposer(
                live: live,
                context: try CursorSurfacePlanner.composer(in: live.snapshot)
            )
        } catch CursorSurfaceFailure.composerUnavailable {
            let inputs = live.snapshot.nodes.count { $0.visible && $0.semantic == .composerInput }
            let accessories = live.snapshot.nodes.count { $0.visible && $0.semantic == .composerAccessory }
            let chips = live.snapshot.nodes.count {
                guard $0.visible else { return false }
                if case .modelChip = $0.semantic { return true }
                return false
            }
            logger.error("composer_unavailable inputs=\(inputs, privacy: .public) accessories=\(accessories, privacy: .public) chips=\(chips, privacy: .public)")
            throw SwitchFailure.cursorModelControlUnavailable
        } catch CursorSurfaceFailure.ambiguousComposer {
            throw SwitchFailure.accessibility("Cursor composer model control was ambiguous.")
        }
    }

    private func waitForComposer(
        model: CursorModel?,
        effort: CursorEffort?,
        invocation: HotkeyInvocation
    ) async throws -> VerifiedComposer {
        let clock = ContinuousClock()
        let end = clock.now.advanced(by: verificationTimeout)
        while clock.now < end {
            try TrustedTargetAction.validate(invocation)
            do {
                let current = try composer(invocation: invocation)
                if (model == nil || current.context.model == model),
                   effort == nil || current.context.effort == effort {
                    return current
                }
            } catch SwitchFailure.cursorModelControlUnavailable {
                // Cursor rebuilds the chip briefly after a menu selection.
            }
            try await Task.sleep(for: pollInterval)
        }
        let current = try composer(invocation: invocation)
        let expectedModel = model?.rawValue ?? "current model"
        let expected = effort.map { "\(expectedModel) / \($0.rawValue)" } ?? expectedModel
        let observed = "\(current.context.model?.rawValue ?? "unexposed") / \(current.context.effort?.rawValue ?? "unexposed")"
        throw SwitchFailure.verificationMismatch(expected: expected, observed: observed)
    }

    private func waitForComposerAfterModelSelection(
        _ selectedModel: CursorModel,
        invocation: HotkeyInvocation
    ) async throws -> VerifiedComposer {
        let clock = ContinuousClock()
        let end = clock.now.advanced(by: verificationTimeout)
        var latch = CursorModelTransitionLatch(selectedModel: selectedModel)
        var lastObserved: CursorModel?
        while clock.now < end {
            try TrustedTargetAction.validate(invocation)
            do {
                let current = try composer(invocation: invocation)
                lastObserved = current.context.model
                if latch.observe(current.context.model) {
                    return current
                }
            } catch SwitchFailure.cursorModelControlUnavailable {
                // Cursor may briefly rebuild the composer after closing its menu.
            }
            try await Task.sleep(for: pollInterval)
        }
        throw SwitchFailure.verificationMismatch(
            expected: selectedModel.rawValue,
            observed: lastObserved?.rawValue ?? "unexposed"
        )
    }

    private struct VerifiedParameters {
        let live: LiveCursorSnapshot
        let snapshot: CursorAXSnapshot
        let menuID: Int
        let model: CursorModel
    }

    private struct VerifiedMenu {
        let live: LiveCursorSnapshot
        let snapshot: CursorAXSnapshot
        let menuID: Int
    }

    private func waitForParametersMenu(
        model: CursorModel?,
        invocation: HotkeyInvocation
    ) async throws -> VerifiedParameters {
        let clock = ContinuousClock()
        let end = clock.now.advanced(by: transitionTimeout)
        while clock.now < end {
            let live = try liveSnapshot(invocation: invocation)
            do {
                let menu = try CursorSurfacePlanner.parametersMenu(in: live.snapshot, for: model)
                return VerifiedParameters(
                    live: live,
                    snapshot: live.snapshot,
                    menuID: menu.id,
                    model: menu.model
                )
            } catch CursorSurfaceFailure.pickerUnavailable {
                try await Task.sleep(for: pollInterval)
            } catch CursorSurfaceFailure.ambiguousPicker {
                throw SwitchFailure.accessibility("Cursor parameters menu was ambiguous.")
            }
        }
        throw SwitchFailure.cursorPickerDidNotOpen
    }

    private func waitForModelMenu(invocation: HotkeyInvocation) async throws -> VerifiedMenu {
        let clock = ContinuousClock()
        let end = clock.now.advanced(by: transitionTimeout)
        while clock.now < end {
            let live = try liveSnapshot(invocation: invocation)
            do {
                _ = try CursorSurfacePlanner.modelMenu(in: live.snapshot)
                try await Task.sleep(for: .milliseconds(120))
                let stable = try liveSnapshot(invocation: invocation)
                let stableMenu = try CursorSurfacePlanner.modelMenu(in: stable.snapshot)
                return VerifiedMenu(
                    live: stable,
                    snapshot: stable.snapshot,
                    menuID: stableMenu
                )
            } catch CursorSurfaceFailure.pickerUnavailable {
                try await Task.sleep(for: pollInterval)
            } catch CursorSurfaceFailure.ambiguousPicker {
                throw SwitchFailure.accessibility("Cursor model-selection menu was ambiguous.")
            }
        }
        throw SwitchFailure.cursorPickerDidNotOpen
    }

    private func waitForMenusToClose(invocation: HotkeyInvocation) async throws {
        let clock = ContinuousClock()
        let end = clock.now.advanced(by: verificationTimeout)
        while clock.now < end {
            let live = try liveSnapshot(invocation: invocation)
            if CursorSurfacePlanner.openMenuIDs(in: live.snapshot).isEmpty { return }
            try await Task.sleep(for: pollInterval)
        }
        throw SwitchFailure.deadlineExceeded("waiting for Cursor’s verified model menu to close")
    }

    private func closeVerifiedMenu(invocation: HotkeyInvocation) async throws {
        let live = try liveSnapshot(invocation: invocation)
        guard !CursorSurfacePlanner.openMenuIDs(in: live.snapshot).isEmpty else {
            throw SwitchFailure.verificationMismatch(
                expected: "verified Cursor parameters menu",
                observed: "menu disappeared before final verification"
            )
        }
        try TrustedTargetAction.postKey(keyCode: 53, flags: [], invocation: invocation)
        try await waitForMenusToClose(invocation: invocation)
    }

    /// Sends at most one Escape, and only when the captured window still exposes a verified
    /// Cursor model menu root. No cleanup key is sent after normal menu auto-dismissal.
    private func dismissVerifiedMenuIfNeeded(invocation: HotkeyInvocation) async throws {
        let live = try liveSnapshot(invocation: invocation)
        guard !CursorSurfacePlanner.openMenuIDs(in: live.snapshot).isEmpty else { return }
        try TrustedTargetAction.postKey(keyCode: 53, flags: [], invocation: invocation)
    }

    private func perform(
        _ target: CursorActionTarget,
        in live: LiveCursorSnapshot,
        invocation: HotkeyInvocation
    ) throws -> CGPoint? {
        switch target {
        case .press(let id):
            guard let node = live.snapshot.byID[id], node.visible, node.actionable,
                  let element = live.elements[id]
            else { throw SwitchFailure.accessibility("Cursor action target became unavailable.") }
            try TrustedTargetAction.press(element, invocation: invocation)
            return nil
        case .showMenu(let id):
            guard let node = live.snapshot.byID[id], node.visible, node.showsMenu,
                  let element = live.elements[id]
            else { throw SwitchFailure.accessibility("Cursor menu target became unavailable.") }
            try TrustedTargetAction.showMenu(element, invocation: invocation)
            return nil
        case .clickControl(let id):
            guard let node = live.snapshot.byID[id],
                  node.visible,
                  case .modelChip = node.semantic,
                  let frame = node.frame
            else {
                throw SwitchFailure.accessibility("Cursor model control became unavailable.")
            }
            return try TrustedTargetAction.click(frame: frame, invocation: invocation)
        case .click(let rowID, let menuID):
            guard let row = live.snapshot.byID[rowID], row.visible,
                  let rowFrame = row.frame,
                  let menu = live.snapshot.byID[menuID], menu.visible,
                  let menuFrame = menu.frame,
                  menuFrame.width > 0, menuFrame.height > 0,
                  menuFrame.width <= 1_000, menuFrame.height <= 1_000
            else {
                throw SwitchFailure.accessibility("Cursor click target became unavailable.")
            }
            let point = CGPoint(x: menuFrame.midX, y: rowFrame.midY)
            guard menuFrame.contains(point) else {
                throw SwitchFailure.accessibility("Cursor menu row geometry was invalid.")
            }
            let target = CGRect(x: point.x - 1, y: point.y - 1, width: 2, height: 2)
            return try TrustedTargetAction.click(frame: target, invocation: invocation)
        }
    }

    private struct RawCursorNode {
        let id: Int
        let parentID: Int?
        let element: AXUIElement
        let role: String
        let actionable: Bool
        let showsMenu: Bool
        let visible: Bool
    }

    private struct LiveCursorSnapshot {
        let snapshot: CursorAXSnapshot
        let elements: [Int: AXUIElement]
    }

    private func liveSnapshot(invocation: HotkeyInvocation) throws -> LiveCursorSnapshot {
        try TrustedTargetAction.validate(invocation)
        let application = AXUIElementCreateApplication(invocation.pid)
        guard let window: AXUIElement = value(application, kAXFocusedWindowAttribute),
              AXWindowIdentity.focusedWindowID(application: application, pid: invocation.pid)
                == invocation.focusedWindowID
        else { throw SwitchFailure.targetChanged(ApplicationTarget.cursor.displayName) }

        let raw = rawNodes(root: window, maxDepth: 22, maxNodes: 6_000)
        let rawByID = Dictionary(uniqueKeysWithValues: raw.map { ($0.id, $0) })
        let menuPairs: [(Int, CursorAXSemantic)] = raw.compactMap { node -> (Int, CursorAXSemantic)? in
            guard node.role == kAXMenuRole as String else { return nil }
            let labels = safeLabels(node.element, includeValue: false)
            if labels.contains("Model selection") {
                return (node.id, .modelSelectionMenu)
            }
            let normalizedLabels = Set(labels.map { $0.lowercased() })
            for model in CursorModel.allCases where !CursorModelLabels.parameterMenuLabels(for: model).isDisjoint(with: normalizedLabels) {
                return (node.id, .parametersMenu(model: model))
            }
            return nil
        }
        let menuSemantics = Dictionary(uniqueKeysWithValues: menuPairs)

        func isInsideVerifiedMenu(_ node: RawCursorNode) -> Bool {
            var current = node.parentID
            var visited = Set<Int>()
            while let id = current, visited.insert(id).inserted {
                if menuSemantics[id] != nil { return true }
                current = rawByID[id]?.parentID
            }
            return false
        }

        func parametersMenuAncestor(of node: RawCursorNode) -> Int? {
            var current: Int? = node.id
            var visited = Set<Int>()
            while let id = current, visited.insert(id).inserted {
                if case .parametersMenu? = menuSemantics[id] { return id }
                current = rawByID[id]?.parentID
            }
            return nil
        }

        func nearestActionableAncestor(of node: RawCursorNode, stoppingAt menuID: Int) -> Int? {
            var current: Int? = node.id
            var visited = Set<Int>()
            while let id = current, id != menuID, visited.insert(id).inserted {
                if rawByID[id]?.actionable == true { return id }
                current = rawByID[id]?.parentID
            }
            return nil
        }

        let modelTriggerIDs = Set(raw.compactMap { node -> Int? in
            guard let menuID = parametersMenuAncestor(of: node),
                  case .parametersMenu(let model)? = menuSemantics[menuID],
                  safeLabels(node.element, includeValue: true).contains(where: {
                      CursorModelLabels.isModelTriggerLabel($0, for: model)
                  })
            else { return nil }
            return nearestActionableAncestor(of: node, stoppingAt: menuID)
        })
        let nodes = raw.map { node -> CursorAXNode in
            let semantic: CursorAXSemantic
            if let menu = menuSemantics[node.id] {
                semantic = menu
            } else if modelTriggerIDs.contains(node.id) {
                semantic = .modelTrigger
            } else if [kAXTextAreaRole as String, kAXTextFieldRole as String].contains(node.role) {
                semantic = .composerInput
            } else if node.role == kAXPopUpButtonRole as String,
                      safeLabels(node.element, includeValue: true).contains(Self.composerAccessoryLabel) {
                semantic = .composerAccessory
            } else if node.role == kAXPopUpButtonRole as String,
                      let chip = chipSemantic(
                          labels: safeLabels(node.element, includeValue: true)
                      ) {
                semantic = chip
            } else if isInsideVerifiedMenu(node) {
                let labels = safeLabels(node.element, includeValue: true)
                if let menuID = parametersMenuAncestor(of: node),
                   case .parametersMenu(let model)? = menuSemantics[menuID],
                   labels.contains(where: {
                       CursorModelLabels.isModelTriggerLabel($0, for: model)
                   }) {
                    semantic = .modelTrigger
                } else if let effort = labels.compactMap(CursorModelLabels.effort(inParameterLabel:)).first {
                    semantic = .effortItem(effort)
                } else if let modelValue = labels.compactMap(CursorModelLabels.model(inTitle:)).first,
                          let model = CursorModel(rawValue: modelValue) {
                    semantic = .modelItem(model)
                } else {
                    semantic = .container
                }
            } else {
                semantic = .container
            }
            return CursorAXNode(
                id: node.id,
                parentID: node.parentID,
                semantic: semantic,
                actionable: node.actionable,
                showsMenu: node.showsMenu,
                visible: node.visible,
                frame: AXWindowIdentity.frame(node.element)
            )
        }
        try TrustedTargetAction.validate(invocation)
        return LiveCursorSnapshot(
            snapshot: CursorAXSnapshot(nodes: nodes),
            elements: Dictionary(uniqueKeysWithValues: raw.map { ($0.id, $0.element) })
        )
    }

    private static let composerAccessoryLabel = "Add agents, context, tools"

    private func chipSemantic(labels: [String]) -> CursorAXSemantic? {
        if let parsed = labels.compactMap(CursorModelLabels.parsedChipTitle).first {
            return .modelChip(model: parsed.model, effort: parsed.effort)
        }
        if let effort = labels.compactMap(CursorModelLabels.effort(inChipTitle:)).first {
            return .modelChip(model: nil, effort: effort)
        }
        if let model = CursorModelLabels.modelOnlyChip(in: labels) {
            return .modelChip(model: model, effort: nil)
        }
        return nil
    }

    private func rawNodes(root: AXUIElement, maxDepth: Int, maxNodes: Int) -> [RawCursorNode] {
        var queue: [(AXUIElement, Int?, Int)] = [(root, nil, 0)]
        var output: [RawCursorNode] = []
        var identities = CursorAXIdentityRegistry<AXUIElement>(
            hash: { Int(CFHash($0)) },
            equal: { CFEqual($0, $1) }
        )
        var index = 0
        while index < queue.count, output.count < maxNodes {
            let (element, parentID, depth) = queue[index]
            index += 1
            let identity = identities.insert(element)
            guard identity.isNew else { continue }
            let id = identity.id
            let role: String = value(element, kAXRoleAttribute) ?? ""
            let hidden: Bool = value(element, "AXHidden") ?? false
            let actionNames = actions(element)
            output.append(RawCursorNode(
                id: id,
                parentID: parentID,
                element: element,
                role: role,
                actionable: actionNames.contains(kAXPressAction as String),
                showsMenu: actionNames.contains(kAXShowMenuAction as String),
                visible: !hidden
            ))
            guard depth < maxDepth else { continue }
            let children: [AXUIElement] = value(element, kAXChildrenAttribute) ?? []
            let visibleChildren: [AXUIElement] = value(element, kAXVisibleChildrenAttribute) ?? []
            queue.append(contentsOf: (children + visibleChildren).map { ($0, id, depth + 1) })
        }
        return output
    }

    /// Reads labels only from allowlisted control roles or descendants of an already verified
    /// model menu. It never reads editor, transcript, or arbitrary text-node values.
    private func safeLabels(_ element: AXUIElement, includeValue: Bool) -> [String] {
        var attributes = [kAXTitleAttribute, kAXDescriptionAttribute, kAXHelpAttribute]
        if includeValue { attributes.append(kAXValueAttribute) }
        return attributes
            .compactMap { value(element, $0) as String? }
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
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
