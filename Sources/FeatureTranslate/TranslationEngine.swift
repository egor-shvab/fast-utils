import Combine
import Foundation
import SwiftUI
import Translation

struct TranslationRequest: Sendable, Equatable {
    var text: String
    /// `nil` = let the engine detect it.
    var source: String?
    var target: String
}

struct TranslationResult: Sendable, Equatable {
    var text: String
    var source: String?
    var target: String
    /// Which engine actually translated (set by `ResilientEngine`).
    var engineName: String?
    /// Why the chosen online engine was not used, when Apple stepped in.
    var fallbackReason: String?
}

/// A translation backend: Apple Translation, DeepL or Google.
@MainActor
protocol TranslationEngine: AnyObject {
    var name: String { get }
    /// A view the window must contain for the engine to work (Apple needs a SwiftUI host).
    var hostView: AnyView? { get }
    func translate(_ request: TranslationRequest) async throws -> TranslationResult
    /// Download language data if needed (Apple). Engines without local data do nothing.
    func prepare(source: String?, target: String) async throws
}

/// Apple's on-device Translation framework.
///
/// On macOS 15 a `TranslationSession` exists only inside SwiftUI's `.translationTask`. So the
/// engine is a bridge: a request sets `configuration`; the invisible `AppleTranslationHost`
/// in the window runs the task, takes the pending text, translates and resumes the caller.
/// The session never leaves the task closure, which keeps Swift 6 concurrency checks happy.
@MainActor
final class AppleTranslationEngine: ObservableObject, TranslationEngine {
    @Published fileprivate var configuration: TranslationSession.Configuration?

    private enum Job {
        case translate(String)
        case prepare
    }
    private var pending: (job: Job, continuation: CheckedContinuation<TranslationResult?, Error>)?

    var name: String { String(localized: "translate.engine.apple") }
    var hostView: AnyView? { AnyView(AppleTranslationHost(engine: self)) }

    func translate(_ request: TranslationRequest) async throws -> TranslationResult {
        guard let result = try await run(.translate(request.text), source: request.source, target: request.target) else {
            throw TranslationError.internalError
        }
        return result
    }

    func prepare(source: String?, target: String) async throws {
        _ = try await run(.prepare, source: source, target: target)
    }

    private func run(_ job: Job, source: String?, target: String) async throws -> TranslationResult? {
        pending?.continuation.resume(throwing: CancellationError())
        return try await withCheckedThrowingContinuation { continuation in
            pending = (job, continuation)
            let wanted = TranslationSession.Configuration(
                source: source.map { Locale.Language(identifier: $0) },
                target: Locale.Language(identifier: target)
            )
            if configuration?.source == wanted.source, configuration?.target == wanted.target {
                configuration?.invalidate()  // same languages: re-run the task
            } else {
                configuration = wanted
            }
        }
    }

    /// Called from the task: what to do now. `nil` text means "prepare".
    fileprivate func takeJob() -> (text: String?, isPrepare: Bool)? {
        guard let pending else { return nil }
        switch pending.job {
        case .translate(let text): return (text, false)
        case .prepare: return (nil, true)
        }
    }

    fileprivate func finish(_ result: Result<TranslationResult?, Error>) {
        let continuation = pending?.continuation
        pending = nil
        continuation?.resume(with: result)
    }
}

/// Invisible host for `.translationTask`; must be inside the translation window. If language
/// data is missing, the system shows its download prompt attached to this window.
private struct AppleTranslationHost: View {
    @ObservedObject var engine: AppleTranslationEngine

    var body: some View {
        Color.clear
            .frame(width: 0, height: 0)
            .translationTask(engine.configuration) { @Sendable [engine] session in
                guard let job = await engine.takeJob() else { return }
                do {
                    if job.isPrepare {
                        try await session.prepareTranslation()
                        await engine.finish(.success(nil))
                    } else if let text = job.text {
                        let response = try await session.translate(text)
                        await engine.finish(.success(TranslationResult(
                            text: response.targetText,
                            source: response.sourceLanguage.minimalIdentifier,
                            target: response.targetLanguage.minimalIdentifier
                        )))
                    }
                } catch {
                    await engine.finish(.failure(error))
                }
            }
    }
}

/// Languages Apple Translation supports, as short identifiers, sorted by display name.
enum AppleLanguages {
    static func supported() async -> [String] {
        let languages = await LanguageAvailability().supportedLanguages.map(\.minimalIdentifier)
        return Array(Set(languages)).sorted { TranslationDirection.displayName($0) < TranslationDirection.displayName($1) }
    }
}
