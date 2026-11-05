import CoreGraphics
import Foundation

/// How recognized lines become text.
public enum LineMode: String, CaseIterable, Sendable {
    /// Keep line breaks as on screen; blank line between paragraphs.
    case asOnScreen
    /// Join the lines of a paragraph with spaces, removing end-of-line hyphenation.
    case joinParagraphs
}

/// Turns Vision lines into text: reading order (columns, then rows top to bottom, left to
/// right), paragraph detection by vertical gaps, whitespace cleanup. Pure — covered by tests.
enum TextLayout {
    static func format(_ lines: [RecognizedLine], mode: LineMode) -> String {
        let cleaned = lines.compactMap { line -> RecognizedLine? in
            let text = collapseSpaces(line.text)
            return text.isEmpty ? nil : RecognizedLine(text: text, box: line.box)
        }
        let columns = splitIntoColumns(cleaned)
        return columns
            .map { formatColumn(rows(of: $0), mode: mode) }
            .filter { !$0.isEmpty }
            .joined(separator: "\n\n")
    }

    // MARK: Rows

    struct Row {
        var text: String
        var box: CGRect
    }

    /// Groups lines whose vertical centers overlap into rows, top to bottom; a row's pieces
    /// are ordered left to right.
    static func rows(of lines: [RecognizedLine]) -> [Row] {
        let sorted = lines.sorted { $0.box.midY > $1.box.midY }
        var groups: [[RecognizedLine]] = []
        for line in sorted {
            if let last = groups.last?.last,
               abs(last.box.midY - line.box.midY) < min(last.box.height, line.box.height) * 0.5 {
                groups[groups.count - 1].append(line)
            } else {
                groups.append([line])
            }
        }
        return groups.map { group in
            let ordered = group.sorted { $0.box.minX < $1.box.minX }
            let box = ordered.dropFirst().reduce(ordered[0].box) { $0.union($1.box) }
            return Row(text: ordered.map(\.text).joined(separator: " "), box: box)
        }
    }

    // MARK: Columns

    /// Splits lines into columns when a vertical gap (≥ 3% of the width) separates them and
    /// each side has at least two lines. Applied recursively; a full-width line (a title over
    /// two columns) prevents the split, which keeps such layouts in plain row order.
    static func splitIntoColumns(_ lines: [RecognizedLine]) -> [[RecognizedLine]] {
        guard lines.count >= 4 else { return [lines] }
        let sorted = lines.sorted { $0.box.minX < $1.box.minX }
        var reach = sorted[0].box.maxX
        for index in 1..<sorted.count {
            let line = sorted[index]
            if line.box.minX - reach >= 0.03 {
                let left = Array(sorted[..<index])
                let right = Array(sorted[index...])
                if left.count >= 2 && right.count >= 2 {
                    return splitIntoColumns(left) + splitIntoColumns(right)
                }
            }
            reach = max(reach, line.box.maxX)
        }
        return [lines]
    }

    // MARK: Paragraphs

    static func formatColumn(_ rows: [Row], mode: LineMode) -> String {
        guard !rows.isEmpty else { return "" }
        let heights = rows.map(\.box.height).sorted()
        let typical = heights[heights.count / 2]

        var paragraphs: [[String]] = [[rows[0].text]]
        for index in 1..<rows.count {
            let gap = rows[index - 1].box.minY - rows[index].box.maxY
            if gap > typical * 0.8 {
                paragraphs.append([rows[index].text])
            } else {
                paragraphs[paragraphs.count - 1].append(rows[index].text)
            }
        }

        switch mode {
        case .asOnScreen:
            return paragraphs.map { $0.joined(separator: "\n") }.joined(separator: "\n\n")
        case .joinParagraphs:
            return paragraphs.map(joinLines).joined(separator: "\n\n")
        }
    }

    /// Joins lines with spaces; "приме-" + "р" → "пример" when a line ends with a hyphen right
    /// after a letter and the next line starts with a lowercase letter.
    static func joinLines(_ lines: [String]) -> String {
        var result = ""
        for line in lines {
            guard !result.isEmpty else { result = line; continue }
            if let last = result.last, "-‐­".contains(last),
               result.dropLast().last?.isLetter == true,
               line.first?.isLowercase == true {
                result.removeLast()
                result += line
            } else {
                result += " " + line
            }
        }
        return result
    }

    static func collapseSpaces(_ text: String) -> String {
        text.split(whereSeparator: { $0 == " " || $0 == "\t" }).joined(separator: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
