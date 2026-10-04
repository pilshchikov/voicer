import AppKit
import SwiftUI

@MainActor
final class OverlayController {
    private var panel: NSPanel?

    func attach(to model: AppModel) {
        let panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 440, height: 56),
            styleMask: [.nonactivatingPanel, .borderless],
            backing: .buffered,
            defer: true
        )
        panel.level = .statusBar
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.ignoresMouseEvents = true
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
        panel.contentView = NSHostingView(rootView: OverlayView(model: model))
        self.panel = panel
        track(model)
    }

    private func track(_ model: AppModel) {
        withObservationTracking {
            update(visible: model.phase != .idle, atTop: model.settings.overlayPosition == .top)
        } onChange: { [weak self] in
            Task { @MainActor in self?.track(model) }
        }
    }

    private func update(visible: Bool, atTop: Bool) {
        guard let panel else { return }
        if visible, !panel.isVisible {
            let screen = NSScreen.screens.first { $0.frame.contains(NSEvent.mouseLocation) } ?? NSScreen.main
            if let frame = screen?.visibleFrame {
                let y = atTop ? frame.maxY - panel.frame.height - 12 : frame.minY + 48
                panel.setFrameOrigin(NSPoint(x: frame.midX - panel.frame.width / 2, y: y))
            }
            panel.orderFrontRegardless()
        } else if !visible, panel.isVisible {
            panel.orderOut(nil)
        }
    }
}

private struct OverlayView: View {
    let model: AppModel

    var body: some View {
        HStack(spacing: 10) {
            content
        }
        .font(.system(size: 13, weight: .medium))
        .foregroundStyle(.white)
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(Capsule().fill(Color.black.opacity(0.88)))
        .overlay(Capsule().strokeBorder(Color.white.opacity(0.18)))
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    @ViewBuilder
    private var content: some View {
        switch model.phase {
        case .idle:
            EmptyView()
        case .recording(let locked):
            Circle().fill(Color.red).frame(width: 9, height: 9)
            LevelBars(level: model.level)
            if let start = model.recordingStartedAt {
                Text(timerInterval: start...Date.distantFuture, countsDown: false)
                    .monospacedDigit()
                    .frame(width: 44, alignment: .leading)
            }
            if locked {
                Image(systemName: "lock.fill")
                Text("press shortcut to finish, esc to cancel")
            }
        case .transcribing:
            ProgressView().controlSize(.small).tint(.white)
            Text("Transcribing")
        case .formatting:
            ProgressView().controlSize(.small).tint(.white)
            Text(model.activeMode == .translate ? "Translating" : "Cleaning up")
        case .done(let message):
            Image(systemName: "checkmark.circle.fill").foregroundStyle(.green)
            Text(message)
        case .failed(let message):
            Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.yellow)
            Text(message).lineLimit(2)
        }
    }
}

private struct LevelBars: View {
    let level: Float
    private let weights: [Float] = [0.5, 0.8, 1, 0.7, 0.9, 0.6, 0.4]

    var body: some View {
        HStack(spacing: 3) {
            ForEach(weights.indices, id: \.self) { index in
                Capsule()
                    .fill(Color.white)
                    .frame(width: 3, height: CGFloat(4 + 18 * min(1, level * weights[index])))
            }
        }
        .frame(height: 22)
        .animation(.easeOut(duration: 0.08), value: level)
    }
}
