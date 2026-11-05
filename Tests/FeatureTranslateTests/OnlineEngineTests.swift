import Core
import Foundation
import Testing
@testable import FeatureTranslate

/// Records requests and answers with a canned response.
final class FakeHTTP: HTTPClient, @unchecked Sendable {
    var requests: [URLRequest] = []
    var status = 200
    var body = Data()
    var error: Error?

    func send(_ request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        requests.append(request)
        if let error { throw error }
        return (body, HTTPURLResponse(url: request.url!, statusCode: status, httpVersion: nil, headerFields: nil)!)
    }

    func json(_ object: Any) { body = try! JSONSerialization.data(withJSONObject: object) }

    var lastJSON: [String: Any] {
        (try? JSONSerialization.jsonObject(with: requests.last?.httpBody ?? Data())) as? [String: Any] ?? [:]
    }
}

@MainActor
struct DeepLTests {
    let http = FakeHTTP()

    @Test func freeKeyUsesFreeEndpointAndHeader() async throws {
        http.json(["translations": [["text": "Привет", "detected_source_language": "EN"]]])
        let result = try await DeepLEngine(key: "abc:fx", http: http)
            .translate(TranslationRequest(text: "Hello", source: nil, target: "ru"))

        let request = try #require(http.requests.first)
        #expect(request.url?.absoluteString == "https://api-free.deepl.com/v2/translate")
        #expect(request.value(forHTTPHeaderField: "Authorization") == "DeepL-Auth-Key abc:fx")
        #expect(request.timeoutInterval == 10)
        #expect(http.lastJSON["target_lang"] as? String == "RU")
        #expect(http.lastJSON["source_lang"] == nil)
        #expect(result == TranslationResult(text: "Привет", source: "en", target: "ru"))
    }

    @Test func proKeyAndRegionalTarget() async throws {
        http.json(["translations": [["text": "Hi"]]])
        _ = try await DeepLEngine(key: "pro-key", http: http)
            .translate(TranslationRequest(text: "Привет", source: "ru", target: "en"))
        #expect(http.requests.first?.url?.host() == "api.deepl.com")
        #expect(http.lastJSON["target_lang"] as? String == "EN-US")
        #expect(http.lastJSON["source_lang"] as? String == "RU")
    }

    @Test func statusCodesBecomeReadableErrors() async {
        let engine = DeepLEngine(key: "k", http: http)
        let request = TranslationRequest(text: "x", source: nil, target: "ru")
        for (status, expected) in [(403, OnlineTranslationError.invalidKey), (456, .quotaExceeded),
                                   (429, .rateLimited), (500, .server(500))] {
            http.status = status
            await #expect(throws: expected) { _ = try await engine.translate(request) }
        }
        http.error = URLError(.notConnectedToInternet)
        await #expect(throws: OnlineTranslationError.offline) { _ = try await engine.translate(request) }
        http.error = URLError(.timedOut)
        await #expect(throws: OnlineTranslationError.timeout) { _ = try await engine.translate(request) }
    }

    @Test func usageReportsQuota() async throws {
        http.json(["character_count": 1200, "character_limit": 500_000])
        let usage = try await DeepLEngine(key: "k:fx", http: http).usage()
        #expect(usage.used == 1200 && usage.limit == 500_000)
        #expect(http.requests.first?.httpMethod == "GET")
    }

    @Test func longTextIsSentInChunksAndJoined() async throws {
        let paragraph = String(repeating: "word ", count: 3_000)  // 15 000 chars
        http.json(["translations": [["text": "A"], ["text": "B"]]])
        let result = try await DeepLEngine(key: "k", http: http)
            .translate(TranslationRequest(text: paragraph + "\n\n" + paragraph, source: nil, target: "ru"))
        #expect((http.lastJSON["text"] as? [String])?.count == 2)
        #expect(result.text == "A\n\nB")
    }
}

@MainActor
struct GoogleTests {
    let http = FakeHTTP()

    @Test func keyGoesInHeaderNotURL() async throws {
        http.json(["data": ["translations": [["translatedText": "Привет", "detectedSourceLanguage": "en"]]]])
        let result = try await GoogleEngine(key: "secret", http: http)
            .translate(TranslationRequest(text: "Hello", source: nil, target: "ru"))
        let request = try #require(http.requests.first)
        #expect(request.value(forHTTPHeaderField: "X-goog-api-key") == "secret")
        #expect(request.url?.query == nil)
        #expect(http.lastJSON["target"] as? String == "ru")
        #expect(http.lastJSON["format"] as? String == "text")
        #expect(result.text == "Привет" && result.source == "en")
    }

    @Test func invalidKeyIsRecognized() async {
        http.status = 400
        http.body = Data(#"{"error":{"message":"API key not valid. Please pass a valid API key."}}"#.utf8)
        await #expect(throws: OnlineTranslationError.invalidKey) {
            _ = try await GoogleEngine(key: "bad", http: http).translate(TranslationRequest(text: "x", source: nil, target: "ru"))
        }
    }

