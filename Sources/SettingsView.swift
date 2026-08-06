import AppKit
import SwiftUI

struct SettingsView: View {
    @Bindable var store: ProfileStore
    @Bindable var readiness: PermissionReadiness
    let onRetryHotkeys: () -> Void
    @State private var assignmentError: String?

    var body: some View {
        Form {
            Section("Setup") {
                VStack(spacing: 0) {
                    permissionRow(
                        title: "Accessibility",
                        isGranted: readiness.snapshot.accessibilityGranted
                    ) {
                        Button("Request Permission…") { readiness.requestAccessibility() }
                        Button("Open Settings…") { readiness.openAccessibilitySettings() }
                    }

                    Divider()
                        .padding(.vertical, 12)

                    permissionRow(
                        title: "Input Monitoring",
                        isGranted: readiness.snapshot.inputMonitoringGranted
                    ) {
                        Button("Request Permission…") { readiness.requestInputMonitoring() }
                        Button("Open Settings…") { readiness.openInputMonitoringSettings() }
                        Button("Retry Hotkeys") { onRetryHotkeys() }
                    }

                    Divider()
                        .padding(.vertical, 12)

                    Text("ChatGPT must be installed and frontmost when you use a shortcut. This app only inspects the active ChatGPT window.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }

            if store.isValid {
                if store.entries.isEmpty {
                    ContentUnavailableView {
                        Label("No Shortcuts", systemImage: "keyboard")
                    } description: {
                        Text("Add a shortcut, then choose its keyboard command, model, and reasoning effort.")
                    } actions: {
                        addShortcutButton
                    }
                    .frame(maxWidth: .infinity, minHeight: 260)
                } else {
                    ForEach(store.entries) { entry in
                        Section {
                            HStack(spacing: 12) {
                                LabeledContent("Keyboard shortcut") {
                                    ShortcutRecorder(shortcut: entry.shortcut) { shortcut in
                                        do {
                                            try store.setShortcut(shortcut, for: entry.id)
                                        } catch let error as ShortcutAssignmentError {
                                            assignmentError = error.message
                                        } catch {
                                            assignmentError = "The shortcut could not be saved."
                                        }
                                    }
                                    .frame(width: 150)
                                }

                                Button(role: .destructive) {
                                    store.deleteEntry(entry.id)
                                } label: {
                                    Image(systemName: "trash")
                                }
                                .buttonStyle(.borderless)
                                .help("Delete shortcut")
                                .accessibilityLabel("Delete shortcut")
                            }

                            Picker("Model", selection: modelBinding(for: entry.id)) {
                                ForEach(ChatGPTModel.allCases) { model in
                                    Text(model.rawValue).tag(model)
                                }
                            }

                            Picker("Reasoning", selection: effortBinding(for: entry.id)) {
                                ForEach(ReasoningEffort.allCases) { effort in
                                    Text(effort.rawValue).tag(effort)
                                }
                            }

                            Text("Use at least Command, Option, or Control. Click the shortcut again to replace it; press Delete while recording to clear it.")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }

                    HStack {
                        Spacer()
                        addShortcutButton
                        Spacer()
                    }
                }
            } else {
                ContentUnavailableView {
                    Label("Shortcuts Need Reset", systemImage: "exclamationmark.triangle")
                } description: {
                    Text(store.invalidReason ?? "Saved shortcuts are invalid.")
                } actions: {
                    Button("Reset to Empty") { store.reset() }
                }
                .frame(maxWidth: .infinity, minHeight: 260)
            }
        }
        .formStyle(.grouped)
        .frame(minWidth: 520, idealWidth: 560, minHeight: 440, idealHeight: 500)
        .navigationTitle("Shortcuts")
        .alert("Shortcut Unavailable", isPresented: Binding(
            get: { assignmentError != nil },
            set: { if !$0 { assignmentError = nil } }
        )) {
            Button("OK") { assignmentError = nil }
        } message: {
            Text(assignmentError ?? "")
        }
    }

    private var addShortcutButton: some View {
        Button {
            store.addEntry()
        } label: {
            Label("Add Shortcut", systemImage: "plus")
        }
    }

    @ViewBuilder
    private func permissionRow<Actions: View>(
        title: String,
        isGranted: Bool,
        @ViewBuilder actions: () -> Actions
    ) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 12) {
                Text(title)

                Spacer(minLength: 12)

                Label(
                    isGranted ? "Granted" : "Required",
                    systemImage: isGranted ? "checkmark.circle.fill" : "exclamationmark.circle"
                )
                .font(.callout)
                .foregroundStyle(isGranted ? .green : .secondary)
            }

            if !isGranted {
                HStack(spacing: 8) {
                    Spacer(minLength: 0)
                    actions()
                }
            }
        }
    }

    private func modelBinding(for id: UUID) -> Binding<ChatGPTModel> {
        Binding(
            get: { store.entry(id: id)?.selection.model ?? .sol56 },
            set: { store.setModel($0, for: id) }
        )
    }

    private func effortBinding(for id: UUID) -> Binding<ReasoningEffort> {
        Binding(
            get: { store.entry(id: id)?.selection.effort ?? .extraHigh },
            set: { store.setEffort($0, for: id) }
        )
    }
}

private struct ShortcutRecorder: NSViewRepresentable {
    let shortcut: KeyboardShortcut?
    let onChange: (KeyboardShortcut?) -> Void

