import ServiceManagement
import SwiftUI

enum SettingsTab: String, Hashable {
    case general, shortcuts, ai, glossary, history
}

struct SettingsView: View {
    @Bindable var model: AppModel

    var body: some View {
        TabView(selection: $model.settingsTab) {
            GeneralTab(model: model)
                .tabItem { Label("General", systemImage: "gearshape") }
                .tag(SettingsTab.general)
            ShortcutsTab(model: model)
                .tabItem { Label("Shortcuts", systemImage: "keyboard") }
                .tag(SettingsTab.shortcuts)
            AITab(model: model)
                .tabItem { Label("AI", systemImage: "sparkles") }
                .tag(SettingsTab.ai)
            GlossaryTab(settings: model.settings)
                .tabItem { Label("Glossary", systemImage: "character.book.closed") }
                .tag(SettingsTab.glossary)
            HistoryTab(model: model)
                .tabItem { Label("History", systemImage: "clock.arrow.circlepath") }
                .tag(SettingsTab.history)
        }
        .frame(width: 620, height: 540)
        .onAppear { model.refreshPermissions() }
    }
}

private struct GeneralTab: View {
    let model: AppModel
    @State private var launchAtLogin = SMAppService.mainApp.status == .enabled

    var body: some View {
        @Bindable var settings = model.settings
        Form {
            Section {
                HStack(spacing: 14) {
                    AppBadge(size: 48)
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Voicer").font(.title2.weight(.semibold))
                        StatusChip(model: model)
                    }
                }
                .padding(.vertical, 4)
            }

            Section("Speech") {
                Picker("I speak", selection: $settings.language) {
                    ForEach(SpokenLanguage.allCases) { Text($0.title).tag($0) }
                }
                Picker("Speech model", selection: $settings.whisperModel) {
                    ForEach(WhisperModel.allCases) { Text($0.title).tag($0) }
                }
            }

            Section("Feedback") {
                Toggle("Play sounds when recording starts and stops", isOn: $settings.playSounds)
                Picker("Status pill position", selection: $settings.overlayPosition) {
                    Text("Bottom of screen").tag(OverlayPosition.bottom)
                    Text("Top of screen").tag(OverlayPosition.top)
                }
                Toggle("Keep result in clipboard after pasting", isOn: $settings.keepResultInClipboard)
            }

            Section("Permissions") {
                PermissionRow(title: "Microphone", granted: model.microphoneAuthorized) { model.requestMicrophone() }
                PermissionRow(title: "Accessibility", granted: model.accessibilityTrusted) { model.openAccessibilitySettings() }
            }

            Section {
                Toggle("Launch at login", isOn: $launchAtLogin)
                    .onChange(of: launchAtLogin) { _, enabled in
                        try? enabled ? SMAppService.mainApp.register() : SMAppService.mainApp.unregister()
                    }
            }
        }
        .formStyle(.grouped)
    }
}

private struct PermissionRow: View {
    let title: String
    let granted: Bool
    let action: () -> Void

    var body: some View {
        LabeledContent(title) {
            if granted {
                Label("Granted", systemImage: "checkmark.circle.fill")
                    .foregroundStyle(.green)
            } else {
                Button("Grant access", action: action)
            }
        }
    }
}

private struct ShortcutsTab: View {
    let model: AppModel

