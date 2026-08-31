import Foundation
import Testing
@testable import ReasonDeck

@Test func applicationInstallLocationRecognizesSystemApplications() {
    #expect(AppInstallLocation.classify(
        URL(fileURLWithPath: "/Applications/ReasonDeck.app")
    ) == .installed)
}

@Test func applicationInstallLocationRejectsTransientBuildProducts() {
    #expect(AppInstallLocation.classify(
        URL(fileURLWithPath: "/tmp/DerivedData/Build/Products/Release/ReasonDeck.app")
    ) == .requiresInstallation)
}

@Test func applicationInstallLocationDoesNotOfferToCopyABareExecutable() {
    #expect(AppInstallLocation.classify(
        URL(fileURLWithPath: "/tmp/.build/arm64-apple-macosx/debug/ReasonDeck")
    ) == .unsupportedBuild)
}

@Test func permissionSnapshotRequiresAccessibilityFirst() {
    let snapshot = PermissionSnapshot(
        accessibilityGranted: false,
        inputMonitoringGranted: false
    )

    #expect(snapshot.state == .accessibilityRequired)
}

@Test func permissionSnapshotRequiresInputMonitoringAfterAccessibility() {
    let snapshot = PermissionSnapshot(
        accessibilityGranted: true,
        inputMonitoringGranted: false
    )

    #expect(snapshot.state == .inputMonitoringRequired)
}

@Test func permissionSnapshotIsReadyOnlyWhenBothPermissionsAreAvailable() {
    let snapshot = PermissionSnapshot(
        accessibilityGranted: true,
        inputMonitoringGranted: true
    )

    #expect(snapshot.state == .ready)
}

@Test func aRunningListenerDoesNotReplaceInputMonitoringAuthorization() {
    // Regression: macOS can create the event tap with Accessibility alone, but it
    // will not deliver real shortcuts until Input Monitoring is explicitly granted.
    let snapshot = PermissionController.snapshot(
        accessibilityGranted: true,
        inputMonitoringPreflightGranted: false,
        eventTapAvailable: true
    )

    #expect(!snapshot.inputMonitoringGranted)
    #expect(snapshot.state == .inputMonitoringRequired)
}
