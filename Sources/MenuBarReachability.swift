import AppKit
import Observation

struct MenuBarDisplayGeometry: Equatable, Sendable {
    let frame: CGRect
    let visibleFrame: CGRect
    let auxiliaryTopRightArea: CGRect?

    init(frame: CGRect, visibleFrame: CGRect, auxiliaryTopRightArea: CGRect?) {
        self.frame = frame
        self.visibleFrame = visibleFrame
        self.auxiliaryTopRightArea = auxiliaryTopRightArea
    }

    init(_ screen: NSScreen) {
        self.init(
            frame: screen.frame,
            visibleFrame: screen.visibleFrame,
            auxiliaryTopRightArea: screen.auxiliaryTopRightArea
        )
    }

    var usableStatusStrip: CGRect {
        if let auxiliaryTopRightArea { return auxiliaryTopRightArea }
        return CGRect(
            x: frame.minX,
            y: visibleFrame.maxY,
            width: frame.width,
            height: max(0, frame.maxY - visibleFrame.maxY)
        )
    }
}

enum MenuBarIconReachability: Equatable, Sendable {
    case unknown, reachable, unreachable
}

struct MenuBarStatusWindowSnapshot: Equatable, Sendable {
    let number: CGWindowID
    let coreGraphicsFrame: CGRect
}

enum MenuBarStatusWindowLocator {
    nonisolated static func markerWindow(
        in current: [MenuBarStatusWindowSnapshot],
        comparedTo existing: [MenuBarStatusWindowSnapshot]
    ) -> MenuBarStatusWindowSnapshot? {
        let existingByNumber = Dictionary(uniqueKeysWithValues: existing.map { ($0.number, $0) })
        let candidates = current.filter {
            !$0.coreGraphicsFrame.isEmpty
                && $0.coreGraphicsFrame.width > 64
                && $0.coreGraphicsFrame.width <= 96
                && $0.coreGraphicsFrame.height <= 64
                && existingByNumber[$0.number] != $0
        }
        return candidates.count == 1 ? candidates[0] : nil
    }

    nonisolated static func appKitFrame(
        for coreGraphicsFrame: CGRect,
        coreGraphicsDisplayFrame: CGRect,
        appKitDisplayFrame: CGRect
    ) -> CGRect {
        CGRect(
            x: appKitDisplayFrame.minX + coreGraphicsFrame.minX - coreGraphicsDisplayFrame.minX,
            y: appKitDisplayFrame.minY + coreGraphicsDisplayFrame.maxY - coreGraphicsFrame.maxY,
            width: coreGraphicsFrame.width,
            height: coreGraphicsFrame.height
        )
    }
}

@MainActor
@Observable
final class MenuBarReachability {
    private var statusItemFrame: CGRect?
    private(set) var state: MenuBarIconReachability = .unknown

    var advisory: String? {
        guard state == .unreachable else { return nil }
        return "ReasonDeck's menu bar icon is outside the usable area on this display. Open ReasonDeck from Applications to return to Settings. Free menu bar space or use an overflow manager, then relaunch ReasonDeck so macOS can place the icon again."
    }

    func update(statusItemFrame: CGRect) {
        guard !statusItemFrame.isEmpty else { return }
        self.statusItemFrame = statusItemFrame
        refresh()
    }

    func refresh() {
        guard let statusItemFrame else {
            state = .unknown
            return
        }
        state = Self.classify(
            statusItemFrame: statusItemFrame,
            displays: NSScreen.screens.map(MenuBarDisplayGeometry.init)
        )
    }

    /// Status items only render in the top-right auxiliary area on a notched display.
    /// Control Center's host window can include a one-point border below that area,
    /// so require intersection rather than exact origin containment. macOS may keep
    /// an overflow item alive elsewhere without drawing any pixels.
    nonisolated static func classify(
        statusItemFrame: CGRect,
        displays: [MenuBarDisplayGeometry]
    ) -> MenuBarIconReachability {
        guard let display = displays.first(where: { $0.frame.intersects(statusItemFrame) }) else {
            return .unknown
        }
        return display.usableStatusStrip.intersects(statusItemFrame)
            ? .reachable
            : .unreachable
    }
}
