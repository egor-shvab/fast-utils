import AppKit
import Core
import Testing
@testable import FeatureScreenshot

@MainActor
struct EditorDocumentTests {
    private func line(_ x: CGFloat) -> Annotation {
        Annotation(shape: .rectangle(CGRect(x: x, y: 0, width: 10, height: 10)), color: .red, size: .medium)
    }

    @Test func undoAndRedo() {
        let document = EditorDocument()
        document.add(line(1))
        document.add(line(2))
        document.undo()
        #expect(document.annotations == [line(1)])
        #expect(document.canRedo)
        document.redo()
        #expect(document.annotations == [line(1), line(2)])
        document.undo()
        document.undo()
        #expect(document.annotations.isEmpty)
        #expect(!document.canUndo)
        document.undo()  // nothing left: no crash, no change
        #expect(document.annotations.isEmpty)
    }

    @Test func newDrawingAfterUndoClearsRedo() {
        let document = EditorDocument()
        document.add(line(1))
        document.undo()
        document.add(line(3))
        #expect(!document.canRedo)
        #expect(document.annotations == [line(3)])
    }

    @Test func degenerateDrawingsAreDropped() {
        let document = EditorDocument()
        document.add(Annotation(shape: .rectangle(CGRect(x: 5, y: 5, width: 0, height: 1)), color: .red, size: .small))
        document.add(Annotation(shape: .arrow(from: .zero, to: CGPoint(x: 1, y: 1)), color: .red, size: .small))
        document.add(Annotation(shape: .text(origin: .zero, string: "  ", fontSize: 16), color: .red, size: .small))
        #expect(document.annotations.isEmpty)
        #expect(!document.canUndo)
    }
}

struct EditorGeometryTests {
    let bounds = CGRect(x: 0, y: 0, width: 1000, height: 800)
    let area = CGRect(x: 100, y: 100, width: 200, height: 100)

