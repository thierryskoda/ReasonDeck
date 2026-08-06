import AppKit
import ApplicationServices
import SwiftUI
import os

@MainActor
final class SettingsWindowController {
    private var window: NSWindow?

    func show(store: ProfileStore, readiness: PermissionReadiness, onRetryHotkeys: @escaping () -> Void) {
        if window == nil {
            let controller = NSHostingController(rootView: SettingsView(
                store: store,
                readiness: readiness,
                onRetryHotkeys: onRetryHotkeys
            ))
            let window = NSWindow(contentViewController: controller)
            window.title = "Shortcuts"
            window.styleMask = [.titled, .closable, .miniaturizable, .resizable]
            window.setContentSize(NSSize(width: 560, height: 560))
            window.minSize = NSSize(width: 520, height: 440)
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
    private let logger = Logger(subsystem: "com.thierryai.ChatGPTProfileKeys", category: "result")
    private let coordinator = ProfileSwitchCoordinator(client: SystemAccessibilityClient())
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
        hotkeyTap = HotkeyEventTap { [weak self] id in
            Task { @MainActor in self?.apply(id) }
        }
        store.onChange = { [weak self] in self?.syncHotkeys() }
        syncHotkeys()
        _ = hotkeyTap?.start()
        activationObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.didBecomeActiveNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in self?.refreshPermissions() }
        }
        refreshPermissions()
        let firstRunKey = "com.thierryai.ChatGPTProfileKeys.didOpenInitialSettings.v1"
        if !UserDefaults.standard.bool(forKey: firstRunKey) {
            UserDefaults.standard.set(true, forKey: firstRunKey)
            DispatchQueue.main.async { [weak self] in self?.openSettings() }
        }
    }

    func apply(_ id: UUID) {
        guard !isSwitching else { NSSound.beep(); return }
        guard let entry = store.entry(id: id), entry.shortcut != nil else {
            status = .invalidConfiguration(store.invalidReason ?? "Saved shortcuts are invalid.")
            NSSound.beep()
            return
        }
        let profile = entry.selection
        isSwitching = true
        status = .switching(profile.displayName)
        Task {
            let result = await coordinator.apply(profile)
            switch result {
            case .success(let applied, let title, let elapsed):
                status = .success(title)
                logger.info("profile=\(applied.id, privacy: .public) outcome=success elapsed=\(String(describing: elapsed), privacy: .public)")
            case .partialFailure(let applied, let title, let failure):
                status = .partial(title: title, message: failure.message)
                logger.error("profile=\(applied.id, privacy: .public) outcome=partial failure=\(failure.message, privacy: .public)")
                NSSound.beep()
            case .failure(let applied, let failure):
                status = .failure(failure.message)
                logger.error("profile=\(applied.id, privacy: .public) outcome=failure failure=\(failure.message, privacy: .public)")
                NSSound.beep()
            }
            isSwitching = false
        }
    }

    func openSettings() {
        refreshPermissions()
        settingsWindowController.show(
            store: store,
            readiness: readiness,
            onRetryHotkeys: { [weak self] in self?.retryPermissions() }
        )
    }
    func retryPermissions() {
        if hotkeyTap?.state != .running { _ = hotkeyTap?.start() }
        refreshPermissions()
    }
    func refreshPermissions() {
        readiness.refresh(eventTapAvailable: hotkeyTap?.state == .running)
        if !store.isValid {
            status = .invalidConfiguration(store.invalidReason ?? "Saved shortcuts are invalid.")
        }
    }

    private func syncHotkeys() {
        let bindings = store.entries.compactMap { entry in
            entry.shortcut.map { HotkeyBinding(id: entry.id, shortcut: $0) }
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
        if model.permissionState == .accessibilityRequired {
            Text("ChatGPT Profile Keys needs Accessibility permission to select model-menu controls. It only inspects the active ChatGPT window.")
            Button("Request Accessibility Permission…") { model.readiness.requestAccessibility() }
            Button("Open Accessibility Settings…") { model.readiness.openAccessibilitySettings() }
            Divider()
        } else if model.permissionState == .inputMonitoringRequired {
            Text("Input Monitoring is required for app-scoped shortcuts.")
            Button("Request Input Monitoring…") { model.readiness.requestInputMonitoring() }
            Button("Open Input Monitoring Settings…") { model.readiness.openInputMonitoringSettings() }
            Button("Retry Hotkeys") { model.retryPermissions() }
            Divider()
        }
        if model.store.entries.isEmpty {
            Text("No shortcuts configured")
        } else {
            ForEach(model.store.entries) { entry in
                let shortcut = entry.shortcut?.displayName ?? "Set shortcut in Settings"
                Button("\(entry.selection.displayName)    \(shortcut)") { model.apply(entry.id) }
                    .disabled(model.isSwitching || !model.trusted || !model.store.isValid || entry.shortcut == nil)
            }
        }
        Divider()
        Button("Settings…") {
            model.openSettings()
        }
        Divider()
        Text(model.permissionState.message)
        if let version = model.chatGPTVersion { Text("ChatGPT \(version)") }
        Label(model.status.message, systemImage: model.status.systemImage).lineLimit(3)
        Divider()
        Button("Quit") { model.stop(); NSApplication.shared.terminate(nil) }
    }
}

@main
struct ChatGPTProfileKeysApp: App {
    @State private var model = MenuBarViewModel(store: ProfileStore())
    var body: some Scene {
        MenuBarExtra("ChatGPT Profile Keys", systemImage: model.isSwitching ? "arrow.triangle.2.circlepath" : "switch.2") {
            MenuBarContent(model: model)
        }
        .menuBarExtraStyle(.menu)

    }
}
