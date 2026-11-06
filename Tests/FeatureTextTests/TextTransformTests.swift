import Testing
@testable import FeatureText

struct KeyboardLayoutMapTests {
    @Test(arguments: [
        ("ghbdtn", "привет"),
        ("Ghbdtn? Rfr ltkf", "Привет, Как дела"),
        ("kj;rf", "ложка"),
        ("`krf", "ёлка"),
        ("{jhjij", "Хорошо"),
        ("'nj dc` pf 100 he,", "это всё за 100 руб"),
    ])
    func latinBecomesRussian(_ typed: String, _ expected: String) {
        let result = KeyboardLayoutMap.convert(typed)
        #expect(result.text == expected)
        #expect(result.target == .russian)
    }

    @Test func cyrillicBecomesEnglish() {
        let result = KeyboardLayoutMap.convert("руддщ, цщкдв!")
        #expect(result.text == "hello? world!")
        #expect(result.target == .english)
    }

    @Test func roundTrip() {
        let text = "Ghbdtn? Rfr ltkf; `krf [jhjij/"
        let there = KeyboardLayoutMap.convert(text).text
        #expect(KeyboardLayoutMap.convert(there).text == text)
    }

    @Test func directionFollowsTheMajorityOfLetters() {
        #expect(KeyboardLayoutMap.target(of: "ghbdtn vbh") == .russian)
        #expect(KeyboardLayoutMap.target(of: "руддщ") == .english)
        #expect(KeyboardLayoutMap.target(of: "руддщ ok") == .english)
        #expect(KeyboardLayoutMap.target(of: "123") == .russian)  // no letters: a tie
    }
}

struct CaseToggleTests {
    @Test func lowercaseAnywhereMakesEverythingUpper() {
        #expect(CaseToggle.apply("Hello world") == "HELLO WORLD")
        #expect(CaseToggle.apply("привет, Мир 2") == "ПРИВЕТ, МИР 2")
    }

    @Test func allUpperBecomesLower() {
        #expect(CaseToggle.apply("HELLO 123") == "hello 123")
        #expect(CaseToggle.apply("ПРИВЕТ") == "привет")
    }

    @Test func togglingTwiceFromLowerReturnsTheText() {
        #expect(CaseToggle.apply(CaseToggle.apply("привет")) == "привет")
    }
}
