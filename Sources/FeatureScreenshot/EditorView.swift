import AppKit
import Carbon.HIToolbox
import Combine
import Core

/// The overlay of one screen: area selection, then drawing inside the area.
@MainActor
final class EditorView: NSView, NSTextFieldDelegate {
    enum Phase { case selecting, editing, inactive }

    let snapshot: ScreenSnapshot
    var phase: Phase = .selecting { didSet { needsDisplay = true } }

    private let windowFrames: [CGRect]
    private let document: EditorDocument
    private weak var session: EditorSession?
    private var observation: AnyCancellable?

    // Selecting.
    private var anchor: CGPoint?
    private var current: CGPoint?
    private var pointer: CGPoint?
    private var hoveredWindow: CGRect?

    // Editing.
    private enum Drag {
        case drawing(start: CGPoint, annotation: Annotation)
        case resizing(Handle, original: CGRect)
        case moving(last: CGPoint)
        /// A caption follows the pointer; `current` is drawn, the document gets it on mouse up.
        case movingText(index: Int, original: Annotation, start: CGPoint, current: Annotation)
        case scalingText(index: Int, original: Annotation, current: Annotation)
    }
    private var drag: Drag?
    private var textField: NSTextField?
    /// The caption being edited in `textField`; `nil` for a new one.
    private var editingIndex: Int?

    init(snapshot: ScreenSnapshot, windowFrames: [CGRect], document: EditorDocument, session: EditorSession) {
        self.snapshot = snapshot
        self.windowFrames = windowFrames
        self.document = document
        self.session = session
        super.init(frame: CGRect(origin: .zero, size: snapshot.frame.size))
        // Undo/redo from the toolbar change the document: redraw.
        observation = document.objectWillChange.sink { [weak self] _ in self?.needsDisplay = true }
    }

    required init?(coder: NSCoder) { fatalError() }

