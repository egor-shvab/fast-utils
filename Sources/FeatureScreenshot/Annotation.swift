import AppKit
import Combine

enum Tool: String, CaseIterable, Sendable {
    /// Drag inside the area to move it.
    case move
    case pen, arrow, ellipse, rectangle, text

    /// Clicking a caption with this tool selects it (to move, scale, edit, delete).
    var grabsText: Bool { self == .text || self == .move }

    var symbol: String {
        switch self {
        case .move: "arrow.up.and.down.and.arrow.left.and.right"
        case .pen: "pencil.tip"
        case .arrow: "arrow.up.right"
        case .ellipse: "circle"
        case .rectangle: "rectangle"
        case .text: "textformat"
        }
    }
}

enum InkColor: String, CaseIterable, Sendable {
    case red, orange, yellow, green, blue, black, white

    var nsColor: NSColor {
        switch self {
        case .red: NSColor(srgbRed: 1, green: 0.23, blue: 0.19, alpha: 1)
        case .orange: NSColor(srgbRed: 1, green: 0.58, blue: 0, alpha: 1)
        case .yellow: NSColor(srgbRed: 1, green: 0.8, blue: 0, alpha: 1)
        case .green: NSColor(srgbRed: 0.2, green: 0.78, blue: 0.35, alpha: 1)
        case .blue: NSColor(srgbRed: 0, green: 0.48, blue: 1, alpha: 1)
        case .black: .black
        case .white: .white
        }
    }
}

enum StrokeSize: String, CaseIterable, Sendable {
    case small, medium, large

    var lineWidth: CGFloat {
        switch self {
        case .small: 2
        case .medium: 4
        case .large: 8
        }
    }

    var fontSize: CGFloat {
        switch self {
        case .small: 16
        case .medium: 24
        case .large: 36
        }
    }
}

/// One drawing. Coordinates are points of the edited screen (bottom-left origin).
struct Annotation: Equatable {
    enum Shape: Equatable {
        case pen([CGPoint])
        case arrow(from: CGPoint, to: CGPoint)
        case ellipse(CGRect)
        case rectangle(CGRect)
        /// `origin`: bottom-left of the text. Its own font size: captions can be scaled freely.
        case text(origin: CGPoint, string: String, fontSize: CGFloat)
    }

    var shape: Shape
    var color: InkColor
    var size: StrokeSize

    /// Too small to be intended (a click with a shape tool).
    var isDegenerate: Bool {
        switch shape {
        case .pen(let points): points.isEmpty
        case .arrow(let from, let to): hypot(to.x - from.x, to.y - from.y) < 4
        case .ellipse(let rect), .rectangle(let rect): rect.width < 2 && rect.height < 2
        case .text(_, let string, _): string.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        }
    }

    static let fontSizeRange: ClosedRange<CGFloat> = 8...200

    static func font(ofSize size: CGFloat) -> NSFont { .systemFont(ofSize: size, weight: .semibold) }

    /// The frame of a caption's text; `nil` for other shapes.
    var textBounds: CGRect? {
        guard case .text(let origin, let string, let fontSize) = shape else { return nil }
        let size = (string as NSString).size(withAttributes: [.font: Self.font(ofSize: fontSize)])
        return CGRect(origin: origin, size: size)
    }

    var isText: Bool { textBounds != nil }
}

/// The editor state: area, drawings with undo/redo, current tool. An ObservableObject, not
/// `@State` (see CLAUDE.md), shared by the overlay view and the toolbar.
@MainActor
final class EditorDocument: ObservableObject {
    @Published private(set) var annotations: [Annotation] = []
    @Published var selection: CGRect?
    @Published var tool: Tool {
        // Only "Text" and "Move" grab captions; with a brush, a panel color is for the brush.
        didSet { if !tool.grabsText { selectedText = nil } }
    }
    @Published var color: InkColor
    @Published var size: StrokeSize
    @Published private(set) var canUndo = false
    @Published private(set) var canRedo = false

