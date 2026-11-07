import Core
import Testing
@testable import FeatureColor

struct ColorFormatTests {
    let blue = Core.RGBColor(red: 0x3a, green: 0x7b, blue: 0xd5)

    @Test func everyFormatForOneColor() {
        #expect(ColorFormat.hexLower.format(blue) == "#3a7bd5")
        #expect(ColorFormat.hexUpper.format(blue) == "#3A7BD5")
        #expect(ColorFormat.rgb.format(blue) == "rgb(58, 123, 213)")
        #expect(ColorFormat.hsl.format(blue) == "hsl(215, 65%, 53%)")
        #expect(ColorFormat.swiftUI.format(blue) == "Color(red: 0.227, green: 0.482, blue: 0.835)")
    }

    @Test func blackWhiteAndGray() {
        let black = Core.RGBColor(red: 0, green: 0, blue: 0)
        let white = Core.RGBColor(red: 255, green: 255, blue: 255)
        #expect(ColorFormat.hexLower.format(black) == "#000000")
        #expect(ColorFormat.hexLower.format(white) == "#ffffff")
        #expect(ColorFormat.hsl.format(white) == "hsl(0, 0%, 100%)")
        #expect(ColorFormat.hsl.format(Core.RGBColor(red: 128, green: 128, blue: 128)) == "hsl(0, 0%, 50%)")
    }

    @Test func hueAroundTheCircle() {
        #expect(ColorFormat.hsl(Core.RGBColor(red: 255, green: 0, blue: 0)) == (0, 100, 50))
        #expect(ColorFormat.hsl(Core.RGBColor(red: 0, green: 255, blue: 0)) == (120, 100, 50))
        #expect(ColorFormat.hsl(Core.RGBColor(red: 0, green: 0, blue: 255)) == (240, 100, 50))
        #expect(ColorFormat.hsl(Core.RGBColor(red: 255, green: 0, blue: 128)) == (330, 100, 50))
    }
}
