import AppKit
import Carbon.HIToolbox
import Core
import Observation
import OSLog
import SwiftUI

/// Screenshot with drawing: freeze the screen, select an area, draw, copy or save a PNG.
public final class ScreenshotFeature: Feature {
    public static let id: FeatureID = "screenshot"

    private let context: AppContext
    private let log: Logger
    let settings: ScreenshotSettings
    private var isRunning = false

    public init(context: AppContext) {
        self.context = context
        log = context.logger(Self.id.rawValue)
        settings = ScreenshotSettings(store: context.settings.scoped(Self.id))
    }

    public var title: String { String(localized: "feature.screenshot.title") }
    public var icon: String { "camera.viewfinder" }
    public var summary: String { String(localized: "feature.screenshot.summary") }
    public var tint: Color { .indigo }
    public var requiredPermissions: Set<Permission> { [.screenRecording, .pasteboard] }

    public var actions: [FeatureAction] {
        [
            FeatureAction(
                id: "screenshot.capture",
                title: String(localized: "screenshot.action.capture"),
                defaultShortcut: Shortcut(kVK_ANSI_2, [.shift, .command])
            ) { [weak self] _ in
                await self?.capture()
                return .none
            },
        ]
    }

    public var settingsView: AnyView? { AnyView(ScreenshotSettingsView(settings: settings)) }

    func capture() async {
        guard !isRunning else { return }
        isRunning = true
        defer { isRunning = false }

        let started = ContinuousClock.now
        let snapshots: [ScreenSnapshot]
        do {
            snapshots = try await context.screenCapture.captureAllScreens()
        } catch ScreenCaptureError.notPermitted {
            log.error("Screen capture: no Screen Recording permission")
            context.permissions.request(.screenRecording)
            context.hud.show(String(localized: "screenshot.hud.noPermission"), style: .error)
            return
        } catch {
            log.error("Screen capture failed: \(String(describing: error), privacy: .public)")
            context.hud.show(String(localized: "screenshot.hud.captureFailed"), style: .error)
            return
        }

        // Window frames before the overlays cover them (click-to-select-window).
        let document = EditorDocument(tool: settings.tool, color: settings.color, size: settings.size)
        let session = EditorSession(snapshots: snapshots, windowFrames: AreaSelectionService.visibleWindowFrames(), document: document)
        // The snapshot is most of the time to open; the overlays appear right after it.
        log.notice("Screenshot editor opened in \((ContinuousClock.now - started).formatted(.units(allowed: [.milliseconds])), privacy: .public)")
        let result = await session.run()
        settings.tool = document.tool
        settings.color = document.color
        settings.size = document.size

        switch result {
        case nil:
            return
        case .copy(let image):
            guard let png = ScreenshotExporter.pngData(image) else { return failed() }
            context.pasteboard.write(PasteboardSnapshot(image: png))
            log.notice("Screenshot copied, \(image.width)×\(image.height) px")
            context.hud.show(String(localized: "screenshot.hud.copied"))
        case .save(let image):
            guard let png = ScreenshotExporter.pngData(image) else { return failed() }
            let folder = settings.folderURL
            let url = ScreenshotExporter.uniqueURL(
                in: folder, baseName: ScreenshotExporter.baseName(for: Date(), format: String(localized: "screenshot.fileName"))
            )
            do {
                try png.write(to: url, options: .atomic)
                log.notice("Screenshot saved, \(image.width)×\(image.height) px")
                context.hud.show(String(localized: "screenshot.hud.saved"), detail: url.lastPathComponent)
            } catch {
                log.error("Saving a screenshot failed: \(String(describing: error), privacy: .public)")
                failed()
            }
        }
    }

    private func failed() {
        context.hud.show(String(localized: "screenshot.hud.saveFailed"), style: .error)
    }
}

/// Preferences, persisted under `screenshot.*`.
@MainActor
@Observable
final class ScreenshotSettings {
    /// Where "Save" puts the PNG; the Desktop by default.
    var folderPath: String { didSet { store.set(folderPath, for: "folder") } }
    // The last tool, color and size, so the next screenshot starts the same.
    var tool: Tool { didSet { store.set(tool.rawValue, for: "tool") } }
    var color: InkColor { didSet { store.set(color.rawValue, for: "color") } }
    var size: StrokeSize { didSet { store.set(size.rawValue, for: "size") } }

    @ObservationIgnored private let store: ScopedSettings

    static var desktop: URL {
        FileManager.default.urls(for: .desktopDirectory, in: .userDomainMask).first
            ?? FileManager.default.homeDirectoryForCurrentUser.appending(path: "Desktop")
    }

    init(store: ScopedSettings) {
        self.store = store
        folderPath = store.value("folder", default: Self.desktop.path)
        tool = Tool(rawValue: store.value("tool", default: "")) ?? .pen
        color = InkColor(rawValue: store.value("color", default: "")) ?? .red
        size = StrokeSize(rawValue: store.value("size", default: "")) ?? .medium
    }

    var folderURL: URL { URL(filePath: folderPath, directoryHint: .isDirectory) }
}

struct ScreenshotSettingsView: View {
    @Bindable var settings: ScreenshotSettings

    var body: some View {
        Group {
            Section {
                LabeledContent(String(localized: "screenshot.settings.folder")) {
                    HStack {
                        Text(FileManager.default.displayName(atPath: settings.folderPath))
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                            .truncationMode(.middle)
                            .help(settings.folderPath)
                        Button(String(localized: "screenshot.settings.choose"), action: chooseFolder)
                        Button(String(localized: "screenshot.settings.showInFinder")) {
                            NSWorkspace.shared.activateFileViewerSelecting([settings.folderURL])
                        }
                    }
                }
            } footer: {
                Text(String(localized: "screenshot.settings.footer"))
            }
        }
    }

    private func chooseFolder() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        panel.canCreateDirectories = true
        panel.directoryURL = settings.folderURL
        panel.prompt = String(localized: "screenshot.settings.choose")
        if panel.runModal() == .OK, let url = panel.url { settings.folderPath = url.path }
    }
}