    private var undoStack: [[Annotation]] = []
    private var redoStack: [[Annotation]] = []

    init(tool: Tool = .pen, color: InkColor = .red, size: StrokeSize = .medium) {
        self.tool = tool
        self.color = color
        self.size = size
    }

    /// The caption selected for moving, scaling, recoloring or deleting.
    @Published var selectedText: Int?

    func add(_ annotation: Annotation) {
        guard !annotation.isDegenerate else { return }
        record { $0.append(annotation) }
    }

    /// One undo step. An emptied caption is removed instead.
    func replace(at index: Int, with annotation: Annotation) {
        guard annotations.indices.contains(index), annotations[index] != annotation else { return }
        if annotation.isDegenerate { return remove(at: index) }
        record { $0[index] = annotation }
    }

    func remove(at index: Int) {
        guard annotations.indices.contains(index) else { return }
        record { $0.remove(at: index) }
        if selectedText == index { selectedText = nil }
    }

    /// The panel's color: for the next drawings, and for the selected caption if there is one.
    func setColor(_ color: InkColor) {
        self.color = color
        if let index = selectedText, var annotation = annotations[safe: index] {
            annotation.color = color
            replace(at: index, with: annotation)
        }
    }

    /// The panel's size; a selected caption gets the size's font.
    func setSize(_ size: StrokeSize) {
        self.size = size
        if let index = selectedText, var annotation = annotations[safe: index],
           case .text(let origin, let string, _) = annotation.shape {
            annotation.size = size
            annotation.shape = .text(origin: origin, string: string, fontSize: size.fontSize)
            replace(at: index, with: annotation)
        }
    }

    func undo() {
        guard let previous = undoStack.popLast() else { return }
        redoStack.append(annotations)
        annotations = previous
        updateFlags()
    }

    func redo() {
        guard let next = redoStack.popLast() else { return }
        undoStack.append(annotations)
        annotations = next
        updateFlags()
    }

    private func record(_ change: (inout [Annotation]) -> Void) {
        undoStack.append(annotations)
        redoStack.removeAll()
        change(&annotations)
        updateFlags()
    }

    private func updateFlags() {
        canUndo = !undoStack.isEmpty
        canRedo = !redoStack.isEmpty
        // Undo/redo may have removed or replaced the selected caption.
        if let index = selectedText, annotations[safe: index]?.isText != true { selectedText = nil }
    }
}

extension Array {
    subscript(safe index: Int) -> Element? { indices.contains(index) ? self[index] : nil }
}

/// The eight resize handles of the area.
enum Handle: CaseIterable, Sendable {
    case bottomLeft, bottom, bottomRight, right, topRight, top, topLeft, left

    func point(in rect: CGRect) -> CGPoint {
        switch self {
        case .bottomLeft: CGPoint(x: rect.minX, y: rect.minY)
        case .bottom: CGPoint(x: rect.midX, y: rect.minY)
        case .bottomRight: CGPoint(x: rect.maxX, y: rect.minY)
        case .right: CGPoint(x: rect.maxX, y: rect.midY)
        case .topRight: CGPoint(x: rect.maxX, y: rect.maxY)
        case .top: CGPoint(x: rect.midX, y: rect.maxY)
        case .topLeft: CGPoint(x: rect.minX, y: rect.maxY)
        case .left: CGPoint(x: rect.minX, y: rect.midY)
        }
    }

    /// The system "resize frame" cursor for this edge or corner.
    var cursor: NSCursor {
        let position: NSCursor.FrameResizePosition = switch self {
        case .bottomLeft: .bottomLeft
        case .bottom: .bottom
        case .bottomRight: .bottomRight
        case .right: .right
        case .topRight: .topRight
        case .top: .top
        case .topLeft: .topLeft
        case .left: .left
        }
        return NSCursor.frameResize(position: position, directions: .all)
    }

