import AppKit
import Carbon.HIToolbox

/// A selected screen area: the cropped image plus where it was (global AppKit points).
public struct AreaSelection: @unchecked Sendable {
    public let rect: CGRect
    public let image: CGImage
    public let scale: CGFloat
}

/// Screenshot-style area selection over a *frozen* snapshot of every screen, so menus and
/// tooltips that would vanish on mouse move can still be captured (TZ.md §5.1).
/// Reusable by future features (color picker, screenshots).
@MainActor
public final class AreaSelectionService {
    private let capture: ScreenCaptureService
    private var session: SelectionSession?

    public init(capture: ScreenCaptureService = ScreenCaptureService()) {
        self.capture = capture
    }

    public var isSelecting: Bool { session != nil }

    /// Returns `nil` when the user cancels (Esc / right click) or a selection is already running.
    public func selectArea() async throws -> AreaSelection? {
        guard session == nil else { return nil }
        let snapshots = try await capture.captureAllScreens()
        return await withCheckedContinuation { continuation in
            let session = SelectionSession(snapshots: snapshots) { [weak self] result in
                self?.session = nil
                continuation.resume(returning: result)
            }
            self.session = session
            session.begin()
        }
    }
}

/// One selection run: an overlay window per screen.
@MainActor
private final class SelectionSession {
    private let snapshots: [ScreenSnapshot]
    private let completion: (AreaSelection?) -> Void
    private var windows: [OverlayWindow] = []
    private var finished = false

    init(snapshots: [ScreenSnapshot], completion: @escaping (AreaSelection?) -> Void) {
        self.snapshots = snapshots
        self.completion = completion
    }

    func begin() {
        for snapshot in snapshots {
            let window = OverlayWindow(snapshot: snapshot)
            let view = OverlayView(snapshot: snapshot)
            view.onFinish = { [weak self] rect in self?.finish(snapshot: snapshot, rect: rect) }
            view.onCancel = { [weak self] in self?.finish(snapshot: nil, rect: nil) }
            window.contentView = view
            windows.append(window)
            window.orderFrontRegardless()
        }
        let mouse = NSEvent.mouseLocation
        (windows.first { NSMouseInRect(mouse, $0.frame, false) } ?? windows.first)?.makeKey()
        NSCursor.crosshair.set()
    }

    private func finish(snapshot: ScreenSnapshot?, rect: CGRect?) {
        guard !finished else { return }
        finished = true
        windows.forEach { $0.orderOut(nil) }
        windows.removeAll()
        NSCursor.arrow.set()
        guard let snapshot, let rect, let image = snapshot.crop(rect) else {
            completion(nil)
            return
        }
        completion(AreaSelection(rect: rect, image: image, scale: snapshot.scale))
    }
}

private final class OverlayWindow: NSPanel {
    init(snapshot: ScreenSnapshot) {
        super.init(contentRect: snapshot.frame, styleMask: [.borderless, .nonactivatingPanel],
                   backing: .buffered, defer: false)
        level = .screenSaver
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
        isOpaque = true
        backgroundColor = .black
        hasShadow = false
        hidesOnDeactivate = false
        acceptsMouseMovedEvents = true
        animationBehavior = .none
        setFrame(snapshot.frame, display: false)
    }

    override var canBecomeKey: Bool { true }
}

private final class OverlayView: NSView {
    var onFinish: ((CGRect) -> Void)?
    var onCancel: (() -> Void)?

    private let snapshot: ScreenSnapshot
    private var anchor: CGPoint?
    private var current: CGPoint?
    private var movingWithSpace = false
    private var lastDragPoint: CGPoint?

    init(snapshot: ScreenSnapshot) {
        self.snapshot = snapshot
        super.init(frame: CGRect(origin: .zero, size: snapshot.frame.size))
    }

    required init?(coder: NSCoder) { fatalError() }

