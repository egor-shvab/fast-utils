import Foundation
import SwiftUI

/// The last ~50 translations, so showing the same text again is instant.
@MainActor
final class TranslationCache {
    private struct Key: Hashable {
        let engine: String
        let text: String
        let source: String?
        let target: String
    }

    private var entries: [Key: TranslationResult] = [:]
    private var order: [Key] = []
    private let capacity: Int

    init(capacity: Int = 50) {
        self.capacity = capacity
    }

    func value(engine: String, request: TranslationRequest) -> TranslationResult? {
        entries[Key(engine: engine, text: request.text, source: request.source, target: request.target)]
    }

    func store(_ result: TranslationResult, engine: String, request: TranslationRequest) {
        let key = Key(engine: engine, text: request.text, source: request.source, target: request.target)
        if entries[key] == nil { order.append(key) }
        entries[key] = result
        while order.count > capacity { entries[order.removeFirst()] = nil }
    }

    var count: Int { entries.count }
}

/// The engine a window uses: the chosen one, with the cache in front and Apple as a fallback
/// when an online engine fails (no network, bad key, quota). Apple's host view is always in
/// the window so the fallback can run.
@MainActor
final class ResilientEngine: TranslationEngine {
    private let primary: (any TranslationEngine)?
    private let primaryError: OnlineTranslationError?
    private let apple: any TranslationEngine
    private let fallbackToApple: Bool
    private let cache: TranslationCache
    private let cacheKey: String

    /// - Parameters:
    ///   - primary: an online engine, or `nil` to use Apple directly.
    ///   - primaryError: why the online engine could not even be created (missing key).
    init(primary: (any TranslationEngine)?, primaryError: OnlineTranslationError? = nil, apple: any TranslationEngine,
         fallbackToApple: Bool, cache: TranslationCache, cacheKey: String) {
        self.primary = primary
        self.primaryError = primaryError
        self.apple = apple
        self.fallbackToApple = fallbackToApple
        self.cache = cache
        self.cacheKey = cacheKey
    }

    var name: String { primary?.name ?? apple.name }
    var hostView: AnyView? { apple.hostView }

    func prepare(source: String?, target: String) async throws {
        try await apple.prepare(source: source, target: target)
    }

    func translate(_ request: TranslationRequest) async throws -> TranslationResult {
        if let cached = cache.value(engine: cacheKey, request: request) { return cached }
        var result = try await translateUncached(request)
        if result.engineName == nil { result.engineName = name }
        cache.store(result, engine: cacheKey, request: request)
        return result
    }

    private func translateUncached(_ request: TranslationRequest) async throws -> TranslationResult {
        let failure: OnlineTranslationError
        if let primary {
            do {
                return try await primary.translate(request)
            } catch is CancellationError {
                throw CancellationError()
            } catch {
                failure = OnlineTranslationError.from(error)
            }
        } else if let primaryError {
            failure = primaryError
        } else {
            return try await apple.translate(request)
        }
        guard fallbackToApple else { throw failure }
        var result = try await apple.translate(request)
        result.engineName = apple.name
        result.fallbackReason = failure.message
        return result
    }
}
