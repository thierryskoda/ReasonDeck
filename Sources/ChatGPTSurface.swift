import CoreGraphics
import Foundation

/// A privacy-safe projection of the ChatGPT Accessibility tree.  It never
/// retains arbitrary strings: labels are classified only into closed product
/// values or an `unknownText` marker before reaching the planner.
enum ChatGPTAXLabel: Hashable, Sendable {
    case model(ChatGPTModel)
    case effort(ChatGPTReasoningEffort)
    case modelRow
    case effortRow
    case selectModel
    case selectEffort
    case power
    case powerInstructions
    case powerStatus(ChatGPTPowerStatus)
    case unknownText
}

enum ChatGPTAXAction: Hashable, Sendable {
    case press
    case showMenu
}

struct ChatGPTAXNode: Equatable, Sendable {
    let id: Int
    let parentID: Int?
    let role: String
    let labels: Set<ChatGPTAXLabel>
    let actions: Set<ChatGPTAXAction>
    let visible: Bool
    let frame: CGRect?
    var expanded: Bool? = nil
}

struct ChatGPTAXSnapshot: Equatable, Sendable {
    let windowFrame: CGRect
    let nodes: [ChatGPTAXNode]

    var byID: [Int: ChatGPTAXNode] {
        Dictionary(uniqueKeysWithValues: nodes.map { ($0.id, $0) })
    }

    func isDescendant(_ child: Int, of ancestor: Int) -> Bool {
        let index = byID
        var current = index[child]?.parentID
        var visited = Set<Int>()
        while let id = current, visited.insert(id).inserted {
            if id == ancestor { return true }
            current = index[id]?.parentID
        }
        return false
    }
}

enum ChatGPTActionTarget: Equatable, Sendable {
    case press(Int)
    case showMenu(Int)
    /// Geometry is allowed only for a single framed control inside the already
    /// proven composer; callers must bind this ID to its originating snapshot.
    case click(Int)
}

struct ChatGPTComposerSurface: Equatable, Sendable {
    let composerID: Int
    let modelControlID: Int
    let observedModel: ChatGPTModel?
    let observedEffort: ChatGPTReasoningEffort?
}

/// The top-level state exposed by ChatGPT after its own Select model command
/// opens the native picker. The action targets are snapshot-local and must be
/// resolved again after every mutation.
struct ChatGPTNativePicker: Equatable, Sendable {
    let model: ChatGPTModel
    let effort: ChatGPTReasoningEffort
    let modelRow: ChatGPTActionTarget
    let effortRow: ChatGPTActionTarget
}

enum ChatGPTSurfaceFailure: Error, Equatable, Sendable {
    case unsupportedSurface
    case ambiguousComposer
    case controlUnavailable
    case ambiguousControl
    case itemMissing
    case ambiguousItem
}

enum ChatGPTSurfacePlanner {
    static func nativePicker(in snapshot: ChatGPTAXSnapshot) throws -> ChatGPTNativePicker {
        let modelRow = try uniqueNativePickerRow(.modelRow, in: snapshot)
        let effortRow = try uniqueNativePickerRow(.effortRow, in: snapshot)
        guard modelRow != effortRow else { throw ChatGPTSurfaceFailure.ambiguousItem }
        guard let model = uniqueModel(near: modelRow, in: snapshot),
              let effort = uniqueEffort(near: effortRow, in: snapshot)
        else { throw ChatGPTSurfaceFailure.itemMissing }
        return ChatGPTNativePicker(
            model: model,
            effort: effort,
            modelRow: modelRow,
            effortRow: effortRow
        )
    }

    static func composer(in snapshot: ChatGPTAXSnapshot) throws -> ChatGPTComposerSurface {
        let inputs = snapshot.nodes.filter { $0.visible && $0.role == "AXTextArea" }
        let controls = snapshot.nodes.filter { node in
            node.visible && node.frame != nil
                && (node.labels.contains(where: isModelBearing) || node.labels.contains(.modelRow))
        }
        var candidates: [ChatGPTComposerSurface] = []
        for input in inputs {
            for control in controls {
                guard let root = nearestCommonAncestor(input.id, control.id, in: snapshot, maximumDistance: 6),
                      let rootNode = snapshot.byID[root], rootNode.visible,
                      let frame = rootNode.frame,
                      frame.contains(inputFrame(input, snapshot: snapshot)),
                      frame.contains(controlFrame(control, snapshot: snapshot))
                else { continue }
                candidates.append(ChatGPTComposerSurface(
                    composerID: root,
                    modelControlID: control.id,
                    observedModel: control.labels.compactMap(model).first,
                    observedEffort: control.labels.compactMap(effort).first
                ))
            }
        }
        guard !candidates.isEmpty else { throw ChatGPTSurfaceFailure.unsupportedSurface }
        let unique = Dictionary(grouping: candidates, by: { "\($0.composerID):\($0.modelControlID)" }).values.compactMap { $0.first }
        guard unique.count == 1 else { throw ChatGPTSurfaceFailure.ambiguousComposer }
        return unique[0]
    }