    @Test func chineseCodes() {
        #expect(GoogleEngine.code("zh") == "zh-CN")
        #expect(GoogleEngine.code("zh-Hant") == "zh-TW")
        #expect(GoogleEngine.code("ru-RU") == "ru")
    }
}

struct ChunkerTests {
    @Test func shortTextIsOneChunk() {
        #expect(TextChunker.chunks("один\n\nдва", limit: 100) == ["один\n\nдва"])
    }

    @Test func paragraphsAreGroupedUnderTheLimit() {
        let chunks = TextChunker.chunks("aaaa\n\nbbbb\n\ncccc", limit: 10)
        #expect(chunks == ["aaaa\n\nbbbb", "cccc"])
        #expect(chunks.allSatisfy { $0.count <= 10 })
    }

    @Test func longParagraphIsCutAtSentences() {
        let text = "Первое предложение. Второе предложение. Третье предложение."
        let chunks = TextChunker.chunks(text, limit: 25)
        #expect(chunks.allSatisfy { $0.count <= 25 })
        #expect(chunks.first == "Первое предложение.")
        #expect(chunks.joined(separator: " ") == text)
    }
}

@MainActor
struct ResilientEngineTests {
    let cache = TranslationCache()

    @Test func fallsBackToAppleWithReason() async throws {
        let online = FakeEngine()
        online.failure = OnlineTranslationError.offline
        let apple = FakeEngine()
        let engine = ResilientEngine(primary: online, apple: apple, fallbackToApple: true, cache: cache, cacheKey: "deepl")

        let result = try await engine.translate(TranslationRequest(text: "Hello", source: "en", target: "ru"))
        #expect(apple.requests.count == 1)
        #expect(result.fallbackReason == OnlineTranslationError.offline.message)
        #expect(result.engineName == "Fake")
    }

    @Test func withoutFallbackTheErrorIsShown() async {
        let online = FakeEngine()
        online.failure = OnlineTranslationError.invalidKey
        let engine = ResilientEngine(primary: online, apple: FakeEngine(), fallbackToApple: false, cache: cache, cacheKey: "deepl")
        await #expect(throws: OnlineTranslationError.invalidKey) {
            _ = try await engine.translate(TranslationRequest(text: "x", source: nil, target: "ru"))
        }
    }

    @Test func missingKeyUsesAppleRightAway() async throws {
        let apple = FakeEngine()
        let engine = ResilientEngine(primary: nil, primaryError: .missingKey, apple: apple, fallbackToApple: true,
                                     cache: cache, cacheKey: "google")
        let result = try await engine.translate(TranslationRequest(text: "x", source: nil, target: "ru"))
        #expect(result.fallbackReason == OnlineTranslationError.missingKey.message)
    }

    @Test func repeatedRequestComesFromCache() async throws {
        let online = FakeEngine()
        let engine = ResilientEngine(primary: online, apple: FakeEngine(), fallbackToApple: true, cache: cache, cacheKey: "deepl")
        let request = TranslationRequest(text: "Hello", source: "en", target: "ru")
        _ = try await engine.translate(request)
        _ = try await engine.translate(request)
        #expect(online.requests.count == 1)
        #expect(cache.count == 1)
    }

    @Test func cacheKeepsOnlyTheNewest() {
        let small = TranslationCache(capacity: 2)
        for i in 0..<3 {
            let request = TranslationRequest(text: "\(i)", source: nil, target: "ru")
            small.store(TranslationResult(text: "t\(i)", source: nil, target: "ru"), engine: "a", request: request)
        }
        #expect(small.count == 2)
        #expect(small.value(engine: "a", request: TranslationRequest(text: "0", source: nil, target: "ru")) == nil)
    }
}

@MainActor
struct EngineSelectionTests {
    let context = AppContext.testing()

    @Test func chosenEngineAndKeyFromKeychain() throws {
        let feature = TranslateFeature(context: context)
        #expect(feature.makeEngine().name == String(localized: "translate.engine.apple"))

        feature.settings.engine = .deepl
        try context.secrets.setSecret("key:fx", for: TranslateSettings.secretKey(for: .deepl))
        #expect(feature.makeEngine().name == "DeepL")

        feature.settings.engine = .google
        #expect(feature.makeEngine().name == String(localized: "translate.engine.apple"))  // no Google key → Apple
    }

    @Test func checkingKeySavesItAndReportsQuota() async throws {
        let http = FakeHTTP()
        http.json(["character_count": 10, "character_limit": 500_000])
        let keys = APIKeysModel(secrets: context.secrets, http: http)
        keys.deeplKey = "  abc:fx  "
        keys.check(.deepl)
        for _ in 0..<50 where keys.checking != nil { await Task.yield() }
        #expect(context.secrets.secret(for: TranslateSettings.secretKey(for: .deepl)) == "abc:fx")
        // Interface strings are not bundled in tests, so only check it is a success, not a warning.
        let status = try #require(keys.status[.deepl])
        #expect(!status.hasPrefix("⚠️"))
        #expect(http.requests.first?.url?.lastPathComponent == "usage")
    }
}
