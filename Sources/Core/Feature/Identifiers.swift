/// Stable identifier of a feature module, e.g. "ocr". Used as a settings/storage namespace.
public struct FeatureID: Hashable, Sendable, ExpressibleByStringLiteral, CustomStringConvertible {
    public let rawValue: String
    public init(_ rawValue: String) { self.rawValue = rawValue }
    public init(stringLiteral value: String) { self.init(value) }
    public var description: String { rawValue }
}

/// Stable identifier of an action, prefixed with its feature: "ocr.captureText".
/// Hotkeys, menu items and cross-feature chains refer to actions by this id.
public struct ActionID: Hashable, Sendable, ExpressibleByStringLiteral, CustomStringConvertible {
    public let rawValue: String
    public init(_ rawValue: String) { self.rawValue = rawValue }
    public init(stringLiteral value: String) { self.init(value) }
    public var description: String { rawValue }
}
