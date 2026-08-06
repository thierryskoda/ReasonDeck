import Foundation

protocol AccessibilityClient: Sendable {
    func currentPickerTitle() async throws -> String
    func selectModel(_ model: ChatGPTModel) async throws -> String
    func selectEffort(_ effort: ReasoningEffort) async throws -> String
}

actor ProfileSwitchCoordinator {
    private let client: any AccessibilityClient
    private(set) var isSwitching = false

    init(client: any AccessibilityClient) { self.client = client }

    func apply(_ profile: ProfileSelection) async -> ProfileSwitchResult {
        guard !isSwitching else { return .failure(profile: profile, failure: .accessibility("Another switch is already running.")) }
        isSwitching = true
        defer { isSwitching = false }
        let clock = ContinuousClock()
        let start = clock.now
        do {
            var title = try await client.currentPickerTitle()
            if profile.matches(title: title) {
                return .success(profile: profile, observedTitle: title, elapsed: start.duration(to: clock.now))
            }
            if !profile.title(title, containsModel: profile.model) {
                title = try await client.selectModel(profile.model)
                guard profile.title(title, containsModel: profile.model) else {
                    throw SwitchFailure.verificationMismatch(expected: profile.model.rawValue, observed: title)
                }
            }
            if !profile.title(title, containsEffort: profile.effort) {
                do {
                    title = try await client.selectEffort(profile.effort)
                } catch let failure as SwitchFailure {
                    title = (try? await client.currentPickerTitle()) ?? title
                    return .partialFailure(profile: profile, observedTitle: title, failure: failure)
                }
            }
            guard profile.matches(title: title) else {
                return .partialFailure(profile: profile, observedTitle: title, failure: .verificationMismatch(expected: profile.expectedTitle, observed: title))
            }
            return .success(profile: profile, observedTitle: title, elapsed: start.duration(to: clock.now))
        } catch let failure as SwitchFailure {
            return .failure(profile: profile, failure: failure)
        } catch {
            return .failure(profile: profile, failure: .accessibility(String(describing: error)))
        }
    }
}
