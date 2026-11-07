import Foundation

/// UserDefaults-backed settings, split into namespaces so features never clash:
/// `settings.scoped("ocr").value("languages", default: …)` reads key `ocr.languages`.
/// Secrets (API keys) do not belong here — use `SecretStore`.
@MainActor
public final class SettingsStore {
    let defaults: UserDefaults

    public init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    public func scoped(_ namespace: FeatureID) -> ScopedSettings {
        ScopedSettings(prefix: namespace.rawValue, defaults: defaults)
    }

    /// App-wide settings that belong to no feature.
    public var app: ScopedSettings { scoped("app") }

    // MARK: Export / import

    /// Namespaces that belong to FastUtils. Secrets are never here (they live in the Keychain).
    static let exportedPrefixes = ["app.", "features.", "hotkeys.", "ocr.", "translate.", "clipboard.", "text.", "color."]

    /// All FastUtils settings as JSON.
    public func exportJSON() throws -> Data {
        let values = defaults.dictionaryRepresentation().filter { key, value in
            Self.exportedPrefixes.contains(where: key.hasPrefix) && JSONSerialization.isValidJSONObject([value])
        }
        return try JSONSerialization.data(withJSONObject: values, options: [.prettyPrinted, .sortedKeys])
    }

    /// Applies exported settings; unknown keys are ignored. Returns how many were applied.
    /// Features read settings at launch, so the app should restart afterwards.
    @discardableResult
    public func importJSON(_ data: Data) throws -> Int {
        guard let values = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw CocoaError(.fileReadCorruptFile)
        }
        var applied = 0
        for (key, value) in values where Self.exportedPrefixes.contains(where: key.hasPrefix) {
            defaults.set(value, forKey: key)
            applied += 1
        }
        return applied
    }
}

@MainActor
public struct ScopedSettings {
    let prefix: String
    let defaults: UserDefaults

    public func key(_ name: String) -> String { "\(prefix).\(name)" }

    /// Property-list values only (Bool, Int, Double, String, Data, Date, arrays/dicts of them).
    public func value<T>(_ name: String, default defaultValue: T) -> T {
        defaults.object(forKey: key(name)) as? T ?? defaultValue
    }

    /// The stored value as is, for values whose type is known only after reading.
    public func rawValue(_ name: String) -> Any? {
        defaults.object(forKey: key(name))
    }

    public func set(_ value: Any?, for name: String) {
        defaults.set(value, forKey: key(name))
    }

    public func remove(_ name: String) {
        defaults.removeObject(forKey: key(name))
    }
}
