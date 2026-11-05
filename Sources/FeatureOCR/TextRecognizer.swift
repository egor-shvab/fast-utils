import CoreGraphics
import Foundation
import Vision

/// One recognized line. `box` is normalized to the image (0…1), origin at the bottom-left.
public struct RecognizedLine: Equatable, Sendable {
    public var text: String
    public var box: CGRect

    public init(text: String, box: CGRect) {
        self.text = text
        self.box = box
    }
}

/// Vision text recognition (`RecognizeTextRequest`, accurate level, language correction).
struct TextRecognizer {
    /// Languages Vision supports in this OS, as short identifiers ("ru", "en", …).
    static func supportedLanguages() -> [String] {
        var request = RecognizeTextRequest()
        request.recognitionLevel = .accurate
        return request.supportedRecognitionLanguages.map(\.minimalIdentifier)
    }

    func recognize(_ image: CGImage, languages: [String], autoDetect: Bool) async throws -> [RecognizedLine] {
        var request = RecognizeTextRequest()
        request.recognitionLevel = .accurate
        request.usesLanguageCorrection = true
        request.automaticallyDetectsLanguage = autoDetect
        if !languages.isEmpty {
            request.recognitionLanguages = languages.map { Locale.Language(identifier: $0) }
        }
        let observations = try await request.perform(on: Self.upscaledIfSmall(image))
        return observations.compactMap { observation in
            guard let candidate = observation.topCandidates(1).first else { return nil }
            let box = observation.boundingBox
            return RecognizedLine(
                text: candidate.string,
                box: CGRect(origin: box.origin, size: CGSize(width: box.width, height: box.height))
            )
        }
    }

    /// Small selections recognize noticeably better when enlarged 2–3× first.
    static func upscaledIfSmall(_ image: CGImage) -> CGImage {
        let pixels = image.width * image.height
        let factor = pixels < 150_000 ? 3 : (pixels < 600_000 ? 2 : 1)
        guard factor > 1,
              let context = CGContext(
                  data: nil, width: image.width * factor, height: image.height * factor,
                  bitsPerComponent: 8, bytesPerRow: 0, space: CGColorSpaceCreateDeviceRGB(),
                  bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
              )
        else { return image }
        context.interpolationQuality = .high
        context.draw(image, in: CGRect(x: 0, y: 0, width: image.width * factor, height: image.height * factor))
        return context.makeImage() ?? image
    }
}
