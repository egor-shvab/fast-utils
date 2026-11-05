import SwiftUI

/// Recognizes color strings in history items to show a swatch: #RGB, #RRGGBB, #RRGGBBAA,
/// rgb(…) / rgba(…).
enum ColorParser {
    struct RGBA: Equatable {
        var red: Double, green: Double, blue: Double, alpha: Double
        var color: Color { Color(.sRGB, red: red, green: green, blue: blue, opacity: alpha) }
    }

    static func parse(_ raw: String) -> RGBA? {
        let text = raw.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard text.count <= 40 else { return nil }
        if text.hasPrefix("#") { return parseHex(String(text.dropFirst())) }
        if text.hasPrefix("rgb") { return parseRGB(text) }
        return nil
    }

    private static func parseHex(_ hex: String) -> RGBA? {
        guard hex.allSatisfy(\.isHexDigit) else { return nil }
        let expanded: String
        switch hex.count {
        case 3: expanded = hex.map { "\($0)\($0)" }.joined() + "ff"
        case 6: expanded = hex + "ff"
        case 8: expanded = hex
        default: return nil
        }
        guard let value = UInt64(expanded, radix: 16) else { return nil }
        return RGBA(red: Double((value >> 24) & 0xff) / 255, green: Double((value >> 16) & 0xff) / 255,
                    blue: Double((value >> 8) & 0xff) / 255, alpha: Double(value & 0xff) / 255)
    }

    private static func parseRGB(_ text: String) -> RGBA? {
        guard let open = text.firstIndex(of: "("), text.hasSuffix(")") else { return nil }
        let parts = text[text.index(after: open)..<text.index(before: text.endIndex)]
            .split(whereSeparator: { $0 == "," || $0 == " " || $0 == "/" })
            .compactMap { Double($0.trimmingCharacters(in: .whitespaces)) }
        guard parts.count == 3 || parts.count == 4, parts.prefix(3).allSatisfy({ (0...255).contains($0) }) else { return nil }
        let alpha = parts.count == 4 ? (parts[3] > 1 ? parts[3] / 100 : parts[3]) : 1
        return RGBA(red: parts[0] / 255, green: parts[1] / 255, blue: parts[2] / 255, alpha: alpha)
    }
}