    var body: some View {
        @Bindable var settings = model.settings
        Form {
            Section {
                LabeledContent("Keys Voicer sees now") {
                    if model.heldModifiers.isEmpty {
                        Text(model.accessibilityTrusted ? "Press any modifier to test" : "Nothing, Accessibility is off")
                            .foregroundStyle(model.accessibilityTrusted ? Color.primary : Color.red)
                    } else {
                        KeyCaps(shortcut: Shortcut(modifiers: model.heldModifiers, keyCode: nil, keyLabel: nil, sideSpecific: true))
                    }
                }
            }
            Section {
                ForEach(OutputMode.allCases) { mode in
                    ShortcutRow(model: model, mode: mode)
                }
            } header: {
                Text("Shortcuts")
            } footer: {
                Text("Click a field, then press the keys. You can use modifiers alone (⌃⌥, Right ⌥, fn) or a combination with a key (⌥Space, ⌃⇧D). Esc cancels recording.")
                    .foregroundStyle(.secondary)
            }

            Section {
                Picker("Behavior", selection: $settings.triggerBehavior) {
                    ForEach(TriggerBehavior.allCases) { Text($0.title).tag($0) }
                }
                .pickerStyle(.radioGroup)
                Text(settings.triggerBehavior.explanation)
                    .font(.callout)
                    .foregroundStyle(.secondary)
            } header: {
                Text("How the shortcut works")
            } footer: {
                Text("While recording hands-free, press Esc to cancel. If you use fn, set System Settings › Keyboard › \"Press 🌐 key to\" to \"Do Nothing\".")
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
    }
}

private struct ShortcutRow: View {
    let model: AppModel
    let mode: OutputMode

    var body: some View {
        let settings = model.settings
        let binding = Binding<Shortcut?>(
            get: { settings.shortcuts[mode] },
            set: { newValue in
                var all = settings.shortcuts
                if let newValue {
                    for (other, shortcut) in all where other != mode && shortcut == newValue {
                        all[other] = nil
                    }
                }
                all[mode] = newValue
                settings.shortcuts = all
            }
        )
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: mode.symbol)
                .font(.system(size: 16, weight: .medium))
                .foregroundStyle(Color.accentColor)
                .frame(width: 24, height: 30)
            VStack(alignment: .leading, spacing: 3) {
                Text(mode.title).font(.system(size: 13, weight: .medium))
                Text(mode.subtitle).font(.callout).foregroundStyle(.secondary)
                if let shortcut = binding.wrappedValue, shortcut.isModifierOnly, shortcut.modifiers.count > 1, shortcut.hasSides {
                    Toggle("Match exact left/right keys", isOn: Binding(
                        get: { shortcut.sideSpecific },
                        set: { binding.wrappedValue?.sideSpecific = $0 }
                    ))
                    .toggleStyle(.checkbox)
                    .font(.callout)
                    .padding(.top, 2)
                }
            }
            Spacer()
            ShortcutRecorder(shortcut: binding, model: model)
        }
        .padding(.vertical, 4)
    }
}

private struct AITab: View {
    let model: AppModel
    @State private var testState = TestState.idle

    enum TestState: Equatable {
        case idle, running
        case success(String)
        case failure(String)
    }

