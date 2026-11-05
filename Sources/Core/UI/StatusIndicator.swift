import Observation

/// Lets a feature change the status bar icon to show a state, e.g. paused clipboard history.
/// `nil` symbol = the normal icon.
@MainActor
@Observable
public final class StatusIndicator {
    public private(set) var symbol: String?
    public private(set) var tooltip: String?

    public init() {}

    public func set(symbol: String?, tooltip: String? = nil) {
        self.symbol = symbol
        self.tooltip = tooltip
    }
}
