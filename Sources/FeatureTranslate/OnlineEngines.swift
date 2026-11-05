import Foundation
import SwiftUI

/// Network access, abstracted so tests never hit real services.
protocol HTTPClient: Sendable {
    func send(_ request: URLRequest) async throws -> (Data, HTTPURLResponse)
}

struct URLSessionHTTPClient: HTTPClient {
    func send(_ request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse else { throw URLError(.badServerResponse) }
        return (data, http)
    }
}

/// Why an online engine failed. All of these make the fallback to Apple kick in.
enum OnlineTranslationError: Error, Equatable {
    case missingKey
    case invalidKey
    case quotaExceeded
    case rateLimited
    case offline
    case timeout
    case server(Int)
    case badResponse

    var message: String {
        switch self {
        case .missingKey: String(localized: "translate.online.missingKey")
        case .invalidKey: String(localized: "translate.online.invalidKey")
        case .quotaExceeded: String(localized: "translate.online.quota")
        case .rateLimited: String(localized: "translate.online.rateLimited")
        case .offline: String(localized: "translate.online.offline")
        case .timeout: String(localized: "translate.online.timeout")
        case .server(let code): String(format: String(localized: "translate.online.server"), code)
        case .badResponse: String(localized: "translate.online.badResponse")
        }
    }

    static func from(_ error: Error) -> OnlineTranslationError {
        if let error = error as? OnlineTranslationError { return error }
        if let error = error as? URLError {
            switch error.code {
            case .timedOut: return .timeout
            case .notConnectedToInternet, .networkConnectionLost, .cannotFindHost, .cannotConnectToHost,
                 .dnsLookupFailed, .dataNotAllowed:
                return .offline
            default: return .badResponse
            }
        }
        return .badResponse
    }
}

/// Splits long text for APIs with request limits: by paragraphs, then sentences, then words.
/// Joining the chunks with "\n\n" restores paragraph structure.
enum TextChunker {
    static func chunks(_ text: String, limit: Int) -> [String] {
        var result: [String] = []
        var current = ""
        for paragraph in text.components(separatedBy: "\n\n") {
            for piece in split(paragraph, limit: limit) {
                if current.isEmpty {
                    current = piece
                } else if current.count + 2 + piece.count <= limit {
                    current += "\n\n" + piece
                } else {
                    result.append(current)
                    current = piece
                }
            }
        }
        if !current.isEmpty { result.append(current) }
        return result
    }

    /// A single paragraph longer than the limit is cut at sentence ends or spaces.
    private static func split(_ paragraph: String, limit: Int) -> [String] {
        guard paragraph.count > limit else { return [paragraph] }
        var pieces: [String] = []
        var rest = Substring(paragraph)
        while rest.count > limit {
            let window = rest.prefix(limit)
            let cut = window.lastIndex(where: { ".!?…".contains($0) }).map { rest.index(after: $0) }
                ?? window.lastIndex(of: " ")
                ?? window.endIndex
            pieces.append(String(rest[..<cut]).trimmingCharacters(in: .whitespaces))
            rest = rest[cut...].drop(while: { $0 == " " })
        }
        if !rest.isEmpty { pieces.append(String(rest)) }
        return pieces
    }
}

/// DeepL API (Free and Pro). Free keys end with ":fx" and use api-free.deepl.com.
@MainActor
final class DeepLEngine: TranslationEngine {
    private let key: String
    private let http: any HTTPClient

    init(key: String, http: any HTTPClient = URLSessionHTTPClient()) {
        self.key = key
        self.http = http
    }

    var name: String { "DeepL" }
    var hostView: AnyView? { nil }
    func prepare(source: String?, target: String) async throws {}

    var baseURL: URL {
        URL(string: key.hasSuffix(":fx") ? "https://api-free.deepl.com/v2/" : "https://api.deepl.com/v2/")!
    }

    func translate(_ request: TranslationRequest) async throws -> TranslationResult {
        var body: [String: Any] = [
            "text": TextChunker.chunks(request.text, limit: 20_000),
            "target_lang": Self.targetCode(request.target),
        ]
        if let source = request.source { body["source_lang"] = Self.sourceCode(source) }
        let data = try await call("translate", method: "POST", json: body)

        struct Response: Decodable {
            struct Item: Decodable {
                let text: String
                let detected_source_language: String?
            }
            let translations: [Item]
        }
        guard let response = try? JSONDecoder().decode(Response.self, from: data), !response.translations.isEmpty
        else { throw OnlineTranslationError.badResponse }
        return TranslationResult(
            text: response.translations.map(\.text).joined(separator: "\n\n"),
            source: response.translations.first?.detected_source_language?.lowercased(),
            target: request.target
        )
    }

