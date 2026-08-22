import AppKit
import CoreGraphics
import Foundation
import os

enum SyntheticEventMarker {
    static let value: Int64 = 0x52444B // "RDK"
}

struct HotkeyBinding: Equatable, Sendable {
    let id: UUID
    let shortcut: KeyboardShortcut
    let enabledTargets: Set<ApplicationTarget>
}

enum WindowIdentitySource: String, Equatable, Sendable {
    case axWindowNumber = "ax_window_number"
    case correlatedWindowGeometry = "correlated_window_geometry"
}

struct FocusedWindowIdentity: Equatable, Sendable {
    let id: CGWindowID
    let source: WindowIdentitySource
}

/// Lightweight key-down context captured inside the event-tap callback.
/// Focused-window discovery is deliberately deferred because Accessibility
/// calls can block long enough for macOS to disable the tap.
struct HotkeyCapture: Equatable, Sendable {
    let entryID: UUID
    let target: ApplicationTarget
    let pid: pid_t
}

struct HotkeyInvocation: Equatable, Sendable {
    let entryID: UUID
    let target: ApplicationTarget
    let pid: pid_t
    let focusedWindowID: CGWindowID
    let identitySource: WindowIdentitySource

    init(
        entryID: UUID,
        target: ApplicationTarget,
        pid: pid_t,
        focusedWindowID: CGWindowID,
        identitySource: WindowIdentitySource = .axWindowNumber
    ) {
        self.entryID = entryID
        self.target = target
        self.pid = pid
        self.focusedWindowID = focusedWindowID
        self.identitySource = identitySource
    }
}

enum HotkeyInvocationFactory {
    static func make(
        capture: HotkeyCapture,
        observedTarget: ApplicationTarget,
        observedPID: pid_t,
        identity: FocusedWindowIdentity
    ) -> HotkeyInvocation? {
        guard capture.target == observedTarget, capture.pid == observedPID else { return nil }
        return HotkeyInvocation(
            entryID: capture.entryID,
            target: capture.target,
            pid: capture.pid,
            focusedWindowID: identity.id,
            identitySource: identity.source
        )
    }
}

/// The only context that may authorize an external Accessibility or synthetic
/// input action. It deliberately has no fallback identity representation.
struct ObservedTargetContext: Equatable, Sendable {
    let target: ApplicationTarget
    let pid: pid_t
    let focusedWindowID: CGWindowID
}

enum TargetContextValidator {
    static func matches(_ invocation: HotkeyInvocation, observed: ObservedTargetContext) -> Bool {
        invocation.target == observed.target
            && invocation.pid == observed.pid
            && invocation.focusedWindowID == observed.focusedWindowID
    }
}

/// Centralizes all real external input. Callers cannot select a background
/// process or omit the captured-window revalidation.
enum TrustedTargetAction {
    private static let logger = Logger(
        subsystem: "com.thierryai.ReasonDeck",
        category: "target-context"
    )

    static func validate(_ invocation: HotkeyInvocation) throws {
        guard AXIsProcessTrusted() else { throw SwitchFailure.permissionMissing }
        guard let running = NSWorkspace.shared.frontmostApplication else {
            throw SwitchFailure.targetChanged(invocation.target.displayName)
        }
        guard running.processIdentifier == invocation.pid,
              running.bundleIdentifier == bundleID(for: invocation.target)
        else {
            throw SwitchFailure.targetChanged(invocation.target.displayName)
        }

        let application = AXUIElementCreateApplication(invocation.pid)
        let focusedWindowID = AXWindowIdentity.focusedWindowIdentity(
            application: application,
            pid: invocation.pid
        )?.id
        guard let focusedWindowID,
        TargetContextValidator.matches(
            invocation,
            observed: ObservedTargetContext(
                target: invocation.target,
                pid: running.processIdentifier,
                focusedWindowID: focusedWindowID
            )
        ) else {
            logger.error("validation target=\(invocation.target.rawValue, privacy: .public) reason=window_mismatch captured=\(invocation.focusedWindowID, privacy: .public) observed=\(focusedWindowID ?? 0, privacy: .public)")
            throw SwitchFailure.targetChanged(invocation.target.displayName)
        }
    }

    static func press(_ element: AXUIElement, invocation: HotkeyInvocation) throws {
        try validate(invocation)
        let error = AXUIElementPerformAction(element, kAXPressAction as CFString)
        guard error == .success else {
            throw SwitchFailure.accessibility("AXPress error \(error.rawValue)")
        }
        try validate(invocation)
    }

