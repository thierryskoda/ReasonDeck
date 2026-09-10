import AppKit
import ApplicationServices
import SwiftUI
import os

@MainActor
final class SettingsWindowController {
    private var window: NSWindow?

    func show(
        store: ProfileStore,
        readiness: PermissionReadiness,
        menuBarReachability: MenuBarReachability,
        compatibilityHealth: CompatibilityHealth,
        beginShortcutRecording: @escaping (@escaping @MainActor @Sendable (ShortcutRecordingResult) -> Void) -> Bool,
        cancelShortcutRecording: @escaping () -> Void
    ) {
        if window == nil {
            let controller = NSHostingController(rootView: SettingsView(
                store: store,
                readiness: readiness,
                menuBarReachability: menuBarReachability,
                compatibilityHealth: compatibilityHealth,
                beginShortcutRecording: beginShortcutRecording,
                cancelShortcutRecording: cancelShortcutRecording
            ))
            let window = NSWindow(contentViewController: controller)
            window.title = "Shortcuts"
            window.styleMask = [.titled, .closable, .miniaturizable, .resizable]
            window.setContentSize(NSSize(width: 680, height: 700))
            window.minSize = NSSize(width: 640, height: 560)
            window.isReleasedWhenClosed = false
            window.setFrameAutosaveName("ShortcutSettingsWindow")
            window.center()
            self.window = window
        }
        NSApplication.shared.activate(ignoringOtherApps: true)
        window?.makeKeyAndOrderFront(nil)
    }
}

