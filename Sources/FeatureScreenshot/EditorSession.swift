import AppKit
import Core
import SwiftUI

enum EditorResult {
    case copy(CGImage)
    case save(CGImage)
}

/// One screenshot run: frozen overlays on every screen, area selection, then drawing with a
/// floating toolbar. Ends with an image to copy or save, or `nil` when cancelled.
@MainActor
final class EditorSession {
    let document: EditorDocument
    private let snapshots: [ScreenSnapshot]
    private let windowFrames: [CGRect]
    private var windows: [OverlayWindow] = []
    private var views: [EditorView] = []
    private var toolbar: ToolbarPanel?
    private var editingView: EditorView?
    private var continuation: CheckedContinuation<EditorResult?, Never>?

    init(snapshots: [ScreenSnapshot], windowFrames: [CGRect], document: EditorDocument) {
        self.snapshots = snapshots
        self.windowFrames = windowFrames
        self.document = document
    }

    func run() async -> EditorResult? {
        await withCheckedContinuation { continuation in
            self.continuation = continuation
            begin()
        }
    }

    private func begin() {
        for snapshot in snapshots {
            let window = OverlayWindow(snapshot: snapshot)
            let view = EditorView(snapshot: snapshot, windowFrames: windowFrames, document: document, session: self)
            window.contentView = view
            windows.append(window)
            views.append(view)
            window.orderFrontRegardless()
        }
        let mouse = NSEvent.mouseLocation
        let window = windows.first { NSMouseInRect(mouse, $0.frame, false) } ?? windows.first
        window?.makeKey()
        window?.makeFirstResponder(window?.contentView)
        NSCursor.crosshair.set()
    }

    /// The area is chosen on `view`'s screen: drawing starts there, other screens go quiet.
    func beginEditing(on view: EditorView, rect: CGRect) {
        editingView = view
        document.selection = rect
        for other in views where other !== view { other.phase = .inactive }
        view.phase = .editing
        view.window?.makeKey()
        view.window?.makeFirstResponder(view)
        showToolbar(near: rect, on: view)
    }

    private func showToolbar(near rect: CGRect, on view: EditorView) {
        guard let screenFrame = view.window?.frame else { return }
        var panel: ToolbarPanel?
        var dragStart: (origin: CGPoint, mouse: CGPoint)?
        let actions = ToolbarActions(
            copy: { [weak self] in self?.finish(.copy) },
            save: { [weak self] in self?.finish(.save) },
            close: { [weak self] in self?.finish(nil) },
            dragChanged: {
                guard let panel else { return }
                let mouse = NSEvent.mouseLocation
                let start = dragStart ?? (panel.frame.origin, mouse)
                dragStart = start
                panel.setFrameOrigin(CGPoint(x: start.origin.x + mouse.x - start.mouse.x, y: start.origin.y + mouse.y - start.mouse.y))
            },
            dragEnded: { dragStart = nil }
        )
        let created = ToolbarPanel(content: ToolbarView(document: document, actions: actions))
        panel = created
        let global = rect.offsetBy(dx: screenFrame.minX, dy: screenFrame.minY)
        created.setFrameOrigin(EditorGeometry.toolbarOrigin(for: global, size: created.frame.size, in: screenFrame))
        created.orderFrontRegardless()
        toolbar = created
    }

    enum Action { case copy, save }

    func finish(_ action: Action?) {
        guard let continuation else { return }
        self.continuation = nil
        editingView?.commitText()
        var result: EditorResult?
        if let action, let view = editingView, let rect = document.selection,
           let image = ScreenshotExporter.render(snapshot: view.snapshot, rect: rect, annotations: document.annotations) {
            result = action == .copy ? .copy(image) : .save(image)
        }
        toolbar?.orderOut(nil)
        toolbar = nil
        windows.forEach { $0.orderOut(nil) }
        windows.removeAll()
        views.removeAll()
        editingView = nil
        NSCursor.arrow.set()
        continuation.resume(returning: result)
    }
}
