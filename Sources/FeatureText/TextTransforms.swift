import Foundation

/// Text typed in the wrong keyboard layout ("ghbdtn" ↔ "привет"), converted by *physical key*
/// between ABC and "Russian – PC" — the layouts the owner uses. A static table rather than
/// `UCKeyTranslate`: the Text Input Sources API aborts the process when called from two
/// threads at once (see CLAUDE.md).
enum KeyboardLayoutMap {
    enum Language: String, Sendable {
        case english = "en"
        case russian = "ru"
    }

    /// Pairs of characters on the same key: ABC first, Russian – PC second. Unshifted and shifted.
    private static let pairs: [(Character, Character)] = {
        let english = "`qwertyuiop[]asdfghjkl;'zxcvbnm,./" + "~QWERTYUIOP{}ASDFGHJKL:\"ZXCVBNM<>?" + "@#$^&|"
        let russian = "ёйцукенгшщзхъфывапролджэячсмитьбю." + "ЁЙЦУКЕНГШЩЗХЪФЫВАПРОЛДЖЭЯЧСМИТЬБЮ," + "\"№;:?/"
        return Array(zip(english, russian))
    }()

    private static let toRussian = Dictionary(uniqueKeysWithValues: pairs.map { ($0.0, $0.1) })
    private static let toEnglish = Dictionary(uniqueKeysWithValues: pairs.map { ($0.1, $0.0) })

    /// Mostly Latin letters (or a tie) → Russian, mostly Cyrillic → English.
    static func target(of text: String) -> Language {
        var latin = 0
        var cyrillic = 0
        for scalar in text.unicodeScalars where scalar.properties.isAlphabetic {
            if scalar.isASCII { latin += 1 } else if (0x0400...0x04FF).contains(scalar.value) { cyrillic += 1 }
        }
        return latin >= cyrillic ? .russian : .english
    }

    static func convert(_ text: String) -> (text: String, target: Language) {
        let target = target(of: text)
        let table = target == .russian ? toRussian : toEnglish
        return (String(text.map { table[$0] ?? $0 }), target)
    }
}

/// UPPER ↔ lower: any lowercase letter → everything upper, otherwise everything lower,
/// so pressing the shortcut again undoes it.
enum CaseToggle {
    static func apply(_ text: String) -> String {
        text.contains(where: \.isLowercase) ? text.uppercased() : text.lowercased()
    }
}
