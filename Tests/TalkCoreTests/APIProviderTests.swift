import XCTest
@testable import TalkCore

final class APIProviderTests: XCTestCase {
    func testEachPurposeListsOnlyServicesThatSupportIt() {
        XCTAssertEqual(APIProvider.choices(for: .speech), [.openAI, .groq, .custom])
        XCTAssertEqual(APIProvider.choices(for: .text), [.openAI, .gemini, .claude, .custom])
    }

    func testPickingAServiceFillsItsAddressAndModel() {
        var settings = APISettings(baseURL: "https://example.com/v1", model: "old")
        APIProvider.gemini.apply(to: &settings, for: .text)
        XCTAssertEqual(settings.baseURL, "https://generativelanguage.googleapis.com/v1beta/openai/")
        XCTAssertEqual(settings.model, "gemini-3.5-flash-lite")
        APIProvider.groq.apply(to: &settings, for: .speech)
        XCTAssertEqual(settings.baseURL, "https://api.groq.com/openai/v1")
        XCTAssertEqual(settings.model, "whisper-large-v3-turbo")
    }

    func testCustomKeepsWhatTheUserTyped() {
        var settings = APISettings(baseURL: "https://example.com/v1", model: "mine")
        APIProvider.custom.apply(to: &settings, for: .text)
        XCTAssertEqual(settings, APISettings(baseURL: "https://example.com/v1", model: "mine"))
    }

    func testRecognisesASavedAddressIgnoringATrailingSlash() {
        XCTAssertEqual(APIProvider.matching(baseURL: "https://generativelanguage.googleapis.com/v1beta/openai"), .gemini)
        XCTAssertEqual(APIProvider.matching(baseURL: " https://api.openai.com/v1/ "), .openAI)
        XCTAssertEqual(APIProvider.matching(baseURL: "https://api.anthropic.com/v1"), .claude)
        XCTAssertEqual(APIProvider.matching(baseURL: "http://localhost:8080/v1"), .custom)
    }
}
