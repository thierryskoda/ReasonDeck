import CoreGraphics
import Foundation
import Testing
@testable import ModelKey

private let firstID = UUID()
private let secondID = UUID()
private let bindings = [
    HotkeyBinding(id: firstID, shortcut: try! KeyboardShortcut(keyCode: 18, keyLabel: "1", modifiers: [.command, .shift])),
    HotkeyBinding(id: secondID, shortcut: try! KeyboardShortcut(keyCode: 19, keyLabel: "2", modifiers: [.control, .option]))
]

@Test func exactDynamicHotkeysResolveTheirEntry() {
    #expect(HotkeyMatcher.entryID(keyCode: 18, flags: [.maskCommand, .maskShift], isRepeat: false, frontmostBundleID: AppConstants.chatGPTBundleID, bindings: bindings) == firstID)
    #expect(HotkeyMatcher.entryID(keyCode: 19, flags: [.maskControl, .maskAlternate], isRepeat: false, frontmostBundleID: AppConstants.chatGPTBundleID, bindings: bindings) == secondID)
}

@Test func hotkeysPassThroughOutsideChatGPT() {
    #expect(HotkeyMatcher.entryID(keyCode: 18, flags: [.maskCommand, .maskShift], isRepeat: false, frontmostBundleID: "com.apple.TextEdit", bindings: bindings) == nil)
    #expect(HotkeyMatcher.entryID(keyCode: 18, flags: [.maskCommand, .maskShift], isRepeat: false, frontmostBundleID: nil, bindings: bindings) == nil)
}

@Test func repeatsExtraModifiersAndUnknownKeysAreRejected() {
    #expect(HotkeyMatcher.entryID(keyCode: 18, flags: [.maskCommand, .maskShift], isRepeat: true, frontmostBundleID: AppConstants.chatGPTBundleID, bindings: bindings) == nil)
    #expect(HotkeyMatcher.entryID(keyCode: 18, flags: [.maskCommand, .maskShift, .maskAlternate], isRepeat: false, frontmostBundleID: AppConstants.chatGPTBundleID, bindings: bindings) == nil)
    #expect(HotkeyMatcher.entryID(keyCode: 20, flags: [.maskCommand, .maskShift], isRepeat: false, frontmostBundleID: AppConstants.chatGPTBundleID, bindings: bindings) == nil)
}

@Test func capsLockDoesNotInvalidateAHotkey() {
    #expect(HotkeyMatcher.entryID(keyCode: 18, flags: [.maskCommand, .maskShift, .maskAlphaShift], isRepeat: false, frontmostBundleID: AppConstants.chatGPTBundleID, bindings: bindings) == firstID)
}
