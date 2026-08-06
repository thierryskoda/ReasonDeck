import Foundation
import Observation

@MainActor
@Observable
final class ProfileStore {
    static let storageKey = "com.thierryai.ModelKey.shortcutConfiguration.v1"

    private(set) var configuration: ShortcutConfiguration?
    private(set) var invalidReason: String?
    @ObservationIgnored private let defaults: UserDefaults
    @ObservationIgnored var onChange: (@MainActor () -> Void)?

    var isValid: Bool { configuration != nil }
    var entries: [ShortcutEntry] { configuration?.entries ?? [] }

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        guard defaults.object(forKey: Self.storageKey) != nil else {
            configuration = .empty
            return
        }
        guard let data = defaults.data(forKey: Self.storageKey) else {
            invalidReason = "Saved shortcuts are invalid. Reset to empty to continue."
            return
        }
        do {
            configuration = try JSONDecoder().decode(ShortcutConfiguration.self, from: data)
        } catch {
            invalidReason = "Saved shortcuts are invalid. Reset to empty to continue."
        }
    }

    func entry(id: UUID) -> ShortcutEntry? {
        configuration?.entry(id: id)
    }

    @discardableResult
    func addEntry() -> UUID? {
        guard let configuration else { return nil }
        let addition = configuration.addingEntry(
            selection: ProfileSelection(model: .sol56, effort: .extraHigh)
        )
        save(addition.configuration)
        return addition.id
    }

    func deleteEntry(_ id: UUID) {
        guard let configuration else { return }
        save(configuration.deleting(id))
    }

    func setShortcut(_ shortcut: KeyboardShortcut?, for id: UUID) throws {
        guard let configuration, let current = configuration.entry(id: id) else { return }
        let updated = ShortcutEntry(id: id, shortcut: shortcut, selection: current.selection)
        do {
            save(try configuration.replacing(updated))
        } catch ShortcutConfiguration.ValidationError.duplicateShortcut {
            throw ShortcutAssignmentError.duplicate
        }
    }

    func setModel(_ model: ChatGPTModel, for id: UUID) {
        guard let configuration, let current = configuration.entry(id: id) else { return }
        save(configuration.replacingSelection(
            ProfileSelection(model: model, effort: current.selection.effort),
            for: id
        ))
    }

    func setEffort(_ effort: ReasoningEffort, for id: UUID) {
        guard let configuration, let current = configuration.entry(id: id) else { return }
        save(configuration.replacingSelection(
            ProfileSelection(model: current.selection.model, effort: effort),
            for: id
        ))
    }

    func reset() {
        save(.empty)
    }

    private func save(_ configuration: ShortcutConfiguration) {
        do {
            defaults.set(try JSONEncoder().encode(configuration), forKey: Self.storageKey)
            self.configuration = configuration
            invalidReason = nil
            onChange?()
        } catch {
            self.configuration = nil
            invalidReason = "Profiles could not be saved. Reset to continue."
            onChange?()
        }
    }
}