    var movesLeft: Bool { [.bottomLeft, .topLeft, .left].contains(self) }
    var movesRight: Bool { [.bottomRight, .topRight, .right].contains(self) }
    var movesBottom: Bool { [.bottomLeft, .bottomRight, .bottom].contains(self) }
    var movesTop: Bool { [.topLeft, .topRight, .top].contains(self) }
}

/// Pure geometry of the editor, covered by tests.
enum EditorGeometry {
    static let minimumSide: CGFloat = 8

    static func rect(from a: CGPoint, to b: CGPoint) -> CGRect {
        CGRect(x: min(a.x, b.x), y: min(a.y, b.y), width: abs(b.x - a.x), height: abs(b.y - a.y))
    }

    /// With ⇧: a square/circle for rectangles and ellipses, a multiple of 45° for arrows.
    static func constrained(_ end: CGPoint, from start: CGPoint, tool: Tool) -> CGPoint {
        let dx = end.x - start.x, dy = end.y - start.y
        switch tool {
        case .rectangle, .ellipse:
            let side = max(abs(dx), abs(dy))
            return CGPoint(x: start.x + (dx < 0 ? -side : side), y: start.y + (dy < 0 ? -side : side))
        case .arrow:
            let length = hypot(dx, dy)
            let step = Double.pi / 4
            let angle = (atan2(dy, dx) / step).rounded() * step
            return CGPoint(x: start.x + length * cos(angle), y: start.y + length * sin(angle))
        default:
            return end
        }
    }

    /// The area resized by dragging `handle` from the rect it had when the drag began.
    /// Crossing the opposite edge flips naturally; the result stays inside `bounds` and is at
    /// least `minimumSide` wide and high.
    static func resize(_ original: CGRect, handle: Handle, to point: CGPoint, bounds: CGRect) -> CGRect {
        let p = CGPoint(x: min(max(point.x, bounds.minX), bounds.maxX), y: min(max(point.y, bounds.minY), bounds.maxY))
        var x1 = original.minX, x2 = original.maxX, y1 = original.minY, y2 = original.maxY
        if handle.movesLeft { x1 = p.x }
        if handle.movesRight { x2 = p.x }
        if handle.movesBottom { y1 = p.y }
        if handle.movesTop { y2 = p.y }
        var rect = CGRect(x: min(x1, x2), y: min(y1, y2), width: abs(x2 - x1), height: abs(y2 - y1))
        if rect.width < minimumSide { rect.size.width = minimumSide; rect.origin.x = min(rect.minX, bounds.maxX - minimumSide) }
        if rect.height < minimumSide { rect.size.height = minimumSide; rect.origin.y = min(rect.minY, bounds.maxY - minimumSide) }
        return rect
    }

    /// The area moved by `delta`, kept inside `bounds`.
    static func move(_ rect: CGRect, by delta: CGVector, within bounds: CGRect) -> CGRect {
        var moved = rect.offsetBy(dx: delta.dx, dy: delta.dy)
        moved.origin.x = min(max(moved.minX, bounds.minX), bounds.maxX - moved.width)
        moved.origin.y = min(max(moved.minY, bounds.minY), bounds.maxY - moved.height)
        return moved
    }

