import AppKit
import ApplicationServices
import CoreGraphics
import Foundation
import Observation

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
    private(set) var snapshot = PermissionSnapshot(
        accessibilityGranted: false,
        inputMonitoringGranted: false
    )

    var state: PermissionState { snapshot.state }

    func refresh(eventTapAvailable: Bool) {
        snapshot = PermissionController.snapshot(eventTapAvailable: eventTapAvailable)
    }

    func requestAccessibility() {
        PermissionController.requestAccessibility()
    }

    func openAccessibilitySettings() {
        PermissionController.openPrivacyPane("Privacy_Accessibility")
    }

    func requestInputMonitoring() {
        PermissionController.requestInputMonitoring()
    }

    func openInputMonitoringSettings() {
        PermissionController.openPrivacyPane("Privacy_ListenEvent")
    }
}

enum PermissionController {
    static func state(eventTapAvailable: Bool) -> PermissionState {
        snapshot(eventTapAvailable: eventTapAvailable).state
    }

    static func snapshot(eventTapAvailable: Bool) -> PermissionSnapshot {
        PermissionSnapshot(
            accessibilityGranted: AXIsProcessTrusted(),
            inputMonitoringGranted: eventTapAvailable || CGPreflightListenEventAccess()
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
