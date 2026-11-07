import Core
import Foundation

/// How a picked color is written to the clipboard.
enum ColorFormat: String, CaseIterable, Sendable {
    case hexLower, hexUpper, rgb, hsl, swiftUI

    func format(_ color: RGBColor) -> String {
        switch self {
        case .hexLower: return Self.hex(color)
        case .hexUpper: return Self.hex(color).uppercased()
        case .rgb: return "rgb(\(color.red), \(color.green), \(color.blue))"
        case .hsl:
            let (h, s, l) = Self.hsl(color)
            return "hsl(\(h), \(s)%, \(l)%)"
        case .swiftUI:
            func component(_ value: UInt8) -> String { String(format: "%.3f", Double(value) / 255) }
            return "Color(red: \(component(color.red)), green: \(component(color.green)), blue: \(component(color.blue)))"
        }
    }

    private static func hex(_ color: RGBColor) -> String {
        String(format: "#%02x%02x%02x", color.red, color.green, color.blue)
    }

    /// Hue in degrees, saturation and lightness in percent, rounded like design tools show them.
    static func hsl(_ color: RGBColor) -> (Int, Int, Int) {
        let r = Double(color.red) / 255, g = Double(color.green) / 255, b = Double(color.blue) / 255
        let maxValue = max(r, g, b), minValue = min(r, g, b)
        let lightness = (maxValue + minValue) / 2
        let delta = maxValue - minValue
        guard delta > 0 else { return (0, 0, Int((lightness * 100).rounded())) }
        let saturation = delta / (1 - abs(2 * lightness - 1))
        var hue: Double
        switch maxValue {
        case r: hue = ((g - b) / delta).truncatingRemainder(dividingBy: 6)
        case g: hue = (b - r) / delta + 2
        default: hue = (r - g) / delta + 4
        }
        hue *= 60
        if hue < 0 { hue += 360 }
        return (Int(hue.rounded()) % 360, Int((saturation * 100).rounded()), Int((lightness * 100).rounded()))
    }
}