    override var acceptsFirstResponder: Bool { true }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        trackingAreas.forEach(removeTrackingArea)
        addTrackingArea(NSTrackingArea(rect: bounds, options: [.mouseMoved, .mouseEnteredAndExited, .activeAlways, .inVisibleRect, .cursorUpdate], owner: self))
    }

    // MARK: Cursor

    override func cursorUpdate(with event: NSEvent) { updateCursor(at: convert(event.locationInWindow, from: nil)) }

    private func updateCursor(at point: CGPoint) {
        cursor(at: point).set()
    }

    /// Crosshair while selecting; over the area: resize on its edges, then by tool. Outside the
    /// area nothing can be drawn (it would be cut), so the plain arrow.
    private func cursor(at point: CGPoint) -> NSCursor {
        guard phase == .editing, let selection = document.selection else { return .crosshair }
        if let edge = EditorGeometry.edge(at: point, of: selection) { return edge.cursor }
        if document.tool.grabsText {
            if let frame = selectedTextFrame, EditorGeometry.isOnTextHandle(point, bounds: frame) {
                return Handle.bottomRight.cursor
            }
            if EditorGeometry.textIndex(at: point, in: document.annotations) != nil { return .openHand }
        }
        guard selection.contains(point) else { return .arrow }
        switch document.tool {
        case .move: return .openHand
        case .pen: return Self.brushCursor(color: document.color, size: document.size)
        case .arrow, .ellipse, .rectangle: return .crosshair
        case .text: return .iBeam
        }
    }

    private static var brushCursors: [String: NSCursor] = [:]

    /// A dot of the brush's color and width, outlined black and white so it shows on any
    /// background.
    static func brushCursor(color: InkColor, size: StrokeSize) -> NSCursor {
        let key = "\(color.rawValue).\(size.rawValue)"
        if let cached = brushCursors[key] { return cached }
        let diameter = max(size.lineWidth, 4)
        let side = ceil(diameter + 6)
        let image = NSImage(size: NSSize(width: side, height: side), flipped: false) { rect in
            let dot = CGRect(x: (rect.width - diameter) / 2, y: (rect.height - diameter) / 2, width: diameter, height: diameter)
            color.nsColor.setFill()
            NSBezierPath(ovalIn: dot).fill()
            NSColor.white.setStroke()
            let inner = NSBezierPath(ovalIn: dot.insetBy(dx: -1, dy: -1))
            inner.lineWidth = 1
            inner.stroke()
            NSColor.black.withAlphaComponent(0.7).setStroke()
            let outer = NSBezierPath(ovalIn: dot.insetBy(dx: -2, dy: -2))
            outer.lineWidth = 1
            outer.stroke()
            return true
        }
        let cursor = NSCursor(image: image, hotSpot: NSPoint(x: side / 2, y: side / 2))
        brushCursors[key] = cursor
        return cursor
    }

    // MARK: Mouse

    override func mouseEntered(with event: NSEvent) {
        // During selection the screen under the pointer is key, so Esc works on any monitor.
        if phase == .selecting { window?.makeKey() }
        updateCursor(at: convert(event.locationInWindow, from: nil))
    }

    override func mouseMoved(with event: NSEvent) {
        let point = convert(event.locationInWindow, from: nil)
        updateCursor(at: point)
        guard phase == .selecting else { return }
        pointer = point
        let global = CGPoint(x: point.x + snapshot.frame.minX, y: point.y + snapshot.frame.minY)
        hoveredWindow = windowFrames.first { $0.contains(global) }
            .map { $0.intersection(snapshot.frame).offsetBy(dx: -snapshot.frame.minX, dy: -snapshot.frame.minY) }
        needsDisplay = true
    }

    override func mouseExited(with event: NSEvent) {
        guard phase == .selecting else { return }
        pointer = nil
        hoveredWindow = nil
        needsDisplay = true
    }

    override func mouseDown(with event: NSEvent) {
        let point = convert(event.locationInWindow, from: nil)
        switch phase {
        case .inactive:
            return
        case .selecting:
            window?.makeKey()
            anchor = point
            current = point
        case .editing:
            // A click outside the text being typed finishes it.
            if textField != nil {
                commitText()
                if document.tool == .text { return }
            }
            guard let selection = document.selection else { return }
            if let edge = EditorGeometry.edge(at: point, of: selection) {
                drag = .resizing(edge, original: selection)
                edge.cursor.set()
                return
            }
            if document.tool.grabsText, grabText(at: point, clickCount: event.clickCount) {
                needsDisplay = true
                return
            }
            // Outside the area nothing can be drawn: it would be cut away invisibly.
            guard selection.contains(point) else { return }
            let annotation: (Annotation.Shape) -> Annotation = { [document] in
                Annotation(shape: $0, color: document.color, size: document.size)
            }
            switch document.tool {
            case .move:
                drag = .moving(last: point)
                NSCursor.closedHand.set()
            case .text:
                beginText(at: point)
            case .pen:
                drag = .drawing(start: point, annotation: annotation(.pen([point])))
            case .arrow:
                drag = .drawing(start: point, annotation: annotation(.arrow(from: point, to: point)))
            case .ellipse:
                drag = .drawing(start: point, annotation: annotation(.ellipse(CGRect(origin: point, size: .zero))))
            case .rectangle:
                drag = .drawing(start: point, annotation: annotation(.rectangle(CGRect(origin: point, size: .zero))))
            }
        }
        needsDisplay = true
    }

    override func mouseDragged(with event: NSEvent) {
        let point = clamp(convert(event.locationInWindow, from: nil))
        let shift = event.modifierFlags.contains(.shift)
        switch phase {
        case .inactive:
            return
        case .selecting:
            current = point
            pointer = point
        case .editing:
            guard let drag else { return }
            switch drag {
            case .resizing(let handle, let original):
                document.selection = EditorGeometry.resize(original, handle: handle, to: point, bounds: bounds)
            case .moving(let last):
                if let selection = document.selection {
                    document.selection = EditorGeometry.move(selection, by: CGVector(dx: point.x - last.x, dy: point.y - last.y), within: bounds)
                }
                self.drag = .moving(last: point)
            case .movingText(let index, let original, let start, _):
                guard case .text(let origin, let string, let fontSize) = original.shape else { return }
                var moved = original
                moved.shape = .text(origin: CGPoint(x: origin.x + point.x - start.x, y: origin.y + point.y - start.y),
                                    string: string, fontSize: fontSize)
                self.drag = .movingText(index: index, original: original, start: start, current: moved)
            case .scalingText(let index, let original, _):
                guard let textBounds = original.textBounds, case .text(_, let string, let fontSize) = original.shape else { return }
                // The handle sits on the 4 pt margin around the text: measure from the text itself.
                let scaled = EditorGeometry.scaledText(bounds: textBounds, fontSize: fontSize, to: CGPoint(x: point.x - 4, y: point.y + 4))
                var resized = original
                resized.shape = .text(origin: scaled.origin, string: string, fontSize: scaled.fontSize)
                self.drag = .scalingText(index: index, original: original, current: resized)
            case .drawing(let start, var annotation):
                let end = shift ? EditorGeometry.constrained(point, from: start, tool: document.tool) : point
                switch annotation.shape {
                case .pen(var points):
                    points.append(point)
                    annotation.shape = .pen(points)
                case .arrow:
                    annotation.shape = .arrow(from: start, to: end)
                case .ellipse:
                    annotation.shape = .ellipse(EditorGeometry.rect(from: start, to: end))
                case .rectangle:
                    annotation.shape = .rectangle(EditorGeometry.rect(from: start, to: end))
                case .text:
                    break
                }
                self.drag = .drawing(start: start, annotation: annotation)
            }
        }
        needsDisplay = true
    }

    override func mouseUp(with event: NSEvent) {
        switch phase {
        case .inactive:
            return
        case .selecting:
            finishSelection()
        case .editing:
            switch drag {
            case .drawing(_, let annotation): document.add(annotation)
            case .movingText(let index, _, _, let current), .scalingText(let index, _, let current):
                document.replace(at: index, with: current)  // one undo step for the whole drag
            default: break
            }
            drag = nil
            updateCursor(at: convert(event.locationInWindow, from: nil))
        }
        needsDisplay = true
    }

    override func rightMouseDown(with event: NSEvent) {
        if phase == .selecting { session?.finish(nil) }
    }

    private var selectionRect: CGRect? {
        guard let anchor, let current else { return nil }
        return EditorGeometry.rect(from: anchor, to: current).integral
    }

    private func finishSelection() {
        if let rect = selectionRect, rect.width >= 4, rect.height >= 4 {
            session?.beginEditing(on: self, rect: rect)
        } else if let hoveredWindow, !hoveredWindow.isEmpty {
            // A click without dragging takes the window under the pointer.
            session?.beginEditing(on: self, rect: hoveredWindow.integral)
        }
        anchor = nil
        current = nil
    }

    private func clamp(_ point: CGPoint) -> CGPoint {
        CGPoint(x: min(max(point.x, 0), bounds.width), y: min(max(point.y, 0), bounds.height))
    }

    // MARK: Keys

    override func keyDown(with event: NSEvent) {
        switch Int(event.keyCode) {
        case kVK_Escape:
            // First Esc drops the caption selection, the next one closes.
            if document.selectedText != nil { document.selectedText = nil } else { session?.finish(nil) }
        case kVK_Delete, kVK_ForwardDelete:
            if let index = document.selectedText { document.remove(at: index) }
        default:
            break
        }
    }

    // MARK: Captions: select, move, scale

    /// The selected caption's frame (with a 4 pt margin), as currently drawn.
    private var selectedTextFrame: CGRect? {
        guard let index = document.selectedText, index != editingIndex else { return nil }
        return displayedAnnotations[safe: index]?.textBounds?.insetBy(dx: -4, dy: -4)
    }

    /// The document's drawings with the caption being dragged in its new place.
    private var displayedAnnotations: [Annotation] {
        var annotations = document.annotations
        switch drag {
        case .movingText(let index, _, _, let current), .scalingText(let index, _, let current):
            if annotations.indices.contains(index) { annotations[index] = current }
        default:
            break
        }
        return annotations
    }

    /// With "Text" or "Move": the selected caption's handle scales it, a caption is selected and
    /// dragged (double click edits it), a click elsewhere drops the selection. `true` when the
    /// click was about a caption.
    private func grabText(at point: CGPoint, clickCount: Int) -> Bool {
        if let index = document.selectedText, let frame = selectedTextFrame, let original = document.annotations[safe: index],
           EditorGeometry.isOnTextHandle(point, bounds: frame) {
            drag = .scalingText(index: index, original: original, current: original)
            Handle.bottomRight.cursor.set()
            return true
        }
        guard let index = EditorGeometry.textIndex(at: point, in: document.annotations) else {
            document.selectedText = nil
            return false
        }
        document.selectedText = index
        if clickCount >= 2 {
            beginText(at: point, editing: index)
        } else {
            let original = document.annotations[index]
            drag = .movingText(index: index, original: original, start: point, current: original)
            NSCursor.closedHand.set()
        }
        return true
    }

    /// ⌘Z, ⇧⌘Z, ⌘C, ⌘S by physical key (any layout). Not while typing a caption: the text
    /// field gets its own ⌘Z and ⌘C.
    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        guard phase == .editing, textField == nil else { return super.performKeyEquivalent(with: event) }
        let flags = event.modifierFlags.intersection([.command, .shift, .option, .control])
        switch (Int(event.keyCode), flags) {
        case (kVK_ANSI_Z, [.command]): document.undo()
        case (kVK_ANSI_Z, [.command, .shift]): document.redo()
        case (kVK_ANSI_C, [.command]): session?.finish(.copy)
        case (kVK_ANSI_S, [.command]): session?.finish(.save)
        default: return super.performKeyEquivalent(with: event)
        }
        return true
    }

    // MARK: Caption

    /// A text field for a new caption at `point`, or over an existing one to edit it.
    private func beginText(at point: CGPoint, editing index: Int? = nil) {
        var fontSize = document.size.fontSize
        var color = document.color
        var string = ""
        var origin: CGPoint?
        if let index, case .text(let textOrigin, let text, let size) = document.annotations[safe: index]?.shape {
            fontSize = size
            color = document.annotations[index].color
            string = text
            origin = textOrigin
        }
        let field = NSTextField(string: string)
        field.isBordered = false
        field.isBezeled = false
        field.drawsBackground = false
        field.focusRingType = .none
        field.font = Annotation.font(ofSize: fontSize)
        field.textColor = color.nsColor
        field.delegate = self
        field.cell?.wraps = false
        field.cell?.isScrollable = true
        let height = ceil(("Hg" as NSString).size(withAttributes: [.font: field.font!]).height) + 2
        // The text sits 2 pt in and 1 pt up inside the field (see `commitText`).
        let fieldOrigin = origin.map { CGPoint(x: $0.x - 2, y: $0.y - 1) } ?? CGPoint(x: point.x - 2, y: point.y - height / 2)
        field.frame = CGRect(origin: fieldOrigin, size: CGSize(width: 40, height: height))
        addSubview(field)
        window?.makeFirstResponder(field)
        textField = field
        editingIndex = index
        controlTextDidChange(Notification(name: NSControl.textDidChangeNotification))
    }

    func controlTextDidChange(_ notification: Notification) {
        guard let field = textField, let font = field.font else { return }
        let width = (field.stringValue as NSString).size(withAttributes: [.font: font]).width
        field.frame.size.width = max(40, ceil(width) + 16)
    }

    func control(_ control: NSControl, textView: NSTextView, doCommandBy selector: Selector) -> Bool {
        switch selector {
        case #selector(NSResponder.insertNewline(_:)):
            commitText()
            return true
        case #selector(NSResponder.cancelOperation(_:)):
            cancelText()
            return true
        default:
            return false
        }
    }

    /// The caption being typed becomes a drawing (an empty one is dropped).
    func commitText() {
        guard let field = textField else { return }
        textField = nil
        let string = field.stringValue
        // The field draws its text 2 pt in from its left edge.
        let origin = CGPoint(x: field.frame.minX + 2, y: field.frame.minY + 1)
        let fontSize = field.font?.pointSize ?? document.size.fontSize
        field.removeFromSuperview()
        window?.makeFirstResponder(self)
        if let index = editingIndex, var annotation = document.annotations[safe: index] {
            // An emptied caption is removed (`replace` does that).
            annotation.shape = .text(origin: origin, string: string, fontSize: fontSize)
            document.replace(at: index, with: annotation)
        } else {
            document.add(Annotation(shape: .text(origin: origin, string: string, fontSize: fontSize),
                                    color: document.color, size: document.size))
        }
        editingIndex = nil
        needsDisplay = true
    }

    private func cancelText() {
        textField?.removeFromSuperview()
        textField = nil
        editingIndex = nil
        window?.makeFirstResponder(self)
        needsDisplay = true
    }

    // MARK: Drawing

    override func draw(_ dirtyRect: NSRect) {
        guard let context = NSGraphicsContext.current?.cgContext else { return }
        context.interpolationQuality = .high
        context.draw(snapshot.image, in: bounds)

        switch phase {
        case .inactive:
            dim(except: nil)
        case .selecting:
            let highlight = selectionRect ?? (anchor == nil ? hoveredWindow : nil)
            dim(except: highlight)
            if let selection = selectionRect {
                strokeBorder(selection, color: .white, width: 1)
                drawSizeLabel(for: selection)
            } else if let highlight {
                strokeBorder(highlight.insetBy(dx: 0.5, dy: 0.5), color: .controlAccentColor, width: 2)
            }
            if let pointer { drawMagnifier(at: pointer, in: context) }
        case .editing:
            guard let selection = document.selection else { return }
            dim(except: selection)
            context.saveGState()
            context.clip(to: selection)
            for (index, annotation) in displayedAnnotations.enumerated() where index != editingIndex {
                AnnotationRenderer.draw(annotation, in: context)  // the edited caption is in its field
            }
            if case .drawing(_, let draft) = drag { AnnotationRenderer.draw(draft, in: context) }
            context.restoreGState()
            strokeBorder(selection, color: .white, width: 1)
            drawHandles(of: selection)
            if let frame = selectedTextFrame { drawTextSelection(frame) }
            if case .resizing = drag { drawSizeLabel(for: selection) }
            if case .moving = drag { drawSizeLabel(for: selection) }
        }
    }

    private func dim(except rect: CGRect?) {
        let path = NSBezierPath(rect: bounds)
        if let rect { path.append(NSBezierPath(rect: rect)) }
        path.windingRule = .evenOdd
        NSColor.black.withAlphaComponent(0.35).setFill()
        path.fill()
    }

    private func strokeBorder(_ rect: CGRect, color: NSColor, width: CGFloat) {
        color.setStroke()
        let path = NSBezierPath(rect: rect.insetBy(dx: -0.5, dy: -0.5))
        path.lineWidth = width
        path.stroke()
    }

    private func drawHandles(of rect: CGRect) {
        for handle in Handle.allCases {
            let center = handle.point(in: rect)
            let box = CGRect(x: center.x - 4, y: center.y - 4, width: 8, height: 8)
            NSColor.white.setFill()
            NSBezierPath(rect: box).fill()
            NSColor.controlAccentColor.setStroke()
            NSBezierPath(rect: box).stroke()
        }
    }

    /// A dashed frame around the selected caption and its scaling handle.
    private func drawTextSelection(_ frame: CGRect) {
        let path = NSBezierPath(rect: frame)
        path.lineWidth = 1
        NSColor.black.withAlphaComponent(0.6).setStroke()
        path.stroke()
        path.setLineDash([4, 3], count: 2, phase: 0)
        NSColor.white.setStroke()
        path.stroke()
        let handle = EditorGeometry.textHandle(of: frame)
        let box = CGRect(x: handle.x - 4, y: handle.y - 4, width: 8, height: 8)
        NSColor.white.setFill()
        NSBezierPath(rect: box).fill()
        NSColor.controlAccentColor.setStroke()
        NSBezierPath(rect: box).stroke()
    }

    private func drawMagnifier(at point: CGPoint, in context: CGContext) {
        let side: CGFloat = 120
        var origin = CGPoint(x: point.x + 24, y: point.y - 24 - side)
        if origin.x + side > bounds.width { origin.x = point.x - 24 - side }
        if origin.y < 0 { origin.y = point.y + 24 }
        let source = CGRect(x: point.x - 7.5, y: point.y - 7.5, width: 15, height: 15)
            .offsetBy(dx: snapshot.frame.minX, dy: snapshot.frame.minY)
        guard let crop = snapshot.crop(source) else { return }
        Magnifier.draw(crop, in: CGRect(origin: origin, size: CGSize(width: side, height: side)), style: .selection, context: context)
    }

    private func drawSizeLabel(for rect: CGRect) {
        let text = "\(Int(rect.width)) × \(Int(rect.height))" as NSString
        let attributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.monospacedDigitSystemFont(ofSize: 12, weight: .medium),
            .foregroundColor: NSColor.white,
        ]
        let size = text.size(withAttributes: attributes)
        var origin = CGPoint(x: rect.minX, y: rect.maxY + 6)
        if origin.y + size.height + 4 > bounds.height { origin.y = rect.maxY - size.height - 10 }
        origin.x = min(max(origin.x, 4), bounds.width - size.width - 16)
        let background = CGRect(x: origin.x, y: origin.y, width: size.width + 12, height: size.height + 4)
        NSColor.black.withAlphaComponent(0.7).setFill()
        NSBezierPath(roundedRect: background, xRadius: 4, yRadius: 4).fill()
        text.draw(at: CGPoint(x: origin.x + 6, y: origin.y + 2), withAttributes: attributes)
    }
}
