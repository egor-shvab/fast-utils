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
    /// The contents were not read (a password, or an app excluded from history): only `types`
    /// and the source are known.
    public var contentsWithheld = false

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

    /// Apps whose copies the monitor does not read (history exclusions), by bundle id.
    public var excludedApps: Set<String> = []
    /// `true` lets the monitor read concealed items (the user turned off skipping passwords
    /// in history). `readText()` / `readImage()` refuse them regardless.
    public var monitorReadsConcealed = false
    /// `false` when history keeps no images: the monitor then skips image data, which can be
    /// tens of megabytes (a screenshot as TIFF) and is read on the main thread.
    public var monitorReadsImages = true

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

    /// The clipboard holds a password or other data marked as private.
    public var containsConcealed: Bool {
        (pasteboard.pasteboardItems ?? []).contains { PasteboardPrivacy.isConcealed($0.types.map(\.rawValue)) }
    }

    /// Clipboard text; `nil` when there is none or it is concealed (a password).
    public func readText() -> String? {
        guard !containsConcealed else { return nil }
        return pasteboard.string(forType: .string)
    }

    /// An image on the clipboard (screenshot, copied picture); `nil` when concealed.
    public func readImage() -> CGImage? {
        guard !containsConcealed,
              let data = pasteboard.data(forType: .png) ?? pasteboard.data(forType: .tiff),
              let source = CGImageSourceCreateWithData(data as CFData, nil)
        else { return nil }
        return CGImageSourceCreateImageAtIndex(source, 0, nil)
    }

    private func noteOwnWrite(recordInHistory: Bool) {
        if !recordInHistory { transientChangeCounts.insert(pasteboard.changeCount) }
    }

    // MARK: Backup

    /// Everything on the clipboard — every item with every type — to put back exactly as it was.
    /// Holds private data too, so its contents are never inspected or logged.
    public struct Backup: Sendable {
        fileprivate let items: [[Representation]]
        fileprivate struct Representation: Sendable {
            let type: String
            let data: Data
        }
    }

    public func backup() -> Backup {
        Backup(items: (pasteboard.pasteboardItems ?? []).map { item in
            item.types.compactMap { type in
                item.data(forType: type).map { Backup.Representation(type: type.rawValue, data: $0) }
            }
        })
    }

    /// Puts a backup back. A technical write: history ignores it.
    public func restore(_ backup: Backup) {
        pasteboard.clearContents()
        let items = backup.items.filter { !$0.isEmpty }.map { representations in
            let item = NSPasteboardItem()
            for representation in representations {
                item.setData(representation.data, forType: NSPasteboard.PasteboardType(representation.type))
            }
            return item
        }
        if !items.isEmpty { pasteboard.writeObjects(items) }
        noteOwnWrite(recordInHistory: false)
    }

    // MARK: Reading

    /// The first item for history. Concealed items and copies from excluded apps come back with
    /// `contentsWithheld` and no data: the decision uses only the type list and the source.
    func readSnapshot() -> PasteboardSnapshot? {
        guard let item = pasteboard.pasteboardItems?.first else { return nil }
        let types = item.types.map(\.rawValue)
        let source = Self.source(of: item)
        var snapshot = PasteboardSnapshot(
            changeCount: pasteboard.changeCount, types: types,
            sourceBundleID: source.bundleID, sourceName: source.name
        )
        let concealed = PasteboardPrivacy.isConcealed(types) && !monitorReadsConcealed
        if concealed || source.bundleID.map(excludedApps.contains) == true {
            snapshot.contentsWithheld = true
            return snapshot
        }
        snapshot.fileURLs = (pasteboard.readObjects(forClasses: [NSURL.self], options: [.urlReadingFileURLsOnly: true]) as? [URL]) ?? []
        snapshot.string = item.string(forType: .string)
        snapshot.rtf = item.data(forType: .rtf)
        snapshot.html = item.data(forType: .html)
        if monitorReadsImages {
            snapshot.image = item.data(forType: .png) ?? item.data(forType: .tiff)
        }
        return snapshot
    }

    /// The app that wrote the item: its own `org.nspasteboard.source` mark when present,
    /// otherwise the frontmost app now (polling notices a change up to 0.5 s late, so a quick
    /// app switch right after copying can attribute it to the wrong app).
    private static func source(of item: NSPasteboardItem) -> (bundleID: String?, name: String?) {
        let marked = item.string(forType: NSPasteboard.PasteboardType(PasteboardPrivacy.sourceType))?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        if let marked, !marked.isEmpty {
            let name = NSRunningApplication.runningApplications(withBundleIdentifier: marked).first?.localizedName
                ?? NSWorkspace.shared.urlForApplication(withBundleIdentifier: marked)
                    .map { FileManager.default.displayName(atPath: $0.path).replacingOccurrences(of: ".app", with: "") }
            return (marked, name)
        }
        let frontmost = NSWorkspace.shared.frontmostApplication
        return (frontmost?.bundleIdentifier, frontmost?.localizedName)
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
