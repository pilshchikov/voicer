import AppKit
import AVFoundation
import Observation

struct HistoryEntry: Codable, Identifiable {
    var id = UUID()
    var date: Date
    var transcript: String
    var result: String
}

@MainActor
@Observable
final class AppModel {
    enum Phase: Equatable {
        case idle
        case recording(locked: Bool)
        case transcribing
        case formatting
        case done(String)
        case failed(String)
    }

    private static let minimumSamples = Int(AudioRecorder.sampleRate * 0.4)
    private static let maxHistory = 50

    let settings = AppSettings.shared
    private(set) var phase = Phase.idle
    private(set) var activeMode = OutputMode.translate
    private(set) var level: Float = 0
    private(set) var modelState = Transcriber.LoadState.notLoaded
    private(set) var history: [HistoryEntry] = []
    private(set) var accessibilityTrusted = AXIsProcessTrusted()
    private(set) var microphoneAuthorized = AVCaptureDevice.authorizationStatus(for: .audio) == .authorized
    private(set) var executables: [AIProvider: URL] = AppModel.findExecutables()
    private(set) var recordingStartedAt: Date?
    private(set) var heldModifiers = Set<ModifierKey>()

    var settingsTab = SettingsTab.general

    var isRecordingShortcut = false {
        didSet { hotkeys.isSuspended = isRecordingShortcut }
    }

    private let recorder = AudioRecorder()
    private let transcriber = Transcriber()
    private let hotkeys = HotkeyMonitor()
    private let overlay = OverlayController()
    private var pipeline: Task<Void, Never>?
    private var resetPhase: Task<Void, Never>?
    private var targetApp: NSRunningApplication?

    init() {
        if let data = UserDefaults.standard.data(forKey: "history"),
           let saved = try? JSONDecoder().decode([HistoryEntry].self, from: data) {
            history = saved
        }
        recorder.onLevel = { [weak self] value in
            Task { @MainActor in self?.level = value }
        }
        hotkeys.onEvent = { [weak self] event in self?.handle(event) }
        hotkeys.onModifiersChanged = { [weak self] keys in self?.heldModifiers = keys }
        syncHotkeys()
    }

    func launch() {
        overlay.attach(to: self)
        requestAccessibility(prompt: !AXIsProcessTrusted())
        requestMicrophone()
        loadModel()
        observeSettings()
    }

    var needsSetup: Bool {
        !accessibilityTrusted || !microphoneAuthorized || (executables[settings.provider] == nil && settings.shortcuts.keys.contains { $0 != .raw })
    }

    func loadModel() {
        let model = settings.whisperModel.rawValue
        Task {
            await transcriber.load(model: model) { [weak self] state in
                Task { @MainActor in self?.modelState = state }
            }
        }
    }

    func requestAccessibility(prompt: Bool) {
        let options = ["AXTrustedCheckOptionPrompt": prompt] as CFDictionary
        accessibilityTrusted = AXIsProcessTrustedWithOptions(options)
        DebugLog.write("accessibility trusted=\(accessibilityTrusted) bindings=\(settings.shortcuts)")
        if accessibilityTrusted {
            hotkeys.start()
            return
        }
        Task {
            while !AXIsProcessTrusted() {
                try? await Task.sleep(for: .seconds(1))
            }
            accessibilityTrusted = true
            hotkeys.start()
        }
    }

    func refreshPermissions() {
        microphoneAuthorized = AVCaptureDevice.authorizationStatus(for: .audio) == .authorized
        accessibilityTrusted = AXIsProcessTrusted()
        executables = Self.findExecutables()
    }

    func requestMicrophone() {
        if AVCaptureDevice.authorizationStatus(for: .audio) == .denied {
            NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Microphone")!)
            return
        }
        Task {
            microphoneAuthorized = await AudioRecorder.requestPermission()
        }
    }

    func openAccessibilitySettings() {
        NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")!)
    }

    private static func findExecutables() -> [AIProvider: URL] {
        AIProvider.allCases.reduce(into: [:]) { result, provider in
            result[provider] = provider.findExecutable()
        }
    }

    private func makeRewriter(quick: Bool = false) -> TextRewriter? {
        guard let executable = executables[settings.provider] else { return nil }
        switch settings.provider {
        case .claude:
            return ClaudeClient(
                executable: executable,
                configDirectory: settings.claudeAccount,
                model: settings.claudeModel,
                effort: quick ? .low : settings.claudeEffort
            )
        case .codex:
            return CodexClient(
                executable: executable,
                home: settings.codexAccount,
                model: settings.codexModel,
                effort: quick ? .low : settings.codexEffort
            )
        }
    }

