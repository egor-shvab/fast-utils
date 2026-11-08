import AppKit
import Core
import UniformTypeIdentifiers

/// Draws annotations into a CGContext — the same code on screen and in the exported image.
@MainActor
enum AnnotationRenderer {
    static func textAttributes(color: InkColor, fontSize: CGFloat) -> [NSAttributedString.Key: Any] {
        [.font: Annotation.font(ofSize: fontSize), .foregroundColor: color.nsColor]
    }

    /// Expects `NSGraphicsContext.current` to wrap `context` (needed for text).
    static func draw(_ annotation: Annotation, in context: CGContext) {
        let color = annotation.color.nsColor.cgColor
        let width = annotation.size.lineWidth
        context.saveGState()
        defer { context.restoreGState() }
        context.setStrokeColor(color)
        context.setFillColor(color)
        context.setLineWidth(width)
        context.setLineCap(.round)
        context.setLineJoin(.round)

        switch annotation.shape {
        case .pen(let points):
            guard let first = points.first else { return }
            if points.count == 1 {
                context.fillEllipse(in: CGRect(x: first.x - width / 2, y: first.y - width / 2, width: width, height: width))
                return
            }
            context.addLines(between: points)
            context.strokePath()
        case .arrow(let from, let to):
            let head = EditorGeometry.arrowHead(from: from, to: to, lineWidth: width)
            context.move(to: from)
            context.addLine(to: head.shaftEnd)
            context.strokePath()
            context.move(to: head.tip)
            context.addLine(to: head.left)
            context.addLine(to: head.right)
            context.closePath()
            context.fillPath()
        case .ellipse(let rect):
            context.strokeEllipse(in: rect)
        case .rectangle(let rect):
            context.stroke(rect)
        case .text(let origin, let string, let fontSize):
            (string as NSString).draw(at: origin, withAttributes: textAttributes(color: annotation.color, fontSize: fontSize))
        }
    }
}

/// The result image: the area of the frozen screen at full resolution, with the drawings.
@MainActor
enum ScreenshotExporter {
    /// - Parameter rect: the area in points of the snapshot's screen (local, bottom-left origin).
    static func render(snapshot: ScreenSnapshot, rect: CGRect, annotations: [Annotation]) -> CGImage? {
        let global = rect.offsetBy(dx: snapshot.frame.minX, dy: snapshot.frame.minY)
        let pixels = ScreenSnapshot.pixelRect(for: global, screenFrame: snapshot.frame,
                                              imageSize: CGSize(width: snapshot.image.width, height: snapshot.image.height))
        guard let crop = snapshot.image.cropping(to: pixels),
              let space = snapshot.image.colorSpace ?? CGColorSpace(name: CGColorSpace.sRGB),
              let context = CGContext(data: nil, width: crop.width, height: crop.height, bitsPerComponent: 8,
                                      bytesPerRow: 0, space: space, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
        else { return nil }
        context.draw(crop, in: CGRect(x: 0, y: 0, width: crop.width, height: crop.height))

        // Points → pixels of this image, so lines and text are as sharp as the screen.
        context.scaleBy(x: CGFloat(crop.width) / rect.width, y: CGFloat(crop.height) / rect.height)
        context.translateBy(x: -rect.minX, y: -rect.minY)
        context.clip(to: rect)
        let previous = NSGraphicsContext.current
        NSGraphicsContext.current = NSGraphicsContext(cgContext: context, flipped: false)
        annotations.forEach { AnnotationRenderer.draw($0, in: context) }
        NSGraphicsContext.current = previous
        return context.makeImage()
    }

    static func pngData(_ image: CGImage) -> Data? {
        let data = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(data, UTType.png.identifier as CFString, 1, nil) else { return nil }
        CGImageDestinationAddImage(destination, image, nil)
        return CGImageDestinationFinalize(destination) ? data as Data : nil
    }

    /// "Снимок экрана 2026-11-07 в 08.15.30" — like the system's names.
    static func baseName(for date: Date, format: String) -> String {
        let day = DateFormatter()
        day.locale = Locale(identifier: "en_US_POSIX")
        day.dateFormat = "yyyy-MM-dd"
        let time = DateFormatter()
        time.locale = Locale(identifier: "en_US_POSIX")
        time.dateFormat = "HH.mm.ss"
        return String(format: format, day.string(from: date), time.string(from: date))
    }

    /// A file URL in `folder` that does not exist yet: "name.png", "name (2).png", …
    static func uniqueURL(in folder: URL, baseName: String) -> URL {
        var url = folder.appending(path: baseName + ".png")
        var number = 2
        while FileManager.default.fileExists(atPath: url.path) {
            url = folder.appending(path: "\(baseName) (\(number)).png")
            number += 1
        }
        return url
    }
}