    @Test func everyHandleMovesItsEdges() {
        #expect(EditorGeometry.resize(area, handle: .right, to: CGPoint(x: 400, y: 0), bounds: bounds)
            == CGRect(x: 100, y: 100, width: 300, height: 100))
        #expect(EditorGeometry.resize(area, handle: .top, to: CGPoint(x: 0, y: 250), bounds: bounds)
            == CGRect(x: 100, y: 100, width: 200, height: 150))
        #expect(EditorGeometry.resize(area, handle: .bottomLeft, to: CGPoint(x: 50, y: 50), bounds: bounds)
            == CGRect(x: 50, y: 50, width: 250, height: 150))
        #expect(EditorGeometry.resize(area, handle: .topRight, to: CGPoint(x: 310, y: 210), bounds: bounds)
            == CGRect(x: 100, y: 100, width: 210, height: 110))
    }

    @Test func crossingTheOppositeEdgeFlips() {
        #expect(EditorGeometry.resize(area, handle: .left, to: CGPoint(x: 350, y: 0), bounds: bounds)
            == CGRect(x: 300, y: 100, width: 50, height: 100))
    }

    @Test func staysInsideTheScreenAndAboveTheMinimum() {
        let out = EditorGeometry.resize(area, handle: .topRight, to: CGPoint(x: 5000, y: 5000), bounds: bounds)
        #expect(out == CGRect(x: 100, y: 100, width: 900, height: 700))
        let tiny = EditorGeometry.resize(area, handle: .right, to: CGPoint(x: 101, y: 0), bounds: bounds)
        #expect(tiny.width == EditorGeometry.minimumSide)
    }

    @Test func movingKeepsTheAreaOnScreen() {
        #expect(EditorGeometry.move(area, by: CGVector(dx: 10, dy: -20), within: bounds) == area.offsetBy(dx: 10, dy: -20))
        #expect(EditorGeometry.move(area, by: CGVector(dx: -500, dy: 5000), within: bounds) == CGRect(x: 0, y: 700, width: 200, height: 100))
    }

    @Test func shiftMakesSquaresAndFortyFiveDegreeArrows() {
        let start = CGPoint(x: 10, y: 10)
        #expect(EditorGeometry.constrained(CGPoint(x: 50, y: 20), from: start, tool: .rectangle) == CGPoint(x: 50, y: 50))
        #expect(EditorGeometry.constrained(CGPoint(x: -30, y: 0), from: start, tool: .ellipse) == CGPoint(x: -30, y: -30))
        let arrow = EditorGeometry.constrained(CGPoint(x: 110, y: 15), from: start, tool: .arrow)
        #expect(abs(arrow.y - 10) < 0.001)  // nearly horizontal snaps to 0°
        let diagonal = EditorGeometry.constrained(CGPoint(x: 60, y: 50), from: start, tool: .arrow)
        #expect(abs((diagonal.x - start.x) - (diagonal.y - start.y)) < 0.001)  // 45°
    }

    @Test func anywhereAlongAnEdge() {
        #expect(EditorGeometry.edge(at: CGPoint(x: 103, y: 150), of: area) == .left)
        #expect(EditorGeometry.edge(at: CGPoint(x: 140, y: 202), of: area) == .top)
        #expect(EditorGeometry.edge(at: CGPoint(x: 260, y: 97), of: area) == .bottom)
        #expect(EditorGeometry.edge(at: CGPoint(x: 296, y: 130), of: area) == .right)
    }

    @Test func cornersWinOverEdges() {
        #expect(EditorGeometry.edge(at: CGPoint(x: 101, y: 99), of: area) == .bottomLeft)
        #expect(EditorGeometry.edge(at: CGPoint(x: 306, y: 206), of: area) == .topRight)  // on the handle, just outside
    }

    @Test func insideAndFarOutsideAreNoEdge() {
        #expect(EditorGeometry.edge(at: CGPoint(x: 200, y: 150), of: area) == nil)
        #expect(EditorGeometry.edge(at: CGPoint(x: 90, y: 150), of: area) == nil)
        #expect(EditorGeometry.edge(at: CGPoint(x: 103, y: 260), of: area) == nil)  // in line with the left edge, but above
    }

    @Test func narrowAreaPicksTheNearerSide() {
        let narrow = CGRect(x: 100, y: 100, width: 6, height: 100)
        #expect(EditorGeometry.edge(at: CGPoint(x: 101, y: 150), of: narrow) == .left)
        #expect(EditorGeometry.edge(at: CGPoint(x: 105, y: 150), of: narrow) == .right)
    }

    @Test func arrowHeadPointsAtTheEnd() {
        let head = EditorGeometry.arrowHead(from: .zero, to: CGPoint(x: 100, y: 0), lineWidth: 4)
        #expect(head.tip == CGPoint(x: 100, y: 0))
        #expect(head.left.x < 100 && head.right.x < 100)
        #expect(abs(head.left.y + head.right.y) < 0.001)  // symmetric
        #expect(head.shaftEnd.x < 100 && head.shaftEnd.x > head.left.x)
    }

    @Test func toolbarGoesBelowOrAboveTheArea() {
        let size = CGSize(width: 300, height: 36)
        let below = EditorGeometry.toolbarOrigin(for: area, size: size, in: bounds)
        #expect(below.y + size.height < area.minY)
        let low = CGRect(x: 100, y: 5, width: 200, height: 100)
        #expect(EditorGeometry.toolbarOrigin(for: low, size: size, in: bounds).y > low.maxY)
        let edge = EditorGeometry.toolbarOrigin(for: CGRect(x: 950, y: 300, width: 40, height: 40), size: size, in: bounds)
        #expect(edge.x + size.width <= bounds.maxX)
    }
}

