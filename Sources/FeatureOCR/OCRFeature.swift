import AppKit
import Carbon.HIToolbox
import Core
import OSLog
import SwiftUI

/// Function 1 (TZ.md §5): select a screen area → recognize text → copy it.
public final class OCRFeature: Feature {
    public static let id: FeatureID = "ocr"

    private let context: AppContext
    private let log: Logger
    let settings: OCRSettings
    private let recognizer = TextRecognizer()
    private var isRunning = false

    public init(context: AppContext) {
        self.context = context
        log = context.logger(Self.id.rawValue)
        settings = OCRSettings(store: context.settings.scoped(Self.id))
    }

    public var title: String { String(localized: "feature.ocr.title") }
    public var icon: String { "text.viewfinder" }
    public var summary: String { String(localized: "feature.ocr.summary") }
    public var tint: Color { .blue }
    public var requiredPermissions: Set<Permission> { [.screenRecording] }

    public var actions: [FeatureAction] {
        [
            FeatureAction(
                id: "ocr.captureText",
                title: String(localized: "ocr.action.captureText"),
                defaultShortcut: Shortcut(kVK_ANSI_2, [.shift, .command])
            ) { [weak self] _ in
                guard let self else { return .none }
                return await captureText()
            },
            FeatureAction(id: "ocr.captureAndTranslate", title: String(localized: "ocr.action.captureAndTranslate")) { [weak self] _ in
                guard let self else { return .none }
                return await captureAndTranslate()
            },
            // For other features: text from an image (clipboard image translation, history menu).
            FeatureAction(
                id: "ocr.recognizeImage", title: String(localized: "ocr.action.recognizeImage"), isInternal: true,
                accepts: [.image], contentTitle: String(localized: "ocr.action.recognizeImage")
            ) { [weak self] input in
                guard let self, case .image(let image) = input else { return .none }
                return .text(try await recognize(image))
            },
        ]
    }

    public var settingsView: AnyView? {
        AnyView(OCRSettingsView(settings: settings))
    }

    /// Select → recognize → copy (or show the result window). Output: the text, for chains.
    func captureText() async -> ActionOutput {
        guard let text = await selectAndRecognize() else { return .none }
        if settings.showResultWindow {
            showResultWindow(text)
        } else {
            copy(text)
        }
        return .text(text)
    }

    /// TZ.md §5.6: select → recognize → show the translation window right away.
    func captureAndTranslate() async -> ActionOutput {
        guard let text = await selectAndRecognize() else { return .none }
        if settings.copyWhenTranslating { context.pasteboard.writeText(text) }
        do {
            try await context.actions.perform("translate.show", input: .text(text))
        } catch {
            // Translation is turned off: at least keep the text.
            copy(text)
            context.hud.show(String(localized: "ocr.hud.translateOff"), style: .info)
        }
        return .text(text)
    }

    /// Text (and code contents) of an image; empty when nothing is found.
    func recognize(_ image: CGImage) async throws -> String {
        async let codes = settings.codeMode == .off ? [] : CodeDetector.payloads(in: image)
        let lines = try await recognizer.recognize(image, languages: settings.languages, autoDetect: settings.autoDetectLanguage)
        let text = TextLayout.format(lines, mode: settings.lineMode)
        return CodeDetector.combine(codes: await codes, text: text, mode: settings.codeMode)
    }

    /// The shared part: area selection, recognition, HUD for errors / nothing found.
    private func selectAndRecognize() async -> String? {
        guard !isRunning else { return nil }
        isRunning = true
        defer { isRunning = false }

        let selection: AreaSelection
        do {
            guard let selected = try await context.areaSelection.selectArea(showMagnifier: settings.showMagnifier) else {
                return nil
            }
            selection = selected
        } catch {
            log.error("Screen capture failed: \(String(describing: error), privacy: .public)")
            context.permissions.request(.screenRecording)
            context.hud.show(String(localized: "ocr.hud.noPermission"), style: .error)
            return nil
        }

        let started = ContinuousClock.now
        let text: String
        do {
            text = try await recognize(selection.image)
        } catch {
            log.error("Recognition failed: \(String(describing: error), privacy: .public)")
            context.hud.show(String(localized: "ocr.hud.failed"), style: .error)
            return nil
        }
        let elapsed = ContinuousClock.now - started
        // Only sizes and timing are logged, never the text.
        log.notice("Recognized \(text.count) chars from \(selection.image.width)x\(selection.image.height) px in \(elapsed.formatted(.units(allowed: [.milliseconds])), privacy: .public)")

        guard !text.isEmpty else {
            context.hud.show(String(localized: "ocr.hud.notFound"), icon: "text.magnifyingglass", style: .info)
            return nil
        }
        return text
    }

    private func copy(_ text: String) {
        context.pasteboard.writeText(text)
        if settings.playSound { NSSound(named: "Tink")?.play() }
        let format = NSLocalizedString("ocr.hud.copied", comment: "")
        // The HUD truncates the preview itself; just keep it to one paragraph.
        let preview = text.split(whereSeparator: \.isNewline).first.map(String.init) ?? ""
        context.hud.show(String.localizedStringWithFormat(format, text.count), detail: String(preview.prefix(200)))
    }

    private func showResultWindow(_ text: String) {
        let model = OCRResultModel(text: text)
        context.panels.present(id: "ocr.result", size: CGSize(width: 480, height: 320), placement: .center) { handle in
            OCRResultView(model: model, handle: handle) { [weak self] edited in
                handle.close()
                self?.copy(edited)
            }
        }
    }
}
