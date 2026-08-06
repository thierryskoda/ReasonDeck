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