    static func showMenu(_ element: AXUIElement, invocation: HotkeyInvocation) throws {
        try validate(invocation)
        let error = AXUIElementPerformAction(element, kAXShowMenuAction as CFString)
        guard error == .success else {
            throw SwitchFailure.accessibility("AXShowMenu error \(error.rawValue)")
        }
        try validate(invocation)
    }

    static func postKey(
        keyCode: CGKeyCode,
        flags: CGEventFlags,
        invocation: HotkeyInvocation
    ) throws {
        try validate(invocation)
        guard let down = CGEvent(keyboardEventSource: nil, virtualKey: keyCode, keyDown: true),
              let up = CGEvent(keyboardEventSource: nil, virtualKey: keyCode, keyDown: false)
        else { throw SwitchFailure.accessibility("Could not create a keyboard event.") }
        for event in [down, up] {
            try validate(invocation)
            event.flags = flags
            event.setIntegerValueField(.eventSourceUserData, value: SyntheticEventMarker.value)
            event.postToPid(invocation.pid)
        }
        try validate(invocation)
    }

    static func click(frame: CGRect, invocation: HotkeyInvocation) throws -> CGPoint? {
        try validate(invocation)
        guard frame.width > 0, frame.height > 0,
              frame.width <= 1_000, frame.height <= 200,
              frame.minX.isFinite, frame.minY.isFinite,
              frame.maxX.isFinite, frame.maxY.isFinite
        else { throw SwitchFailure.accessibility("Invalid Accessibility click target geometry.") }

        let application = AXUIElementCreateApplication(invocation.pid)
        guard let window: AXUIElement = axValue(application, kAXFocusedWindowAttribute),
              let windowFrame = AXWindowIdentity.frame(window),
              windowFrame.intersects(frame),
              windowFrame.contains(CGPoint(x: frame.midX, y: frame.midY))
        else { throw SwitchFailure.targetChanged(invocation.target.displayName) }

        let point = CGPoint(x: frame.midX, y: frame.midY)
        let previous = CGEvent(source: nil)?.location

        guard let move = CGEvent(
            mouseEventSource: nil,
            mouseType: .mouseMoved,
            mouseCursorPosition: point,
            mouseButton: .left
        ), let down = CGEvent(
            mouseEventSource: nil,
            mouseType: .leftMouseDown,
            mouseCursorPosition: point,
            mouseButton: .left
        ), let up = CGEvent(
            mouseEventSource: nil,
            mouseType: .leftMouseUp,
            mouseCursorPosition: point,
            mouseButton: .left
        ) else { throw SwitchFailure.accessibility("Could not create a mouse event.") }

        for event in [move, down, up] {
            event.setIntegerValueField(.eventSourceUserData, value: SyntheticEventMarker.value)
        }
        move.post(tap: .cghidEventTap)
        try validate(invocation)
        down.post(tap: .cghidEventTap)
        up.post(tap: .cghidEventTap)
        // Cursor may temporarily unpublish its focused AX window while rebuilding the
        // composer after a menu-row click. The exact target was revalidated immediately
        // before delivery; the caller performs the next strict observation and final-state
        // verification after Cursor finishes that transition.
        return previous
    }

    static func restorePointer(to point: CGPoint?) {
        guard let point,
              let restore = CGEvent(
                  mouseEventSource: nil,
                  mouseType: .mouseMoved,
                  mouseCursorPosition: point,
                  mouseButton: .left
              ) else { return }
        restore.setIntegerValueField(.eventSourceUserData, value: SyntheticEventMarker.value)
        restore.post(tap: .cghidEventTap)
    }

    private static func axValue<T>(_ element: AXUIElement, _ attribute: String) -> T? {
        var result: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, attribute as CFString, &result) == .success else {
            return nil
        }
        return result as? T
    }

    private static func bundleID(for target: ApplicationTarget) -> String {
        switch target {
        case .chatGPT: AppConstants.chatGPTBundleID
        case .claudeCode: AppConstants.claudeDesktopBundleID
        case .cursor: AppConstants.cursorBundleID
        case .antigravity: AppConstants.antigravityBundleID
        }
    }
}

enum AXWindowIdentity {
    struct GeometryCandidate: Equatable, Sendable {
        let id: CGWindowID
        let pid: pid_t
        let bounds: CGRect
        let layer: Int
        let isOnscreen: Bool
    }

