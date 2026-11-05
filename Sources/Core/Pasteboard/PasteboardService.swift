import AppKit

/// The single place that reads and writes the system clipboard. Features never touch
/// `NSPasteboard` directly: Core needs to know which changes FastUtils made itself so clipboard
/// history (stage 5) can tell them apart from the user's copies.
@MainActor
public final class PasteboardService {
    private let pasteboard: NSPasteboard
    /// `changeCount` right after our last write.
    public private(set) var lastOwnChangeCount: Int?

    public init(pasteboard: NSPasteboard = .general) {
        self.pasteboard = pasteboard
    }

    public var changeCount: Int { pasteboard.changeCount }

    /// Whether the current clipboard content was written by FastUtils.
    public var currentContentIsOwn: Bool { lastOwnChangeCount == pasteboard.changeCount }

    public func writeText(_ text: String) {
        pasteboard.clearContents()
        pasteboard.setString(text, forType: .string)
        lastOwnChangeCount = pasteboard.changeCount
    }

    public func readText() -> String? {
        pasteboard.string(forType: .string)
    }
}
