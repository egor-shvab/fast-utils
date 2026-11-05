import Foundation

/// Per-feature data directories under `~/Library/Application Support/FastUtils/`.
public struct StorageService: Sendable {
    public let baseURL: URL

    public init(baseURL: URL = StorageService.defaultBaseURL) {
        self.baseURL = baseURL
    }

    public static var defaultBaseURL: URL {
        URL.applicationSupportDirectory.appending(path: AppInfo.name, directoryHint: .isDirectory)
    }

    /// Returns the feature's directory, creating it if needed.
    public func directory(for feature: FeatureID) throws -> URL {
        let url = baseURL.appending(path: feature.rawValue, directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }
}
