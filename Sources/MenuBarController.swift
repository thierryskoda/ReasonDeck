import AppKit
import os

@MainActor
final class MenuBarController: NSObject, NSMenuDelegate {
    private static let identificationLength: CGFloat = 57
    private let model: MenuBarViewModel
    private let statusItem: NSStatusItem
    private let menu = NSMenu()
    private let logger = Logger(subsystem: "com.thierryai.ReasonDeck", category: "menu-bar")
    private let preexistingStatusWindows: [MenuBarStatusWindowSnapshot]
    private var statusWindowNumber: CGWindowID?

    init(model: MenuBarViewModel) {
        self.model = model
        preexistingStatusWindows = Self.controlCenterStatusWindows()
        statusItem = NSStatusBar.system.statusItem(withLength: Self.identificationLength)
        super.init()

        menu.delegate = self
        statusItem.menu = menu
        statusItem.button?.toolTip = "ReasonDeck"
        statusItem.button?.setAccessibilityLabel("ReasonDeck")
        updateIcon()
        captureFrameAfterStatusItemMounts()

        model.menuBarPresentationDidChange = { [weak self] in self?.updateIcon() }
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(screenParametersDidChange),
            name: NSApplication.didChangeScreenParametersNotification,
            object: nil
        )
    }

    func menuWillOpen(_ menu: NSMenu) {
        refreshStatusItemFrame()
        rebuildMenu()
    }

    private func rebuildMenu() {
        menu.removeAllItems()

        if model.readiness.installLocation != .installed {
            addInformationalItem("Install ReasonDeck in Applications before granting permissions.")
            addAction("Open Settings…", action: #selector(openSettings))
            menu.addItem(.separator())
        } else if model.permissionState == .accessibilityRequired {
            addInformationalItem("ReasonDeck needs Accessibility permission to select model-menu controls. It only inspects the active ChatGPT, Claude Desktop, Cursor, or Antigravity window.")
            addAction("Allow Accessibility…", action: #selector(requestAccessibility))
            menu.addItem(.separator())
        } else if model.permissionState == .inputMonitoringRequired {
            addInformationalItem("Input Monitoring is required for app-scoped shortcuts.")
            addAction("Allow Input Monitoring…", action: #selector(requestInputMonitoring))
            menu.addItem(.separator())
        }

        if model.store.entries.isEmpty {
            addInformationalItem("No shortcuts configured")
        } else {
            for entry in model.store.entries {
                let shortcut = entry.shortcut?.displayName ?? "Set shortcut in Settings"
                let apps = entry.enabledTargets.map(\.displayName).sorted().joined(separator: " + ")
                let title = "\(apps)    \(shortcut)"
                let item = addAction(title, action: #selector(applyEntry(_:)))
                item.representedObject = entry.id.uuidString
                item.isEnabled = model.readiness.installLocation == .installed
                    && !model.isSwitching
                    && model.trusted
                    && model.store.isValid
                    && entry.shortcut != nil
            }
        }

        menu.addItem(.separator())
        addAction("Settings…", action: #selector(openSettings))
        menu.addItem(.separator())

        addInformationalItem(
            model.readiness.installLocation == .installed
                ? model.permissionState.message
                : "Installation required"
        )
        let status = addInformationalItem(model.status.message)
        status.image = NSImage(systemSymbolName: model.status.systemImage, accessibilityDescription: nil)

        if model.lastFailureDiagnostic != nil {
            addAction("Copy Failure Details", action: #selector(copyFailureDetails))
        }

        menu.addItem(.separator())
        addAction("Quit", action: #selector(quit))
    }

    @discardableResult
    private func addAction(_ title: String, action: Selector) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: "")
        item.target = self
        menu.addItem(item)
        return item
    }

    @discardableResult
    private func addInformationalItem(_ title: String) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: nil, keyEquivalent: "")
        item.isEnabled = false
        menu.addItem(item)
        return item
    }

    private func updateIcon() {
        let symbol = model.isSwitching ? "arrow.triangle.2.circlepath" : "switch.2"
        statusItem.button?.image = NSImage(systemSymbolName: symbol, accessibilityDescription: "ReasonDeck")
    }

    private func captureFrameAfterStatusItemMounts() {
        Task { @MainActor [weak self] in
            for _ in 0..<20 {
                guard let self else { return }
                if self.accessibilityStatusItemFrame() != nil {
                    self.statusItem.length = NSStatusItem.squareLength
                    try? await Task.sleep(for: .milliseconds(25))
                    if self.refreshStatusItemFrame() { return }
                }

                if let window = MenuBarStatusWindowLocator.markerWindow(
                    in: Self.controlCenterStatusWindows(),
                    comparedTo: self.preexistingStatusWindows
                ) {
                    self.statusWindowNumber = window.number
                    self.statusItem.length = NSStatusItem.squareLength
                    for _ in 0..<20 {
                        try? await Task.sleep(for: .milliseconds(25))
                        if self.refreshStatusItemFrame() { return }
                    }
                    break
                }
                try? await Task.sleep(for: .milliseconds(25))
            }
            self?.statusItem.length = NSStatusItem.squareLength
            self?.logger.error("event=status_item_frame_unavailable")
        }
    }

    @discardableResult
    private func refreshStatusItemFrame() -> Bool {
        if let frame = accessibilityStatusItemFrame() {
            recordStatusItemFrame(frame)
            return true
        }

        let windows = Self.controlCenterStatusWindows()
        guard let statusWindowNumber,
              let window = windows.first(where: { $0.number == statusWindowNumber }),
              let frame = Self.appKitFrame(for: window.coreGraphicsFrame)
        else { return false }

        recordStatusItemFrame(frame)
        return true
    }

    private func recordStatusItemFrame(_ frame: CGRect) {
        model.menuBarReachability.update(statusItemFrame: frame)
        logger.info("event=status_item_frame x=\(frame.minX) y=\(frame.minY) width=\(frame.width) height=\(frame.height) state=\(String(describing: self.model.menuBarReachability.state), privacy: .public)")
    }

    /// Some macOS versions expose button-local coordinates through
    /// accessibilityFrame(). Only accept it when it resolves to a real display;
    /// otherwise use the remote Control Center window metadata below.
    private func accessibilityStatusItemFrame() -> CGRect? {
        guard let frame = statusItem.button?.accessibilityFrame(), !frame.isEmpty,
              MenuBarReachability.classify(
                statusItemFrame: frame,
                displays: NSScreen.screens.map(MenuBarDisplayGeometry.init)
              ) != .unknown
        else { return nil }
        return frame
    }

    /// macOS 26 remotely hosts third-party status items inside Control Center, so
    /// NSStatusBarButton may have no local window or Accessibility frame. Snapshot
    /// only Control Center's public status-window metadata and identify the one
    /// window created by this controller; no screen content is read.
    private static func controlCenterStatusWindows() -> [MenuBarStatusWindowSnapshot] {
        guard let pid = NSRunningApplication.runningApplications(
            withBundleIdentifier: "com.apple.controlcenter"
        ).first?.processIdentifier,
              let rows = CGWindowListCopyWindowInfo([.optionAll], kCGNullWindowID)
                as? [[String: Any]]
        else { return [] }

        return rows.compactMap { row in
            guard (row[kCGWindowOwnerPID as String] as? NSNumber)?.int32Value == pid,
                  (row[kCGWindowLayer as String] as? NSNumber)?.intValue
                    == NSWindow.Level.statusBar.rawValue,
                  let number = (row[kCGWindowNumber as String] as? NSNumber)?.uint32Value,
                  let bounds = row[kCGWindowBounds as String] as? NSDictionary
            else { return nil }
            var frame = CGRect.zero
            guard CGRectMakeWithDictionaryRepresentation(bounds, &frame) else { return nil }
            return MenuBarStatusWindowSnapshot(number: number, coreGraphicsFrame: frame)
        }
    }

    private static func appKitFrame(for coreGraphicsFrame: CGRect) -> CGRect? {
        for screen in NSScreen.screens {
            let key = NSDeviceDescriptionKey("NSScreenNumber")
            guard let number = screen.deviceDescription[key] as? NSNumber else { continue }
            let displayFrame = CGDisplayBounds(CGDirectDisplayID(number.uint32Value))
            guard displayFrame.intersects(coreGraphicsFrame) else { continue }
            return MenuBarStatusWindowLocator.appKitFrame(
                for: coreGraphicsFrame,
                coreGraphicsDisplayFrame: displayFrame,
                appKitDisplayFrame: screen.frame
            )
        }
        return nil
    }

    @objc private func screenParametersDidChange() {
        refreshStatusItemFrame()
    }

    @objc private func openSettings() {
        model.openSettings()
    }

    @objc private func requestAccessibility() {
        model.readiness.requestAccessibility()
    }

    @objc private func requestInputMonitoring() {
        model.readiness.requestInputMonitoring()
    }

    @objc private func copyFailureDetails() {
        model.copyLastFailureDiagnostic()
    }

    @objc private func applyEntry(_ sender: NSMenuItem) {
        guard let rawID = sender.representedObject as? String,
              let id = UUID(uuidString: rawID) else { return }
        model.applyFromMenu(id)
    }

    @objc private func quit() {
        model.stop()
        NSApplication.shared.terminate(nil)
    }
}