    /// Characters used and the monthly limit (also validates the key).
    func usage() async throws -> (used: Int, limit: Int) {
        let data = try await call("usage", method: "GET", json: nil)
        struct Usage: Decodable {
            let character_count: Int
            let character_limit: Int
        }
        guard let usage = try? JSONDecoder().decode(Usage.self, from: data) else { throw OnlineTranslationError.badResponse }
        return (usage.character_count, usage.character_limit)
    }

    private func call(_ path: String, method: String, json: [String: Any]?) async throws -> Data {
        var request = URLRequest(url: baseURL.appending(path: path), timeoutInterval: 10)
        request.httpMethod = method
        request.setValue("DeepL-Auth-Key \(key)", forHTTPHeaderField: "Authorization")
        if let json {
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.httpBody = try JSONSerialization.data(withJSONObject: json)
        }
        let data: Data
        let response: HTTPURLResponse
        do {
            (data, response) = try await http.send(request)
        } catch {
            throw OnlineTranslationError.from(error)
        }
        switch response.statusCode {
        case 200..<300: return data
        case 401, 403: throw OnlineTranslationError.invalidKey
        case 456: throw OnlineTranslationError.quotaExceeded
        case 429: throw OnlineTranslationError.rateLimited
        default: throw OnlineTranslationError.server(response.statusCode)
        }
    }

    /// DeepL wants regional variants for some target languages.
    static func targetCode(_ language: String) -> String {
        switch TranslationDirection.baseCode(language) {
        case "en": "EN-US"
        case "pt": "PT-BR"
        case "zh": "ZH-HANS"
        case let code: code.uppercased()
        }
    }

    static func sourceCode(_ language: String) -> String {
        TranslationDirection.baseCode(language).uppercased()
    }
}

/// Google Cloud Translation API v2 (basic). The key goes in a header, not in the URL.
@MainActor
final class GoogleEngine: TranslationEngine {
    private let key: String
    private let http: any HTTPClient

    init(key: String, http: any HTTPClient = URLSessionHTTPClient()) {
        self.key = key
        self.http = http
    }

    var name: String { "Google Translate" }
    var hostView: AnyView? { nil }
    func prepare(source: String?, target: String) async throws {}

    func translate(_ request: TranslationRequest) async throws -> TranslationResult {
        var body: [String: Any] = [
            "q": TextChunker.chunks(request.text, limit: 5_000),
            "target": Self.code(request.target),
            "format": "text",
        ]
        if let source = request.source { body["source"] = Self.code(source) }
        var urlRequest = URLRequest(url: URL(string: "https://translation.googleapis.com/language/translate/v2")!,
                                    timeoutInterval: 10)
        urlRequest.httpMethod = "POST"
        urlRequest.setValue(key, forHTTPHeaderField: "X-goog-api-key")
        urlRequest.setValue("application/json", forHTTPHeaderField: "Content-Type")
        urlRequest.httpBody = try JSONSerialization.data(withJSONObject: body)

        let data: Data
        let response: HTTPURLResponse
        do {
            (data, response) = try await http.send(urlRequest)
        } catch {
            throw OnlineTranslationError.from(error)
        }
        switch response.statusCode {
        case 200..<300: break
        case 400 where String(decoding: data, as: UTF8.self).contains("API key not valid"):
            throw OnlineTranslationError.invalidKey
        case 401, 403: throw OnlineTranslationError.invalidKey
        case 429: throw OnlineTranslationError.quotaExceeded
        default: throw OnlineTranslationError.server(response.statusCode)
        }

        struct Response: Decodable {
            struct Payload: Decodable {
                struct Item: Decodable {
                    let translatedText: String
                    let detectedSourceLanguage: String?
                }
                let translations: [Item]
            }
            let data: Payload
        }
        guard let decoded = try? JSONDecoder().decode(Response.self, from: data), !decoded.data.translations.isEmpty
        else { throw OnlineTranslationError.badResponse }
        return TranslationResult(
            text: decoded.data.translations.map(\.translatedText).joined(separator: "\n\n"),
            source: decoded.data.translations.first?.detectedSourceLanguage ?? request.source,
            target: request.target
        )
    }

    static func code(_ language: String) -> String {
        switch language {
        case "zh", "zh-Hans": "zh-CN"
        case "zh-Hant", "zh-TW": "zh-TW"
        default: TranslationDirection.baseCode(language)
        }
    }
}
