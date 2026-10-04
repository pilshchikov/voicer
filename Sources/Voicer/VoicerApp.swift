import SwiftUI

@main
struct VoicerApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var delegate

    var body: some Scene {
        MenuBarExtra {
            MenuBarView(model: delegate.model)
        } label: {
            Image(systemName: delegate.model.menuBarSymbol)
        }
        .menuBarExtraStyle(.window)

        Settings {
            SettingsView(model: delegate.model)
        }
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    @MainActor let model = AppModel()

    func applicationDidFinishLaunching(_ notification: Notification) {
        MainActor.assumeIsolated { model.launch() }
    }
}

extension AppModel {
    var menuBarSymbol: String {
        switch phase {
        case .recording: "mic.fill"
        case .transcribing, .formatting: "ellipsis.circle"
        default: "waveform"
        }
    }
}
