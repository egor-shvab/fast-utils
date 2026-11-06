import Core
import CryptoKit
import Foundation
import UniformTypeIdentifiers

public enum ClipKind: String, CaseIterable, Sendable {
    case text, link, image, files
}

/// Content extracted from a clipboard snapshot, ready to be stored.
struct ClipContent: Sendable, Equatable {
    var kind: ClipKind
    /// Plain text; the URL for links; file names for files.
    var text: String?
    var rtf: Data?
    var html: Data?
    var image: Data?
    var fileURLs: [URL] = []

    /// Identity for de-duplication: the same content copied again bumps the old entry.
    var hash: String {
        var hasher = SHA256()
        hasher.update(data: Data(kind.rawValue.utf8))
        switch kind {
        case .text, .link: hasher.update(data: Data((text ?? "").utf8))
        case .image: hasher.update(data: image ?? Data())
        case .files: hasher.update(data: Data(fileURLs.map(\.path).joined(separator: "\n").utf8))
        }
        return hasher.finalize().map { String(format: "%02x", $0) }.joined()
    }

    var byteSize: Int {
        (text?.utf8.count ?? 0) + (rtf?.count ?? 0) + (html?.count ?? 0) + (image?.count ?? 0)
    }

    /// Largest text item history keeps (a copied log or a whole web page would bloat the
    /// database and slow down the list and search). Images have their own size setting.
    static let maxTextBytes = 1_048_576

    /// The item within `maxBytes`: formatting (RTF/HTML) goes first, the plain text stays;
    /// `nil` when even the plain text is over the limit. Images are left to their own limit.
    func limited(to maxBytes: Int) -> ClipContent? {
        guard image == nil else { return self }
        if (text?.utf8.count ?? 0) > maxBytes { return nil }
        guard byteSize > maxBytes else { return self }
        var plain = self
        plain.rtf = nil
        plain.html = nil
        return plain
    }
}

/// A stored history entry.
public struct ClipItem: Identifiable, Sendable, Equatable {
    public let id: Int64
    public var kind: ClipKind
    public var text: String?
    public var rtf: Data?
    public var html: Data?
    /// Absolute paths inside the history folder.
    public var imageURL: URL?
    public var thumbnailURL: URL?
    public var imageSize: CGSize?
    public var fileURLs: [URL]
    public var sourceBundleID: String?
    public var sourceName: String?
    public var createdAt: Date
    public var updatedAt: Date
    public var isPinned: Bool
    public var byteSize: Int
}

/// Turns a snapshot into content of one kind. New kinds (colors, code…) are added
/// as new handlers without touching the store or the history window.
protocol ClipContentHandler: Sendable {
    func content(from snapshot: PasteboardSnapshot) -> ClipContent?
}

struct FilesHandler: ClipContentHandler {
    func content(from snapshot: PasteboardSnapshot) -> ClipContent? {
        guard !snapshot.fileURLs.isEmpty else { return nil }
        return ClipContent(kind: .files, text: snapshot.fileURLs.map(\.lastPathComponent).joined(separator: "\n"),
                           fileURLs: snapshot.fileURLs)
    }
}

struct ImageHandler: ClipContentHandler {
    /// An image is the item only when the source app prefers it (first type) or there is no text:
    /// copying from a rich editor also puts a preview image next to the text.
    /// Decided by the types too: when history keeps no images, Core does not read the data, and
    /// the item must still count as an image (and be skipped), not turn into its alt text.
    static let imageTypes: Set<String> = ["public.png", "public.tiff"]

    func content(from snapshot: PasteboardSnapshot) -> ClipContent? {
        let image = snapshot.image
        guard image != nil || snapshot.types.contains(where: Self.imageTypes.contains) else { return nil }
        let preferred = snapshot.types.first.flatMap { UTType($0)?.conforms(to: .image) } ?? false
        let hasText = !(snapshot.string?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ?? true)
        guard preferred || !hasText else { return nil }
        return ClipContent(kind: .image, image: image)
    }
}

struct LinkHandler: ClipContentHandler {
    func content(from snapshot: PasteboardSnapshot) -> ClipContent? {
        guard let text = snapshot.string?.trimmingCharacters(in: .whitespacesAndNewlines),
              !text.contains(where: \.isWhitespace),
              let url = URL(string: text), let scheme = url.scheme?.lowercased(),
              ["http", "https"].contains(scheme), url.host() != nil
        else { return nil }
        return ClipContent(kind: .link, text: text)
    }
}

struct TextHandler: ClipContentHandler {
    func content(from snapshot: PasteboardSnapshot) -> ClipContent? {
        guard let text = snapshot.string, !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return nil }
        return ClipContent(kind: .text, text: text, rtf: snapshot.rtf, html: snapshot.html)
    }
}

enum ClipContentFactory {
    /// Order matters: the first handler that accepts the snapshot wins.
    static let handlers: [any ClipContentHandler] = [FilesHandler(), ImageHandler(), LinkHandler(), TextHandler()]

    static func content(from snapshot: PasteboardSnapshot) -> ClipContent? {
        for handler in handlers {
            if let content = handler.content(from: snapshot) { return content }
        }
        return nil
    }
}
