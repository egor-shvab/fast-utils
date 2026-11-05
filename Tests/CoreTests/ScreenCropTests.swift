import CoreGraphics
import Testing
@testable import Core

struct ScreenCropTests {
    @Test func retinaPointsToPixelsWithFlippedY() {
        // 1440×900 pt screen at 2×; select 100×50 pt at (10, 20) from the bottom-left.
        let rect = ScreenSnapshot.pixelRect(
            for: CGRect(x: 10, y: 20, width: 100, height: 50),
            screenFrame: CGRect(x: 0, y: 0, width: 1440, height: 900),
            imageSize: CGSize(width: 2880, height: 1800)
        )
        #expect(rect == CGRect(x: 20, y: 1660, width: 200, height: 100))
    }

    @Test func secondScreenOffsetIsRemoved() {
        // Second monitor to the right, non-Retina.
        let rect = ScreenSnapshot.pixelRect(
            for: CGRect(x: 1540, y: 100, width: 200, height: 100),
            screenFrame: CGRect(x: 1440, y: 0, width: 1920, height: 1080),
            imageSize: CGSize(width: 1920, height: 1080)
        )
        #expect(rect == CGRect(x: 100, y: 880, width: 200, height: 100))
    }
}