    static func modelControl(
        in snapshot: ChatGPTAXSnapshot,
        composer: ChatGPTComposerSurface
    ) throws -> ChatGPTActionTarget {
        guard let control = snapshot.byID[composer.modelControlID], control.visible,
              snapshot.isDescendant(control.id, of: composer.composerID) || control.id == composer.composerID
        else { throw ChatGPTSurfaceFailure.controlUnavailable }
        if control.actions.contains(.showMenu) { return .showMenu(control.id) }
        if control.actions.contains(.press) { return .press(control.id) }
        guard let frame = control.frame,
              frame.width > 0, frame.height > 0,
              snapshot.windowFrame.contains(CGPoint(x: frame.midX, y: frame.midY))
        else { throw ChatGPTSurfaceFailure.controlUnavailable }
        return .click(control.id)
    }

    static func row(
        _ label: ChatGPTAXLabel,
        in snapshot: ChatGPTAXSnapshot,
        menuID: Int
    ) throws -> ChatGPTActionTarget {
        try uniqueActionable(
            snapshot.nodes.filter { $0.visible && $0.labels.contains(label) && snapshot.isDescendant($0.id, of: menuID) },
            snapshot: snapshot
        )
    }

    static func item(
        model: ChatGPTModel,
        in snapshot: ChatGPTAXSnapshot,
        menuID: Int
    ) throws -> ChatGPTActionTarget {
        try row(.model(model), in: snapshot, menuID: menuID)
    }

    static func item(
        effort: ChatGPTReasoningEffort,
        in snapshot: ChatGPTAXSnapshot,
        menuID: Int
    ) throws -> ChatGPTActionTarget {
        try row(.effort(effort), in: snapshot, menuID: menuID)
    }

    private static func uniqueActionable(_ nodes: [ChatGPTAXNode], snapshot: ChatGPTAXSnapshot) throws -> ChatGPTActionTarget {
        let matches = nodes.compactMap { node -> ChatGPTActionTarget? in
            if node.actions.contains(.press) { return .press(node.id) }
            if node.actions.contains(.showMenu) { return .showMenu(node.id) }
            guard let frame = node.frame,
                  snapshot.windowFrame.contains(CGPoint(x: frame.midX, y: frame.midY))
            else { return nil }
            return .click(node.id)
        }
        guard !matches.isEmpty else { throw ChatGPTSurfaceFailure.itemMissing }
        guard matches.count == 1, let match = matches.first else { throw ChatGPTSurfaceFailure.ambiguousItem }
        return match
    }

    /// A real ChatGPT picker row is a pressable menu item. Its closed label can
    /// live on a static-text child, but generic AXGroups that merely contain the
    /// whole popover must never become a row action.
    private static func uniqueNativePickerRow(
        _ label: ChatGPTAXLabel,
        in snapshot: ChatGPTAXSnapshot
    ) throws -> ChatGPTActionTarget {
        var matches: [ChatGPTActionTarget] = []
        for node in snapshot.nodes where node.visible && node.labels.contains(label) {
            guard let candidate = directActionableAncestor(of: node.id, in: snapshot),
                  case .press(let id) = candidate,
                  let target = snapshot.byID[id],
                  target.role == "AXMenuItem",
                  !matches.contains(candidate)
            else { continue }
            matches.append(candidate)
        }
        guard !matches.isEmpty else { throw ChatGPTSurfaceFailure.itemMissing }
        guard matches.count == 1, let match = matches.first else { throw ChatGPTSurfaceFailure.ambiguousItem }
        return match
    }

    private static func directActionableAncestor(
        of nodeID: Int,
        in snapshot: ChatGPTAXSnapshot
    ) -> ChatGPTActionTarget? {
        var current: Int? = nodeID
        var visited = Set<Int>()
        for _ in 0..<4 {
            guard let id = current, visited.insert(id).inserted, let node = snapshot.byID[id] else { return nil }
            if node.actions.contains(.press) { return .press(id) }
            if node.actions.contains(.showMenu) { return .showMenu(id) }
            current = node.parentID
        }
        return nil
    }

    private static func isModelBearing(_ label: ChatGPTAXLabel) -> Bool {
        if case .model = label { return true }
        return false
    }
    private static func model(_ label: ChatGPTAXLabel) -> ChatGPTModel? { if case .model(let value) = label { return value }; return nil }
    private static func effort(_ label: ChatGPTAXLabel) -> ChatGPTReasoningEffort? { if case .effort(let value) = label { return value }; return nil }

