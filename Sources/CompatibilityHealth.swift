import AppKit
import Foundation
import Observation

enum CompatibilityCertification: Equatable, Sendable {
    case verified
    case unverified
}

enum CompatibilityStatus: Equatable, Sendable {
    case verified
    case workingUnverified
    case unknown
    case needsUpdate
    case notInstalled

    var title: String {
        switch self {
        case .verified: "Verified"
        case .workingUnverified: "Working, unverified"
        case .unknown: "Unknown"
        case .needsUpdate: "Needs update"
        case .notInstalled: "Not installed"
        }
    }

    var systemImage: String {
        switch self {
        case .verified: "checkmark.seal.fill"
        case .workingUnverified: "checkmark.circle"
        case .unknown: "questionmark.circle"
        case .needsUpdate: "exclamationmark.triangle.fill"
        case .notInstalled: "minus.circle"
        }
    }
}

enum CompatibilityObservation: Equatable, Sendable {
    case working(version: String, processIdentifier: pid_t)
    case needsUpdate(version: String, processIdentifier: pid_t)

    func applies(version: String?, processIdentifier: pid_t?) -> Bool {
        guard let version, let processIdentifier else { return false }
        switch self {
        case .working(let observedVersion, let observedPID),
             .needsUpdate(let observedVersion, let observedPID):
            return version == observedVersion && processIdentifier == observedPID
        }
    }
}

struct CompatibilitySnapshot: Equatable, Identifiable, Sendable {
    let target: ApplicationTarget
    let version: String?
    let processIdentifier: pid_t?
    let isInstalled: Bool
    let observation: CompatibilityObservation?

    var id: ApplicationTarget { target }
    var isRunning: Bool { processIdentifier != nil }

    var status: CompatibilityStatus {
        guard isInstalled else { return .notInstalled }
        if let observation, observation.applies(version: version, processIdentifier: processIdentifier) {
            switch observation {
            case .needsUpdate: return .needsUpdate
            case .working: break
            }
        }
        if CompatibilityPolicy.certification(for: target, version: version) == .verified {
            return .verified
        }
        if case .working = observation,
           observation?.applies(version: version, processIdentifier: processIdentifier) == true {
            return .workingUnverified
        }
        return .unknown
    }

    var detail: String {
        guard isInstalled else { return "App not found" }
        let versionText = version.map { "Version \($0)" } ?? "Version unavailable"
        return isRunning ? "\(versionText) · Running" : "\(versionText) · Not running"
    }
}

enum CompatibilityPolicy {
    /// Only exact app versions with recorded signed live evidence are certified.
    /// Nearby patch versions remain unknown until their picker contract is exercised.
    private static let verifiedVersions: [ApplicationTarget: Set<String>] = [
        .claudeCode: ["1.40609.0", "1.46388.4"],
        .cursor: ["3.15.6", "3.16.29"],
    ]

    static func certification(for target: ApplicationTarget, version: String?) -> CompatibilityCertification {
        guard let version, verifiedVersions[target]?.contains(version) == true else {
            return .unverified
        }
        return .verified
    }

    static func isContractFailure(_ failure: AttemptFailureCode) -> Bool {
        switch failure {
        case .cursorPickerDidNotOpen,
             .pickerNotFound,
             .modelRowNotActionable,
             .effortRowNotActionable,
             .deadlineExceeded,
             .verificationMismatch,
             .accessibilityError:
            true
        case .busy,
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
             .cursorMenuItemMissing,
             .cursorUnreadNavigationUnavailable,
             .cursorNoUnreadSessions,
             .cursorUnreadStateNotObservable,
             .modelUnavailable,
             .effortUnavailable:
            false
        }
    }
}

struct CompatibilityInventoryItem: Equatable, Sendable {
    let version: String?
    let processIdentifier: pid_t?
    let isInstalled: Bool
}

@MainActor
@Observable
final class CompatibilityHealth {
    private(set) var snapshots: [CompatibilitySnapshot] = []
    @ObservationIgnored private var observations: [ApplicationTarget: CompatibilityObservation] = [:]
    @ObservationIgnored private let inspectApplications: @MainActor () -> [ApplicationTarget: CompatibilityInventoryItem]

    init(
        inspectApplications: @escaping @MainActor () -> [ApplicationTarget: CompatibilityInventoryItem] = {
            CompatibilityHealth.systemInventory()
        }
    ) {
        self.inspectApplications = inspectApplications
        refresh()
    }

    func refresh() {
        rebuild(from: inspectApplications())
    }

    func recordWorking(for target: ApplicationTarget) {
        let inventory = inspectApplications()
        guard let item = inventory[target],
              let version = item.version,
              let processIdentifier = item.processIdentifier
        else {
            rebuild(from: inventory)
            return
        }
        observations[target] = .working(version: version, processIdentifier: processIdentifier)
        rebuild(from: inventory)
    }

    func recordFailure(_ failure: AttemptFailureCode, for target: ApplicationTarget) {
        let inventory = inspectApplications()
        guard CompatibilityPolicy.isContractFailure(failure),
              let item = inventory[target],
              let version = item.version,
              let processIdentifier = item.processIdentifier
        else {
            rebuild(from: inventory)
            return
        }
        observations[target] = .needsUpdate(version: version, processIdentifier: processIdentifier)
        rebuild(from: inventory)
    }

    private func rebuild(from inventory: [ApplicationTarget: CompatibilityInventoryItem]) {
        snapshots = ApplicationTarget.allCases.map { target in
            let item = inventory[target] ?? CompatibilityInventoryItem(
                version: nil,
                processIdentifier: nil,
                isInstalled: false
            )
            let observation = observations[target]
            if let observation,
               !observation.applies(version: item.version, processIdentifier: item.processIdentifier) {
                observations[target] = nil
            }
            return CompatibilitySnapshot(
                target: target,
                version: item.version,
                processIdentifier: item.processIdentifier,
                isInstalled: item.isInstalled,
                observation: observations[target]
            )
        }
    }

    private static func systemInventory() -> [ApplicationTarget: CompatibilityInventoryItem] {
        Dictionary(uniqueKeysWithValues: ApplicationTarget.allCases.map { target in
            let running = NSRunningApplication.runningApplications(
                withBundleIdentifier: target.bundleIdentifier
            ).first(where: { !$0.isTerminated })
            let bundleURL = running?.bundleURL
                ?? NSWorkspace.shared.urlForApplication(withBundleIdentifier: target.bundleIdentifier)
            let bundle = bundleURL.flatMap(Bundle.init(url:))
            let version = bundle?.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String
                ?? bundle?.object(forInfoDictionaryKey: "CFBundleVersion") as? String
            return (target, CompatibilityInventoryItem(
                version: version,
                processIdentifier: running?.processIdentifier,
                isInstalled: bundleURL != nil
            ))
        })
    }
}
