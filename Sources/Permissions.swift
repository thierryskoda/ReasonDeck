import AppKit
import ApplicationServices
import CoreGraphics
import Foundation
import Observation
import Security

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

/// How durably macOS can recognize this build when it stores a privacy grant.
///
/// TCC keys Accessibility and Input Monitoring grants by the app's designated code
/// requirement. An identity-signed build (Apple Development or Developer ID) yields
/// `identifier + team`, which survives rebuilds. An ad-hoc build yields only a `cdhash`,
/// so every rebuild is a new app to TCC: System Settings keeps showing the old toggle
/// on while the new binary is denied. See ADR-001 point 10.
enum BuildSigningIdentity: Equatable, Sendable {
    case stable, adHoc, unsigned

    static func classify(_ bundleURL: URL) -> Self {
        var staticCode: SecStaticCode?
        guard SecStaticCodeCreateWithPath(bundleURL as CFURL, [], &staticCode) == errSecSuccess,
              let staticCode else { return .unsigned }
        var info: CFDictionary?
        guard SecCodeCopySigningInformation(staticCode, [], &info) == errSecSuccess,
              let info = info as? [String: Any] else { return .unsigned }
        let flags = (info[kSecCodeInfoFlags as String] as? UInt32).map(SecCodeSignatureFlags.init(rawValue:))
        return classify(
            isSigned: info[kSecCodeInfoIdentifier as String] != nil,
            flags: flags ?? []
        )
    }

    static func classify(isSigned: Bool, flags: SecCodeSignatureFlags) -> Self {
        guard isSigned else { return .unsigned }
        return flags.contains(.adhoc) ? .adHoc : .stable
    }

    /// Nil when grants are expected to persist across rebuilds.
    var advisory: String? {
        switch self {
        case .stable: nil
        case .adHoc:
            "This build is ad-hoc signed, so macOS forgets its Accessibility and Input Monitoring grants on every rebuild. Sign with a stable Apple Development team for lasting permissions."
        case .unsigned:
            "This build is unsigned, so macOS cannot keep its Accessibility and Input Monitoring grants. Sign with a stable Apple Development team for lasting permissions."
        }
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
    let signingIdentity: BuildSigningIdentity
    private(set) var installLocation: AppInstallLocation
    private(set) var installationError: String?
    private(set) var isInstalling = false
    private(set) var snapshot = PermissionSnapshot(
        accessibilityGranted: false,
        inputMonitoringGranted: false
    )

    init(
        bundleURL: URL = Bundle.main.bundleURL,
        signingIdentity: BuildSigningIdentity? = nil
    ) {
        self.bundleURL = bundleURL
        self.signingIdentity = signingIdentity ?? BuildSigningIdentity.classify(bundleURL)
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

    /// Input Monitoring is applied only to processes started after the grant, which is
    /// why macOS offers "Quit & Reopen" when the toggle changes for a running app. Offer
    /// the same remedy in place so a fresh grant does not look broken.
    func relaunch() {
        Task {
            let configuration = NSWorkspace.OpenConfiguration()
            configuration.activates = true
            configuration.createsNewApplicationInstance = true
            _ = try? await NSWorkspace.shared.openApplication(at: bundleURL, configuration: configuration)
            NSApplication.shared.terminate(nil)
        }
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
