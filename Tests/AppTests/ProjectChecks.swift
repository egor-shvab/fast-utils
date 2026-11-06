import Core
import Foundation
import Testing
@testable import FastUtilsApp

/// The repository root, found from this file's location.
private let root = URL(filePath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()

/// Every Swift source of the app with its path, for checks that span all modules.
private func sources() throws -> [(path: String, text: String)] {
    let enumerator = FileManager.default.enumerator(at: root.appending(path: "Sources"), includingPropertiesForKeys: nil)
    return try (enumerator?.compactMap { $0 as? URL } ?? [])
        .filter { $0.pathExtension == "swift" }
        .map { ($0.path, try String(contentsOf: $0, encoding: .utf8)) }
}

/// All string-literal captures of `pattern` (one capture group) across the sources.
private func matches(_ pattern: String, in files: [(path: String, text: String)]) throws -> Set<String> {
    let regex = try NSRegularExpression(pattern: pattern)
    var result = Set<String>()
    for file in files {
        let range = NSRange(file.text.startIndex..., in: file.text)
        for match in regex.matches(in: file.text, range: range) {
            if let capture = Range(match.range(at: 1), in: file.text) { result.insert(String(file.text[capture])) }
        }
    }
    return result
}

@MainActor
struct FeatureLinkTests {
    /// Features call each other by action id ("translate.show"). A renamed action still compiles,
    /// but the chain would quietly fall back to "turn the feature on"; this catches it.
    @Test func everyActionReferencedByIDIsDeclared() throws {
        let context = AppContext.testing()
        let declared = Set(featureTypes.flatMap { $0.init(context: context).actions.map(\.id.rawValue) })
        let referenced = try matches(#"(?:perform|actionID:)\(?\s*"([a-z]+\.[A-Za-z]+)""#, in: sources())
        #expect(referenced.contains("translate.show"))  // the scan itself works
        #expect(referenced.subtracting(declared).isEmpty, "unknown action ids: \(referenced.subtracting(declared).sorted())")
    }
}

struct LocalizationTests {
    private func keys(_ language: String) throws -> (strings: Set<String>, plurals: Set<String>) {
        let folder = root.appending(path: "Resources/\(language).lproj")
        let strings = try #require(NSDictionary(contentsOf: folder.appending(path: "Localizable.strings")) as? [String: String])
        let plurals = try #require(NSDictionary(contentsOf: folder.appending(path: "Localizable.stringsdict")) as? [String: Any])
        return (Set(strings.keys), Set(plurals.keys))
    }

    @Test func russianAndEnglishHaveTheSameKeys() throws {
        let ru = try keys("ru")
        let en = try keys("en")
        #expect(ru.strings.subtracting(en.strings).isEmpty, "only in ru: \(ru.strings.subtracting(en.strings).sorted())")
        #expect(en.strings.subtracting(ru.strings).isEmpty, "only in en: \(en.strings.subtracting(ru.strings).sorted())")
        #expect(ru.plurals == en.plurals)
    }

    /// Literal keys in code (`String(localized: "…")`, `NSLocalizedString("…"`, `LocalizationValue("…")`)
    /// must exist; otherwise the interface shows the raw key. Keys built at runtime are not covered.
    @Test func everyLiteralKeyInCodeExists() throws {
        let ru = try keys("ru")
        let used = try matches(#"(?:localized: |NSLocalizedString\(|LocalizationValue\()"([a-zA-Z0-9_.]+)""#, in: sources())
        #expect(used.count > 100)  // the scan itself works
        let missing = used.subtracting(ru.strings).subtracting(ru.plurals)
        #expect(missing.isEmpty, "missing keys: \(missing.sorted())")
    }
}