    static func windowID(_ element: AXUIElement) -> CGWindowID? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(
            element,
            "AXWindowNumber" as CFString,
            &value
        ) == .success,
        let number = value as? NSNumber
        else { return nil }
        return CGWindowID(number.uint32Value)
    }

    static func focusedWindowIdentity(
        application: AXUIElement,
        pid: pid_t
    ) -> FocusedWindowIdentity? {
        var value: CFTypeRef?
        if AXUIElementCopyAttributeValue(application, kAXFocusedWindowAttribute as CFString, &value) == .success,
           let window = value as! AXUIElement? {
            if let id = windowID(window) {
                return FocusedWindowIdentity(id: id, source: .axWindowNumber)
            }
            guard let frame = frame(window) else { return nil }
            guard let id = correlatedWindowID(
                pid: pid,
                focusedAXFrame: frame,
                candidates: onScreenCandidates()
            ) else { return nil }
            return FocusedWindowIdentity(id: id, source: .correlatedWindowGeometry)
        }
        return nil
    }

    static func focusedWindowID(application: AXUIElement, pid: pid_t) -> CGWindowID? {
        focusedWindowIdentity(application: application, pid: pid)?.id
    }

    static func correlatedWindowID(
        pid: pid_t,
        focusedAXFrame: CGRect,
        candidates: [GeometryCandidate]
    ) -> CGWindowID? {
        let matches = candidates.filter {
            $0.pid == pid
                && $0.layer == 0
                && $0.isOnscreen
                && framesMatch($0.bounds, focusedAXFrame)
        }
        guard matches.count == 1 else { return nil }
        return matches[0].id
    }

    private static func onScreenCandidates() -> [GeometryCandidate] {
        guard let values = CGWindowListCopyWindowInfo(
            [.optionOnScreenOnly, .excludeDesktopElements],
            kCGNullWindowID
        ) as? [[String: Any]] else { return [] }
        return values.compactMap { value in
            guard let id = value[kCGWindowNumber as String] as? NSNumber,
                  let ownerPID = value[kCGWindowOwnerPID as String] as? NSNumber,
                  let layer = value[kCGWindowLayer as String] as? NSNumber,
                  let boundsValue = value[kCGWindowBounds as String] as? NSDictionary,
                  let bounds = CGRect(dictionaryRepresentation: boundsValue)
            else { return nil }
            return GeometryCandidate(
                id: CGWindowID(id.uint32Value),
                pid: pid_t(ownerPID.int32Value),
                bounds: bounds,
                layer: layer.intValue,
                isOnscreen: (value[kCGWindowIsOnscreen as String] as? NSNumber)?.boolValue == true
            )
        }
    }

    static func frame(_ element: AXUIElement) -> CGRect? {
        var positionRef: CFTypeRef?
        var sizeRef: CFTypeRef?
        guard AXUIElementCopyAttributeValue(
            element,
            kAXPositionAttribute as CFString,
            &positionRef
        ) == .success,
        AXUIElementCopyAttributeValue(
            element,
            kAXSizeAttribute as CFString,
            &sizeRef
        ) == .success,
        let positionValue = positionRef as! AXValue?,
        let sizeValue = sizeRef as! AXValue?
        else { return nil }
        var position = CGPoint.zero
        var size = CGSize.zero
        guard AXValueGetValue(positionValue, .cgPoint, &position),
              AXValueGetValue(sizeValue, .cgSize, &size)
        else { return nil }
        return CGRect(origin: position, size: size)
    }

    private static func framesMatch(_ lhs: CGRect, _ rhs: CGRect) -> Bool {
        abs(lhs.minX - rhs.minX) <= 1
            && abs(lhs.minY - rhs.minY) <= 1
            && abs(lhs.width - rhs.width) <= 2
            && abs(lhs.height - rhs.height) <= 2
    }
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

enum ShortcutRecordingResult: Equatable, Sendable {
    case captured(KeyboardShortcut)
    case cleared
    case cancelled
    case rejected
}

enum ShortcutRecording {
    static func capture(
        keyCode: UInt16,
        flags: CGEventFlags,
        keyLabel: String?
    ) -> ShortcutRecordingResult {
        let modifiers = ShortcutModifiers(eventFlags: flags)
        if keyCode == 53, modifiers.isEmpty { return .cancelled }
        if keyCode == 51, modifiers.isEmpty { return .cleared }
        guard let keyLabel = KeyboardKeyLabel.label(for: keyCode, fallback: keyLabel),
              let shortcut = try? KeyboardShortcut(
                keyCode: keyCode,
                keyLabel: keyLabel,
                modifiers: modifiers
              ) else {
            return .rejected
        }
        return .captured(shortcut)
    }
}

typealias ShortcutRecordingHandler = @Sendable (ShortcutRecordingResult) -> Void

private final class ShortcutRecorderRegistry: @unchecked Sendable {
    private let lock = NSLock()
    private var handler: ShortcutRecordingHandler?

    func begin(_ handler: @escaping ShortcutRecordingHandler) {
        lock.withLock { self.handler = handler }
    }

    func cancel() {
        lock.withLock { handler = nil }
    }

