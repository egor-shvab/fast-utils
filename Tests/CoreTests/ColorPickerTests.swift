import AppKit
import Carbon.HIToolbox
import Testing
@testable import Core

struct ScreenPixelTests {
    @Test func retinaPointMapsToTwoByTwoPixels() {
        let frame = CGRect(x: 0, y: 0, width: 100, height: 50)
        let size = CGSize(width: 200, height: 100)
        // Bottom-left point space, top-left pixels.
        #expect(ScreenSnapshot.pixel(at: CGPoint(x: 0.2, y: 49.9), screenFrame: frame, imageSize: size) == PixelPoint(x: 0, y: 0))
        #expect(ScreenSnapshot.pixel(at: CGPoint(x: 10.5, y: 40), screenFrame: frame, imageSize: size) == PixelPoint(x: 21, y: 20))
        #expect(ScreenSnapshot.pixel(at: CGPoint(x: 100, y: 0), screenFrame: frame, imageSize: size) == PixelPoint(x: 199, y: 99))
    }

    @Test func secondScreenWithAnOffset() {
        let frame = CGRect(x: -1920, y: 200, width: 1920, height: 1080)
        let size = CGSize(width: 1920, height: 1080)
        #expect(ScreenSnapshot.pixel(at: CGPoint(x: -1910, y: 1270), screenFrame: frame, imageSize: size) == PixelPoint(x: 10, y: 10))
    }

    @Test func pixelCenterRoundTrips() {
        let snapshot = ScreenSnapshot(frame: CGRect(x: 100, y: 0, width: 50, height: 50), scale: 2,
                                      image: Self.image(width: 100, height: 100, color: .white), displayID: 0)
        for pixel in [PixelPoint(x: 0, y: 0), PixelPoint(x: 37, y: 81), PixelPoint(x: 99, y: 99)] {
            #expect(snapshot.pixel(at: snapshot.point(ofPixel: pixel)) == pixel)
        }
    }

    @Test func movesByWholePixelsWithinTheImage() {
        let size = (width: 100, height: 50)
        #expect(PixelPoint(x: 5, y: 5).moved(dx: 1, dy: -1, within: size) == PixelPoint(x: 6, y: 4))
        #expect(PixelPoint(x: 5, y: 5).moved(dx: -10, dy: 10, within: size) == PixelPoint(x: 0, y: 15))
        #expect(PixelPoint(x: 99, y: 49).moved(dx: 10, dy: 10, within: size) == PixelPoint(x: 99, y: 49))
    }

    @Test func readsTheExactSRGBColor() throws {
        let image = Self.image(width: 4, height: 4, color: NSColor(srgbRed: 0x3a / 255, green: 0x7b / 255, blue: 0xd5 / 255, alpha: 1))
        #expect(ScreenSnapshot.color(in: image, atPixel: PixelPoint(x: 2, y: 3)) == RGBColor(red: 0x3a, green: 0x7b, blue: 0xd5))
    }

    /// A Display P3 snapshot reads back as the sRGB color that was shown, not the raw P3 values.
    @Test func convertsDisplayP3ToSRGB() throws {
        let srgb = NSColor(srgbRed: 0x3a / 255, green: 0x7b / 255, blue: 0xd5 / 255, alpha: 1)
        let p3 = try #require(CGColorSpace(name: CGColorSpace.displayP3))
        let image = Self.image(width: 2, height: 2, color: srgb, space: p3)
        let color = try #require(ScreenSnapshot.color(in: image, atPixel: PixelPoint(x: 0, y: 0)))
        #expect(abs(Int(color.red) - 0x3a) <= 1)
        #expect(abs(Int(color.green) - 0x7b) <= 1)
        #expect(abs(Int(color.blue) - 0xd5) <= 1)
    }

    @Test func pickerKeys() {
        #expect(PickerCommand.from(keyCode: kVK_Escape, shift: false) == .cancel)
        #expect(PickerCommand.from(keyCode: kVK_Return, shift: false) == .pick)
        #expect(PickerCommand.from(keyCode: kVK_Space, shift: false) == .pick)
        #expect(PickerCommand.from(keyCode: kVK_UpArrow, shift: false) == .move(dx: 0, dy: -1))
        #expect(PickerCommand.from(keyCode: kVK_RightArrow, shift: true) == .move(dx: 10, dy: 0))
        #expect(PickerCommand.from(keyCode: kVK_ANSI_A, shift: false) == nil)
    }

    static func image(width: Int, height: Int, color: NSColor,
                      space: CGColorSpace = CGColorSpace(name: CGColorSpace.sRGB)!) -> CGImage {
        let context = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
                                space: space, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        context.setFillColor(color.cgColor)
        context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        return context.makeImage()!
    }
}

struct PickerLayoutTests {
    let bounds = CGRect(x: 0, y: 0, width: 1000, height: 800)

    @Test func loupeSitsBelowRightAndNeverCoversThePointer() {
        let pointer = CGPoint(x: 500, y: 400)
        let box = PickerLayout.loupeFrame(pointer: pointer, side: 132, labelHeight: 32, in: bounds)
        #expect(box.minX > pointer.x && box.maxY < pointer.y)
        #expect(!box.insetBy(dx: -10, dy: -10).contains(pointer))
    }

    @Test func flipsAtTheRightAndBottomEdges() {
        let pointer = CGPoint(x: 990, y: 20)
        let box = PickerLayout.loupeFrame(pointer: pointer, side: 132, labelHeight: 32, in: bounds)
        #expect(box.maxX < pointer.x)
        #expect(box.minY > pointer.y)
        #expect(bounds.contains(box))
    }
}
