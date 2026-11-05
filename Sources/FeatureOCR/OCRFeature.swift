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
        ]
    }

    public var settingsView: AnyView? {
        AnyView(OCRSettingsView(settings: settings))
    }

    /// Select → recognize → copy (or show the result window). Output: the text, for chains.
    func captureText() async -> ActionOutput {
        guard !isRunning else { return .none }
        isRunning = true
        defer { isRunning = false }

        let selection: AreaSelection
        do {
            guard let selected = try await context.areaSelection.selectArea() else { return .none }
            selection = selected
        } catch {
            log.error("Screen capture failed: \(String(describing: error), privacy: .public)")
            context.permissions.request(.screenRecording)
            context.hud.show(String(localized: "ocr.hud.noPermission"), style: .error)
            return .none
        }

        let started = ContinuousClock.now
        let text: String
        do {
            let lines = try await recognizer.recognize(
                selection.image, languages: settings.languages, autoDetect: settings.autoDetectLanguage
            )
            text = TextLayout.format(lines, mode: settings.lineMode)
        } catch {
            log.error("Recognition failed: \(String(describing: error), privacy: .public)")
            context.hud.show(String(localized: "ocr.hud.failed"), style: .error)
            return .none
        }
        let elapsed = ContinuousClock.now - started
        // Only sizes and timing are logged, never the text.
        log.notice("Recognized \(text.count) chars from \(selection.image.width)x\(selection.image.height) px in \(elapsed.formatted(.units(allowed: [.milliseconds])), privacy: .public)")

        guard !text.isEmpty else {
            context.hud.show(String(localized: "ocr.hud.notFound"), icon: "text.magnifyingglass", style: .info)
            return .none
        }

        if settings.showResultWindow {
            showResultWindow(text)
        } else {
            copy(text)
        }
        return .text(text)
    }

    private func copy(_ text: String) {
        context.pasteboard.writeText(text)
        if settings.playSound { NSSound(named: "Tink")?.play() }
        let format = NSLocalizedString("ocr.hud.copied", comment: "")
        let preview = text.split(whereSeparator: \.isNewline).first.map(String.init) ?? ""
        let shortPreview = preview.count > 60 ? String(preview.prefix(60)) + "…" : preview
        context.hud.show(String.localizedStringWithFormat(format, text.count) + "\n" + shortPreview)
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
