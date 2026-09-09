import AppKit
import Testing
@testable import ReasonDeck

@Test func statusItemInsideNotchedDisplaysRightStripIsReachable() {
    let display = MenuBarDisplayGeometry(
        frame: CGRect(x: 0, y: 0, width: 1512, height: 982),
        visibleFrame: CGRect(x: 0, y: 0, width: 1512, height: 950),
        auxiliaryTopRightArea: CGRect(x: 848, y: 950, width: 664, height: 32)
    )

    #expect(MenuBarReachability.classify(
        // Control Center's host window includes a one-point border below the
        // auxiliary strip even though the status item is visibly inside it.
        statusItemFrame: CGRect(x: 1012, y: 949, width: 28, height: 33),
        displays: [display]
    ) == .reachable)
}

@Test func statusItemInsideNotchOrAppMenuStripIsUnreachable() {
    let display = MenuBarDisplayGeometry(
        frame: CGRect(x: 0, y: 0, width: 1512, height: 982),
        visibleFrame: CGRect(x: 0, y: 0, width: 1512, height: 950),
        auxiliaryTopRightArea: CGRect(x: 848, y: 950, width: 664, height: 32)
    )

    #expect(MenuBarReachability.classify(
        statusItemFrame: CGRect(x: 763, y: 950, width: 28, height: 32),
        displays: [display]
    ) == .unreachable)
    #expect(MenuBarReachability.classify(
        statusItemFrame: CGRect(x: 453, y: 950, width: 28, height: 32),
        displays: [display]
    ) == .unreachable)
}

@Test func displayWithoutNotchUsesItsWholeMenuBar() {
    let display = MenuBarDisplayGeometry(
        frame: CGRect(x: 0, y: 0, width: 1920, height: 1080),
        visibleFrame: CGRect(x: 0, y: 0, width: 1920, height: 1055),
        auxiliaryTopRightArea: nil
    )

    #expect(MenuBarReachability.classify(
        statusItemFrame: CGRect(x: 20, y: 1055, width: 28, height: 25),
        displays: [display]
    ) == .reachable)
}

@Test func statusItemWithoutAMatchingDisplayIsUnknown() {
    let display = MenuBarDisplayGeometry(
        frame: CGRect(x: 0, y: 0, width: 1920, height: 1080),
        visibleFrame: CGRect(x: 0, y: 0, width: 1920, height: 1055),
        auxiliaryTopRightArea: nil
    )

    #expect(MenuBarReachability.classify(
        statusItemFrame: CGRect(x: 2200, y: 1055, width: 28, height: 25),
        displays: [display]
    ) == .unknown)
}

@Test func remoteStatusItemLocatorSelectsOnlyTheOneNewOrResizedMarkerWindow() {
    let existing = MenuBarStatusWindowSnapshot(
        number: 10,
        coreGraphicsFrame: CGRect(x: 1400, y: 0, width: 38, height: 33)
    )
    let created = MenuBarStatusWindowSnapshot(
        number: 11,
        coreGraphicsFrame: CGRect(x: 453, y: 0, width: 73, height: 33)
    )

    #expect(MenuBarStatusWindowLocator.markerWindow(
        in: [existing, created],
        comparedTo: [existing]
    ) == created)

    let resized = MenuBarStatusWindowSnapshot(
        number: existing.number,
        coreGraphicsFrame: CGRect(x: 1365, y: 0, width: 73, height: 33)
    )
    #expect(MenuBarStatusWindowLocator.markerWindow(
        in: [resized],
        comparedTo: [existing]
    ) == resized)

    #expect(MenuBarStatusWindowLocator.markerWindow(
        in: [created, .init(number: 12, coreGraphicsFrame: created.coreGraphicsFrame)],
        comparedTo: []
    ) == nil)
}

@Test func coreGraphicsMenuBarFrameConvertsToAppKitCoordinates() {
    let converted = MenuBarStatusWindowLocator.appKitFrame(
        for: CGRect(x: 453, y: 0, width: 38, height: 32),
        coreGraphicsDisplayFrame: CGRect(x: 0, y: 0, width: 1512, height: 982),
        appKitDisplayFrame: CGRect(x: 0, y: 0, width: 1512, height: 982)
    )

    #expect(converted == CGRect(x: 453, y: 950, width: 38, height: 32))
}