    /// The edge or corner of the area under the pointer: anywhere along an edge within
    /// `tolerance`, a corner when near both of its edges or on its handle.
    static func edge(at point: CGPoint, of rect: CGRect, tolerance: CGFloat = 5) -> Handle? {
        let cornerReach: CGFloat = 8
        for corner in [Handle.bottomLeft, .bottomRight, .topRight, .topLeft] {
            let center = corner.point(in: rect)
            if abs(center.x - point.x) <= cornerReach && abs(center.y - point.y) <= cornerReach { return corner }
        }
        guard point.x >= rect.minX - tolerance, point.x <= rect.maxX + tolerance,
              point.y >= rect.minY - tolerance, point.y <= rect.maxY + tolerance
        else { return nil }
        // The nearer side wins when the area is narrower than two tolerances.
        let left = abs(point.x - rect.minX), right = abs(point.x - rect.maxX)
        let bottom = abs(point.y - rect.minY), top = abs(point.y - rect.maxY)
        let horizontal: Handle? = min(left, right) <= tolerance ? (left <= right ? .left : .right) : nil
        let vertical: Handle? = min(bottom, top) <= tolerance ? (bottom <= top ? .bottom : .top) : nil
        switch (horizontal, vertical) {
        case (.left?, .bottom?): return .bottomLeft
        case (.left?, .top?): return .topLeft
        case (.right?, .bottom?): return .bottomRight
        case (.right?, .top?): return .topRight
        case (let side?, nil), (nil, let side?): return side
        default: return nil
        }
    }

    /// The topmost caption under `point` (its frame grown by 4 pt), as an index.
    static func textIndex(at point: CGPoint, in annotations: [Annotation]) -> Int? {
        annotations.indices.reversed().first { annotations[$0].textBounds?.insetBy(dx: -4, dy: -4).contains(point) == true }
    }

    /// The scaling handle of a caption: its bottom-right corner.
    static func textHandle(of bounds: CGRect) -> CGPoint { CGPoint(x: bounds.maxX, y: bounds.minY) }

    static func isOnTextHandle(_ point: CGPoint, bounds: CGRect) -> Bool {
        let handle = textHandle(of: bounds)
        return abs(handle.x - point.x) <= 7 && abs(handle.y - point.y) <= 7
    }

    /// A caption scaled by dragging its handle to `point`: by the new width, keeping the top-left
    /// corner in place; the font stays within `Annotation.fontSizeRange`.
    static func scaledText(bounds: CGRect, fontSize: CGFloat, to point: CGPoint) -> (origin: CGPoint, fontSize: CGFloat) {
        let scale = max(point.x - bounds.minX, 1) / max(bounds.width, 1)
        let range = Annotation.fontSizeRange
        let newSize = min(max(fontSize * scale, range.lowerBound), range.upperBound)
        let newHeight = bounds.height * newSize / fontSize
        return (CGPoint(x: bounds.minX, y: bounds.maxY - newHeight), newSize)
    }

    /// The arrowhead triangle (tip, left, right) and where the shaft should end.
    static func arrowHead(from start: CGPoint, to end: CGPoint, lineWidth: CGFloat)
        -> (tip: CGPoint, left: CGPoint, right: CGPoint, shaftEnd: CGPoint) {
        let angle = atan2(end.y - start.y, end.x - start.x)
        let length = min(max(10, lineWidth * 4), hypot(end.x - start.x, end.y - start.y))
        let spread = Double.pi / 7  // ~26° each side
        let left = CGPoint(x: end.x - length * cos(angle - spread), y: end.y - length * sin(angle - spread))
        let right = CGPoint(x: end.x - length * cos(angle + spread), y: end.y - length * sin(angle + spread))
        let base = length * cos(spread) * 0.8
        let shaftEnd = CGPoint(x: end.x - base * cos(angle), y: end.y - base * sin(angle))
        return (end, left, right, shaftEnd)
    }

    /// The toolbar under the area, or above it when there is no room, inside `bounds`.
    static func toolbarOrigin(for selection: CGRect, size: CGSize, in bounds: CGRect) -> CGPoint {
        let gap: CGFloat = 10
        var y = selection.minY - gap - size.height
        if y < bounds.minY + gap { y = selection.maxY + gap }
        if y + size.height > bounds.maxY - gap { y = selection.minY + gap }  // full-screen area: inside it
        var x = selection.midX - size.width / 2
        x = min(max(x, bounds.minX + gap), bounds.maxX - size.width - gap)
        return CGPoint(x: x, y: y)
    }
}
