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

    private static func uniqueLabeledDirectActionable(_ nodes: [ChatGPTAXNode], snapshot: ChatGPTAXSnapshot) throws -> ChatGPTActionTarget {
        var matches: [ChatGPTActionTarget] = []
        for node in nodes {
            guard let candidate = directActionableAncestor(of: node.id, in: snapshot),
                  !matches.contains(candidate) else { continue }
            matches.append(candidate)
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
