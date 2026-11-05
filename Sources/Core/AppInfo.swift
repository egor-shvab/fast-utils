import Foundation

/// Static facts about the app shared by all modules.
public enum AppInfo {
    public static let bundleIdentifier = "com.yahor.FastUtils"
    public static let name = "FastUtils"

    /// Version from Info.plist; "dev" when running outside the .app bundle (e.g. `swift run`).
    public static var version: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "dev"
    }
}
