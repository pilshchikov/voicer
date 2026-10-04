import AppKit
import SwiftUI

struct KeyCap: View {
    let label: String
    var prominent = false

    var body: some View {
        Text(label)
            .font(.system(size: 12, weight: .semibold, design: .rounded))
            .foregroundStyle(.primary)
            .padding(.horizontal, 7)
            .padding(.vertical, 3)
            .frame(minWidth: 24)
            .background(
                RoundedRectangle(cornerRadius: 5, style: .continuous)
                    .fill(Color(nsColor: .textBackgroundColor))
                    .shadow(color: .black.opacity(0.18), radius: 0, x: 0, y: 1)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 5, style: .continuous)
                    .strokeBorder(prominent ? Color.accentColor : Color(nsColor: .separatorColor))
            )
    }
}

struct KeyCaps: View {
    let shortcut: Shortcut

    var body: some View {
        HStack(spacing: 4) {
            ForEach(Array(shortcut.keycaps.enumerated()), id: \.offset) { _, cap in
                KeyCap(label: cap)
            }
        }
    }
}

struct ShortcutRecorder: View {
    @Binding var shortcut: Shortcut?
    let model: AppModel

    @State private var isRecording = false
    @State private var peak = Set<ModifierKey>()
    @State private var monitor: Any?
    @State private var hint: String?

    var body: some View {
        VStack(alignment: .trailing, spacing: 4) {
            HStack(spacing: 6) {
                Button(action: toggleRecording) {
                    HStack(spacing: 4) {
                        if isRecording {
                            if peak.isEmpty {
                                Text("Press a shortcut…")
                                    .foregroundStyle(Color.accentColor)
                            } else {
                                KeyCaps(shortcut: Shortcut(modifiers: peak, keyCode: nil, keyLabel: nil, sideSpecific: peak.count == 1))
                            }
                        } else if let shortcut {
                            KeyCaps(shortcut: shortcut)
                        } else {
                            Text("Record shortcut")
                                .foregroundStyle(.primary)
                        }
                    }
                    .font(.system(size: 12, weight: .medium))
                    .frame(minWidth: 170, minHeight: 30)
                    .padding(.horizontal, 8)
                    .background(
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .fill(isRecording ? Color.accentColor.opacity(0.14) : Color(nsColor: .controlBackgroundColor))
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .strokeBorder(isRecording ? Color.accentColor : Color(nsColor: .separatorColor), lineWidth: isRecording ? 1.5 : 1)
                    )
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)

                if shortcut != nil, !isRecording {
                    Button {
                        shortcut = nil
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 14))
                            .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Remove shortcut")
                }
            }
            if let hint {
                Text(hint)
                    .font(.caption)
                    .foregroundStyle(.orange)
            } else if isRecording {
                Text("Esc cancels")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .onDisappear(perform: stopRecording)
    }

    private func toggleRecording() {
        isRecording ? stopRecording() : startRecording()
    }

    private func startRecording() {
        hint = nil
        peak = []
        isRecording = true
        model.isRecordingShortcut = true
        monitor = NSEvent.addLocalMonitorForEvents(matching: [.flagsChanged, .keyDown]) { event in
            handle(event) ? nil : event
        }
    }

    private func stopRecording() {
        if let monitor { NSEvent.removeMonitor(monitor) }
        monitor = nil
        isRecording = false
        peak = []
        model.isRecordingShortcut = false
    }

    private func handle(_ event: NSEvent) -> Bool {
        let active = ModifierKey.active(in: UInt64(event.modifierFlags.rawValue))
        switch event.type {
        case .flagsChanged:
            if active.isEmpty, !peak.isEmpty {
                commitModifierOnly(peak)
            } else {
                peak.formUnion(active)
            }
            return true
        case .keyDown:
            let keyCode = event.keyCode
            if keyCode == 53, active.isEmpty {
                stopRecording()
                return true
            }
            let isFunctionKey = Shortcut.functionKeyCodes.contains(keyCode)
            guard !active.subtracting([.fn]).isEmpty || isFunctionKey else {
                hint = "Add a modifier like ⌃, ⌥ or ⌘ to that key"
                return true
            }
            let label = Shortcut.label(forKeyCode: keyCode, characters: event.charactersIgnoringModifiers)
            shortcut = Shortcut(modifiers: active, keyCode: keyCode, keyLabel: label, sideSpecific: false)
            hint = nil
            stopRecording()
            return true
        default:
            return false
        }
    }

    private func commitModifierOnly(_ keys: Set<ModifierKey>) {
        if keys.count == 1, let key = keys.first, key.kind != .fn, !key.isRight {
            hint = "A single left-side key clashes with typing. Use a right-side key or a combination."
            peak = []
            return
        }
        shortcut = Shortcut(modifiers: keys, keyCode: nil, keyLabel: nil, sideSpecific: keys.count == 1)
        hint = nil
        stopRecording()
    }
}
