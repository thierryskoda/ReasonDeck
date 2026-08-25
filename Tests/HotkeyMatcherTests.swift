import CoreGraphics
import Foundation
import Testing
@testable import ReasonDeck

private let firstID = UUID()
private let secondID = UUID()
private let bindings = [
    HotkeyBinding(id: firstID, shortcut: try! KeyboardShortcut(keyCode: 18, keyLabel: "1", modifiers: [.command, .shift]), enabledTargets: [.chatGPT, .claudeCode, .cursor]),
    HotkeyBinding(id: secondID, shortcut: try! KeyboardShortcut(keyCode: 19, keyLabel: "2", modifiers: [.control, .option]), enabledTargets: [.chatGPT])
]

@Test func exactDynamicHotkeysResolveTheirEntry() {
    #expect(HotkeyMatcher.match(keyCode: 18, flags: [.maskCommand, .maskShift], isRepeat: false, frontmostBundleID: AppConstants.chatGPTBundleID, bindings: bindings)?.id == firstID)
    #expect(HotkeyMatcher.match(keyCode: 19, flags: [.maskControl, .maskAlternate], isRepeat: false, frontmostBundleID: AppConstants.chatGPTBundleID, bindings: bindings)?.id == secondID)
    #expect(HotkeyMatcher.match(keyCode: 18, flags: [.maskCommand, .maskShift], isRepeat: false, frontmostBundleID: AppConstants.claudeDesktopBundleID, bindings: bindings)?.target == .claudeCode)
    #expect(HotkeyMatcher.match(keyCode: 18, flags: [.maskCommand, .maskShift], isRepeat: false, frontmostBundleID: AppConstants.cursorBundleID, bindings: bindings)?.target == .cursor)
    #expect(HotkeyMatcher.match(keyCode: 19, flags: [.maskControl, .maskAlternate], isRepeat: false, frontmostBundleID: AppConstants.claudeDesktopBundleID, bindings: bindings) == nil)
    #expect(HotkeyMatcher.match(keyCode: 19, flags: [.maskControl, .maskAlternate], isRepeat: false, frontmostBundleID: AppConstants.cursorBundleID, bindings: bindings) == nil)
}

@Test func hotkeysPassThroughOutsideChatGPT() {
    #expect(HotkeyMatcher.match(keyCode: 18, flags: [.maskCommand, .maskShift], isRepeat: false, frontmostBundleID: "com.apple.TextEdit", bindings: bindings) == nil)
    #expect(HotkeyMatcher.match(keyCode: 18, flags: [.maskCommand, .maskShift], isRepeat: false, frontmostBundleID: nil, bindings: bindings) == nil)
}

@Test func repeatsExtraModifiersAndUnknownKeysAreRejected() {
    #expect(HotkeyMatcher.match(keyCode: 18, flags: [.maskCommand, .maskShift], isRepeat: true, frontmostBundleID: AppConstants.chatGPTBundleID, bindings: bindings) == nil)
    #expect(HotkeyMatcher.match(keyCode: 18, flags: [.maskCommand, .maskShift, .maskAlternate], isRepeat: false, frontmostBundleID: AppConstants.chatGPTBundleID, bindings: bindings) == nil)
    #expect(HotkeyMatcher.match(keyCode: 20, flags: [.maskCommand, .maskShift], isRepeat: false, frontmostBundleID: AppConstants.chatGPTBundleID, bindings: bindings) == nil)
}

@Test func capsLockDoesNotInvalidateAHotkey() {
    #expect(HotkeyMatcher.match(keyCode: 18, flags: [.maskCommand, .maskShift, .maskAlphaShift], isRepeat: false, frontmostBundleID: AppConstants.chatGPTBundleID, bindings: bindings)?.id == firstID)
}

@Test func recorderCapturesAReservedMacOSShortcutBeforeItReachesTheSystem() throws {
    let expected = try KeyboardShortcut(
        keyCode: 20,
        keyLabel: "3",
        modifiers: [.command, .shift]
    )

    #expect(ShortcutRecording.capture(
        keyCode: 20,
        flags: [.maskCommand, .maskShift],
        keyLabel: "3"
    ) == .captured(expected))
}

@Test func recorderPreservesTheExistingCancelClearAndModifierRules() {
    #expect(ShortcutRecording.capture(keyCode: 53, flags: [], keyLabel: nil) == .cancelled)
    #expect(ShortcutRecording.capture(keyCode: 51, flags: [], keyLabel: nil) == .cleared)
    #expect(ShortcutRecording.capture(keyCode: 0, flags: [], keyLabel: "a") == .rejected)
}

@Test func everySupportedAdapterConsumesItsConfiguredShortcut() throws {
    let shortcut = try KeyboardShortcut(keyCode: 18, keyLabel: "1", modifiers: [.command, .shift])
    let entry = ShortcutEntry(
        shortcut: shortcut,
        chatGPT: ChatGPTSelection(model: .sol56, effort: .extraHigh),
        claudeCode: ClaudeCodeSelection(model: .opus5, effort: .high),
        cursor: CursorSelection(model: .grok45, effort: .high)
    )
    let binding = HotkeyBinding(
        id: entry.id,
        shortcut: shortcut,
        enabledTargets: RuntimeCapabilities.runnableTargets(for: entry)
    )

    #expect(HotkeyMatcher.match(keyCode: 18, flags: [.maskCommand, .maskShift], isRepeat: false, frontmostBundleID: AppConstants.chatGPTBundleID, bindings: [binding])?.target == .chatGPT)
    #expect(HotkeyMatcher.match(keyCode: 18, flags: [.maskCommand, .maskShift], isRepeat: false, frontmostBundleID: AppConstants.claudeDesktopBundleID, bindings: [binding])?.target == .claudeCode)
    #expect(HotkeyMatcher.match(keyCode: 18, flags: [.maskCommand, .maskShift], isRepeat: false, frontmostBundleID: AppConstants.cursorBundleID, bindings: [binding])?.target == .cursor)
}
