import Foundation
import Testing
@testable import Core

@MainActor
struct SettingsStoreTests {
    let context = AppContext.testing()

    @Test func namespacesDoNotClash() {
        let ocr = context.settings.scoped("ocr")
        let translate = context.settings.scoped("translate")

        ocr.set("ru", for: "language")
        translate.set("en", for: "language")

        #expect(ocr.value("language", default: "") == "ru")
        #expect(translate.value("language", default: "") == "en")
        #expect(ocr.key("language") == "ocr.language")
    }

    @Test func returnsDefaultWhenMissingOrWrongType() {
        let s = context.settings.scoped("x")
        #expect(s.value("missing", default: 42) == 42)
        s.set("text", for: "number")
        #expect(s.value("number", default: 7) == 7)
    }

    @Test func storageCreatesFeatureDirectory() throws {
        let url = try context.storage.directory(for: "ocr")
        var isDir: ObjCBool = false
        #expect(FileManager.default.fileExists(atPath: url.path, isDirectory: &isDir) && isDir.boolValue)
        #expect(url.lastPathComponent == "ocr")
    }

    @Test func inMemorySecrets() throws {
        try context.secrets.setSecret("k", for: "deepl")
        #expect(context.secrets.secret(for: "deepl") == "k")
        try context.secrets.setSecret(nil, for: "deepl")
        #expect(context.secrets.secret(for: "deepl") == nil)
    }
}

@MainActor
struct KeychainSecretStoreTests {
    /// A throwaway service in the login keychain; removed at the end.
    @Test func updatesInPlaceAndDeletes() throws {
        let store = KeychainSecretStore(service: "com.yahor.FastUtils.tests.\(UUID().uuidString)")
        defer { try? store.setSecret(nil, for: "key") }
        try store.setSecret("first", for: "key")
        try store.setSecret("second", for: "key")  // existing item: updated, not deleted and re-added
        #expect(store.secret(for: "key") == "second")
        try store.setSecret(nil, for: "key")
        #expect(store.secret(for: "key") == nil)
        try store.setSecret(nil, for: "key")  // deleting a missing item is fine
    }
}
