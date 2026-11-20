import AppKit
import XCTest

@testable import ReasonDeck

/// Opt-in check against the real, frontmost Claude Desktop window. It changes
/// the visible session's effort (and, when asked, model) and then restores
/// both, so run it only in an idle session.
final class ClaudeDesktopLiveTest: XCTestCase {
    func testLive() async throws {
        let environment = ProcessInfo.processInfo.environment
        try XCTSkipUnless(
            environment["REASONDECK_RUN_CLAUDE_LIVE_TEST"] == "1",
            "Set REASONDECK_RUN_CLAUDE_LIVE_TEST=1 to run this test against the live app."
        )

        guard let app = NSWorkspace.shared.runningApplications.first(where: {
            $0.bundleIdentifier == AppConstants.claudeDesktopBundleID
        }) else {
            XCTFail("Claude Desktop is not running.")
            return
        }
        app.activate()
        try await Task.sleep(for: .seconds(1))

        let axApp = AXUIElementCreateApplication(app.processIdentifier)
        guard let identity = AXWindowIdentity.focusedWindowIdentity(
            application: axApp,
            pid: app.processIdentifier
        ) else {
            XCTFail("Claude Desktop has no focused window.")
            return
        }
        let invocation = HotkeyInvocation(
            entryID: UUID(),
            target: .claudeCode,
            pid: app.processIdentifier,
            focusedWindowID: identity.id,
            identitySource: identity.source
        )
        let client = SystemClaudeCodeUIClient()
        // REASONDECK_CLAUDE_LIVE_SET="Sonnet 5.5|Low" applies one exact
        // selection and stops, e.g. to put a session back by hand.
        if let request = environment["REASONDECK_CLAUDE_LIVE_SET"] {
            let parts = request.split(separator: "|").map(String.init)
            guard parts.count == 2,
                  let model = ClaudeCodeModel(rawValue: parts[0]),
                  let effort = ClaudeCodeEffort(rawValue: parts[1])
            else {
                XCTFail("REASONDECK_CLAUDE_LIVE_SET must be \"<exact model>|<exact effort>\".")
                return
            }
            let result = await ClaudeCodeSwitchCoordinator(client: client).apply(
                ClaudeCodeSelection(model: model, effort: effort),
                invocation: invocation
            )
            guard case .success = result else {
                XCTFail("Live apply did not succeed: \(result)")
                return
            }
            return
        }
        let initial = try await client.observeSelection(invocation: invocation)
        guard let initialEffort = initial.effort else {
            XCTFail("The current Claude model exposes no effort to round-trip.")
            return
        }
        // REASONDECK_CLAUDE_LIVE_OBSERVE_ONLY=1 proves surface recognition
        // without opening the picker.
        if environment["REASONDECK_CLAUDE_LIVE_OBSERVE_ONLY"] == "1" { return }

        let alternateEffort: ClaudeCodeEffort = initialEffort == .high ? .medium : .high
        var liveError: (any Error)?
        do {
            let applied = try await client.selectEffort(alternateEffort, invocation: invocation)
            XCTAssertEqual(applied, alternateEffort.rawValue)
            let observed = try await client.observeSelection(invocation: invocation)
            XCTAssertEqual(observed.effort, alternateEffort)
            XCTAssertEqual(observed.model, initial.model)

            // Name an exact model, e.g. "Haiku 5.5", to also round-trip the model.
            if let name = environment["REASONDECK_CLAUDE_LIVE_ALTERNATE_MODEL"] {
                guard let alternateModel = ClaudeCodeModel(rawValue: name), alternateModel != initial.model else {
                    XCTFail("REASONDECK_CLAUDE_LIVE_ALTERNATE_MODEL must be a different exact model name.")
                    return
                }
                let model = try await client.selectModel(alternateModel, invocation: invocation)
                XCTAssertEqual(model, alternateModel.rawValue)
                let afterModel = try await client.observeSelection(invocation: invocation)
                XCTAssertEqual(afterModel.model, alternateModel)
            }
        } catch {
            liveError = error
        }

        _ = try await client.selectModel(initial.model, invocation: invocation)
        _ = try await client.selectEffort(initialEffort, invocation: invocation)
        let restored = try await client.observeSelection(invocation: invocation)
        XCTAssertEqual(restored.model, initial.model)
        XCTAssertEqual(restored.effort, initialEffort)
        if let liveError { throw liveError }
    }
}
