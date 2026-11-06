import AppKit
import ImageIO
import OSLog

/// What was on the clipboard at one moment. Only the representations FastUtils uses are read.
public struct PasteboardSnapshot: Sendable {
    public var changeCount: Int
    /// All type identifiers of the first item, in the order the source app wrote them
    /// (the first one is the source's preferred representation).
    public var types: [String]
    public var string: String?
    public var rtf: Data?
    public var html: Data?
    public var image: Data?
    public var fileURLs: [URL]
    public var sourceBundleID: String?
    public var sourceName: String?
    public var date: Date

    public init(changeCount: Int = 0, types: [String] = [], string: String? = nil, rtf: Data? = nil,
                html: Data? = nil, image: Data? = nil, fileURLs: [URL] = [], sourceBundleID: String? = nil,
                sourceName: String? = nil, date: Date = Date()) {
        self.changeCount = changeCount
        self.types = types
        self.string = string
        self.rtf = rtf
        self.html = html
        self.image = image
        self.fileURLs = fileURLs
        self.sourceBundleID = sourceBundleID
        self.sourceName = sourceName
        self.date = date
    }
}

/// The clipboard changed. `recordInHistory == false` for FastUtils' own technical writes
/// (e.g. restoring the previous clipboard), which history must ignore.
public struct ClipboardChanged: AppEvent {
    public let snapshot: PasteboardSnapshot
    public let recordInHistory: Bool
}

/// The single place that reads and writes the system clipboard. Features never touch
/// `NSPasteboard` directly, so Core knows which changes FastUtils made itself.
///
/// Monitoring: macOS has no "clipboard changed" event, so `changeCount` is polled
/// every 0.5 s; contents are read only when it changed. Reference-counted: runs only while
/// some feature needs it.
@MainActor
public final class PasteboardService {
    private let pasteboard: NSPasteboard
    private let events: EventBus?
    private let log = Logger(subsystem: AppInfo.bundleIdentifier, category: "pasteboard")
    private var lastSeenChangeCount: Int
    private var transientChangeCounts: Set<Int> = []
    private var monitorUsers = 0
    private var timer: Timer?

    /// Decides, from the type list alone, whether the contents may be read at all
    /// (passwords are skipped without reading their data). Set by the history feature.
    public var shouldReadContents: (@MainActor (_ types: [String], _ sourceBundleID: String?) -> Bool)?

    public init(pasteboard: NSPasteboard = .general, events: EventBus? = nil) {
        self.pasteboard = pasteboard
        self.events = events
        lastSeenChangeCount = pasteboard.changeCount
    }

    public var changeCount: Int { pasteboard.changeCount }

    // MARK: Writing

    /// Writes plain text. `recordInHistory: false` for technical writes history must ignore.
    public func writeText(_ text: String, recordInHistory: Bool = true) {
        pasteboard.clearContents()
        pasteboard.setString(text, forType: .string)
        noteOwnWrite(recordInHistory: recordInHistory)
    }

    /// Writes several representations of one item (text + RTF + HTML, image, files).
    public func write(_ snapshot: PasteboardSnapshot, plainTextOnly: Bool = false, recordInHistory: Bool = true) {
        pasteboard.clearContents()
        if !snapshot.fileURLs.isEmpty && !plainTextOnly {
            pasteboard.writeObjects(snapshot.fileURLs as [NSURL])
        } else {
            let item = NSPasteboardItem()
            if let string = snapshot.string { item.setString(string, forType: .string) }
            if !plainTextOnly {
                if let rtf = snapshot.rtf { item.setData(rtf, forType: .rtf) }
                if let html = snapshot.html { item.setData(html, forType: .html) }
                if let image = snapshot.image {
                    let isPNG = image.starts(with: [0x89, 0x50, 0x4E, 0x47])
                    item.setData(image, forType: isPNG ? .png : .tiff)
                }
            }
            pasteboard.writeObjects([item])
        }
        noteOwnWrite(recordInHistory: recordInHistory)
    }

    public func clear() {
        pasteboard.clearContents()
        noteOwnWrite(recordInHistory: false)
    }

    public func readText() -> String? {
        pasteboard.string(forType: .string)
    }

    /// An image on the clipboard (screenshot, copied picture), if any.
    public func readImage() -> CGImage? {
        guard let data = pasteboard.data(forType: .png) ?? pasteboard.data(forType: .tiff),
              let source = CGImageSourceCreateWithData(data as CFData, nil)
        else { return nil }
        return CGImageSourceCreateImageAtIndex(source, 0, nil)
    }

    private func noteOwnWrite(recordInHistory: Bool) {
        if !recordInHistory { transientChangeCounts.insert(pasteboard.changeCount) }
    }

    // MARK: Reading

    /// `bypassingFilter`: read everything (used to restore the clipboard exactly as it was).
    public func readSnapshot(bypassingFilter: Bool = false) -> PasteboardSnapshot? {
        guard let item = pasteboard.pasteboardItems?.first else { return nil }
        let types = item.types.map(\.rawValue)
        let source = NSWorkspace.shared.frontmostApplication
        var snapshot = PasteboardSnapshot(
            changeCount: pasteboard.changeCount, types: types,
            sourceBundleID: source?.bundleIdentifier, sourceName: source?.localizedName
        )
        if !bypassingFilter, let shouldReadContents, !shouldReadContents(types, snapshot.sourceBundleID) {
            return snapshot
        }
        snapshot.fileURLs = (pasteboard.readObjects(forClasses: [NSURL.self], options: [.urlReadingFileURLsOnly: true]) as? [URL]) ?? []
        snapshot.string = item.string(forType: .string)
        snapshot.rtf = item.data(forType: .rtf)
        snapshot.html = item.data(forType: .html)
        snapshot.image = item.data(forType: .png) ?? item.data(forType: .tiff)
        return snapshot
    }

    // MARK: Monitoring

    public func startMonitoring() {
        monitorUsers += 1
        guard timer == nil else { return }
        lastSeenChangeCount = pasteboard.changeCount
        let timer = Timer(timeInterval: 0.5, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.checkForChanges() }
        }
        timer.tolerance = 0.1
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
    }

    public func stopMonitoring() {
        monitorUsers = max(0, monitorUsers - 1)
        guard monitorUsers == 0 else { return }
        timer?.invalidate()
        timer = nil
    }

    /// While suspended the monitor does not look at the clipboard; on resume the changes made
    /// meanwhile are skipped. Used when FastUtils itself drives the clipboard briefly
    /// (copying the selection for translation, then restoring).
    public private(set) var isSuspended = false

    public func suspendMonitoring() { isSuspended = true }

    public func resumeMonitoring() {
        isSuspended = false
        lastSeenChangeCount = pasteboard.changeCount
    }

    /// One polling tick; public for tests.
    public func checkForChanges() {
        guard !isSuspended else { return }
        let current = pasteboard.changeCount
        guard current != lastSeenChangeCount else { return }
        lastSeenChangeCount = current
        let record = !transientChangeCounts.contains(current)
        transientChangeCounts = transientChangeCounts.filter { $0 > current }
        guard let snapshot = readSnapshot() else { return }
        events?.publish(ClipboardChanged(snapshot: snapshot, recordInHistory: record))
    }
}
