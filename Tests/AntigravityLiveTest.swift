import AppKit
import XCTest

@testable import ReasonDeck

final class AntigravityLiveTest: XCTestCase {
    func testLive() async throws {
        try XCTSkipUnless(
            ProcessInfo.processInfo.environment["REASONDECK_RUN_ANTIGRAVITY_LIVE_TEST"] == "1",
            "Set REASONDECK_RUN_ANTIGRAVITY_LIVE_TEST=1 to run this test against the live app."
        )

        guard let app = NSWorkspace.shared.runningApplications.first(where: {
            $0.bundleIdentifier == AppConstants.antigravityBundleID
        }) else {
            XCTFail("Antigravity is not running.")
            return
        }
        app.activate()
        try await Task.sleep(for: .seconds(1))

        let axApp = AXUIElementCreateApplication(app.processIdentifier)
        guard let identity = AXWindowIdentity.focusedWindowIdentity(
            application: axApp,
            pid: app.processIdentifier
        ) else {
            XCTFail("Antigravity has no focused window.")
            return
        }

        let invocation = HotkeyInvocation(
            entryID: UUID(),
            target: .antigravity,
            pid: app.processIdentifier,
            focusedWindowID: identity.id,
            identitySource: identity.source
        )
        let client = SystemAntigravityUIClient()
        let initial = try await client.observePickerState(invocation: invocation)
        guard let alternate = initial.available.first(where: { $0 != initial.current }) else {
            XCTFail("Antigravity did not expose a second exact model-and-effort row.")
            return
        }

        var liveError: (any Error)?
        do {
            let outcome = await client.apply(alternate, invocation: invocation)
            XCTAssertEqual(outcome, .applied(model: alternate.model, effort: alternate.effort))
            let observed = try await client.observePickerState(invocation: invocation)
            XCTAssertEqual(observed.current, alternate)
        } catch {
            liveError = error
        }

        let restore = await client.apply(initial.current, invocation: invocation)
        XCTAssertEqual(restore, .applied(model: initial.current.model, effort: initial.current.effort))
        if let liveError { throw liveError }
    }
}
