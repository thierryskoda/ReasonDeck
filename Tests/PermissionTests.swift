import Testing
@testable import ReasonDeck

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
