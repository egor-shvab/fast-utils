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

    public func set(_ value: Any?, for name: String) {
        defaults.set(value, forKey: key(name))
    }

    public func remove(_ name: String) {
        defaults.removeObject(forKey: key(name))
    }
}
