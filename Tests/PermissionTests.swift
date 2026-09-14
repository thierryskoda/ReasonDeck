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

@MainActor
private func isolatedPermissionDefaults() -> UserDefaults {
    let suite = "PermissionTests.\(UUID().uuidString)"
    let defaults = UserDefaults(suiteName: suite)!
    defaults.removePersistentDomain(forName: suite)
    return defaults
}

@MainActor
private func readiness(
    defaults: UserDefaults,
    requirement: String?
) -> PermissionReadiness {
    PermissionReadiness(
        bundleURL: URL(fileURLWithPath: "/Applications/ReasonDeck.app"),
        signingIdentity: .stable,
        defaults: defaults,
        currentRequirement: requirement
    )
}

private let granted = PermissionSnapshot(accessibilityGranted: true, inputMonitoringGranted: true)
private let refused = PermissionSnapshot(accessibilityGranted: false, inputMonitoringGranted: false)

@Test func aGrantHeldRightNowIsNeverReportedStale() {
    #expect(!PrivacyGrantContinuity.looksStale(
        isGranted: true,
        currentRequirement: "identifier \"com.thierryai.ReasonDeck\"",
        requirementAtLastGrant: "cdhash H\"abc\""
    ))
}

@Test func aFirstRunWithNoRememberedGrantIsNotReportedStale() {
    // Nobody has allowed anything yet, so the honest advice is ordinary setup guidance,
    // not "delete the System Settings row".
    #expect(!PrivacyGrantContinuity.looksStale(
        isGranted: false,
        currentRequirement: "identifier \"com.thierryai.ReasonDeck\"",
        requirementAtLastGrant: nil
    ))
}

@Test func anUnreadableCurrentRequirementIsNotReportedStale() {
    #expect(!PrivacyGrantContinuity.looksStale(
        isGranted: false,
        currentRequirement: nil,
        requirementAtLastGrant: "identifier \"com.thierryai.ReasonDeck\""
    ))
}

@Test func anUnchangedRequirementIsNotReportedStale() {
    let requirement = "identifier \"com.thierryai.ReasonDeck\" and certificate leaf[subject.OU] = HMP675MR3A"

    #expect(!PrivacyGrantContinuity.looksStale(
        isGranted: false,
        currentRequirement: requirement,
        requirementAtLastGrant: requirement
    ))
}

@Test func aRequirementThatChangedSinceTheGrantIsReportedStale() {
    // Regression: the ad-hoc build the user allowed and the Developer ID build replacing it
    // are different apps to TCC, so System Settings keeps showing the old row switched on
    // while the running copy is denied.
    #expect(PrivacyGrantContinuity.looksStale(
        isGranted: false,
        currentRequirement: "identifier \"com.thierryai.ReasonDeck\" and certificate leaf[subject.OU] = HMP675MR3A",
        requirementAtLastGrant: "cdhash H\"7f3ce118bd6170557f152b5ec53b32256c150ace\""
    ))
}

@MainActor
@Test func aReplacedSignatureExplainsARefusedGrant() {
    let defaults = isolatedPermissionDefaults()

    // The user allows both grants against the build they are running.
    readiness(defaults: defaults, requirement: "cdhash H\"old\"").apply(granted)

    // A differently signed build then finds both refused.
    let updated = readiness(defaults: defaults, requirement: "anchor apple generic and identifier \"com.thierryai.ReasonDeck\"")
    updated.apply(refused)

    #expect(updated.staleGrants == Set(PrivacyService.allCases))
    for service in PrivacyService.allCases {
        #expect(updated.repairGuidance(for: service).hasPrefix("ReasonDeck's signature changed"))
    }
}

@MainActor
@Test func anUnchangedSignatureLeavesRefusedGrantsWithOrdinaryGuidance() {
    let defaults = isolatedPermissionDefaults()
    let requirement = "anchor apple generic and identifier \"com.thierryai.ReasonDeck\""

    readiness(defaults: defaults, requirement: requirement).apply(granted)

    let reopened = readiness(defaults: defaults, requirement: requirement)
    reopened.apply(refused)

    #expect(reopened.staleGrants.isEmpty)
    #expect(reopened.repairGuidance(for: .accessibility).hasPrefix("Already allowed in System Settings"))
}

@MainActor
@Test func eachGrantIsTrackedSeparately() {
    let defaults = isolatedPermissionDefaults()

    // Only Accessibility was ever allowed under the earlier signature.
    readiness(defaults: defaults, requirement: "cdhash H\"old\"")
        .apply(PermissionSnapshot(accessibilityGranted: true, inputMonitoringGranted: false))

    let updated = readiness(defaults: defaults, requirement: "anchor apple generic")
    updated.apply(refused)

    #expect(updated.staleGrants == [.accessibility])
    #expect(updated.repairGuidance(for: .inputMonitoring).hasPrefix("Already allowed in System Settings"))
}

@MainActor
@Test func everyRepairGuidanceNamesTheListAndTheRemoveStep() {
    // Re-toggling a stale row does not repair it; only removing the row does. Both wordings
    // must therefore end in the same remedy, naming the list exactly as System Settings does.
    let subject = readiness(defaults: isolatedPermissionDefaults(), requirement: "anchor apple generic")
    subject.apply(refused)

    for service in PrivacyService.allCases {
        let guidance = subject.repairGuidance(for: service)
        #expect(guidance.contains("Remove ReasonDeck from the \(service.displayName) list"))
    }
}

@Test func designatedRequirementIsUnreadableForAPathThatIsNotCode() {
    #expect(BuildRequirement.designated(URL(fileURLWithPath: "/nonexistent/ReasonDeck.app")) == nil)
}