    func capture(
        _ makeResult: () -> ShortcutRecordingResult
    ) -> (result: ShortcutRecordingResult, handler: ShortcutRecordingHandler)? {
        lock.withLock {
            guard let handler else { return nil }
            let result = makeResult()
            if result != .rejected { self.handler = nil }
            return (result, handler)
        }
    }
}

enum HotkeyMatcher {
    static func match(
        keyCode: UInt16,
        flags: CGEventFlags,
        isRepeat: Bool,
        frontmostBundleID: String?,
        bindings: [HotkeyBinding]
    ) -> (id: UUID, target: ApplicationTarget)? {
        guard !isRepeat, let target = target(for: frontmostBundleID) else { return nil }
        let modifiers = ShortcutModifiers(eventFlags: flags)
        guard let binding = bindings.first(where: {
            $0.enabledTargets.contains(target)
                && $0.shortcut.keyCode == keyCode
                && $0.shortcut.modifiers == modifiers
        }) else { return nil }
        return (binding.id, target)
    }

    private static func target(for bundleID: String?) -> ApplicationTarget? {
        switch bundleID {
        case AppConstants.chatGPTBundleID: .chatGPT
        case AppConstants.claudeDesktopBundleID: .claudeCode
        case AppConstants.cursorBundleID: .cursor
        case AppConstants.antigravityBundleID: .antigravity
        default: nil
        }
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
    private let logger = Logger(subsystem: "com.thierryai.ReasonDeck", category: "hotkeys")
    private let lock = NSLock()
    private let registry = HotkeyRegistry()
    private let recorder = ShortcutRecorderRegistry()
    private var tap: CFMachPort?
    private var source: CFRunLoopSource?
    private var consumedKeyCodes = Set<UInt16>()
    private let onEntry: @Sendable (HotkeyCapture) -> Void
    private(set) var state: State = .stopped

    init(onEntry: @escaping @Sendable (HotkeyCapture) -> Void) { self.onEntry = onEntry }

    func update(bindings: [HotkeyBinding]) {
        registry.replace(with: bindings)
    }

    func beginRecording(_ handler: @escaping ShortcutRecordingHandler) -> Bool {
        guard state == .running else { return false }
        recorder.begin(handler)
        return true
    }

    func cancelRecording() {
        recorder.cancel()
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
        recorder.cancel()
    }

    private static let callback: CGEventTapCallBack = { _, type, event, pointer in
        guard let pointer else { return Unmanaged.passUnretained(event) }
        let owner = Unmanaged<HotkeyEventTap>.fromOpaque(pointer).takeUnretainedValue()
        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
            let reason = type == .tapDisabledByTimeout ? "timeout" : "user_input"
            owner.logger.error("Hotkey event tap disabled reason=\(reason, privacy: .public); re-enabling")
            if let tap = owner.tap { CGEvent.tapEnable(tap: tap, enable: true) }
            return Unmanaged.passUnretained(event)
        }
        if event.getIntegerValueField(.eventSourceUserData) == SyntheticEventMarker.value {
            return Unmanaged.passUnretained(event)
        }
        let keyCode = UInt16(event.getIntegerValueField(.keyboardEventKeycode))
        if type == .keyUp {
            let consumed = owner.lock.withLock { owner.consumedKeyCodes.remove(keyCode) != nil }
            return consumed ? nil : Unmanaged.passUnretained(event)
        }
        guard type == .keyDown else { return Unmanaged.passUnretained(event) }
        let repeated = event.getIntegerValueField(.keyboardEventAutorepeat) != 0
        if repeated, owner.lock.withLock({ owner.consumedKeyCodes.contains(keyCode) }) {
            return nil
        }
        if let capture = owner.recorder.capture({
            ShortcutRecording.capture(
                keyCode: keyCode,
                flags: event.flags,
                keyLabel: NSEvent(cgEvent: event)?.characters(byApplyingModifiers: [])
            )
        }) {
            _ = owner.lock.withLock { owner.consumedKeyCodes.insert(keyCode) }
            capture.handler(capture.result)
            return nil
        }
        guard let running = NSWorkspace.shared.frontmostApplication else {
            return Unmanaged.passUnretained(event)
        }
        guard let match = HotkeyMatcher.match(
            keyCode: keyCode,
            flags: event.flags,
            isRepeat: repeated,
            frontmostBundleID: running.bundleIdentifier,
            bindings: owner.registry.snapshot()
        ) else {
            return Unmanaged.passUnretained(event)
        }
        _ = owner.lock.withLock { owner.consumedKeyCodes.insert(keyCode) }
        owner.onEntry(HotkeyCapture(
            entryID: match.id,
            target: match.target,
            pid: running.processIdentifier
        ))
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
