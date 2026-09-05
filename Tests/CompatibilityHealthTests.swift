import Testing
@testable import ReasonDeck

@MainActor
private final class CompatibilityInventoryStub {
    var items: [ApplicationTarget: CompatibilityInventoryItem]

    init(items: [ApplicationTarget: CompatibilityInventoryItem]) {
        self.items = items
    }
}

@Test func exactSignedLiveVersionsAreCertifiedWithoutAcceptingNearbyVersions() {
    #expect(CompatibilityPolicy.certification(for: .chatGPT, version: "26.803.61601") == .verified)
    #expect(CompatibilityPolicy.certification(for: .claudeCode, version: "1.40609.0") == .verified)
    #expect(CompatibilityPolicy.certification(for: .claudeCode, version: "1.46388.4") == .verified)
    #expect(CompatibilityPolicy.certification(for: .cursor, version: "3.15.6") == .verified)
    #expect(CompatibilityPolicy.certification(for: .cursor, version: "3.16.29") == .verified)
    #expect(CompatibilityPolicy.certification(for: .antigravity, version: "2.8.1") == .verified)

    #expect(CompatibilityPolicy.certification(for: .chatGPT, version: "26.803.61602") == .unverified)
    #expect(CompatibilityPolicy.certification(for: .claudeCode, version: "1.46388.5") == .unverified)
    #expect(CompatibilityPolicy.certification(for: .cursor, version: "3.16.30") == .unverified)
    #expect(CompatibilityPolicy.certification(for: .antigravity, version: "2.8.2") == .unverified)
}

@Test func statusSeparatesCertificationFromObservedRuntimeHealth() {
    let verified = CompatibilitySnapshot(
        target: .claudeCode,
        version: "1.46388.4",
        processIdentifier: 42,
        isInstalled: true,
        observation: nil
    )
    #expect(verified.status == .verified)

    let verifiedAndWorking = CompatibilitySnapshot(
        target: .claudeCode,
        version: "1.46388.4",
        processIdentifier: 42,
        isInstalled: true,
        observation: .working(version: "1.46388.4", processIdentifier: 42)
    )
    #expect(verifiedAndWorking.status == .verified)

    let unknown = CompatibilitySnapshot(
        target: .claudeCode,
        version: "1.46388.5",
        processIdentifier: 43,
        isInstalled: true,
        observation: nil
    )
    #expect(unknown.status == .unknown)

    let working = CompatibilitySnapshot(
        target: .claudeCode,
        version: "1.46388.5",
        processIdentifier: 43,
        isInstalled: true,
        observation: .working(version: "1.46388.5", processIdentifier: 43)
    )
    #expect(working.status == .workingUnverified)

    let needsUpdate = CompatibilitySnapshot(
        target: .claudeCode,
        version: "1.46388.5",
        processIdentifier: 43,
        isInstalled: true,
        observation: .needsUpdate(version: "1.46388.5", processIdentifier: 43)
    )
    #expect(needsUpdate.status == .needsUpdate)

    let staleObservation = CompatibilitySnapshot(
        target: .claudeCode,
        version: "1.46388.6",
        processIdentifier: 44,
        isInstalled: true,
        observation: .needsUpdate(version: "1.46388.5", processIdentifier: 43)
    )
    #expect(staleObservation.status == .unknown)

    let missing = CompatibilitySnapshot(
        target: .claudeCode,
        version: nil,
        processIdentifier: nil,
        isInstalled: false,
        observation: nil
    )
    #expect(missing.status == .notInstalled)
}

@Test func onlyPickerContractFailuresDegradeCompatibilityHealth() {
    let structural: [AttemptFailureCode] = [
        .cursorPickerDidNotOpen,
        .pickerNotFound,
        .modelRowNotActionable,
        .effortRowNotActionable,
        .deadlineExceeded,
        .verificationMismatch,
        .accessibilityError,
    ]
    for failure in structural {
        #expect(CompatibilityPolicy.isContractFailure(failure))
    }

    let contextual: [AttemptFailureCode] = [
        .busy,
        .capabilityGated,
        .installationRequired,
        .invalidConfiguration,
        .missingAssignment,
        .permissionMissing,
        .chatGPTNotFrontmost,
        .targetChanged,
        .noFocusedWindow,
        .claudeCodeSurfaceNotFound,
        .cursorModelControlUnavailable,
        .modelUnavailable,
        .effortUnavailable,
        .cursorMenuItemMissing,
        .cursorUnreadNavigationUnavailable,
        .cursorNoUnreadSessions,
        .cursorUnreadStateNotObservable,
    ]
    for failure in contextual {
        #expect(!CompatibilityPolicy.isContractFailure(failure))
    }
}

@Test func runtimeObservationRequiresTheSameExactProcessAndVersion() {
    let observation = CompatibilityObservation.working(version: "3.16.30", processIdentifier: 100)

    #expect(observation.applies(version: "3.16.30", processIdentifier: 100))
    #expect(!observation.applies(version: "3.16.31", processIdentifier: 100))
    #expect(!observation.applies(version: "3.16.30", processIdentifier: 101))
    #expect(!observation.applies(version: nil, processIdentifier: 100))
    #expect(!observation.applies(version: "3.16.30", processIdentifier: nil))
}

@MainActor
@Test func healthTracksOnlyContractResultsAndInvalidatesRelaunchedProcesses() {
    let inventory = CompatibilityInventoryStub(items: [
        .antigravity: CompatibilityInventoryItem(
            version: "2.8.2",
            processIdentifier: 200,
            isInstalled: true
        )
    ])
    let health = CompatibilityHealth { inventory.items }

    #expect(health.snapshots.first { $0.target == .antigravity }?.status == .unknown)

    health.recordFailure(.permissionMissing, for: .antigravity)
    #expect(health.snapshots.first { $0.target == .antigravity }?.status == .unknown)

    health.recordFailure(.pickerNotFound, for: .antigravity)
    #expect(health.snapshots.first { $0.target == .antigravity }?.status == .needsUpdate)

    health.recordWorking(for: .antigravity)
    #expect(health.snapshots.first { $0.target == .antigravity }?.status == .workingUnverified)

    inventory.items[.antigravity] = CompatibilityInventoryItem(
        version: "2.8.2",
        processIdentifier: 201,
        isInstalled: true
    )
    health.refresh()
    #expect(health.snapshots.first { $0.target == .antigravity }?.status == .unknown)
}