    func testProvider() async -> Result<String, Error> {
        refreshPermissions()
        guard let client = makeRewriter(quick: true) else {
            return .failure(AIError.notInstalled(settings.provider.cliName))
        }
        let system = TextFormatter.systemPrompt(mode: .translate, style: .document, glossary: [])
        do {
            let reply = try await client.complete(
                system: system,
                user: TextFormatter.userMessage(transcript: "ну короче, проверка связи, всё работает")
            )
            return .success(reply)
        } catch {
            return .failure(error)
        }
    }

    func copyToClipboard(_ text: String) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
    }

    func clearHistory() {
        history.removeAll()
        saveHistory()
    }

    func deleteHistory(_ entry: HistoryEntry) {
        history.removeAll { $0.id == entry.id }
        saveHistory()
    }

    private func syncHotkeys() {
        hotkeys.bindings = settings.shortcuts
        hotkeys.behavior = settings.triggerBehavior
        hotkeys.reset()
    }

    private func observeSettings() {
        withObservationTracking {
            _ = settings.shortcuts
            _ = settings.triggerBehavior
            _ = settings.whisperModel
        } onChange: { [weak self] in
            Task { @MainActor in
                guard let self else { return }
                self.syncHotkeys()
                self.loadModel()
                self.observeSettings()
            }
        }
    }

    private func handle(_ event: HotkeyMonitor.Event) {
        DebugLog.write("hotkey event \(event)")
        switch event {
        case .start(let mode): startRecording(mode)
        case .locked: if case .recording = phase { phase = .recording(locked: true) }
        case .stop: finishRecording()
        case .cancel: cancelRecording()
        }
    }

    private func startRecording(_ mode: OutputMode) {
        guard pipeline == nil else { return }
        resetPhase?.cancel()
        do {
            try recorder.start()
            activeMode = mode
            targetApp = NSWorkspace.shared.frontmostApplication
            recordingStartedAt = Date()
            phase = .recording(locked: false)
            play("Tink")
        } catch {
            show(.failed(error.localizedDescription))
            hotkeys.reset()
        }
    }

    private func cancelRecording() {
        guard case .recording = phase else { return }
        _ = recorder.stop()
        level = 0
        phase = .idle
    }

    private func finishRecording() {
        guard case .recording = phase else { return }
        let samples = recorder.stop()
        level = 0
        guard samples.count >= Self.minimumSamples else {
            phase = .idle
            return
        }
        play("Pop")
        let target = targetApp
        let mode = activeMode
        pipeline = Task {
            await process(samples, mode: mode, target: target)
            pipeline = nil
        }
    }

    private func process(_ samples: [Float], mode: OutputMode, target: NSRunningApplication?) async {
        phase = .transcribing
        let transcript: String
        do {
            transcript = try await transcriber.transcribe(
                samples,
                language: settings.language.whisperCode,
                glossary: settings.glossaryTerms
            )
        } catch {
            show(.failed(error.localizedDescription))
            return
        }
        guard !transcript.isEmpty else {
            show(.failed("Didn't catch anything"))
            return
        }

        var result = transcript
        var formatError: String?
        if mode != .raw {
            if let client = makeRewriter() {
                phase = .formatting
                let system = TextFormatter.systemPrompt(
                    mode: mode,
                    style: TargetStyle(bundleID: target?.bundleIdentifier),
                    glossary: settings.glossaryTerms
                )
                do {
                    result = try await client.complete(system: system, user: TextFormatter.userMessage(transcript: transcript))
                } catch {
                    formatError = error.localizedDescription
                }
            } else {
                formatError = "\(settings.provider.cliName) not found, raw transcript used"
            }
        }

        remember(transcript: transcript, result: result)

        if let target, target != NSWorkspace.shared.frontmostApplication {
            target.activate()
            try? await Task.sleep(for: .milliseconds(150))
        }
        let outcome = TextInserter.deliver(result, keepInClipboard: settings.keepResultInClipboard)
        let message = outcome == .pasted ? "Inserted" : "Copied to clipboard"
        if let formatError {
            show(.failed("\(message). \(formatError)"))
        } else {
            show(.done(message))
        }
    }

    private func show(_ newPhase: Phase) {
        phase = newPhase
        if case .failed = newPhase { play("Basso") }
        resetPhase?.cancel()
        let delay: Duration = if case .failed = newPhase { .seconds(4) } else { .seconds(1.2) }
        resetPhase = Task {
            try? await Task.sleep(for: delay)
            guard !Task.isCancelled else { return }
            phase = .idle
        }
    }

    private func play(_ sound: String) {
        guard settings.playSounds else { return }
        NSSound(named: NSSound.Name(sound))?.play()
    }

    private func remember(transcript: String, result: String) {
        history.insert(HistoryEntry(date: Date(), transcript: transcript, result: result), at: 0)
        if history.count > Self.maxHistory { history.removeLast(history.count - Self.maxHistory) }
        saveHistory()
    }

    private func saveHistory() {
        UserDefaults.standard.set(try? JSONEncoder().encode(history), forKey: "history")
    }
}
