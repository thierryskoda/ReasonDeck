import AppKit
import ApplicationServices
import CoreGraphics
import Foundation
import Observation

enum AppInstallLocation: Equatable, Sendable {
    case installed
    case requiresInstallation
    case unsupportedBuild

    static func classify(_ bundleURL: URL) -> Self {
        let url = bundleURL.standardizedFileURL
        guard url.pathExtension == "app" else { return .unsupportedBuild }
        return url.deletingLastPathComponent().path == "/Applications"
            ? .installed
            : .requiresInstallation
    }
}

enum PermissionState: Equatable, Sendable {
    case ready, accessibilityRequired, inputMonitoringRequired

    var message: String {
        switch self {
        case .ready: "Permissions ready"
        case .accessibilityRequired: "Accessibility permission required"
        case .inputMonitoringRequired: "Input Monitoring permission required"
        }
    }
}

struct PermissionSnapshot: Equatable, Sendable {
    let accessibilityGranted: Bool
    let inputMonitoringGranted: Bool

    var state: PermissionState {
        guard accessibilityGranted else { return .accessibilityRequired }
        guard inputMonitoringGranted else { return .inputMonitoringRequired }
        return .ready
    }
}

@MainActor
@Observable
final class PermissionReadiness {
    let bundleURL: URL
    private(set) var installLocation: AppInstallLocation
    private(set) var installationError: String?
    private(set) var isInstalling = false
    private(set) var snapshot = PermissionSnapshot(
        accessibilityGranted: false,
        inputMonitoringGranted: false
    )

    init(bundleURL: URL = Bundle.main.bundleURL) {
        self.bundleURL = bundleURL
        installLocation = AppInstallLocation.classify(bundleURL)
    }

    var state: PermissionState { snapshot.state }

    func refresh(eventTapAvailable: Bool) {
        snapshot = PermissionController.snapshot(eventTapAvailable: eventTapAvailable)
    }

    func requestAccessibility() {
        PermissionController.requestAccessibility()
        openSettingsAfterRequest("Privacy_Accessibility")
    }

    func requestInputMonitoring() {
        PermissionController.requestInputMonitoring()
        openSettingsAfterRequest("Privacy_ListenEvent")
    }

    func installInApplications() {
        guard installLocation == .requiresInstallation, !isInstalling else { return }
        let destination = URL(fileURLWithPath: "/Applications/ReasonDeck.app", isDirectory: true)

        guard !FileManager.default.fileExists(atPath: destination.path) else {
            installationError = "ReasonDeck already exists in Applications. Open that copy, or remove it before installing this build."
            NSWorkspace.shared.activateFileViewerSelecting([destination])
            return
        }

        isInstalling = true
        installationError = nil
        do {
            try FileManager.default.copyItem(at: bundleURL, to: destination)
        } catch {
            isInstalling = false
            installationError = "ReasonDeck could not be copied to Applications: \(error.localizedDescription)"
            return
        }

        Task {
            do {
                UserDefaults.standard.removeObject(
                    forKey: "com.thierryai.ReasonDeck.didOpenInitialSettings.v1"
                )
                let configuration = NSWorkspace.OpenConfiguration()
                configuration.activates = true
                configuration.createsNewApplicationInstance = true
                _ = try await NSWorkspace.shared.openApplication(
                    at: destination,
                    configuration: configuration
                )
                NSApplication.shared.terminate(nil)
            } catch {
                isInstalling = false
                installationError = "ReasonDeck was installed, but the installed copy could not be opened: \(error.localizedDescription)"
                NSWorkspace.shared.activateFileViewerSelecting([destination])
            }
        }
    }

    func clearInstallationError() {
        installationError = nil
    }

    private func openSettingsAfterRequest(_ pane: String) {
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            PermissionController.openPrivacyPane(pane)
        }
    }
}

enum PermissionController {
    static func state(eventTapAvailable: Bool) -> PermissionState {
        snapshot(eventTapAvailable: eventTapAvailable).state
    }

    static func snapshot(eventTapAvailable: Bool) -> PermissionSnapshot {
        snapshot(
            accessibilityGranted: AXIsProcessTrusted(),
            inputMonitoringPreflightGranted: CGPreflightListenEventAccess(),
            eventTapAvailable: eventTapAvailable
        )
    }

    static func snapshot(
        accessibilityGranted: Bool,
        inputMonitoringPreflightGranted: Bool,
        eventTapAvailable _: Bool
    ) -> PermissionSnapshot {
        PermissionSnapshot(
            accessibilityGranted: accessibilityGranted,
            // Creating an event tap can succeed with Accessibility alone while macOS still
            // withholds real keyboard events. Only the dedicated preflight may report this
            // privacy grant as ready.
            inputMonitoringGranted: inputMonitoringPreflightGranted
        )
    }

    static func requestAccessibility() {
        AXIsProcessTrustedWithOptions(["AXTrustedCheckOptionPrompt": true] as CFDictionary)
    }

    static func requestInputMonitoring() { CGRequestListenEventAccess() }

    static func openPrivacyPane(_ pane: String) {
        guard let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?\(pane)") else { return }
        NSWorkspace.shared.open(url)
    }
}
