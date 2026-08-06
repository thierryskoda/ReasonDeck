import AppKit
import CoreGraphics
import Foundation
import os

struct HotkeyBinding: Equatable, Sendable {
    let id: UUID
    let shortcut: KeyboardShortcut
}

extension ShortcutModifiers {
    init(eventFlags: CGEventFlags) {
        var value: ShortcutModifiers = []
        if eventFlags.contains(.maskCommand) { value.insert(.command) }
        if eventFlags.contains(.maskAlternate) { value.insert(.option) }
        if eventFlags.contains(.maskControl) { value.insert(.control) }
        if eventFlags.contains(.maskShift) { value.insert(.shift) }
        self = value
    }
}

enum HotkeyMatcher {
    static func entryID(
        keyCode: UInt16,
        flags: CGEventFlags,
        isRepeat: Bool,
        frontmostBundleID: String?,
        bindings: [HotkeyBinding]
    ) -> UUID? {
        guard !isRepeat, frontmostBundleID == AppConstants.chatGPTBundleID else { return nil }
        let modifiers = ShortcutModifiers(eventFlags: flags)
        return bindings.first {
            $0.shortcut.keyCode == keyCode && $0.shortcut.modifiers == modifiers
        }?.id
    }
}

private final class HotkeyRegistry: @unchecked Sendable {
    private let lock = NSLock()
    private var bindings: [HotkeyBinding] = []

    func replace(with bindings: [HotkeyBinding]) {
        lock.withLock { self.bindings = bindings }
    }

    func snapshot() -> [HotkeyBinding] {
        lock.withLock { bindings }
    }
}

final class HotkeyEventTap: @unchecked Sendable {
    enum State: Equatable { case stopped, running, permissionRequired }
    private let logger = Logger(subsystem: "com.thierryai.ModelKey", category: "hotkeys")
    private let lock = NSLock()
    private let registry = HotkeyRegistry()
    private var tap: CFMachPort?
    private var source: CFRunLoopSource?
    private var consumedKeyCodes = Set<UInt16>()
    private let onEntry: @Sendable (UUID) -> Void
    private(set) var state: State = .stopped

    init(onEntry: @escaping @Sendable (UUID) -> Void) { self.onEntry = onEntry }

    func update(bindings: [HotkeyBinding]) {
        registry.replace(with: bindings)
    }

    func start() -> State {
        guard tap == nil else { return state }
        let mask = (1 << CGEventType.keyDown.rawValue) | (1 << CGEventType.keyUp.rawValue)
        let pointer = Unmanaged.passUnretained(self).toOpaque()
        guard let tap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .defaultTap,
            eventsOfInterest: CGEventMask(mask),
            callback: Self.callback,
            userInfo: pointer
        ) else {
            state = .permissionRequired
            logger.error("Hotkey event tap unavailable; Input Monitoring may be required")
            return state
        }
        self.tap = tap
        let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
        self.source = source
        CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)
        state = .running
        logger.info("Hotkey event tap enabled")
        return state
    }

    func stop() {
        if let tap { CGEvent.tapEnable(tap: tap, enable: false) }
        if let source { CFRunLoopRemoveSource(CFRunLoopGetMain(), source, .commonModes) }
        source = nil
        tap = nil
        state = .stopped
        lock.withLock { consumedKeyCodes.removeAll() }
    }

    private static let callback: CGEventTapCallBack = { _, type, event, pointer in
        guard let pointer else { return Unmanaged.passUnretained(event) }
        let owner = Unmanaged<HotkeyEventTap>.fromOpaque(pointer).takeUnretainedValue()
        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
            if let tap = owner.tap { CGEvent.tapEnable(tap: tap, enable: true) }
            return Unmanaged.passUnretained(event)
        }
        let keyCode = UInt16(event.getIntegerValueField(.keyboardEventKeycode))
        if type == .keyUp {
            let consumed = owner.lock.withLock { owner.consumedKeyCodes.remove(keyCode) != nil }
            return consumed ? nil : Unmanaged.passUnretained(event)
        }
        guard type == .keyDown else { return Unmanaged.passUnretained(event) }
        let repeated = event.getIntegerValueField(.keyboardEventAutorepeat) != 0
        let frontmost = NSWorkspace.shared.frontmostApplication?.bundleIdentifier
        guard let id = HotkeyMatcher.entryID(
            keyCode: keyCode,
            flags: event.flags,
            isRepeat: repeated,
            frontmostBundleID: frontmost,
            bindings: owner.registry.snapshot()
        ) else {
            return Unmanaged.passUnretained(event)
        }
        _ = owner.lock.withLock { owner.consumedKeyCodes.insert(keyCode) }
        owner.onEntry(id)
        return nil
    }
}

private extension NSLock {
    func withLock<T>(_ body: () -> T) -> T {
        lock()
        defer { unlock() }
        return body()
    }
}
