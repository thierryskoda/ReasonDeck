import AppKit
import XCTest

@testable import ReasonDeck

/// Opt-in check against the real, frontmost ChatGPT window. It changes the
/// visible composer's effort and then restores it, so run it only when idle.
final class ChatGPTLiveTest: XCTestCase {
    func testLive() async throws {
        let environment = ProcessInfo.processInfo.environment
        try XCTSkipUnless(
            environment["REASONDECK_RUN_CHATGPT_LIVE_TEST"] == "1",
            "Set REASONDECK_RUN_CHATGPT_LIVE_TEST=1 to run this test against the live app."
        )
        guard let app = NSWorkspace.shared.frontmostApplication,
              app.bundleIdentifier == AppConstants.chatGPTBundleID
        else {
            XCTFail("ChatGPT must already be the frontmost app.")
            return
        }
        let axApp = AXUIElementCreateApplication(app.processIdentifier)
        guard let identity = AXWindowIdentity.focusedWindowIdentity(
            application: axApp,
            pid: app.processIdentifier
        ) else {
            XCTFail("ChatGPT has no focused window.")
            return
        }
        let invocation = HotkeyInvocation(
            entryID: UUID(),
            target: .chatGPT,
            pid: app.processIdentifier,
            focusedWindowID: identity.id,
            identitySource: identity.source
        )
        let client = SystemAccessibilityClient()
        // The first read in a fresh process re-enables Chromium accessibility,
        // which rebuilds the tree; give the composer the adapter's usual 2 s.
        var observed: ChatGPTSelection?
        var lastError: (any Error)?
        for _ in 0..<40 where observed == nil {
            do { observed = try await client.observeModernSelection(invocation: invocation) } catch {
                lastError = error
                try await Task.sleep(for: .milliseconds(50))
            }
        }
        guard let initial = observed else { throw lastError ?? SwitchFailure.pickerNotFound }
        print("[chatgpt-live] initial=\(initial.expectedTitle)")
        // REASONDECK_CHATGPT_LIVE_OBSERVE_ONLY=1 proves composer recognition
        // without opening a picker.
        if environment["REASONDECK_CHATGPT_LIVE_OBSERVE_ONLY"] == "1" { return }

        // REASONDECK_CHATGPT_LIVE_ALTERNATE="6.1 Terra|High" names the exact
        // selection to switch to; the default changes only the effort.
        var alternate = ChatGPTSelection(model: initial.model, effort: initial.effort == .high ? .medium : .high)
        if let request = environment["REASONDECK_CHATGPT_LIVE_ALTERNATE"] {
            let parts = request.split(separator: "|").map(String.init)
            guard parts.count == 2, let model = ChatGPTModel(rawValue: parts[0]),
                  let effort = ChatGPTReasoningEffort(rawValue: parts[1]),
                  ChatGPTSelection(model: model, effort: effort) != initial
            else {
                XCTFail("REASONDECK_CHATGPT_LIVE_ALTERNATE must be a different \"<exact model>|<exact effort>\".")
                return
            }
            alternate = ChatGPTSelection(model: model, effort: effort)
        }
        let changed = await client.apply(alternate, invocation: invocation)
        print("[chatgpt-live] change=\(changed)")
        let restored = await client.apply(initial, invocation: invocation)
        print("[chatgpt-live] restore=\(restored)")
        let final = try await client.observeModernSelection(invocation: invocation)
        XCTAssertEqual(final, initial)
        guard case .applied(alternate.model, alternate.effort, _) = changed else {
            XCTFail("Change did not apply: \(changed)")
            return
        }
    }
}