    var body: some View {
        @Bindable var settings = model.settings
        let provider = settings.provider
        let accounts = provider.accounts()
        Form {
            Section {
                HStack(spacing: 12) {
                    ForEach(AIProvider.allCases) { option in
                        ProviderCard(
                            provider: option,
                            installed: model.executables[option] != nil,
                            selected: option == provider
                        ) {
                            settings.provider = option
                            testState = .idle
                        }
                    }
                }
                .padding(.vertical, 4)
            } header: {
                Text("AI provider")
            } footer: {
                Text("Voicer uses the command line tool you already have, signed in with your own subscription. No API keys. Only the transcript text is sent, never audio.")
                    .foregroundStyle(.secondary)
            }

            Section {
                if model.executables[provider] == nil {
                    Label(provider.installHint, systemImage: "exclamationmark.triangle.fill")
                        .foregroundStyle(.orange)
                } else if accounts.isEmpty {
                    Label("No login found. Run the CLI once in Terminal and sign in.", systemImage: "person.crop.circle.badge.exclamationmark")
                        .foregroundStyle(.orange)
                } else {
                    ForEach(accounts) { account in
                        AccountRow(
                            account: account,
                            selected: account.directory == (provider == .claude ? settings.claudeAccount : settings.codexAccount)
                        ) {
                            if provider == .claude {
                                settings.claudeAccount = account.directory
                            } else {
                                settings.codexAccount = account.directory
                            }
                            testState = .idle
                        }
                    }
                }
            } header: {
                Text("Account")
            }

            Section("Model") {
                if provider == .claude {
                    Picker("Model", selection: $settings.claudeModel) {
                        Text("Claude Sonnet 5.5").tag("claude-sonnet-5-5")
                        Text("Claude Opus 5.5").tag("claude-opus-5-5")
                        Text("Claude Haiku 4.5").tag("claude-haiku-4-5")
                    }
                    Picker("Effort", selection: $settings.claudeEffort) {
                        ForEach(provider.efforts) { Text($0.title).tag($0) }
                    }
                    .pickerStyle(.segmented)
                } else {
                    TextField("Model", text: $settings.codexModel, prompt: Text("Codex default"))
                    Picker("Effort", selection: $settings.codexEffort) {
                        ForEach(provider.efforts) { Text($0.title).tag($0) }
                    }
                    .pickerStyle(.segmented)
                }
            }

            Section {
                HStack(spacing: 10) {
                    Button("Test connection") { runTest() }
                        .disabled(model.executables[provider] == nil || testState == .running)
                    switch testState {
                    case .idle:
                        EmptyView()
                    case .running:
                        ProgressView().controlSize(.small)
                        Text("Asking \(provider.title)…").foregroundStyle(.secondary)
                    case .success:
                        Label("Working", systemImage: "checkmark.circle.fill").foregroundStyle(.green)
                    case .failure(let message):
                        Label(message, systemImage: "xmark.octagon.fill")
                            .foregroundStyle(.red)
                            .lineLimit(3)
                    }
                }
                if case .success(let reply) = testState {
                    Text("\(provider.title) answered: \(reply)")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .formStyle(.grouped)
    }

    private func runTest() {
        testState = .running
        Task {
            switch await model.testProvider() {
            case .success(let reply): testState = .success(reply)
            case .failure(let error): testState = .failure(error.localizedDescription)
            }
        }
    }
}

private struct ProviderCard: View {
    let provider: AIProvider
    let installed: Bool
    let selected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 12) {
                Image(systemName: provider.symbol)
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(selected ? Color.white : Color.accentColor)
                    .frame(width: 36, height: 36)
                    .background(
                        RoundedRectangle(cornerRadius: 9, style: .continuous)
                            .fill(selected ? Color.accentColor : Color.accentColor.opacity(0.14))
                    )
                VStack(alignment: .leading, spacing: 2) {
                    Text(provider.title).font(.system(size: 14, weight: .semibold))
                    Label(installed ? "\(provider.cliName) installed" : "Not installed",
                          systemImage: installed ? "checkmark.circle.fill" : "exclamationmark.circle.fill")
                        .font(.system(size: 11.5, weight: .medium))
                        .foregroundStyle(installed ? Color.green : Color.orange)
                }
                Spacer(minLength: 0)
                Image(systemName: selected ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 16))
                    .foregroundStyle(selected ? Color.accentColor : Color.secondary)
            }
            .padding(12)
            .frame(maxWidth: .infinity)
            .background(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(selected ? Color.accentColor.opacity(0.08) : Color(nsColor: .controlBackgroundColor))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .strokeBorder(selected ? Color.accentColor : Color(nsColor: .separatorColor), lineWidth: selected ? 2 : 1)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

private struct AccountRow: View {
    let account: CLIAccount
    let selected: Bool
    let action: () -> Void
    @State private var isHovered = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 12) {
                Text(String(account.name.prefix(1)))
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(.white)
                    .frame(width: 30, height: 30)
                    .background(Circle().fill(Color.accentColor))
                VStack(alignment: .leading, spacing: 1) {
                    Text(account.name).font(.system(size: 13, weight: .semibold))
                    Text(account.email ?? "Signed in")
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                }
                Spacer()
                if selected {
                    Image(systemName: "checkmark")
                        .font(.system(size: 13, weight: .bold))
                        .foregroundStyle(Color.accentColor)
                }
            }
            .padding(.vertical, 4)
            .padding(.horizontal, 6)
            .background(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(isHovered && !selected ? Color.accentColor.opacity(0.08) : Color.clear)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { isHovered = $0 }
    }
}

private struct GlossaryTab: View {
    @Bindable var settings: AppSettings

    var body: some View {
        Form {
            Section {
                TextEditor(text: $settings.glossary)
                    .font(.system(size: 13, design: .monospaced))
                    .frame(minHeight: 260)
                    .scrollContentBackground(.hidden)
            } header: {
                Text("Terms to spell exactly")
            } footer: {
                Text("One per line or comma-separated: names, products, project jargon. Whisper gets them as a hint, so it writes \"Kubernetes\" instead of \"куберниц\", and Claude keeps the spelling.")
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
    }
}

private struct HistoryTab: View {
    let model: AppModel
    @State private var showTranscript: UUID?

    var body: some View {
        VStack(spacing: 0) {
            if model.history.isEmpty {
                ContentUnavailableView("No dictations yet", systemImage: "waveform", description: Text("Hold your shortcut and start talking."))
            } else {
                List {
                    ForEach(model.history) { entry in
                        VStack(alignment: .leading, spacing: 6) {
                            HStack {
                                Text(entry.date, format: .dateTime.day().month().hour().minute())
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                Spacer()
                                Button(showTranscript == entry.id ? "Hide original" : "Show original") {
                                    showTranscript = showTranscript == entry.id ? nil : entry.id
                                }
                                .buttonStyle(.link)
                                .font(.caption)
                                Button("Copy") { model.copyToClipboard(entry.result) }
                                    .buttonStyle(.link)
                                    .font(.caption)
                                Button("Delete") { model.deleteHistory(entry) }
                                    .buttonStyle(.link)
                                    .font(.caption)
                            }
                            Text(entry.result)
                                .textSelection(.enabled)
                            if showTranscript == entry.id {
                                Text(entry.transcript)
                                    .font(.callout)
                                    .foregroundStyle(.secondary)
                                    .textSelection(.enabled)
                                    .padding(8)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                    .background(RoundedRectangle(cornerRadius: 6).fill(Color(nsColor: .controlBackgroundColor)))
                            }
                        }
                        .padding(.vertical, 4)
                    }
                }
                HStack {
                    Text("\(model.history.count) dictations")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Spacer()
                    Button("Clear history", role: .destructive) { model.clearHistory() }
                }
                .padding(12)
            }
        }
    }
}