    private static func uniqueModel(
        near action: ChatGPTActionTarget,
        in snapshot: ChatGPTAXSnapshot
    ) -> ChatGPTModel? {
        uniqueValue(
            snapshot.nodes.filter { belongs($0.id, to: action, in: snapshot) }.flatMap { $0.labels.compactMap(model) }
        )
    }

    private static func uniqueEffort(
        near action: ChatGPTActionTarget,
        in snapshot: ChatGPTAXSnapshot
    ) -> ChatGPTReasoningEffort? {
        uniqueValue(
            snapshot.nodes.filter { belongs($0.id, to: action, in: snapshot) }.flatMap { $0.labels.compactMap(effort) }
        )
    }

    private static func belongs(_ nodeID: Int, to action: ChatGPTActionTarget, in snapshot: ChatGPTAXSnapshot) -> Bool {
        let actionID: Int
        switch action {
        case .press(let value), .showMenu(let value), .click(let value): actionID = value
        }
        return nodeID == actionID || snapshot.isDescendant(nodeID, of: actionID)
    }

    private static func uniqueValue<T: Hashable>(_ values: [T]) -> T? {
        let unique = Set(values)
        return unique.count == 1 ? unique.first : nil
    }
    private static func inputFrame(_ node: ChatGPTAXNode, snapshot: ChatGPTAXSnapshot) -> CGPoint { let frame = node.frame ?? .zero; return CGPoint(x: frame.midX, y: frame.midY) }
    private static func controlFrame(_ node: ChatGPTAXNode, snapshot: ChatGPTAXSnapshot) -> CGPoint { let frame = node.frame ?? .zero; return CGPoint(x: frame.midX, y: frame.midY) }

    private static func nearestCommonAncestor(_ lhs: Int, _ rhs: Int, in snapshot: ChatGPTAXSnapshot, maximumDistance: Int) -> Int? {
        let index = snapshot.byID
        var left: [Int: Int] = [lhs: 0]
        var current = index[lhs]?.parentID
        var distance = 1
        while let id = current, distance <= maximumDistance { left[id] = distance; current = index[id]?.parentID; distance += 1 }
        current = rhs; distance = 0
        while let id = current, distance <= maximumDistance {
            if left[id] != nil { return id }
            current = index[id]?.parentID; distance += 1
        }
        return nil
    }
}

/// Power announces presentation aliases, not the canonical effort on the composer.
/// Parse the complete closed label and announced bounds; never infer effort from a dot index.
struct ChatGPTPowerStatus: Hashable, Sendable {
    let selection: ChatGPTSelection
    let position: Int
    let total: Int

    static func parse(_ text: String) -> Self? {
        let parts = text.components(separatedBy: ", ")
        guard parts.count == 2, parts[1].hasSuffix(".") else { return nil }
        let bounds = parts[1].dropLast().components(separatedBy: " of ")
        guard bounds.count == 2, let position = Int(bounds[0]), let total = Int(bounds[1]),
              (1...8).contains(total), (1...total).contains(position)
        else { return nil }
        for model in ChatGPTModel.allCases {
            for effort in ChatGPTReasoningEffort.allCases {
                let alias = effort == .medium ? "Standard" : effort == .high ? "Extended" : effort.rawValue
                if ["\(model.rawValue) \(alias)", "GPT-\(model.rawValue) \(alias)"].contains(parts[0]) {
                    return Self(selection: .init(model: model, effort: effort), position: position, total: total)
                }
            }
        }
        return nil
    }

    func direction(toward effort: ChatGPTReasoningEffort) throws -> Bool {
        let order: [ChatGPTReasoningEffort] = [.none, .light, .medium, .high, .extraHigh, .max, .ultra]
        guard let current = order.firstIndex(of: selection.effort), let desired = order.firstIndex(of: effort),
              current != desired else { throw ChatGPTSurfaceFailure.itemMissing }
        let increase = desired > current
        guard increase ? position < total : position > 1 else { throw ChatGPTSurfaceFailure.itemMissing }
        return increase
    }
}

enum ChatGPTControlLabels {
    static func classify(_ text: String) -> Set<ChatGPTAXLabel> {
        switch text {
        case "Model": return [.modelRow]
        case "Effort": return [.effortRow]
        case "Select model": return [.selectModel]
        case "Select effort": return [.selectEffort]
        case "Power": return [.power]
        case "Use Left and Right arrow keys to adjust power": return [.powerInstructions]
        default: break
        }
        if let status = ChatGPTPowerStatus.parse(text) { return [.powerStatus(status)] }
        if let effort = ChatGPTReasoningEffort(rawValue: text) { return [.effort(effort)] }
        for model in ChatGPTModel.allCases {
            for name in [model.rawValue, "GPT-\(model.rawValue)"] {
                if text == name { return [.model(model)] }
                for effort in ChatGPTReasoningEffort.allCases where text == "\(name) \(effort.rawValue)" {
                    return [.model(model), .effort(effort)]
                }
            }
        }
        return text.isEmpty ? [] : [.unknownText]
    }
}

