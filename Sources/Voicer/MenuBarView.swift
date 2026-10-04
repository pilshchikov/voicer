import SwiftUI

struct MenuBarView: View {
    let model: AppModel
    @Environment(\.openSettings) private var openSettings
    @State private var copiedID: UUID?

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            header
            if model.needsSetup { setupCard }
            modes
            if let last = model.history.first { lastResult(last) }
            if model.history.count > 1 { recent }
            Divider()
            footer
        }
        .padding(16)
        .frame(width: 350)
        .onAppear { model.refreshPermissions() }
    }

    private var header: some View {
        HStack(spacing: 12) {
            AppBadge(size: 38)
            VStack(alignment: .leading, spacing: 3) {
                Text("Voicer").font(.system(size: 15, weight: .semibold))
                StatusChip(model: model)
            }
            Spacer()
            Button {
                showSettings(.general)
            } label: {
                Image(systemName: "gearshape.fill")
                    .font(.system(size: 14))
                    .foregroundStyle(.primary)
                    .frame(width: 28, height: 28)
                    .background(Circle().fill(Color(nsColor: .controlBackgroundColor)))
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Settings")
        }
    }

    private var setupCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label("Finish setup", systemImage: "exclamationmark.circle.fill")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(.orange)
            if !model.microphoneAuthorized {
                SetupRow(title: "Microphone access", button: "Allow") { model.requestMicrophone() }
            }
            if !model.accessibilityTrusted {
                SetupRow(title: "Accessibility access", button: "Open Settings") { model.openAccessibilitySettings() }
            }
            if model.executables[model.settings.provider] == nil {
                SetupRow(title: "\(model.settings.provider.cliName) not found", button: "Details") { showSettings(.ai) }
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(Color.orange.opacity(0.12)))
    }

    private var modes: some View {
        VStack(alignment: .leading, spacing: 6) {
            SectionTitle("Dictate")
            ForEach(OutputMode.allCases) { mode in
                HStack(spacing: 10) {
                    Image(systemName: mode.symbol)
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(Color.accentColor)
                        .frame(width: 20)
                    Text(mode.title).font(.system(size: 13))
                    Spacer()
                    if let shortcut = model.settings.shortcuts[mode] {
                        KeyCaps(shortcut: shortcut)
                    } else {
                        Button("Set shortcut") { showSettings(.shortcuts) }
                            .buttonStyle(.link)
                            .font(.system(size: 12))
                    }
                }
                .padding(.vertical, 4)
            }
        }
    }

    private func lastResult(_ entry: HistoryEntry) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                SectionTitle("Last result")
                Spacer()
                Text(entry.date, style: .relative)
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                CopyButton(isCopied: copiedID == entry.id) { copy(entry) }
            }
            Text(entry.result)
                .font(.system(size: 13))
                .lineLimit(5)
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(10)
                .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(Color(nsColor: .controlBackgroundColor)))
        }
    }

    private var recent: some View {
        VStack(alignment: .leading, spacing: 4) {
            SectionTitle("Recent")
            ForEach(model.history.dropFirst().prefix(4)) { entry in
                RecentRow(entry: entry, isCopied: copiedID == entry.id) { copy(entry) }
            }
        }
    }

    private var footer: some View {
        HStack {
            Button("Settings…") { showSettings(.general) }
            Spacer()
            Button("Quit Voicer") { NSApp.terminate(nil) }
        }
        .buttonStyle(.borderless)
        .font(.system(size: 12, weight: .medium))
        .foregroundStyle(.primary)
    }

    private func copy(_ entry: HistoryEntry) {
        model.copyToClipboard(entry.result)
        copiedID = entry.id
        Task {
            try? await Task.sleep(for: .seconds(1.5))
            if copiedID == entry.id { copiedID = nil }
        }
    }

    private func showSettings(_ tab: SettingsTab) {
        model.settingsTab = tab
        NSApp.activate()
        openSettings()
    }
}

struct AppBadge: View {
    let size: CGFloat

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: size * 0.28, style: .continuous)
                .fill(LinearGradient(colors: [Color(red: 0.42, green: 0.36, blue: 1), Color(red: 0.93, green: 0.33, blue: 0.62)], startPoint: .topLeading, endPoint: .bottomTrailing))
            Image(systemName: "waveform")
                .font(.system(size: size * 0.48, weight: .bold))
                .foregroundStyle(.white)
        }
        .frame(width: size, height: size)
    }
}

struct StatusChip: View {
    let model: AppModel

    var body: some View {
        HStack(spacing: 5) {
            Circle().fill(color).frame(width: 7, height: 7)
            Text(text)
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(.primary)
        }
    }

    private var text: String {
        switch model.phase {
        case .recording: return "Listening"
        case .transcribing: return "Transcribing"
        case .formatting: return model.activeMode == .translate ? "Translating" : "Cleaning up"
        default: break
        }
        switch model.modelState {
        case .notLoaded: return "Starting"
        case .downloading(let progress): return "Downloading speech model \(Int(progress * 100))%"
        case .loading: return "Preparing speech model, first run takes a few minutes"
        case .ready: return "Ready"
        case .failed: return "Speech model failed"
        }
    }

    private var color: Color {
        switch model.phase {
        case .recording: return .red
        case .transcribing, .formatting: return .blue
        default: break
        }
        switch model.modelState {
        case .ready: return .green
        case .failed: return .red
        default: return .orange
        }
    }
}

private struct SectionTitle: View {
    let title: String

    init(_ title: String) { self.title = title }

    var body: some View {
        Text(title.uppercased())
            .font(.system(size: 10, weight: .semibold))
            .tracking(0.6)
            .foregroundStyle(.secondary)
    }
}

private struct SetupRow: View {
    let title: String
    let button: String
    let action: () -> Void

    var body: some View {
        HStack {
            Text(title).font(.system(size: 12))
            Spacer()
            Button(button, action: action)
                .controlSize(.small)
        }
    }
}

private struct CopyButton: View {
    let isCopied: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Label(isCopied ? "Copied" : "Copy", systemImage: isCopied ? "checkmark" : "doc.on.doc")
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(isCopied ? Color.green : Color.accentColor)
        }
        .buttonStyle(.plain)
    }
}

private struct RecentRow: View {
    let entry: HistoryEntry
    let isCopied: Bool
    let action: () -> Void
    @State private var isHovered = false

    var body: some View {
        Button(action: action) {
            HStack {
                Text(entry.result)
                    .font(.system(size: 12))
                    .lineLimit(1)
                    .foregroundStyle(.primary)
                Spacer()
                if isCopied {
                    Image(systemName: "checkmark").foregroundStyle(.green)
                } else if isHovered {
                    Image(systemName: "doc.on.doc").foregroundStyle(Color.accentColor)
                }
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 6)
            .background(
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .fill(isHovered ? Color.accentColor.opacity(0.12) : Color.clear)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { isHovered = $0 }
    }
}
