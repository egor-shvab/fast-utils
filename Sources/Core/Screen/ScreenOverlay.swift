import AppKit

/// An sRGB color, 8 bits per channel: what the color picker returns and the HUD can show.
public struct RGBColor: Hashable, Sendable {
    public var red: UInt8
    public var green: UInt8
    public var blue: UInt8

    public init(red: UInt8, green: UInt8, blue: UInt8) {
        self.red = red
        self.green = green
        self.blue = blue
    }

    public var nsColor: NSColor {
        NSColor(srgbRed: CGFloat(red) / 255, green: CGFloat(green) / 255, blue: CGFloat(blue) / 255, alpha: 1)
    }
}

/// A pixel of a snapshot image: top-left origin, like `CGImage`.
public struct PixelPoint: Hashable, Sendable {
    public var x: Int
    public var y: Int

    public init(x: Int, y: Int) {
        self.x = x
        self.y = y
    }

    /// Moved by whole pixels and kept inside an image of `size` pixels.
    func moved(dx: Int, dy: Int, within size: (width: Int, height: Int)) -> PixelPoint {
        PixelPoint(x: min(max(x + dx, 0), size.width - 1), y: min(max(y + dy, 0), size.height - 1))
    }
}

extension ScreenSnapshot {
    var pixelSize: (width: Int, height: Int) { (image.width, image.height) }

    /// The pixel under a point in global AppKit coordinates (bottom-left origin).
    func pixel(at point: CGPoint) -> PixelPoint {
        Self.pixel(at: point, screenFrame: frame, imageSize: CGSize(width: image.width, height: image.height))
    }

    /// Same ratio as `pixelRect`: the real image/screen size, not `scale`.
    static func pixel(at point: CGPoint, screenFrame: CGRect, imageSize: CGSize) -> PixelPoint {
        let sx = imageSize.width / screenFrame.width
        let sy = imageSize.height / screenFrame.height
        let x = Int(((point.x - screenFrame.minX) * sx).rounded(.down))
        let y = Int(((screenFrame.maxY - point.y) * sy).rounded(.down))
        return PixelPoint(x: min(max(x, 0), Int(imageSize.width) - 1), y: min(max(y, 0), Int(imageSize.height) - 1))
    }

    /// The center of a pixel in global AppKit coordinates.
    func point(ofPixel pixel: PixelPoint) -> CGPoint {
        let sx = CGFloat(image.width) / frame.width
        let sy = CGFloat(image.height) / frame.height
        return CGPoint(x: frame.minX + (CGFloat(pixel.x) + 0.5) / sx, y: frame.maxY - (CGFloat(pixel.y) + 0.5) / sy)
    }

    /// The pixel's color converted to sRGB: snapshots come in the display's color space
    /// (Display P3 on Mac screens), and drawing into an sRGB context converts it, so a CSS
    /// `#3a7bd5` on a web page reads back as `#3a7bd5` (±1 from rounding).
    func color(atPixel pixel: PixelPoint) -> RGBColor? {
        Self.color(in: image, atPixel: pixel)
    }

    static func color(in image: CGImage, atPixel pixel: PixelPoint) -> RGBColor? {
        guard let crop = image.cropping(to: CGRect(x: pixel.x, y: pixel.y, width: 1, height: 1)),
              let space = CGColorSpace(name: CGColorSpace.sRGB),
              let context = CGContext(data: nil, width: 1, height: 1, bitsPerComponent: 8, bytesPerRow: 4,
                                      space: space, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
        else { return nil }
        context.draw(crop, in: CGRect(x: 0, y: 0, width: 1, height: 1))
        guard let data = context.data?.assumingMemoryBound(to: UInt8.self) else { return nil }
        return RGBColor(red: data[0], green: data[1], blue: data[2])
    }

    /// `count` × `count` pixels centered on `center`, gray beyond the image edges.
    func pixels(around center: PixelPoint, count: Int) -> CGImage? {
        let radius = count / 2
        let wanted = CGRect(x: center.x - radius, y: center.y - radius, width: count, height: count)
        let available = wanted.intersection(CGRect(x: 0, y: 0, width: image.width, height: image.height))
        guard !available.isNull, let crop = image.cropping(to: available),
              let space = image.colorSpace ?? CGColorSpace(name: CGColorSpace.sRGB),
              let context = CGContext(data: nil, width: count, height: count, bitsPerComponent: 8, bytesPerRow: 0,
                                      space: space, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
        else { return nil }
        context.setFillColor(gray: 0.5, alpha: 1)
        context.fill(CGRect(x: 0, y: 0, width: count, height: count))
        // The context has a bottom-left origin, the image rows a top-left one.
        let x = available.minX - wanted.minX
        let y = wanted.maxY - available.maxY
        context.draw(crop, in: CGRect(x: x, y: y, width: available.width, height: available.height))
        return context.makeImage()
    }
}

/// A full-screen borderless panel over one display, shown over full-screen apps and on
/// every Space. Used by area selection and the color picker.
public final class OverlayWindow: NSPanel {
    public init(snapshot: ScreenSnapshot) {
        super.init(contentRect: snapshot.frame, styleMask: [.borderless, .nonactivatingPanel],
                   backing: .buffered, defer: false)
        level = .screenSaver
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
        isOpaque = true
        backgroundColor = .black
        hasShadow = false
        hidesOnDeactivate = false
        acceptsMouseMovedEvents = true
        animationBehavior = .none
        setFrame(snapshot.frame, display: false)
    }

    override public var canBecomeKey: Bool { true }
}

/// Zoomed pixels with crisp edges (no interpolation).
@MainActor
public enum Magnifier {
    public enum Style: Sendable {
        /// Rounded square with a crosshair: area selection.
        case selection
        /// Rounded square with the center pixel framed; `count` pixels across: the color picker.
        case pixelGrid(count: Int)
    }

    public static func draw(_ image: CGImage, in box: CGRect, style: Style, context: CGContext) {
        let shape = NSBezierPath(roundedRect: box, xRadius: 8, yRadius: 8)
        context.saveGState()
        shape.addClip()
        context.interpolationQuality = .none
        context.draw(image, in: box)
        switch style {
        case .selection:
            NSColor.controlAccentColor.withAlphaComponent(0.8).setStroke()
            let cross = NSBezierPath()
            cross.move(to: CGPoint(x: box.midX, y: box.minY))
            cross.line(to: CGPoint(x: box.midX, y: box.maxY))
            cross.move(to: CGPoint(x: box.minX, y: box.midY))
            cross.line(to: CGPoint(x: box.maxX, y: box.midY))
            cross.lineWidth = 1
            cross.stroke()
        case .pixelGrid(let count):
            let cell = box.width / CGFloat(count)
            let center = CGRect(x: box.midX - cell / 2, y: box.midY - cell / 2, width: cell, height: cell)
            NSColor.black.withAlphaComponent(0.6).setStroke()
            NSBezierPath(rect: center.insetBy(dx: -1, dy: -1)).stroke()
            NSColor.white.setStroke()
            NSBezierPath(rect: center).stroke()
        }
        context.restoreGState()

        NSColor.white.withAlphaComponent(0.9).setStroke()
        shape.lineWidth = 2
        shape.stroke()
    }
}
