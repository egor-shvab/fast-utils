import AppKit
import Carbon.HIToolbox
import OSLog

/// A color picker over a *frozen* snapshot of every screen: a loupe next to the pointer with the
/// value shown below it. Click, Return or Space picks; Esc or right click cancels; arrows move
/// by one physical pixel (⇧ by ten).
@MainActor
public final class ColorPickerService {
    private let capture: ScreenCaptureService
    private var session: PickerSession?
    private let log = Logger(subsystem: AppInfo.bundleIdentifier, category: "colorPicker")

    public init(capture: ScreenCaptureService = ScreenCaptureService()) {
        self.capture = capture
    }

    public var isPicking: Bool { session != nil }

    /// `nil` when the user cancels or a picker is already open.
    /// - Parameter label: the text under the loupe for a color (the format the user copies).
    public func pickColor(label: @escaping (RGBColor) -> String) async throws -> RGBColor? {
        guard session == nil else { return nil }
        let started = ContinuousClock.now
        let snapshots = try await capture.captureAllScreens()
        return await withCheckedContinuation { continuation in
            let session = PickerSession(snapshots: snapshots, label: label) { [weak self] color in
                self?.session = nil
                continuation.resume(returning: color)
            }
            self.session = session
            session.begin()
            // The goal is < 200 ms, like the OCR overlay.
            log.notice("Color picker opened in \((ContinuousClock.now - started).formatted(.units(allowed: [.milliseconds])), privacy: .public)")
        }
    }
}

/// Keyboard commands of the picker; a pure function so it is testable.
enum PickerCommand: Equatable {
    case pick, cancel
    case move(dx: Int, dy: Int)

    static func from(keyCode: Int, shift: Bool) -> PickerCommand? {
        let step = shift ? 10 : 1
        switch keyCode {
        case kVK_Escape: return .cancel
        case kVK_Return, kVK_ANSI_KeypadEnter, kVK_Space: return .pick
        // Pixel rows have a top-left origin: up is −y.
        case kVK_UpArrow: return .move(dx: 0, dy: -step)
        case kVK_DownArrow: return .move(dx: 0, dy: step)
        case kVK_LeftArrow: return .move(dx: -step, dy: 0)
        case kVK_RightArrow: return .move(dx: step, dy: 0)
        default: return nil
        }
    }
}

/// Where the picker draws its loupe; pure, so it is testable.
enum PickerLayout {
    /// The loupe beside the pointer, never over it: below-right, flipped left or up near the
    /// screen edges, with room for the label under it.
    static func loupeFrame(pointer: CGPoint, side: CGFloat, labelHeight: CGFloat, in bounds: CGRect) -> CGRect {
        let gap: CGFloat = 20
        var x = pointer.x + gap
        if x + side > bounds.maxX { x = pointer.x - gap - side }
        // AppKit y grows upward: "below the pointer" is a smaller y.
        var y = pointer.y - gap - side
        if y - labelHeight < bounds.minY { y = pointer.y + gap + labelHeight }
        return CGRect(x: x, y: y, width: side, height: side)
    }

}

@MainActor
private final class PickerSession {
    private let snapshots: [ScreenSnapshot]
    private let label: (RGBColor) -> String
    private let completion: (RGBColor?) -> Void
    private var windows: [OverlayWindow] = []
    private var views: [PickerView] = []
    private var finished = false

    init(snapshots: [ScreenSnapshot], label: @escaping (RGBColor) -> String, completion: @escaping (RGBColor?) -> Void) {
        self.snapshots = snapshots
        self.label = label
        self.completion = completion
    }

    func begin() {
        let mouse = NSEvent.mouseLocation
        for snapshot in snapshots {
            let window = OverlayWindow(snapshot: snapshot)
            let view = PickerView(snapshot: snapshot, label: label)
            view.onPick = { [weak self] color in self?.finish(color) }
            view.onCancel = { [weak self] in self?.finish(nil) }
            view.onActivate = { [weak self, weak view] in
                // Only one loupe at a time: the screen with the pointer.
                self?.views.filter { $0 !== view }.forEach { $0.pixel = nil }
            }
            window.contentView = view
            windows.append(window)
            views.append(view)
            window.orderFrontRegardless()
            if NSMouseInRect(mouse, snapshot.frame, false) { view.pixel = snapshot.pixel(at: mouse) }
        }
        (windows.first { NSMouseInRect(mouse, $0.frame, false) } ?? windows.first)?.makeKey()
        NSCursor.crosshair.set()
    }

    private func finish(_ color: RGBColor?) {
        guard !finished else { return }
        finished = true
        windows.forEach { $0.orderOut(nil) }
        windows.removeAll()
        views.removeAll()
        NSCursor.arrow.set()
        completion(color)
    }
}

