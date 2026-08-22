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

        let client = SystemAntigravityUIClient()
        let selection = AntigravitySelection(model: .claudeOpus46, effort: .thinking)
        let invocation = HotkeyInvocation(
            entryID: UUID(),
            target: .antigravity,
            pid: app.processIdentifier,
            focusedWindowID: identity.id,
            identitySource: identity.source
        )

        let outcome = await client.apply(selection, invocation: invocation)
        XCTAssertEqual(outcome, .applied(model: selection.model, effort: selection.effort))
    }
}
