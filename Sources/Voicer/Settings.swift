import Foundation
import Observation

enum OutputMode: String, CaseIterable, Identifiable, Codable {
    case translate
    case cleanup
    case raw

    var id: String { rawValue }

    var title: String {
        switch self {
        case .translate: "Translate to English"
        case .cleanup: "Clean up, keep language"
        case .raw: "Raw transcript"
        }
    }

    var subtitle: String {
        switch self {
        case .translate: "AI translates, tidies, and formats"
        case .cleanup: "AI tidies without translating"
        case .raw: "Whisper output as is, no AI call"
        }
    }

    var symbol: String {
        switch self {
        case .translate: "character.bubble"
        case .cleanup: "wand.and.stars"
        case .raw: "text.quote"
        }
    }
}

enum OverlayPosition: String, CaseIterable, Identifiable {
    case bottom, top

    var id: String { rawValue }
}

enum SpokenLanguage: String, CaseIterable, Identifiable {
    case russian = "ru"
    case english = "en"
    case auto

    var id: String { rawValue }

    var title: String {
        switch self {
        case .russian: "Russian (with English words)"
        case .english: "English"
        case .auto: "Auto-detect"
        }
    }

    var whisperCode: String? { self == .auto ? nil : rawValue }
}

enum WhisperModel: String, CaseIterable, Identifiable {
    case largeV3Turbo = "large-v3-v20240930_turbo_632MB"
    case largeV3 = "large-v3-v20240930_626MB"
    case small = "small_216MB"

    var id: String { rawValue }

    var title: String {
        switch self {
        case .largeV3Turbo: "Large v3 Turbo (fast, recommended)"
        case .largeV3: "Large v3 (slower, a bit more accurate)"
        case .small: "Small (fastest, weaker on Russian)"
        }
    }
}

@MainActor
@Observable
final class AppSettings {
    static let shared = AppSettings()

    private let defaults = UserDefaults.standard

    var shortcuts: [OutputMode: Shortcut] {
        didSet { defaults.set(try? JSONEncoder().encode(shortcuts), forKey: "shortcuts") }
    }
    var triggerBehavior: TriggerBehavior { didSet { defaults.set(triggerBehavior.rawValue, forKey: "triggerBehavior") } }
    var playSounds: Bool { didSet { defaults.set(playSounds, forKey: "playSounds") } }
    var overlayPosition: OverlayPosition { didSet { defaults.set(overlayPosition.rawValue, forKey: "overlayPosition") } }
    var language: SpokenLanguage { didSet { defaults.set(language.rawValue, forKey: "language") } }
    var whisperModel: WhisperModel { didSet { defaults.set(whisperModel.rawValue, forKey: "whisperModel") } }
    var claudeModel: String { didSet { defaults.set(claudeModel, forKey: "claudeModel") } }
    var claudeEffort: Effort { didSet { defaults.set(claudeEffort.rawValue, forKey: "claudeEffort") } }
    var claudeAccount: String { didSet { defaults.set(claudeAccount, forKey: "claudeAccount") } }
    var provider: AIProvider { didSet { defaults.set(provider.rawValue, forKey: "provider") } }
    var codexModel: String { didSet { defaults.set(codexModel, forKey: "codexModel") } }
    var codexEffort: Effort { didSet { defaults.set(codexEffort.rawValue, forKey: "codexEffort") } }
    var codexAccount: String { didSet { defaults.set(codexAccount, forKey: "codexAccount") } }
    var glossary: String { didSet { defaults.set(glossary, forKey: "glossary") } }
    var keepResultInClipboard: Bool { didSet { defaults.set(keepResultInClipboard, forKey: "keepResultInClipboard") } }

    private init() {
        shortcuts = defaults.data(forKey: "shortcuts")
            .flatMap { try? JSONDecoder().decode([OutputMode: Shortcut].self, from: $0) }
            ?? [.translate: .defaultDictation]
        triggerBehavior = TriggerBehavior(rawValue: defaults.string(forKey: "triggerBehavior") ?? "") ?? .holdOrTap
        playSounds = defaults.object(forKey: "playSounds") as? Bool ?? true
        overlayPosition = OverlayPosition(rawValue: defaults.string(forKey: "overlayPosition") ?? "") ?? .bottom
        language = SpokenLanguage(rawValue: defaults.string(forKey: "language") ?? "") ?? .russian
        whisperModel = WhisperModel(rawValue: defaults.string(forKey: "whisperModel") ?? "") ?? .largeV3Turbo
        claudeModel = defaults.string(forKey: "claudeModel") ?? "claude-sonnet-5-5"
        claudeEffort = Effort(rawValue: defaults.string(forKey: "claudeEffort") ?? "") ?? .medium
        claudeAccount = defaults.string(forKey: "claudeAccount") ?? ""
        provider = AIProvider(rawValue: defaults.string(forKey: "provider") ?? "") ?? .claude
        codexModel = defaults.string(forKey: "codexModel") ?? ""
        codexEffort = Effort(rawValue: defaults.string(forKey: "codexEffort") ?? "") ?? .medium
        codexAccount = defaults.string(forKey: "codexAccount") ?? ""
        glossary = defaults.string(forKey: "glossary") ?? ""
        keepResultInClipboard = defaults.bool(forKey: "keepResultInClipboard")
    }

    var glossaryTerms: [String] {
        glossary
            .split(whereSeparator: { $0 == "\n" || $0 == "," })
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
    }
}
