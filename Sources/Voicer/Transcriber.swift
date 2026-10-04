import Foundation
import WhisperKit

actor Transcriber {
    enum LoadState: Equatable {
        case notLoaded
        case downloading(Double)
        case loading
        case ready
        case failed(String)
    }

    private var whisper: WhisperKit?
    private var loadedModel: String?

    private static var modelsDirectory: URL {
        URL.applicationSupportDirectory.appending(path: "Voicer/models", directoryHint: .isDirectory)
    }

    // Whisper invents these on silence because of its Russian YouTube subtitle training data.
    private static let hallucinations = [
        "продолжение следует",
        "субтитры",
        "редактор субтитров",
        "спасибо за просмотр",
        "подписывайтесь на канал",
        "thank you for watching",
        "thanks for watching",
    ]

    func load(model: String, onState: @Sendable @escaping (LoadState) -> Void) async {
        if loadedModel == model, whisper != nil {
            onState(.ready)
            return
        }
        whisper = nil
        loadedModel = nil
        do {
            onState(.downloading(0))
            let folder = try await WhisperKit.download(
                variant: model,
                downloadBase: Self.modelsDirectory,
                progressCallback: { progress in onState(.downloading(progress.fractionCompleted)) }
            )
            onState(.loading)
            let config = WhisperKitConfig(
                modelFolder: folder.path,
                verbose: false,
                logLevel: .error,
                prewarm: true,
                load: true,
                download: false
            )
            whisper = try await WhisperKit(config)
            loadedModel = model
            onState(.ready)
        } catch {
            onState(.failed(error.localizedDescription))
        }
    }

    func transcribe(_ samples: [Float], language: String?, glossary: [String]) async throws -> String {
        guard let whisper else { throw TranscriberError.notReady }

        var promptTokens: [Int]?
        if !glossary.isEmpty, let tokenizer = whisper.tokenizer {
            promptTokens = tokenizer.encode(text: " " + glossary.joined(separator: ", "))
                .filter { $0 < tokenizer.specialTokens.specialTokenBegin }
        }

        let options = DecodingOptions(
            task: .transcribe,
            language: language,
            temperature: 0,
            usePrefillPrompt: true,
            detectLanguage: language == nil,
            skipSpecialTokens: true,
            withoutTimestamps: true,
            promptTokens: promptTokens,
            chunkingStrategy: samples.count > Int(AudioRecorder.sampleRate) * 30 ? .vad : nil
        )
        let results = try await whisper.transcribe(audioArray: samples, decodeOptions: options)
        let text = results.map(\.text).joined(separator: " ")
            .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return Self.isHallucination(text) ? "" : text
    }

    private static func isHallucination(_ text: String) -> Bool {
        let normalized = text.lowercased().trimmingCharacters(in: .punctuationCharacters.union(.whitespaces))
        guard normalized.count < 80 else { return false }
        return hallucinations.contains { normalized.contains($0) }
    }

    enum TranscriberError: LocalizedError {
        case notReady

        var errorDescription: String? { "Speech model is still loading" }
    }
}