    override var acceptsFirstResponder: Bool { true }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        trackingAreas.forEach(removeTrackingArea)
        addTrackingArea(NSTrackingArea(rect: bounds, options: [.mouseMoved, .mouseEnteredAndExited, .activeAlways, .inVisibleRect, .cursorUpdate], owner: self))
    }

    override func cursorUpdate(with event: NSEvent) { NSCursor.crosshair.set() }

    override func mouseEntered(with event: NSEvent) {
        // Keep the screen under the pointer key, so Esc works on any monitor.
        window?.makeKey()
        NSCursor.crosshair.set()
    }

    override func mouseMoved(with event: NSEvent) { NSCursor.crosshair.set() }

    private var selection: CGRect? {
        guard let anchor, let current else { return nil }
        return CGRect(x: min(anchor.x, current.x), y: min(anchor.y, current.y),
                      width: abs(current.x - anchor.x), height: abs(current.y - anchor.y)).integral
    }

    override func mouseDown(with event: NSEvent) {
        window?.makeKey()
        let point = convert(event.locationInWindow, from: nil)
        anchor = point
        current = point
        lastDragPoint = point
        needsDisplay = true
    }

    override func mouseDragged(with event: NSEvent) {
        let point = clamp(convert(event.locationInWindow, from: nil))
        if movingWithSpace, let last = lastDragPoint, let anchor {
            // Space held: move the whole rectangle instead of resizing it.
            self.anchor = CGPoint(x: anchor.x + point.x - last.x, y: anchor.y + point.y - last.y)
        }
        current = point
        lastDragPoint = point
        needsDisplay = true
    }

    override func mouseUp(with event: NSEvent) {
        guard let selection, selection.width >= 4, selection.height >= 4 else {
            // A click without dragging: keep waiting for a real selection.
            anchor = nil
            current = nil
            needsDisplay = true
            return
        }
        onFinish?(selection.offsetBy(dx: snapshot.frame.minX, dy: snapshot.frame.minY))
    }

    override func rightMouseDown(with event: NSEvent) { onCancel?() }

    override func keyDown(with event: NSEvent) {
        switch Int(event.keyCode) {
        case kVK_Escape: onCancel?()
        case kVK_Space: movingWithSpace = true
        default: break
        }
    }

    override func keyUp(with event: NSEvent) {
        if Int(event.keyCode) == kVK_Space { movingWithSpace = false }
    }

    private func clamp(_ point: CGPoint) -> CGPoint {
        CGPoint(x: min(max(point.x, 0), bounds.width), y: min(max(point.y, 0), bounds.height))
    }

    override func draw(_ dirtyRect: NSRect) {
        guard let context = NSGraphicsContext.current?.cgContext else { return }
        context.interpolationQuality = .high
        context.draw(snapshot.image, in: bounds)

        // Dim everything except the selection.
        let dim = NSBezierPath(rect: bounds)
        if let selection { dim.append(NSBezierPath(rect: selection)) }
        dim.windingRule = .evenOdd
        NSColor.black.withAlphaComponent(0.35).setFill()
        dim.fill()

        guard let selection else { return }
        NSColor.white.setStroke()
        let border = NSBezierPath(rect: selection.insetBy(dx: 0.5, dy: 0.5))
        border.lineWidth = 1
        border.stroke()
        drawSizeLabel(for: selection)
    }

    private func drawSizeLabel(for selection: CGRect) {
        let text = "\(Int(selection.width)) × \(Int(selection.height))" as NSString
        let attributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.monospacedDigitSystemFont(ofSize: 12, weight: .medium),
            .foregroundColor: NSColor.white,
        ]
        let size = text.size(withAttributes: attributes)
        var origin = CGPoint(x: selection.minX, y: selection.minY - size.height - 10)
        if origin.y < 4 { origin.y = selection.maxY + 6 }
        origin.x = min(max(origin.x, 4), bounds.width - size.width - 16)
        let background = CGRect(x: origin.x, y: origin.y, width: size.width + 12, height: size.height + 4)
        NSColor.black.withAlphaComponent(0.7).setFill()
        NSBezierPath(roundedRect: background, xRadius: 4, yRadius: 4).fill()
        text.draw(at: CGPoint(x: origin.x + 6, y: origin.y + 2), withAttributes: attributes)
    }
}