    func makeNSView(context: Context) -> ShortcutRecorderButton {
        let button = ShortcutRecorderButton()
        button.onChange = onChange
        button.shortcut = shortcut
        return button
    }

    func updateNSView(_ button: ShortcutRecorderButton, context: Context) {
        button.onChange = onChange
        button.shortcut = shortcut
    }
}

private final class ShortcutRecorderButton: NSButton {
    var onChange: ((KeyboardShortcut?) -> Void)?
    var shortcut: KeyboardShortcut? { didSet { refreshTitle() } }
    private var isRecording = false { didSet { refreshTitle() } }

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        bezelStyle = .rounded
        target = self
        action = #selector(beginRecording)
        setAccessibilityLabel("Keyboard shortcut")
        toolTip = "Click, then type a keyboard shortcut"
    }

    required init?(coder: NSCoder) { nil }
    override var acceptsFirstResponder: Bool { true }

    @objc private func beginRecording() {
        isRecording = true
        window?.makeFirstResponder(self)
    }

    override func resignFirstResponder() -> Bool {
        isRecording = false
        return super.resignFirstResponder()
    }

    override func keyDown(with event: NSEvent) {
        guard isRecording else {
            super.keyDown(with: event)
            return
        }
        capture(event)
    }

    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        guard isRecording, event.type == .keyDown else {
            return super.performKeyEquivalent(with: event)
        }
        capture(event)
        return true
    }

    private func capture(_ event: NSEvent) {
        let modifiers = ShortcutModifiers(appKitFlags: event.modifierFlags)
        if event.keyCode == 53, modifiers.isEmpty {
            window?.makeFirstResponder(nil)
            return
        }
        if event.keyCode == 51, modifiers.isEmpty {
            onChange?(nil)
            window?.makeFirstResponder(nil)
            return
        }
        guard let label = Self.keyLabel(for: event),
              let shortcut = try? KeyboardShortcut(
                keyCode: event.keyCode,
                keyLabel: label,
                modifiers: modifiers
              ) else {
            NSSound.beep()
            return
        }
        onChange?(shortcut)
        window?.makeFirstResponder(nil)
    }

    private func refreshTitle() {
        title = isRecording ? "Type shortcut…" : (shortcut?.displayName ?? "Set Shortcut")
        setAccessibilityValue(shortcut?.displayName ?? "Not set")
    }

    private static func keyLabel(for event: NSEvent) -> String? {
        KeyboardKeyLabel.label(
            for: event.keyCode,
            fallback: event.characters(byApplyingModifiers: [])
        )
    }
}

private extension ShortcutModifiers {
    init(appKitFlags: NSEvent.ModifierFlags) {
        let flags = appKitFlags.intersection(.deviceIndependentFlagsMask)
        var value: ShortcutModifiers = []
        if flags.contains(.command) { value.insert(.command) }
        if flags.contains(.option) { value.insert(.option) }
        if flags.contains(.control) { value.insert(.control) }
        if flags.contains(.shift) { value.insert(.shift) }
        self = value
    }
}