private final class PickerView: NSView {
    static let pixelsAcross = 11
    static let cellSize: CGFloat = 12

    var onPick: ((RGBColor) -> Void)?
    var onCancel: (() -> Void)?
    var onActivate: (() -> Void)?
    /// The sampled pixel on this screen; `nil` while the pointer is on another one.
    var pixel: PixelPoint? { didSet { if pixel != oldValue { needsDisplay = true } } }

    private let snapshot: ScreenSnapshot
    private let label: (RGBColor) -> String

    init(snapshot: ScreenSnapshot, label: @escaping (RGBColor) -> String) {
        self.snapshot = snapshot
        self.label = label
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
        // Keep the screen under the pointer key, so the keys work on any monitor.
        window?.makeKey()
        NSCursor.crosshair.set()
        track(event)
    }

    override func mouseMoved(with event: NSEvent) {
        NSCursor.crosshair.set()
        track(event)
    }

    override func mouseDown(with event: NSEvent) {
        track(event)
        pick()
    }

    override func rightMouseDown(with event: NSEvent) { onCancel?() }

    override func keyDown(with event: NSEvent) {
        switch PickerCommand.from(keyCode: Int(event.keyCode), shift: event.modifierFlags.contains(.shift)) {
        case .pick: pick()
        case .cancel: onCancel?()
        case .move(let dx, let dy):
            guard let pixel else { return }
            let moved = pixel.moved(dx: dx, dy: dy, within: snapshot.pixelSize)
            self.pixel = moved
            warpPointer(to: snapshot.point(ofPixel: moved))
        case nil: break
        }
    }

    private func track(_ event: NSEvent) {
        let local = convert(event.locationInWindow, from: nil)
        pixel = snapshot.pixel(at: CGPoint(x: local.x + snapshot.frame.minX, y: local.y + snapshot.frame.minY))
        onActivate?()
    }

    private func pick() {
        guard let pixel, let color = snapshot.color(atPixel: pixel) else { return }
        onPick?(color)
    }

    /// Moves the real pointer with the arrows, so the next mouse move continues
    /// from there instead of jumping back.
    private func warpPointer(to point: CGPoint) {
        guard let primaryHeight = NSScreen.screens.first?.frame.height else { return }
        CGWarpMouseCursorPosition(CGPoint(x: point.x, y: primaryHeight - point.y))
        CGAssociateMouseAndMouseCursorPosition(1)
    }

    override func draw(_ dirtyRect: NSRect) {
        guard let context = NSGraphicsContext.current?.cgContext else { return }
        // No dimming: it would change the colors being picked.
        context.interpolationQuality = .high
        context.draw(snapshot.image, in: bounds)
        guard let pixel, let zoomed = snapshot.pixels(around: pixel, count: Self.pixelsAcross) else { return }

        let center = snapshot.point(ofPixel: pixel)
        let local = CGPoint(x: center.x - snapshot.frame.minX, y: center.y - snapshot.frame.minY)
        let side = CGFloat(Self.pixelsAcross) * Self.cellSize
        let box = PickerLayout.loupeFrame(pointer: local, side: side, labelHeight: Self.labelHeight, in: bounds)
        Magnifier.draw(zoomed, in: box, style: .pixelGrid(count: Self.pixelsAcross), context: context)
        if let color = snapshot.color(atPixel: pixel) { drawLabel(for: color, below: box) }
    }

    static let labelHeight: CGFloat = 32

    /// A swatch and the value under the loupe.
    private func drawLabel(for color: RGBColor, below box: CGRect) {
        let text = label(color) as NSString
        let attributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.monospacedSystemFont(ofSize: 12, weight: .medium),
            .foregroundColor: NSColor.white,
        ]
        let textSize = text.size(withAttributes: attributes)
        let swatch: CGFloat = 12
        let size = CGSize(width: 8 + swatch + 6 + textSize.width + 10, height: max(textSize.height, swatch) + 8)
        var origin = CGPoint(x: box.midX - size.width / 2, y: box.minY - size.height - 8)
        if origin.y < 4 { origin.y = box.maxY + 8 }
        origin.x = min(max(origin.x, 4), bounds.width - size.width - 4)
        let background = CGRect(origin: origin, size: size)
        NSColor.black.withAlphaComponent(0.75).setFill()
        NSBezierPath(roundedRect: background, xRadius: 6, yRadius: 6).fill()

        let dot = CGRect(x: origin.x + 8, y: background.midY - swatch / 2, width: swatch, height: swatch)
        color.nsColor.setFill()
        NSBezierPath(ovalIn: dot).fill()
        NSColor.white.withAlphaComponent(0.8).setStroke()
        NSBezierPath(ovalIn: dot).stroke()
        text.draw(at: CGPoint(x: dot.maxX + 6, y: background.midY - textSize.height / 2), withAttributes: attributes)
    }
}