struct ChatGPTModernComposer: Equatable, Sendable {
    let rootID: Int
    let inputID: Int
    let controlID: Int
    let selection: ChatGPTSelection?
}

struct ChatGPTPowerPicker: Equatable, Sendable {
    let rootID: Int
    let powerID: Int
    let modelActionID: Int
    let status: ChatGPTPowerStatus
}

enum ChatGPTModernPlanner {
    /// The observed modern composer has a text area and popup as direct siblings.
    /// Do not widen this to a common window ancestor: transcript buttons also name models.
    static func composer(in snapshot: ChatGPTAXSnapshot) throws -> ChatGPTModernComposer {
        var matches: [ChatGPTModernComposer] = []
        for input in snapshot.nodes where input.visible && input.role == "AXTextArea" {
            guard let parent = input.parentID else { continue }
            for control in snapshot.nodes where control.visible && control.parentID == parent
                && control.role == "AXPopUpButton" && control.actions.contains(.press) {
                let models = control.labels.compactMap { if case .model(let m) = $0 { return m }; return nil }
                let efforts = control.labels.compactMap { if case .effort(let e) = $0 { return e }; return nil }
                let selection: ChatGPTSelection?
                if models.count == 1, efforts.count == 1 {
                    selection = .init(model: models[0], effort: efforts[0])
                } else if control.labels == [.selectEffort] {
                    selection = nil
                } else { continue }
                matches.append(.init(rootID: parent, inputID: input.id, controlID: control.id, selection: selection))
            }
        }
        guard matches.count == 1 else {
            throw matches.isEmpty ? ChatGPTSurfaceFailure.unsupportedSurface : .ambiguousComposer
        }
        return matches[0]
    }

    static func powerPicker(in snapshot: ChatGPTAXSnapshot) throws -> ChatGPTPowerPicker {
        _ = try composer(in: snapshot)
        let powers = snapshot.nodes.filter { $0.visible && $0.role == "AXMenuItem" && $0.labels == [.power] }
        guard powers.count == 1, let power = powers.first, let parent = power.parentID else {
            throw ChatGPTSurfaceFailure.itemMissing
        }
        // The portal owns Power, Select model, the status, and keyboard instructions.
        // Requiring all four prevents a similarly named unrelated menu from authorizing keys.
        let descendants = snapshot.nodes.filter { $0.visible && snapshot.isDescendant($0.id, of: parent) }
        let modelRows = descendants.filter { $0.role == "AXMenuItem" && $0.labels == [.selectModel] && $0.actions.contains(.press) }
        let statuses = descendants.flatMap { $0.labels.compactMap { if case .powerStatus(let s) = $0 { return s }; return nil } }
        guard modelRows.count == 1, Set(statuses).count == 1, let status = statuses.first,
              descendants.contains(where: { $0.labels.contains(.powerInstructions) }) else {
            throw ChatGPTSurfaceFailure.itemMissing
        }
        return .init(rootID: parent, powerID: power.id, modelActionID: modelRows[0].id, status: status)
    }

    /// Compact model rows are siblings in one popup portal. Inline rows are siblings
    /// in the group immediately adjacent to the verified composer, never transcript rows.
    static func modelList(in snapshot: ChatGPTAXSnapshot, composer: ChatGPTModernComposer) throws -> [ChatGPTModel: Int] {
        let popupOpen = snapshot.byID[composer.controlID]?.expanded == true
        let candidates = snapshot.nodes.filter { node in
            node.visible && node.actions.contains(.press)
                && (node.role == "AXMenuItem" || node.role == "AXButton")
                && node.labels.count == 1 && node.labels.contains(where: { if case .model = $0 { return true }; return false })
        }
        let groups = Dictionary(grouping: candidates, by: \.parentID)
        var matches: [[ChatGPTModel: Int]] = []
        for (parent, rows) in groups {
            guard let parent, rows.count >= 2 else { continue }
            let compact = popupOpen && rows.allSatisfy { $0.role == "AXMenuItem" }
            let inline = rows.allSatisfy { $0.role == "AXButton" }
                && snapshot.byID[parent]?.parentID == snapshot.byID[composer.rootID]?.parentID
            guard compact || inline else { continue }
            var items: [ChatGPTModel: Int] = [:]
            for row in rows {
                guard case .model(let model) = row.labels.first, items[model] == nil else { throw ChatGPTSurfaceFailure.ambiguousItem }
                items[model] = row.id
            }
            matches.append(items)
        }
        guard matches.count == 1 else { throw matches.isEmpty ? ChatGPTSurfaceFailure.itemMissing : .ambiguousItem }
        return matches[0]
    }
}
