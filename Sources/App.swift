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
        beginShortcutRecording: @escaping (@escaping @MainActor @Sendable (ShortcutRecordingResult) -> Void) -> Bool,
        cancelShortcutRecording: @escaping () -> Void
    ) {
        if window == nil {
            let controller = NSHostingController(rootView: SettingsView(
                store: store,
                readiness: readiness,
                beginShortcutRecording: beginShortcutRecording,
                cancelShortcutRecording: cancelShortcutRecording
            ))
            let window = NSWindow(contentViewController: controller)
            window.title = "Shortcuts"
            window.styleMask = [.titled, .closable, .miniaturizable, .resizable]
            window.setContentSize(NSSize(width: 680, height: 560))
            window.minSize = NSSize(width: 640, height: 480)
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
    private let settingsWindowController = SettingsWindowController()
    private var hotkeyTap: HotkeyEventTap?
    @ObservationIgnored private var activationObserver: NSObjectProtocol?
    let store: ProfileStore
    let readiness = PermissionReadiness()
    var isSwitching = false
    var status: OperationStatus = .ready
    var permissionState: PermissionState { readiness.state }
    var trusted: Bool { readiness.snapshot.accessibilityGranted }
    var chatGPTVersion: String? {
        guard let url = NSRunningApplication.runningApplications(withBundleIdentifier: AppConstants.chatGPTBundleID).first?.bundleURL,
              let bundle = Bundle(url: url) else { return nil }
        return bundle.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String
    }

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
        let firstRunKey = ProfileStore.didOpenInitialSettingsKey
        if !UserDefaults.standard.bool(forKey: firstRunKey) {
            UserDefaults.standard.set(true, forKey: firstRunKey)
            DispatchQueue.main.async { [weak self] in self?.openSettings() }
        }
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

    /// A MenuBarExtra button fires before macOS has fully dismissed the status menu.
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
        let navigation = entry.navigation(for: invocation.target)
        let selectedProfile = entry.selection(for: invocation.target)
        guard navigation != nil || selectedProfile != nil else {
            status = .invalidConfiguration(store.invalidReason ?? "Saved shortcuts are invalid.")
            log(AttemptEvent(attemptID: attemptID, target: invocation.target, phase: .completed, outcome: .failure, failure: .missingAssignment, elapsed: start.duration(to: clock.now)))
            NSSound.beep()
            isSwitching = false
            return
        }
        status = .switching(navigation?.displayName ?? selectedProfile!.displayName)
        Task {
            let request = navigation.map(AttemptRequest.cursorNavigation) ?? .profile(selectedProfile!)
            let dispatched = await dispatcher.apply(entry: entry, invocation: invocation)
            switch dispatched {
            case .navigation(let navigation):
                switch navigation {
                case .success(let title, let elapsed):
                    status = .success(title)
                    log(AttemptEvent(attemptID: attemptID, target: .cursor, request: request, identitySource: invocation.identitySource, phase: .completed, outcome: .success, failure: nil, elapsed: elapsed))
                case .failure(let failure):
                    status = failure == .busy ? .busy : .failure(failure.message)
                    log(AttemptEvent(attemptID: attemptID, target: .cursor, request: request, identitySource: invocation.identitySource, phase: .completed, outcome: failure == .busy ? .busy : .failure, failure: failure.diagnosticCode, elapsed: start.duration(to: clock.now)))
                    NSSound.beep()
                }
            case .profile(let result):
            switch result {
            case .success(let applied, let title, let elapsed):
                status = .success(title)
                log(AttemptEvent(attemptID: attemptID, target: applied.target, request: request, identitySource: invocation.identitySource, phase: .completed, outcome: .success, failure: nil, elapsed: elapsed))
            case .alreadyApplied(let applied, let title):
                status = .already(title)
                log(AttemptEvent(attemptID: attemptID, target: applied.target, request: request, identitySource: invocation.identitySource, phase: .completed, outcome: .alreadyApplied, failure: nil, elapsed: start.duration(to: clock.now)))
            case .partialFailure(let applied, let title, let failure):
                status = .partial(title: title, message: failure.message)
                log(AttemptEvent(attemptID: attemptID, target: applied.target, request: request, identitySource: invocation.identitySource, phase: .completed, outcome: .partialFailure, failure: failure.diagnosticCode, elapsed: start.duration(to: clock.now)))
                NSSound.beep()
            case .failure(let applied, let failure):
                status = failure == .busy ? .busy : .failure(failure.message)
                log(AttemptEvent(attemptID: attemptID, target: applied.target, request: request, identitySource: invocation.identitySource, phase: .completed, outcome: failure == .busy ? .busy : .failure, failure: failure.diagnosticCode, elapsed: start.duration(to: clock.now)))
                NSSound.beep()
            }
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

    private func targetVersion(_ target: ApplicationTarget) -> String {
        let bundleID: String
        switch target {
        case .chatGPT: bundleID = AppConstants.chatGPTBundleID
        case .claudeCode: bundleID = AppConstants.claudeDesktopBundleID
        case .cursor: bundleID = AppConstants.cursorBundleID
        case .antigravity: bundleID = AppConstants.antigravityBundleID
        }
        guard let url = NSRunningApplication.runningApplications(withBundleIdentifier: bundleID).first?.bundleURL,
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
        settingsWindowController.show(
            store: store,
            readiness: readiness,
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
    }
}

struct MenuBarContent: View {
    @Bindable var model: MenuBarViewModel
    var body: some View {
        if model.readiness.installLocation != .installed {
            Text("Install ReasonDeck in Applications before granting permissions.")
            Button("Open Settings…") { model.openSettings() }
            Divider()
        } else if model.permissionState == .accessibilityRequired {
            Text("ReasonDeck needs Accessibility permission to select model-menu controls. It only inspects the active ChatGPT, Claude Desktop, Cursor, or Antigravity window.")
            Button("Allow Accessibility…") { model.readiness.requestAccessibility() }
            Divider()
        } else if model.permissionState == .inputMonitoringRequired {
            Text("Input Monitoring is required for app-scoped shortcuts.")
            Button("Allow Input Monitoring…") { model.readiness.requestInputMonitoring() }
            Divider()
        }
        if model.store.entries.isEmpty {
            Text("No shortcuts configured")
        } else {
            ForEach(model.store.entries) { entry in
                let shortcut = entry.shortcut?.displayName ?? "Set shortcut in Settings"
                let label: String = {
                    if let navigation = entry.cursorNavigation {
                        return "\(navigation.displayName)    \(shortcut)"
                    }
                    let apps = entry.enabledTargets.map(\.displayName).sorted().joined(separator: " + ")
                    return "\(apps)    \(shortcut)"
                }()
                Button(label) { model.applyFromMenu(entry.id) }
                    .disabled(
                        model.readiness.installLocation != .installed
                            || model.isSwitching
                            || !model.trusted
                            || !model.store.isValid
                            || entry.shortcut == nil
                    )
            }
        }
        Divider()
        Button("Settings…") {
            model.openSettings()
        }
        Divider()
        Text(
            model.readiness.installLocation == .installed
                ? model.permissionState.message
                : "Installation required"
        )
        if let version = model.chatGPTVersion { Text("ChatGPT \(version)") }
        Label(model.status.message, systemImage: model.status.systemImage).lineLimit(3)
        Divider()
        Button("Quit") { model.stop(); NSApplication.shared.terminate(nil) }
    }
}

@main
struct ReasonDeckApp: App {
    @State private var model = MenuBarViewModel(store: ProfileStore())

    var body: some Scene {
        MenuBarExtra("ReasonDeck", systemImage: model.isSwitching ? "arrow.triangle.2.circlepath" : "switch.2") {
            MenuBarContent(model: model)
        }
        .menuBarExtraStyle(.menu)
    }
}
