import AppKit
import Core
import CoreImage
import Testing
@testable import FeatureOCR

private func qrImage(_ text: String) -> CGImage {
    let filter = CIFilter(name: "CIQRCodeGenerator")!
    filter.setValue(Data(text.utf8), forKey: "inputMessage")
    let output = filter.outputImage!.transformed(by: CGAffineTransform(scaleX: 10, y: 10))
    // Quiet zone: put the code on a white canvas.
    let canvas = CIImage(color: .white).cropped(to: output.extent.insetBy(dx: -40, dy: -40))
    return CIContext().createCGImage(output.composited(over: canvas), from: canvas.extent)!
}

struct CodeTests {
    @Test func detectsQRPayload() async {
        let payloads = await CodeDetector.payloads(in: qrImage("https://example.com/fastutils"))
        #expect(payloads == ["https://example.com/fastutils"])
    }

    @Test func combineModes() {
        #expect(CodeDetector.combine(codes: ["C"], text: "T", mode: .withText) == "C\n\nT")
        #expect(CodeDetector.combine(codes: ["C"], text: "T", mode: .codeOnly) == "C")
        #expect(CodeDetector.combine(codes: ["C"], text: "T", mode: .off) == "T")
        #expect(CodeDetector.combine(codes: [], text: "T", mode: .codeOnly) == "T")
        #expect(CodeDetector.combine(codes: ["C"], text: "", mode: .withText) == "C")
    }
}

@MainActor
struct OCRActionTests {
    @Test func recognizeImageActionIsOfferedForImagesAndReturnsText() async throws {
        let context = AppContext.testing()
        let registry = FeatureRegistry(context: context, types: [OCRFeature.self])
        await registry.startEnabledFeatures()

        #expect(context.actions.actions(accepting: .image).map(\.id) == ["ocr.recognizeImage"])
        let output = try await context.actions.perform("ocr.recognizeImage", input: .image(qrImage("QR-текст")))
        guard case .text(let text) = output else { Issue.record("expected text"); return }
        #expect(text.contains("QR-текст"))
        // Not shown in menus / shortcuts.
        #expect(!registry.feature("ocr")!.menuItems.contains { $0.actionID == "ocr.recognizeImage" })
    }
}