@MainActor
@Observable
final class MenuBarViewModel {
    private let logger = Logger(subsystem: "com.thierryai.ReasonDeck", category: "result")
    private let dispatcher = TargetDispatcher()
    private let claudeAccessibilityBootstrapper = ClaudeAccessibilityBootstrapper()
    private let settingsWindowController = SettingsWindowController()
    private var hotkeyTap: HotkeyEventTap?
    @ObservationIgnored private var activationObserver: NSObjectProtocol?
    @ObservationIgnored private var workspaceLaunchObserver: NSObjectProtocol?
    @ObservationIgnored private var workspaceTerminateObserver: NSObjectProtocol?
    let store: ProfileStore
    let readiness = PermissionReadiness()
    let menuBarReachability = MenuBarReachability()
    let compatibilityHealth = CompatibilityHealth()
    @ObservationIgnored var menuBarController: MenuBarController?
    @ObservationIgnored var menuBarPresentationDidChange: (() -> Void)?
    var isSwitching = false {
        didSet { menuBarPresentationDidChange?() }
    }
    var status: OperationStatus = .ready
    private(set) var lastFailureDiagnostic: FailureDiagnostic?
    var permissionState: PermissionState { readiness.state }
    var trusted: Bool { readiness.snapshot.accessibilityGranted }
    init(store: ProfileStore) {
        self.store = store
        hotkeyTap = HotkeyEventTap { [weak self] capture in
            Task { @MainActor in self?.apply(capture) }
        }
        store.onChange = { [weak self] in self?.syncHotkeys() }
        syncHotkeys()
        if readiness.installLocation == .installed {
            _ = hotkeyTap?.start()
        }
        activationObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.didBecomeActiveNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in self?.retryPermissions() }
        }
        refreshPermissions()
        workspaceLaunchObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didLaunchApplicationNotification,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            guard let application = notification.userInfo?[NSWorkspace.applicationUserInfoKey]
                    as? NSRunningApplication else { return }
            Task { @MainActor in
                guard let self else { return }
                if ApplicationTarget.allCases.contains(where: {
                    $0.bundleIdentifier == application.bundleIdentifier
                }) {
                    self.compatibilityHealth.refresh()
                }
                if application.bundleIdentifier == AppConstants.claudeDesktopBundleID {
                    self.prepareClaudeAccessibility(pid: application.processIdentifier)
                }
            }
        }
        workspaceTerminateObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didTerminateApplicationNotification,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            guard let application = notification.userInfo?[NSWorkspace.applicationUserInfoKey]
                    as? NSRunningApplication,
                  ApplicationTarget.allCases.contains(where: {
                      $0.bundleIdentifier == application.bundleIdentifier
                  })
            else { return }
            Task { @MainActor in self?.compatibilityHealth.refresh() }
        }
        prepareClaudeAccessibilityForRunningApp()
        UserDefaults.standard.set(true, forKey: ProfileStore.didOpenInitialSettingsKey)
        AppDelegate.reopenHandler = { [weak self] in self?.openSettings() }
        DispatchQueue.main.async { [weak self] in self?.openSettings() }
    }

    func apply(_ id: UUID) {
        guard let invocation = currentInvocation(for: id) else {
            status = .failure("Bring ChatGPT, Claude Desktop, Cursor, or Antigravity to the front with an active window.")
            NSSound.beep()
            return
        }
        apply(invocation)
    }

    private func apply(_ capture: HotkeyCapture) {
        guard let invocation = currentInvocation(for: capture) else {
            status = .failure("The target app or focused window changed before the shortcut could run.")
            NSSound.beep()
            return
        }
        apply(invocation)
    }

    /// A status-menu item fires before macOS has fully dismissed its menu.
    /// Wait briefly for the previously frontmost supported app and its focused window
    /// to become observable again instead of capturing ReasonDeck/Control Center.
    func applyFromMenu(_ id: UUID) {
        Task { @MainActor in
            for _ in 0..<20 {
                if let invocation = currentInvocation(for: id) {
                    apply(invocation)
                    return
                }
                try? await Task.sleep(for: .milliseconds(20))
            }
            status = .failure("Bring ChatGPT, Claude Desktop, Cursor, or Antigravity to the front with an active window.")
            NSSound.beep()
        }
    }

    func apply(_ invocation: HotkeyInvocation) {
        let attemptID = UUID()
        let clock = ContinuousClock()
        let start = clock.now
        lastFailureDiagnostic = nil
        guard !isSwitching else {
            status = .busy
            log(AttemptEvent(
                attemptID: attemptID,
                target: invocation.target,
                phase: .completed,
                outcome: .busy,
                failure: SwitchFailure.busy.diagnosticCode,
                elapsed: .zero
            ))
            NSSound.beep()
            return
        }
        log(AttemptEvent(
            attemptID: attemptID,
            target: invocation.target,
            phase: .captured,
            outcome: nil,
            failure: nil,
            elapsed: .zero
        ))
        guard readiness.installLocation == .installed else {
            status = .failure("Install ReasonDeck in Applications before using shortcuts.")
            log(AttemptEvent(attemptID: attemptID, target: invocation.target, phase: .completed, outcome: .failure, failure: .installationRequired, elapsed: start.duration(to: clock.now)))
            NSSound.beep()
            return
        }
        guard let entry = store.entry(id: invocation.entryID), entry.shortcut != nil else {
            status = .invalidConfiguration(store.invalidReason ?? "Saved shortcuts are invalid.")
            log(AttemptEvent(attemptID: attemptID, target: invocation.target, phase: .completed, outcome: .failure, failure: .invalidConfiguration, elapsed: start.duration(to: clock.now)))
            NSSound.beep()
            return
        }
        guard RuntimeCapabilities.supports(entry, target: invocation.target) else {
            status = .failure(RuntimeCapabilities.unavailableMessage(for: invocation.target))
            log(AttemptEvent(attemptID: attemptID, target: invocation.target, phase: .completed, outcome: .contextAborted, failure: .capabilityGated, elapsed: start.duration(to: clock.now)))
            NSSound.beep()
            return
        }
        isSwitching = true
        log(AttemptEvent(
            attemptID: attemptID,
            target: invocation.target,
            phase: .dispatched,
            outcome: nil,
            failure: nil,
            elapsed: start.duration(to: clock.now)
        ))
        guard let selectedProfile = entry.selection(for: invocation.target) else {
            status = .invalidConfiguration(store.invalidReason ?? "Saved shortcuts are invalid.")
            log(AttemptEvent(attemptID: attemptID, target: invocation.target, phase: .completed, outcome: .failure, failure: .missingAssignment, elapsed: start.duration(to: clock.now)))
            NSSound.beep()
            isSwitching = false
            return
        }
        status = .switching(selectedProfile.displayName)
        Task {
            let request = AttemptRequest.profile(selectedProfile)
            let result = await dispatcher.apply(entry: entry, invocation: invocation)
            switch result {
            case .success(let applied, let title, let elapsed):
                status = .success(title)
                compatibilityHealth.recordWorking(for: applied.target)
                log(AttemptEvent(attemptID: attemptID, target: applied.target, request: request, identitySource: invocation.identitySource, phase: .completed, outcome: .success, failure: nil, elapsed: elapsed))
            case .alreadyApplied(let applied, let title):
                status = .already(title)
                compatibilityHealth.recordWorking(for: applied.target)
                log(AttemptEvent(attemptID: attemptID, target: applied.target, request: request, identitySource: invocation.identitySource, phase: .completed, outcome: .alreadyApplied, failure: nil, elapsed: start.duration(to: clock.now)))
            case .partialFailure(let applied, let title, let failure):
                status = .partial(title: title, message: failure.message)
                recordFailureDiagnostic(for: applied.target, failure: failure.diagnosticCode)
                if CompatibilityPolicy.isContractFailure(failure.diagnosticCode) {
                    compatibilityHealth.recordFailure(failure.diagnosticCode, for: applied.target)
                } else {
                    compatibilityHealth.recordWorking(for: applied.target)
                }
                log(AttemptEvent(attemptID: attemptID, target: applied.target, request: request, identitySource: invocation.identitySource, phase: .completed, outcome: .partialFailure, failure: failure.diagnosticCode, elapsed: start.duration(to: clock.now)))
                NSSound.beep()
            case .failure(let applied, let failure):
                status = failure == .busy ? .busy : .failure(failure.message)
                recordFailureDiagnostic(for: applied.target, failure: failure.diagnosticCode)
                compatibilityHealth.recordFailure(failure.diagnosticCode, for: applied.target)
                log(AttemptEvent(attemptID: attemptID, target: applied.target, request: request, identitySource: invocation.identitySource, phase: .completed, outcome: failure == .busy ? .busy : .failure, failure: failure.diagnosticCode, elapsed: start.duration(to: clock.now)))
                NSSound.beep()
            }
            isSwitching = false
        }
    }

    private func log(_ event: AttemptEvent) {
        logger.info("event=attempt attempt=\(event.attemptID.uuidString, privacy: .public) target=\(event.target.rawValue, privacy: .public) request=\(event.request?.diagnosticValue ?? "none", privacy: .public) identity=\(event.identitySource.rawValue, privacy: .public) phase=\(event.phase.rawValue, privacy: .public) outcome=\(event.outcome?.rawValue ?? "pending", privacy: .public) failure=\(event.failure?.rawValue ?? "none", privacy: .public) app_version=\(self.targetVersion(event.target), privacy: .public) os_version=\(ProcessInfo.processInfo.operatingSystemVersionString, privacy: .public) build=\(self.reasonDeckBuild, privacy: .public) elapsed=\(String(describing: event.elapsed), privacy: .public)")
    }

    private var reasonDeckBuild: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "unknown"
    }

    private var reasonDeckVersion: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "unknown"
    }

    private func recordFailureDiagnostic(for target: ApplicationTarget, failure: AttemptFailureCode) {
        lastFailureDiagnostic = FailureDiagnostic(
            reasonDeckVersion: reasonDeckVersion,
            reasonDeckBuild: reasonDeckBuild,
            macOSVersion: ProcessInfo.processInfo.operatingSystemVersionString,
            target: target,
            targetVersion: targetVersion(target),
            failure: failure
        )
    }

    func copyLastFailureDiagnostic() {
        guard let lastFailureDiagnostic else { return }
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(lastFailureDiagnostic.clipboardText, forType: .string)
    }

    private func targetVersion(_ target: ApplicationTarget) -> String {
        guard let url = NSRunningApplication.runningApplications(
            withBundleIdentifier: target.bundleIdentifier
        ).first?.bundleURL,
              let bundle = Bundle(url: url)
        else { return "unknown" }
        return bundle.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "unknown"
    }

    private func currentInvocation(for id: UUID) -> HotkeyInvocation? {
        guard let running = NSWorkspace.shared.frontmostApplication else { return nil }
        let target: ApplicationTarget
        switch running.bundleIdentifier {
        case AppConstants.chatGPTBundleID: target = .chatGPT
        case AppConstants.claudeDesktopBundleID: target = .claudeCode
        case AppConstants.cursorBundleID: target = .cursor
        case AppConstants.antigravityBundleID: target = .antigravity
        default: return nil
        }
        let application = AXUIElementCreateApplication(running.processIdentifier)
        guard let identity = AXWindowIdentity.focusedWindowIdentity(
            application: application,
            pid: running.processIdentifier
        ) else { return nil }
        return HotkeyInvocation(
            entryID: id,
            target: target,
            pid: running.processIdentifier,
            focusedWindowID: identity.id,
            identitySource: identity.source
        )
    }

    private func currentInvocation(for capture: HotkeyCapture) -> HotkeyInvocation? {
        guard let running = NSWorkspace.shared.frontmostApplication,
              running.processIdentifier == capture.pid
        else { return nil }
        let observedTarget: ApplicationTarget
        switch running.bundleIdentifier {
        case AppConstants.chatGPTBundleID: observedTarget = .chatGPT
        case AppConstants.claudeDesktopBundleID: observedTarget = .claudeCode
        case AppConstants.cursorBundleID: observedTarget = .cursor
        case AppConstants.antigravityBundleID: observedTarget = .antigravity
        default: return nil
        }
        let application = AXUIElementCreateApplication(running.processIdentifier)
        guard let identity = AXWindowIdentity.focusedWindowIdentity(
            application: application,
            pid: running.processIdentifier
        ) else { return nil }
        return HotkeyInvocationFactory.make(
            capture: capture,
            observedTarget: observedTarget,
            observedPID: running.processIdentifier,
            identity: identity
        )
    }

    func openSettings() {
        refreshPermissions()
        menuBarReachability.refresh()
        compatibilityHealth.refresh()
        settingsWindowController.show(
            store: store,
            readiness: readiness,
            menuBarReachability: menuBarReachability,
            compatibilityHealth: compatibilityHealth,
            beginShortcutRecording: { [weak self] handler in
                self?.beginShortcutRecording(handler) ?? false
            },
            cancelShortcutRecording: { [weak self] in
                self?.cancelShortcutRecording()
            }
        )
    }

    private func beginShortcutRecording(
        _ handler: @escaping @MainActor @Sendable (ShortcutRecordingResult) -> Void
    ) -> Bool {
        hotkeyTap?.beginRecording { result in
            Task { @MainActor in handler(result) }
        } ?? false
    }

    private func cancelShortcutRecording() {
        hotkeyTap?.cancelRecording()
    }
    func retryPermissions() {
        if readiness.installLocation == .installed, hotkeyTap?.state != .running {
            _ = hotkeyTap?.start()
        }
        refreshPermissions()
        compatibilityHealth.refresh()
        prepareClaudeAccessibilityForRunningApp()
    }
    func refreshPermissions() {
        readiness.refresh(eventTapAvailable: hotkeyTap?.state == .running)
        if !store.isValid {
            status = .invalidConfiguration(store.invalidReason ?? "Saved shortcuts are invalid.")
        }
    }

    private func syncHotkeys() {
        let bindings: [HotkeyBinding] = store.entries.compactMap { entry -> HotkeyBinding? in
            guard let shortcut = entry.shortcut else { return nil }
            let targets = RuntimeCapabilities.runnableTargets(for: entry)
            guard !targets.isEmpty else { return nil }
            return HotkeyBinding(id: entry.id, shortcut: shortcut, enabledTargets: targets)
        }
        hotkeyTap?.update(bindings: bindings)
    }

    func stop() {
        hotkeyTap?.stop()
        if let activationObserver { NotificationCenter.default.removeObserver(activationObserver) }
        if let workspaceLaunchObserver {
            NSWorkspace.shared.notificationCenter.removeObserver(workspaceLaunchObserver)
        }
        if let workspaceTerminateObserver {
            NSWorkspace.shared.notificationCenter.removeObserver(workspaceTerminateObserver)
        }
    }

    private func prepareClaudeAccessibilityForRunningApp() {
        guard let application = NSRunningApplication.runningApplications(
            withBundleIdentifier: AppConstants.claudeDesktopBundleID
        ).first else { return }
        prepareClaudeAccessibility(pid: application.processIdentifier)
    }

    private func prepareClaudeAccessibility(pid: pid_t) {
        Task { await claudeAccessibilityBootstrapper.prepare(pid: pid) }
    }
}

/// Reopens Settings when the user launches ReasonDeck again.
///
/// The menu bar icon can be pushed into unusable space on displays with a
/// notch, so relaunching the app is the only reliable way back to Settings.
final class AppDelegate: NSObject, NSApplicationDelegate {
    @MainActor static var reopenHandler: (() -> Void)?

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        MainActor.assumeIsolated { AppDelegate.reopenHandler?() }
        return true
    }
}

@main
struct ReasonDeckApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @State private var model: MenuBarViewModel

    init() {
        let model = MenuBarViewModel(store: ProfileStore())
        _model = State(initialValue: model)
        model.menuBarController = MenuBarController(model: model)
    }

    var body: some Scene {
        Settings {
            EmptyView()
        }
    }
}
