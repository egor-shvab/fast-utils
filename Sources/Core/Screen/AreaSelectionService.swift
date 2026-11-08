import AppKit
import Carbon.HIToolbox

/// A selected screen area: the cropped image plus where it was (global AppKit points).
public struct AreaSelection: @unchecked Sendable {
    public let rect: CGRect
    public let image: CGImage
    public let scale: CGFloat
}

/// Screenshot-style area selection over a *frozen* snapshot of every screen, so menus and
/// tooltips that would vanish on mouse move can still be captured.
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
    /// Dragging selects a rectangle; a click selects the window under the pointer.
    public func selectArea(showMagnifier: Bool = true) async throws -> AreaSelection? {
        guard session == nil else { return nil }
        let snapshots = try await capture.captureAllScreens()
        let windows = Self.visibleWindowFrames()
        return await withCheckedContinuation { continuation in
            let session = SelectionSession(snapshots: snapshots, windows: windows, showMagnifier: showMagnifier) { [weak self] result in
                self?.session = nil
                continuation.resume(returning: result)
            }
            self.session = session
            session.begin()
        }
    }
}

extension AreaSelectionService {
    /// Frames of other apps' normal windows, front to back, in AppKit global coordinates.
    public static func visibleWindowFrames() -> [CGRect] {
        guard let list = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID)
            as? [[String: Any]],
            let primaryHeight = NSScreen.screens.first?.frame.height
        else { return [] }
        let ownPID = ProcessInfo.processInfo.processIdentifier
        return list.compactMap { info in
            guard (info[kCGWindowLayer as String] as? Int) == 0,
                  (info[kCGWindowOwnerPID as String] as? Int32) != ownPID,
                  (info[kCGWindowAlpha as String] as? Double ?? 1) > 0,
                  let bounds = info[kCGWindowBounds as String] as? NSDictionary,
                  let rect = CGRect(dictionaryRepresentation: bounds),
                  rect.width > 40, rect.height > 40
            else { return nil }
            return flipToAppKit(rect, primaryHeight: primaryHeight)
        }
    }

    /// Window Server rects have a top-left origin at the primary screen's top edge.
    static func flipToAppKit(_ rect: CGRect, primaryHeight: CGFloat) -> CGRect {
        CGRect(x: rect.minX, y: primaryHeight - rect.maxY, width: rect.width, height: rect.height)
    }
}

/// One selection run: an overlay window per screen.
@MainActor
private final class SelectionSession {
    private let snapshots: [ScreenSnapshot]
    private let windowFrames: [CGRect]
    private let showMagnifier: Bool
    private let completion: (AreaSelection?) -> Void
    private var windows: [OverlayWindow] = []
    private var finished = false

    init(snapshots: [ScreenSnapshot], windows: [CGRect], showMagnifier: Bool, completion: @escaping (AreaSelection?) -> Void) {
        self.snapshots = snapshots
        self.windowFrames = windows
        self.showMagnifier = showMagnifier
        self.completion = completion
    }

    func begin() {
        for snapshot in snapshots {
            let window = OverlayWindow(snapshot: snapshot)
            let view = OverlayView(snapshot: snapshot, windowFrames: windowFrames, showMagnifier: showMagnifier)
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

private final class OverlayView: NSView {
    var onFinish: ((CGRect) -> Void)?
    var onCancel: (() -> Void)?

    private let snapshot: ScreenSnapshot
    /// Other apps' windows (global coordinates), for click-to-select-window.
    private let windowFrames: [CGRect]
    private let showMagnifier: Bool
    private var anchor: CGPoint?
    private var current: CGPoint?
    private var movingWithSpace = false
    private var lastDragPoint: CGPoint?
    /// Pointer position in view coordinates (for the magnifier and window highlight).
    private var pointer: CGPoint?
    /// The window under the pointer while not dragging, in view coordinates.
    private var hoveredWindow: CGRect?

    init(snapshot: ScreenSnapshot, windowFrames: [CGRect], showMagnifier: Bool) {
        self.snapshot = snapshot
        self.windowFrames = windowFrames
        self.showMagnifier = showMagnifier
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

    override func mouseMoved(with event: NSEvent) {
        NSCursor.crosshair.set()
        let point = convert(event.locationInWindow, from: nil)
        pointer = point
        let global = CGPoint(x: point.x + snapshot.frame.minX, y: point.y + snapshot.frame.minY)
        hoveredWindow = windowFrames.first { $0.contains(global) }
            .map { $0.intersection(snapshot.frame).offsetBy(dx: -snapshot.frame.minX, dy: -snapshot.frame.minY) }
        needsDisplay = true
    }

    override func mouseExited(with event: NSEvent) {
        pointer = nil
        hoveredWindow = nil
        needsDisplay = true
    }

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
        pointer = point
        needsDisplay = true
    }

    override func mouseUp(with event: NSEvent) {
        guard let selection, selection.width >= 4, selection.height >= 4 else {
            // A click without dragging selects the window under the pointer.
            if let hoveredWindow, !hoveredWindow.isEmpty {
                onFinish?(hoveredWindow.offsetBy(dx: snapshot.frame.minX, dy: snapshot.frame.minY))
                return
            }
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

        // Dim everything except the selection (or the window under the pointer).
        let highlight = selection ?? (anchor == nil ? hoveredWindow : nil)
        let dim = NSBezierPath(rect: bounds)
        if let highlight { dim.append(NSBezierPath(rect: highlight)) }
        dim.windingRule = .evenOdd
        NSColor.black.withAlphaComponent(0.35).setFill()
        dim.fill()

        if let selection {
            NSColor.white.setStroke()
            let border = NSBezierPath(rect: selection.insetBy(dx: 0.5, dy: 0.5))
            border.lineWidth = 1
            border.stroke()
            drawSizeLabel(for: selection)
        } else if let highlight {
            NSColor.controlAccentColor.setStroke()
            let border = NSBezierPath(rect: highlight.insetBy(dx: 1, dy: 1))
            border.lineWidth = 2
            border.stroke()
        }
        if showMagnifier, let pointer { drawMagnifier(at: pointer, in: context) }
    }

    /// A zoomed view of the pixels around the pointer for precise selection.
    private func drawMagnifier(at point: CGPoint, in context: CGContext) {
        let side: CGFloat = 120
        var origin = CGPoint(x: point.x + 24, y: point.y - 24 - side)
        if origin.x + side > bounds.width { origin.x = point.x - 24 - side }
        if origin.y < 0 { origin.y = point.y + 24 }
        let box = CGRect(origin: origin, size: CGSize(width: side, height: side))
        // 15 points around the pointer → 8× zoom.
        let source = CGRect(x: point.x - 7.5, y: point.y - 7.5, width: 15, height: 15)
            .offsetBy(dx: snapshot.frame.minX, dy: snapshot.frame.minY)
        guard let crop = snapshot.crop(source) else { return }
        Magnifier.draw(crop, in: box, style: .selection, context: context)
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
