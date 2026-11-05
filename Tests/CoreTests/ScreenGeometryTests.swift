import CoreGraphics
import Testing
@testable import Core

struct ScreenGeometryTests {
    let screen = CGRect(x: 0, y: 0, width: 1000, height: 800)
    let size = CGSize(width: 300, height: 200)

    @Test func placesBelowRightOfCursor() {
        let frame = ScreenGeometry.frame(size: size, near: CGPoint(x: 100, y: 700), in: screen)
        #expect(frame.minX == 112)
        #expect(frame.maxY == 688)
    }

    @Test func flipsLeftAtRightEdge() {
        let frame = ScreenGeometry.frame(size: size, near: CGPoint(x: 950, y: 700), in: screen)
        #expect(frame.maxX == 938)
    }

    @Test func flipsAboveAtBottomEdge() {
        let frame = ScreenGeometry.frame(size: size, near: CGPoint(x: 100, y: 50), in: screen)
        #expect(frame.minY == 62)
    }

    @Test func alwaysStaysInsideVisibleFrame() {
        let visible = CGRect(x: 1000, y: 25, width: 800, height: 600)  // second monitor, menu bar inset
        for point in [CGPoint(x: 1000, y: 625), CGPoint(x: 1800, y: 25), CGPoint(x: 1400, y: 300)] {
            let frame = ScreenGeometry.frame(size: size, near: point, in: visible)
            #expect(visible.contains(frame))
        }
    }

    @Test func bottomCenter() {
        let frame = ScreenGeometry.bottomCenter(size: size, in: screen, bottomInset: 96)
        #expect(frame.midX == 500)
        #expect(frame.minY == 96)
    }
}
