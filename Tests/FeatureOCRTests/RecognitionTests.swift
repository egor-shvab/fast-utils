import AppKit
import Testing
@testable import FeatureOCR

/// Real Vision recognition on images drawn by the test (offline, no screen access).
struct RecognitionTests {
    private func render(_ lines: [String], width: Int = 900, fontSize: CGFloat = 28) -> CGImage {
        let lineHeight = Int(fontSize * 1.6)
        let height = lineHeight * lines.count + 40
        let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: width, pixelsHigh: height,
                                   bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                                   colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
        NSColor.white.setFill()
        NSRect(x: 0, y: 0, width: width, height: height).fill()
        let attributes: [NSAttributedString.Key: Any] = [.font: NSFont.systemFont(ofSize: fontSize), .foregroundColor: NSColor.black]
        for (index, text) in lines.enumerated() {
            (text as NSString).draw(at: CGPoint(x: 20, y: height - 20 - lineHeight * (index + 1)), withAttributes: attributes)
        }
        NSGraphicsContext.restoreGraphicsState()
        return rep.cgImage!
    }

    @Test func recognizesRussianAndEnglishInOrder() async throws {
        let image = render(["Привет, это проверка", "Hello, this is a test", "Третья строка 2026"])
        let lines = try await TextRecognizer().recognize(image, languages: ["ru", "en"], autoDetect: false)
        let text = TextLayout.format(lines, mode: .asOnScreen)
        let rows = text.split(separator: "\n").map(String.init)

        #expect(rows.count == 3)
        #expect(rows.first?.contains("Привет") == true)
        #expect(rows.dropFirst().first?.contains("Hello") == true)
        #expect(rows.last?.contains("2026") == true)
    }

    @Test func smallImageIsUpscaled() {
        let small = render(["tiny"], width: 120, fontSize: 12)
        let upscaled = TextRecognizer.upscaledIfSmall(small)
        #expect(upscaled.width == small.width * 3)
    }

    @Test func blankImageHasNoText() async throws {
        let image = render([])
        let lines = try await TextRecognizer().recognize(image, languages: ["ru", "en"], autoDetect: false)
        #expect(TextLayout.format(lines, mode: .asOnScreen).isEmpty)
    }

    @Test func supportedLanguagesIncludeRussian() {
        #expect(TextRecognizer.supportedLanguages().contains("ru"))
    }
}
