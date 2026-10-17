import Foundation

/// Common OpenAI-compatible services offered in the API settings, so users pick a name
/// instead of remembering an address. Picking one fills its address and a suggested model.
public enum APIProvider: String, CaseIterable, Identifiable, Sendable {
    case openAI, gemini, groq, custom
    public enum Purpose: Sendable { case speech, text }

    public var id: String { rawValue }
    public var title: String {
        switch self {
        case .openAI: return "OpenAI"
        case .gemini: return "Google Gemini"
        case .groq: return "Groq"
        case .custom: return "自訂"
        }
    }
    public var baseURL: String? {
        switch self {
        case .openAI: return "https://api.openai.com/v1"
        case .gemini: return "https://generativelanguage.googleapis.com/v1beta/openai/"
        case .groq: return "https://api.groq.com/openai/v1"
        case .custom: return nil
        }
    }
    /// Where to create an API key for this service.
    public var keyPage: URL? {
        switch self {
        case .openAI: return URL(string: "https://platform.openai.com/api-keys")
        case .gemini: return URL(string: "https://aistudio.google.com/apikey")
        case .groq: return URL(string: "https://console.groq.com/keys")
        case .custom: return nil
        }
    }
    /// The suggested model, or nil when the service is not offered for this purpose.
    public func model(for purpose: Purpose) -> String? {
        switch (self, purpose) {
        case (.openAI, .speech): return "gpt-transcribe"
        case (.openAI, .text): return "gpt-4.1-mini"
        case (.gemini, .text): return "gemini-3.5-flash-lite"
        case (.groq, .speech): return "whisper-large-v3-turbo"
        default: return nil
        }
    }

    public static func choices(for purpose: Purpose) -> [APIProvider] {
        allCases.filter { $0 == .custom || $0.model(for: purpose) != nil }
    }

    public func apply(to settings: inout APISettings, for purpose: Purpose) {
        guard let baseURL, let model = model(for: purpose) else { return }
        settings.baseURL = baseURL; settings.model = model
    }

    public static func matching(baseURL: String) -> APIProvider {
        func normalized(_ url: String) -> String {
            var value = url.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            while value.hasSuffix("/") { value.removeLast() }
            return value
        }
        let target = normalized(baseURL)
        return allCases.first { $0.baseURL.map(normalized) == target } ?? .custom
    }
}
