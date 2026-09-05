import AppKit
import SwiftUI

struct SettingsView: View {
    @Bindable var store: ProfileStore
    @Bindable var readiness: PermissionReadiness
    @Bindable var compatibilityHealth: CompatibilityHealth
    let beginShortcutRecording: (@escaping @MainActor @Sendable (ShortcutRecordingResult) -> Void) -> Bool
    let cancelShortcutRecording: () -> Void
    @State private var assignmentError: String?
    @State private var selectedTab: ShortcutSettingsTab = .modelSwitching
    @State private var showsPermissionDetails = false

    var body: some View {
        Form {
            readinessSection
            compatibilitySection

            if store.isValid {
                Picker("Shortcut type", selection: $selectedTab) {
                    ForEach(ShortcutSettingsTab.allCases) { tab in
                        Text(tab.displayName).tag(tab)
                    }
                }
                .pickerStyle(.segmented)
                .labelsHidden()

                switch selectedTab {
                case .modelSwitching:
                    modelShortcutLibrary
                case .nextFinishedSession:
                    finishedSessionLibrary
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
        .frame(minWidth: 620, idealWidth: 700, minHeight: 480, idealHeight: 620)
        .navigationTitle("Shortcuts")
        .task(id: store.isValid) {
            _ = store.ensureNavigationEntry()
        }
        .alert("Shortcut Unavailable", isPresented: Binding(
            get: { assignmentError != nil },
            set: { if !$0 { assignmentError = nil } }
        )) {
            Button("OK") { assignmentError = nil }
        } message: {
            Text(assignmentError ?? "")
        }
        .alert("Installation Unavailable", isPresented: Binding(
            get: { readiness.installationError != nil },
            set: { if !$0 { readiness.clearInstallationError() } }
        )) {
            Button("OK") { readiness.clearInstallationError() }
        } message: {
            Text(readiness.installationError ?? "")
        }
    }

    @ViewBuilder
    private var readinessSection: some View {
        if readiness.installLocation == .installed {
            Section {
                if permissionsAreReady {
                    HStack(spacing: 12) {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundStyle(.green)
                        Text("ReasonDeck is ready")

                        Spacer(minLength: 12)

                        Button(showsPermissionDetails ? "Hide Permissions" : "Manage Permissions…") {
                            showsPermissionDetails.toggle()
                        }
                    }

                    if showsPermissionDetails {
                        Divider()
                        permissionDetails
                    }
                } else {
                    permissionDetails
                }
            }
        } else {
            Section("Install ReasonDeck") {
                installationGuidance
            }
        }
    }

    private var permissionsAreReady: Bool {
        readiness.snapshot.accessibilityGranted && readiness.snapshot.inputMonitoringGranted
    }

    private var compatibilitySection: some View {
        Section {
            ForEach(compatibilityHealth.snapshots) { snapshot in
                HStack(spacing: 12) {
                    Label(snapshot.target.displayName, systemImage: snapshot.target.systemImage)

                    Spacer(minLength: 12)

                    VStack(alignment: .trailing, spacing: 2) {
                        Label(snapshot.status.title, systemImage: snapshot.status.systemImage)
                            .foregroundStyle(compatibilityColor(snapshot.status))
                        Text(snapshot.detail)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                .accessibilityIdentifier("compatibility-\(snapshot.target.rawValue)")
            }

            HStack(alignment: .firstTextBaseline, spacing: 12) {
                Text("Verified means that exact app version passed a signed live check. Unknown versions still use strict picker checks and stop instead of guessing when the UI changed.")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                Spacer(minLength: 12)

                Button("Refresh") { compatibilityHealth.refresh() }
            }
        } header: {
            Text("App Compatibility")
        }
    }

    private func compatibilityColor(_ status: CompatibilityStatus) -> Color {
        switch status {
        case .verified: .green
        case .workingUnverified: .blue
        case .needsUpdate: .orange
        case .unknown, .notInstalled: .secondary
        }
    }

    private var permissionDetails: some View {
        VStack(spacing: 0) {
            permissionRow(
                title: "Accessibility",
                isGranted: readiness.snapshot.accessibilityGranted
            ) {
                Button("Allow Accessibility…") { readiness.requestAccessibility() }
            }

            Divider()
                .padding(.vertical, 12)

            permissionRow(
                title: "Input Monitoring",
                isGranted: readiness.snapshot.inputMonitoringGranted
            ) {
                Button("Allow Input Monitoring…") { readiness.requestInputMonitoring() }
            }

            Divider()
                .padding(.vertical, 12)

            Text("macOS will open System Settings. Turn on ReasonDeck, then return here. Permissions are checked again automatically.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    @ViewBuilder
    private var modelShortcutLibrary: some View {
        if store.modelEntries.isEmpty {
            ContentUnavailableView {
                Label("No Model Shortcuts", systemImage: "keyboard")
            } description: {
                Text("Add a shortcut, then choose what it should select in each app.")
            } actions: {
                addShortcutButton
            }
            .frame(maxWidth: .infinity, minHeight: 240)
        } else {
            ForEach(store.modelEntries) { entry in
                modelShortcutSection(entry)
            }

            Section {
                HStack {
                    addShortcutButton
                    Spacer()
                }
            }
        }
    }

    @ViewBuilder
    private var finishedSessionLibrary: some View {
        if let entry = store.navigationEntries.first {
            Section {
                VStack(alignment: .leading, spacing: 10) {
                    HStack(spacing: 12) {
                        Label("Next finished session", systemImage: "checkmark.message")
                            .font(.headline)

                        Spacer(minLength: 12)

                        shortcutRecorder(for: entry)
                            .frame(width: 132)
                    }

                    Text("Open the next finished session waiting for a reply.")
                        .font(.callout)
                        .foregroundStyle(.secondary)

                    if !RuntimeCapabilities.supportsCursorNavigation() {
                        Label("Not available in this build", systemImage: "exclamationmark.circle")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }
        } else {
            ProgressView()
                .frame(maxWidth: .infinity, minHeight: 120)
        }
    }

    private func modelShortcutSection(_ entry: ShortcutEntry) -> some View {
        Section {
            VStack(alignment: .leading, spacing: 0) {
                shortcutHeader(entry)
                    .padding(.bottom, 12)
                Divider()

                modelTargetEditor(entry)
                    .padding(.vertical, 12)

                Divider()

                Text("Runs only when an enabled app is frontmost. Use Command, Option, or Control in every shortcut.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .padding(.top, 10)
            }
        }
    }

    private func shortcutHeader(_ entry: ShortcutEntry) -> some View {
        HStack(spacing: 12) {
            shortcutRecorder(for: entry)
                .frame(width: 132)

            Spacer(minLength: 12)

            Button(role: .destructive) {
                store.deleteEntry(entry.id)
            } label: {
                Image(systemName: "trash")
            }
            .buttonStyle(.borderless)
            .help("Delete \(entry.shortcut?.displayName ?? "unassigned") shortcut")
            .accessibilityLabel("Delete \(entry.shortcut?.displayName ?? "unassigned") shortcut")
        }
    }

    private func shortcutRecorder(for entry: ShortcutEntry) -> some View {
        ShortcutRecorder(
            shortcut: entry.shortcut,
            beginRecording: beginShortcutRecording,
            cancelRecording: cancelShortcutRecording,
            onRecordingUnavailable: {
                assignmentError = "Enable Input Monitoring before recording a shortcut."
            }
        ) { shortcut in
            do {
                try store.setShortcut(shortcut, for: entry.id)
            } catch let error as ShortcutAssignmentError {
                assignmentError = error.message
            } catch {
                assignmentError = "The shortcut could not be saved."
            }
        }
    }

    private func modelTargetEditor(_ entry: ShortcutEntry) -> some View {
        Grid(alignment: .leading, horizontalSpacing: 16, verticalSpacing: 10) {
            GridRow {
                Text("Application")
                Text("Enabled")
                Text("Model")
                Text("Effort")
            }
            .font(.caption)
            .foregroundStyle(.secondary)

            Divider()
                .gridCellColumns(4)

            ForEach(ApplicationTarget.allCases) { target in
                GridRow {
                    Label(target.displayName, systemImage: target.systemImage)
                        .frame(minWidth: 120, alignment: .leading)

                    Toggle(
                        "Enable \(target.displayName)",
                        isOn: targetBinding(target, for: entry.id)
                    )
                    .labelsHidden()
                    .disabled(!RuntimeCapabilities.supports(target))

                    if !RuntimeCapabilities.supports(target) {
                        Text("Unavailable")
                            .foregroundStyle(.secondary)
                            .gridCellColumns(2)
                    } else if entry.enabledTargets.contains(target) {
                        modelPicker(for: target, entryID: entry.id)
                        effortPicker(for: target, entryID: entry.id)
                    } else {
                        Text("—")
                            .foregroundStyle(.tertiary)
                        Text("—")
                            .foregroundStyle(.tertiary)
                    }
                }
            }
        }
    }

    @ViewBuilder
    private func modelPicker(for target: ApplicationTarget, entryID: UUID) -> some View {
        switch target {
        case .chatGPT:
            Picker("ChatGPT model", selection: chatGPTModelBinding(for: entryID)) {
                ForEach(ChatGPTModel.allCases) { model in Text(model.rawValue).tag(model) }
            }
            .labelsHidden()
            .frame(minWidth: 130)
        case .claudeCode:
            Picker("Claude Desktop model", selection: claudeCodeModelBinding(for: entryID)) {
                ForEach(ClaudeCodeModel.allCases) { model in Text(model.rawValue).tag(model) }
            }
            .labelsHidden()
            .frame(minWidth: 130)
        case .cursor:
            Picker("Cursor model", selection: cursorModelBinding(for: entryID)) {
                ForEach(CursorModel.allCases) { model in Text(model.rawValue).tag(model) }
            }
            .labelsHidden()
            .frame(minWidth: 130)
        case .antigravity:
            Picker("Antigravity model", selection: antigravityModelBinding(for: entryID)) {
                ForEach(AntigravityModel.allCases) { model in Text(model.rawValue).tag(model) }
            }
            .labelsHidden()
            .frame(minWidth: 130)
        }
    }

    @ViewBuilder
    private func effortPicker(for target: ApplicationTarget, entryID: UUID) -> some View {
        switch target {
        case .chatGPT:
            Picker("ChatGPT reasoning", selection: chatGPTEffortBinding(for: entryID)) {
                ForEach(ChatGPTReasoningEffort.allCases) { effort in Text(effort.rawValue).tag(effort) }
            }
            .labelsHidden()
            .frame(minWidth: 110)
        case .claudeCode:
            Picker("Claude Desktop effort", selection: claudeCodeEffortBinding(for: entryID)) {
                ForEach(ClaudeCodeEffort.allCases) { effort in Text(effort.rawValue).tag(effort) }
            }
            .labelsHidden()
            .frame(minWidth: 110)
        case .cursor:
            Picker("Cursor effort", selection: cursorEffortBinding(for: entryID)) {
                ForEach(CursorEffort.allCases) { effort in Text(effort.rawValue).tag(effort) }
            }
            .labelsHidden()
            .frame(minWidth: 110)
        case .antigravity:
            Picker("Antigravity effort", selection: antigravityEffortBinding(for: entryID)) {
                ForEach(AntigravityEffort.allCases) { effort in Text(effort.rawValue).tag(effort) }
            }
            .labelsHidden()
            .frame(minWidth: 110)
        }
    }

    @ViewBuilder
    private var installationGuidance: some View {
        VStack(alignment: .leading, spacing: 12) {
            switch readiness.installLocation {
            case .requiresInstallation:
                Label("Install before granting permissions", systemImage: "app.badge.checkmark")
                    .font(.headline)

                Text("macOS attaches privacy permissions to a specific installed app. Install this copy in Applications first so those permissions remain stable after relaunching.")
                    .foregroundStyle(.secondary)

                HStack {
                    Spacer()
                    Button("Install in Applications") {
                        readiness.installInApplications()
                    }
                    .disabled(readiness.isInstalling)

                    if readiness.isInstalling {
                        ProgressView()
                            .controlSize(.small)
                    }
                }

            case .unsupportedBuild:
                Label("Open the signed app build", systemImage: "hammer")
                    .font(.headline)

                Text("This executable is not inside a macOS app bundle, so it cannot keep a stable privacy identity. Build and open ReasonDeck.app before testing permissions.")
                    .foregroundStyle(.secondary)

            case .installed:
                EmptyView()
            }
        }
        .padding(.vertical, 4)
    }

    private var addShortcutButton: some View {
        Button {
            _ = store.addEntry()
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

    private func targetBinding(_ target: ApplicationTarget, for id: UUID) -> Binding<Bool> {
        Binding(
            get: { store.entry(id: id)?.enabledTargets.contains(target) ?? false },
            set: { isEnabled in
                do {
                    try store.setTarget(target, enabled: isEnabled, for: id)
                } catch let error as ShortcutAssignmentError {
                    assignmentError = error.message
                } catch {
                    assignmentError = "The target could not be updated."
                }
            }
        )
    }

    private func chatGPTModelBinding(for id: UUID) -> Binding<ChatGPTModel> {
        Binding(
            get: { store.entry(id: id)?.chatGPT?.model ?? .sol56 },
            set: { store.setChatGPTModel($0, for: id) }
        )
    }

    private func chatGPTEffortBinding(for id: UUID) -> Binding<ChatGPTReasoningEffort> {
        Binding(
            get: { store.entry(id: id)?.chatGPT?.effort ?? .extraHigh },
            set: { store.setChatGPTEffort($0, for: id) }
        )
    }

    private func claudeCodeModelBinding(for id: UUID) -> Binding<ClaudeCodeModel> {
        Binding(
            get: { store.entry(id: id)?.claudeCode?.model ?? .sonnet5 },
            set: { store.setClaudeCodeModel($0, for: id) }
        )
    }

    private func claudeCodeEffortBinding(for id: UUID) -> Binding<ClaudeCodeEffort> {
        Binding(
            get: { store.entry(id: id)?.claudeCode?.effort ?? .medium },
            set: { store.setClaudeCodeEffort($0, for: id) }
        )
    }

    private func cursorModelBinding(for id: UUID) -> Binding<CursorModel> {
        Binding(
            get: { store.entry(id: id)?.cursor?.model ?? .automatic },
            set: { store.setCursorModel($0, for: id) }
        )
    }

    private func cursorEffortBinding(for id: UUID) -> Binding<CursorEffort> {
        Binding(
            get: { store.entry(id: id)?.cursor?.effort ?? .high },
            set: { store.setCursorEffort($0, for: id) }
        )
    }

    private func antigravityModelBinding(for id: UUID) -> Binding<AntigravityModel> {
        Binding(
            get: { store.entry(id: id)?.antigravity?.model ?? .gemini31Pro },
            set: { store.setAntigravityModel($0, for: id) }
        )
    }

    private func antigravityEffortBinding(for id: UUID) -> Binding<AntigravityEffort> {
        Binding(
            get: { store.entry(id: id)?.antigravity?.effort ?? .medium },
            set: { store.setAntigravityEffort($0, for: id) }
        )
    }
}

private enum ShortcutSettingsTab: String, CaseIterable, Identifiable {
    case modelSwitching
    case nextFinishedSession

    var id: Self { self }

    var displayName: String {
        switch self {
        case .modelSwitching: "Model switching"
        case .nextFinishedSession: "Next finished session"
        }
    }
}

private struct ShortcutRecorder: NSViewRepresentable {
    let shortcut: KeyboardShortcut?
    let beginRecording: (@escaping @MainActor @Sendable (ShortcutRecordingResult) -> Void) -> Bool
    let cancelRecording: () -> Void
    let onRecordingUnavailable: () -> Void
    let onChange: (KeyboardShortcut?) -> Void

    func makeNSView(context: Context) -> ShortcutRecorderButton {
        let button = ShortcutRecorderButton()
        button.startRecording = beginRecording
        button.cancelRecording = cancelRecording
        button.onRecordingUnavailable = onRecordingUnavailable
        button.onChange = onChange
        button.shortcut = shortcut
        return button
    }

    func updateNSView(_ button: ShortcutRecorderButton, context: Context) {
        button.startRecording = beginRecording
        button.cancelRecording = cancelRecording
        button.onRecordingUnavailable = onRecordingUnavailable
        button.onChange = onChange
        button.shortcut = shortcut
    }
}

@MainActor
private final class ShortcutRecorderButton: NSButton {
    var startRecording: ((@escaping @MainActor @Sendable (ShortcutRecordingResult) -> Void) -> Bool)?
    var cancelRecording: (() -> Void)?
    var onRecordingUnavailable: (() -> Void)?
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
        guard startRecording?({ [weak self] result in self?.capture(result) }) == true else {
            isRecording = false
            onRecordingUnavailable?()
            return
        }
    }

    override func resignFirstResponder() -> Bool {
        if isRecording { cancelRecording?() }
        isRecording = false
        return super.resignFirstResponder()
    }

    private func capture(_ result: ShortcutRecordingResult) {
        switch result {
        case .captured(let shortcut): onChange?(shortcut)
        case .cleared: onChange?(nil)
        case .cancelled: break
        case .rejected:
            NSSound.beep()
            return
        }
        window?.makeFirstResponder(nil)
    }

    private func refreshTitle() {
        title = isRecording ? "Type shortcut…" : (shortcut?.displayName ?? "Set Shortcut")
        setAccessibilityValue(shortcut?.displayName ?? "Not set")
    }
}
