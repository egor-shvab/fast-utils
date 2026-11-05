import CoreGraphics
import Testing
@testable import FeatureOCR

/// Builds a line at (x, top) with the given width; 0.04 high (normalized, origin bottom-left).
private func line(_ text: String, x: CGFloat = 0.05, top: CGFloat, width: CGFloat = 0.5, height: CGFloat = 0.04) -> RecognizedLine {
    RecognizedLine(text: text, box: CGRect(x: x, y: top - height, width: width, height: height))
}

struct TextLayoutTests {
    @Test func ordersTopToBottomRegardlessOfInputOrder() {
        let lines = [line("третья", top: 0.80), line("первая", top: 0.90), line("вторая", top: 0.85)]
        #expect(TextLayout.format(lines, mode: .asOnScreen) == "первая\nвторая\nтретья")
    }

    @Test func piecesOfOneRowAreJoinedLeftToRight() {
        let lines = [line("мир", x: 0.4, top: 0.9, width: 0.2), line("Привет,", x: 0.05, top: 0.9, width: 0.3)]
        #expect(TextLayout.format(lines, mode: .asOnScreen) == "Привет, мир")
    }

    @Test func largeVerticalGapStartsParagraph() {
        let lines = [line("Абзац один", top: 0.9), line("продолжение", top: 0.85), line("Абзац два", top: 0.70)]
        #expect(TextLayout.format(lines, mode: .asOnScreen) == "Абзац один\nпродолжение\n\nАбзац два")
    }

    @Test func joinParagraphsRemovesHyphenation() {
        let lines = [line("Это длинный при-", top: 0.9), line("мер текста и ещё", top: 0.85), line("Second paragraph", top: 0.7)]
        #expect(TextLayout.format(lines, mode: .joinParagraphs) == "Это длинный пример текста и ещё\n\nSecond paragraph")
    }

    @Test func hyphenBeforeCapitalOrSpaceIsKept() {
        #expect(TextLayout.joinLines(["Москва -", "столица"]) == "Москва - столица")
        #expect(TextLayout.joinLines(["Санкт-", "Петербург"]) == "Санкт- Петербург")
    }

    @Test func twoColumnsAreReadOneAfterAnother() {
        let lines = [
            line("L1", x: 0.05, top: 0.9, width: 0.4), line("R1", x: 0.55, top: 0.9, width: 0.4),
            line("L2", x: 0.05, top: 0.85, width: 0.4), line("R2", x: 0.55, top: 0.85, width: 0.4),
        ]
        #expect(TextLayout.format(lines, mode: .asOnScreen) == "L1\nL2\n\nR1\nR2")
    }

    @Test func cleansWhitespaceAndDropsEmptyLines() {
        let lines = [line("  много   пробелов\t здесь ", top: 0.9), line("   ", top: 0.85)]
        #expect(TextLayout.format(lines, mode: .asOnScreen) == "много пробелов здесь")
    }

    @Test func emptyInputGivesEmptyText() {
        #expect(TextLayout.format([], mode: .asOnScreen).isEmpty)
    }
}