@MainActor
struct ScreenshotExportTests {
    /// A 2× snapshot of a 100×50 pt screen, filled gray.
    private func snapshot() -> ScreenSnapshot {
        let space = CGColorSpace(name: CGColorSpace.sRGB)!
        let context = CGContext(data: nil, width: 200, height: 100, bitsPerComponent: 8, bytesPerRow: 0,
                                space: space, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        context.setFillColor(gray: 0.5, alpha: 1)
        context.fill(CGRect(x: 0, y: 0, width: 200, height: 100))
        return ScreenSnapshot(frame: CGRect(x: 0, y: 0, width: 100, height: 50), scale: 2, image: context.makeImage()!, displayID: 0)
    }

    private func pixel(_ image: CGImage, _ x: Int, _ y: Int) -> (UInt8, UInt8, UInt8) {
        let space = CGColorSpace(name: CGColorSpace.sRGB)!
        let context = CGContext(data: nil, width: 1, height: 1, bitsPerComponent: 8, bytesPerRow: 4,
                                space: space, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        context.draw(image.cropping(to: CGRect(x: x, y: y, width: 1, height: 1))!, in: CGRect(x: 0, y: 0, width: 1, height: 1))
        let data = context.data!.assumingMemoryBound(to: UInt8.self)
        return (data[0], data[1], data[2])
    }

    @Test func areaAtFullResolutionWithTheDrawing() throws {
        let area = CGRect(x: 10, y: 10, width: 40, height: 20)
        let mark = Annotation(shape: .rectangle(CGRect(x: 20, y: 15, width: 10, height: 10)), color: .blue, size: .large)
        let image = try #require(ScreenshotExporter.render(snapshot: snapshot(), rect: area, annotations: [mark]))
        #expect(image.width == 80 && image.height == 40)
        // The rectangle's left edge: area x 20 → pixel (20 − 10) × 2 = 20; y 20 pt → row (30 − 20) × 2 = 20.
        let edge = pixel(image, 20, 20)
        #expect(edge.2 > 200 && edge.0 < 50)
        // Far from the drawing: the frozen screen.
        #expect(pixel(image, 2, 2) == (128, 128, 128) || pixel(image, 2, 2) == (127, 127, 127))
    }

    @Test func drawingsOutsideTheAreaAreCut() throws {
        let area = CGRect(x: 10, y: 10, width: 40, height: 20)
        let outside = Annotation(shape: .rectangle(CGRect(x: 0, y: 0, width: 5, height: 5)), color: .red, size: .large)
        let image = try #require(ScreenshotExporter.render(snapshot: snapshot(), rect: area, annotations: [outside]))
        let corner = pixel(image, 0, 39)
        #expect(corner.0 < 140)  // gray, not red
    }

    @Test func pngIsReadable() throws {
        let image = try #require(ScreenshotExporter.render(snapshot: snapshot(), rect: CGRect(x: 0, y: 0, width: 10, height: 10), annotations: []))
        let data = try #require(ScreenshotExporter.pngData(image))
        #expect(data.starts(with: [0x89, 0x50, 0x4E, 0x47]))
        #expect(NSImage(data: data) != nil)
    }

    @Test func fileNamesLikeTheSystemsAndNeverOverwrite() throws {
        var components = DateComponents(year: 2026, month: 11, day: 7, hour: 8, minute: 5, second: 3)
        components.calendar = Calendar(identifier: .gregorian)
        let date = try #require(components.date)
        let name = ScreenshotExporter.baseName(for: date, format: "Снимок экрана %@ в %@")
        #expect(name == "Снимок экрана 2026-11-07 в 08.05.03")

        let folder = FileManager.default.temporaryDirectory.appending(path: "FastUtilsTests.\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        let first = ScreenshotExporter.uniqueURL(in: folder, baseName: name)
        #expect(first.lastPathComponent == "\(name).png")
        try Data().write(to: first)
        #expect(ScreenshotExporter.uniqueURL(in: folder, baseName: name).lastPathComponent == "\(name) (2).png")
    }
}

@MainActor
struct CaptionEditingTests {
    private func caption(_ text: String, at x: CGFloat = 100, size: CGFloat = 24, color: InkColor = .red) -> Annotation {
        Annotation(shape: .text(origin: CGPoint(x: x, y: 100), string: text, fontSize: size), color: color, size: .medium)
    }

    @Test func replaceAndRemoveAreUndoable() {
        let document = EditorDocument()
        document.add(caption("привет"))
        document.replace(at: 0, with: caption("привет", at: 300))
        #expect(document.annotations == [caption("привет", at: 300)])
        document.undo()
        #expect(document.annotations == [caption("привет")])
        document.redo()
        document.remove(at: 0)
        #expect(document.annotations.isEmpty)
        document.undo()
        #expect(document.annotations == [caption("привет", at: 300)])
    }

    @Test func emptiedCaptionIsRemoved() {
        let document = EditorDocument()
        document.add(caption("текст"))
        document.replace(at: 0, with: caption(" "))
        #expect(document.annotations.isEmpty)
    }

    @Test func panelColorAndSizeChangeTheSelectedCaption() {
        let document = EditorDocument(tool: .text)
        document.add(caption("a"))
        document.selectedText = 0
        document.setColor(.blue)
        #expect(document.annotations[0].color == .blue)
        document.setSize(.large)
        #expect(document.annotations[0].textBounds?.height ?? 0 > caption("a").textBounds?.height ?? 0)
        document.undo()
        document.undo()
        #expect(document.annotations == [caption("a")])
    }

    @Test func withoutSelectionThePanelOnlyPicksForNextDrawings() {
        let document = EditorDocument(tool: .pen)
        document.add(caption("a"))
        document.setColor(.green)
        #expect(document.color == .green)
        #expect(document.annotations[0].color == .red)
        #expect(!document.canRedo)
    }

    @Test func selectionIsDroppedWhenTheCaptionGoesAwayOrTheToolChanges() {
        let document = EditorDocument(tool: .text)
        document.add(caption("a"))
        document.selectedText = 0
        document.undo()  // the caption is gone
        #expect(document.selectedText == nil)
        document.redo()
        document.selectedText = 0
        document.tool = .pen
        #expect(document.selectedText == nil)
    }

    @Test func hitTestingFindsTheTopmostCaption() throws {
        let below = caption("нижняя надпись")
        let above = caption("верх", at: 110)
        let annotations = [below, Annotation(shape: .rectangle(CGRect(x: 0, y: 0, width: 50, height: 50)), color: .red, size: .small), above]
        let frame = try #require(above.textBounds)
        #expect(EditorGeometry.textIndex(at: CGPoint(x: frame.midX, y: frame.midY), in: annotations) == 2)
        let farRight = try #require(below.textBounds).maxX - 2
        #expect(EditorGeometry.textIndex(at: CGPoint(x: farRight, y: frame.midY), in: annotations) == 0)
        #expect(EditorGeometry.textIndex(at: CGPoint(x: 25, y: 25), in: annotations) == nil)  // a rectangle is not a caption
    }

    @Test func scalingKeepsTheTopLeftCorner() {
        let bounds = CGRect(x: 100, y: 100, width: 200, height: 30)
        let doubled = EditorGeometry.scaledText(bounds: bounds, fontSize: 24, to: CGPoint(x: 500, y: 0))
        #expect(doubled.fontSize == 48)
        #expect(doubled.origin == CGPoint(x: 100, y: 70))  // top stays at 130
        #expect(EditorGeometry.scaledText(bounds: bounds, fontSize: 24, to: CGPoint(x: 101, y: 0)).fontSize == 8)
        #expect(EditorGeometry.scaledText(bounds: bounds, fontSize: 24, to: CGPoint(x: 100_000, y: 0)).fontSize == 200)
    }
}
