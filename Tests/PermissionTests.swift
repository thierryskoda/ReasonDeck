import Foundation
import Security
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

@Test func adHocSignatureCannotKeepPrivacyGrants() {
    // Regression: an ad-hoc designated requirement is only a cdhash, so TCC treats every
    // rebuild as a new app and silently denies the toggled-on entry (issue #7).
    #expect(BuildSigningIdentity.classify(isSigned: true, flags: [.adhoc, .runtime]) == .adHoc)
}

@Test func identitySignedBuildKeepsPrivacyGrants() {
    #expect(BuildSigningIdentity.classify(isSigned: true, flags: [.runtime]) == .stable)
    #expect(BuildSigningIdentity.classify(isSigned: true, flags: []) == .stable)
}

@Test func unsignedBuildIsReportedBeforeAdHocFlags() {
    #expect(BuildSigningIdentity.classify(isSigned: false, flags: []) == .unsigned)
    #expect(BuildSigningIdentity.classify(isSigned: false, flags: [.adhoc]) == .unsigned)
}

@Test func onlyStableSigningHasNoAdvisory() {
    #expect(BuildSigningIdentity.stable.advisory == nil)
    #expect(BuildSigningIdentity.adHoc.advisory != nil)
    #expect(BuildSigningIdentity.unsigned.advisory != nil)
}

@Test func signingIdentityClassifiesTheRunningTestBundleWithoutCrashing() {
    // Whatever identity the test host has, classification must be deterministic and
    // must fall back to `.unsigned` for a path that is not a code bundle.
    let missing = URL(fileURLWithPath: "/nonexistent/ReasonDeck.app")
    #expect(BuildSigningIdentity.classify(missing) == .unsigned)
}
