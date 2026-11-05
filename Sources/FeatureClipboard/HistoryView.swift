import AppKit
import Core
import SwiftUI

/// The clipboard history window (TZ.md §7.3).
struct HistoryView: View {
    @ObservedObject var model: HistoryViewModel
    @FocusState private var searchFocused: Bool

    var body: some View {
        HStack(spacing: 0) {
            main.frame(width: 440)
            if model.previewOnSelect {
                Divider()
                Group {
                    if let item = model.sidePreview {
                        PreviewContent(item: item)
                    } else {
                        Text(String(localized: "clipboard.window.noSelection")).foregroundStyle(.secondary)
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
    }

    private var main: some View {
        VStack(spacing: 0) {
            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
                TextField(String(localized: "clipboard.window.search"), text: $model.query)
                    .textFieldStyle(.plain)
                    .font(.title3)
                    .focused($searchFocused)
            }
            .padding(.horizontal, 14)
            .padding(.top, 14)
            .padding(.bottom, 8)

            Picker("", selection: $model.filter) {
                ForEach(HistoryFilter.allCases, id: \.self) { filter in
                    Image(systemName: filter.icon).help(filter.title).tag(filter)
                }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .padding(.horizontal, 14)
            .padding(.bottom, 8)

            Divider()

            if model.hasLoaded && model.items.isEmpty {
                Text(String(localized: model.query.isEmpty && model.filter == .all
                            ? "clipboard.window.empty" : "clipboard.window.nothingFound"))
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                list
            }

            Divider()
            Text(String(localized: "clipboard.window.hint"))
                .font(.caption)
                .foregroundStyle(.tertiary)
                .lineLimit(1)
                .padding(.vertical, 6)
        }
        .overlay {
            if let preview = model.preview {
                PreviewOverlay(item: preview)
            }
        }
        .onAppear { searchFocused = true }
    }

    private var list: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 2) {
                    if !model.pinnedItems.isEmpty && model.filter != .pinned {
                        sectionHeader("clipboard.window.pinned")
                        rows(model.pinnedItems)
                        sectionHeader("clipboard.window.recent")
                    }
                    rows(model.filter == .pinned ? model.pinnedItems : model.recentItems)
                }
                .padding(.horizontal, 6)
                .padding(.vertical, 6)
            }
            .onChange(of: model.selectedID) { _, id in
                guard let id else { return }
                proxy.scrollTo(id)
            }
        }
    }

    private func sectionHeader(_ key: String.LocalizationValue) -> some View {
        Text(String(localized: key))
            .font(.caption.weight(.semibold))
            .foregroundStyle(.secondary)
            .padding(.horizontal, 8)
            .padding(.top, 6)
    }

    private func rows(_ items: [ClipItem]) -> some View {
        ForEach(items) { item in
            HistoryRow(item: item, number: model.number(of: item), isSelected: item.id == model.selectedID)
                .id(item.id)
                .contentShape(Rectangle())
                .onHover { inside in if inside { model.selectedID = item.id } }
                .onTapGesture { model.onPaste?(item, false) }
                .contextMenu { contextMenu(for: item) }
        }
    }

    @ViewBuilder
    private func contextMenu(for item: ClipItem) -> some View {
        Button(String(localized: "clipboard.menu.paste")) { model.onPaste?(item, false) }
        if item.kind == .text {
            Button(String(localized: "clipboard.menu.pastePlain")) { model.onPaste?(item, true) }
        }
        Button(String(localized: "clipboard.menu.copy")) { model.onCopy?(item) }
        Button(String(localized: item.isPinned ? "clipboard.menu.unpin" : "clipboard.menu.pin")) {
            Task { await model.setPinned(item, !item.isPinned) }
        }
        if item.kind == .files {
            Button(String(localized: "clipboard.menu.showInFinder")) {
                NSWorkspace.shared.activateFileViewerSelecting(item.fileURLs)
            }
        }
        if item.kind == .link, let url = item.text.flatMap(URL.init(string:)) {
            Button(String(localized: "clipboard.menu.openLink")) { NSWorkspace.shared.open(url) }
        }
        let extras = model.contentActions?(item) ?? []
        if !extras.isEmpty {
            Divider()
            ForEach(extras, id: \.id) { action in
                Button(action.contentTitle ?? action.title) { model.onRunAction?(item, action) }
            }
        }
        Divider()
        Button(String(localized: "clipboard.menu.delete"), role: .destructive) {
            Task { await model.delete(item) }
        }
    }
}

struct HistoryRow: View {
    let item: ClipItem
    let number: Int?
    let isSelected: Bool

    var body: some View {
        HStack(alignment: .center, spacing: 10) {
            AppIconView(bundleID: item.sourceBundleID)
                .frame(width: 18, height: 18)
            ClipContentView(item: item)
            Spacer(minLength: 4)
            VStack(alignment: .trailing, spacing: 2) {
                if item.isPinned {
                    Image(systemName: "pin.fill").font(.caption2).foregroundStyle(.secondary)
                }
                Text(item.updatedAt, format: .relative(presentation: .numeric, unitsStyle: .abbreviated))
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                if let number {
                    Text("⌘\(number)").font(.caption2.monospacedDigit()).foregroundStyle(.tertiary)
                }
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
        .background(
            RoundedRectangle(cornerRadius: 6)
                .fill(isSelected ? Color.accentColor.opacity(0.22) : .clear)
        )
    }
}

/// Row content by kind: text lines, link, image thumbnail, files.
struct ClipContentView: View {
    let item: ClipItem

    var body: some View {
        switch item.kind {
        case .text:
            HStack(spacing: 8) {
                if let color = item.text.flatMap(ColorParser.parse) {
                    RoundedRectangle(cornerRadius: 4)
                        .fill(color.color)
                        .overlay(RoundedRectangle(cornerRadius: 4).stroke(.secondary.opacity(0.5)))
                        .frame(width: 22, height: 22)
                }
                Text(item.text.map { String($0.prefix(400)) } ?? "")
                    .lineLimit(3)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        case .link:
            Label(item.text ?? "", systemImage: "link")
                .lineLimit(1)
                .truncationMode(.middle)
                .foregroundStyle(Color.accentColor)
                .frame(maxWidth: .infinity, alignment: .leading)
        case .image:
            HStack(spacing: 8) {
                ThumbnailView(url: item.thumbnailURL)
                    .frame(maxWidth: 120, maxHeight: 64, alignment: .leading)
                if let size = item.imageSize {
                    Text("\(Int(size.width)) × \(Int(size.height))").font(.caption).foregroundStyle(.secondary)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        case .files:
            FilesView(urls: item.fileURLs)
        }
    }
}

struct FilesView: View {
    let urls: [URL]

    var body: some View {
        HStack(spacing: 8) {
            if let first = urls.first {
                Image(nsImage: IconCache.icon(forFile: first))
                    .resizable()
                    .frame(width: 32, height: 32)
            }
            VStack(alignment: .leading, spacing: 1) {
                Text(urls.count == 1 ? urls[0].lastPathComponent
                     : String(format: String(localized: "clipboard.window.filesCount"), urls.count))
                    .lineLimit(1)
                if urls.count > 1 {
                    Text(urls.map(\.lastPathComponent).joined(separator: ", "))
                        .font(.caption).foregroundStyle(.secondary).lineLimit(1)
                } else if let first = urls.first {
                    if FileManager.default.fileExists(atPath: first.path) {
                        Text(first.deletingLastPathComponent().path(percentEncoded: false))
                            .font(.caption).foregroundStyle(.secondary).lineLimit(1).truncationMode(.head)
                    } else {
                        Text(String(localized: "clipboard.window.fileMissing")).font(.caption).foregroundStyle(.red)
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

struct ThumbnailView: View {
    let url: URL?

    var body: some View {
        if let url, let image = IconCache.image(at: url) {
            Image(nsImage: image)
                .resizable()
                .aspectRatio(contentMode: .fit)
                .clipShape(RoundedRectangle(cornerRadius: 4))
        } else {
            Image(systemName: "photo").foregroundStyle(.secondary)
        }
    }
}

struct AppIconView: View {
    let bundleID: String?

    var body: some View {
        if let bundleID, let icon = IconCache.appIcon(bundleID: bundleID) {
            Image(nsImage: icon).resizable()
        } else {
            Image(systemName: "app.dashed").foregroundStyle(.secondary)
        }
    }
}

/// Full content over the list: Space or Esc closes it.
struct PreviewOverlay: View {
    let item: ClipItem

    var body: some View {
        VStack(spacing: 0) {
            PreviewContent(item: item)
            Divider()
            Text(String(localized: "clipboard.window.previewHint"))
                .font(.caption).foregroundStyle(.tertiary).padding(.vertical, 6)
        }
        .background(.regularMaterial)
    }
}

/// The full text, image or file list of an item.
struct PreviewContent: View {
    let item: ClipItem

    var body: some View {
        Group {
            switch item.kind {
            case .text, .link:
                ScrollView {
                    VStack(alignment: .leading, spacing: 10) {
                        if let color = item.text.flatMap(ColorParser.parse) {
                            RoundedRectangle(cornerRadius: 8).fill(color.color).frame(height: 80)
                        }
                        Text(item.text ?? "")
                            .textSelection(.enabled)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .padding(14)
                }
            case .image:
                if let url = item.imageURL, let image = NSImage(contentsOf: url) {
                    Image(nsImage: image).resizable().aspectRatio(contentMode: .fit).padding(14)
                }
            case .files:
                ScrollView {
                    VStack(alignment: .leading, spacing: 8) {
                        ForEach(item.fileURLs, id: \.self) { url in
                            HStack {
                                Image(nsImage: IconCache.icon(forFile: url)).resizable().frame(width: 32, height: 32)
                                VStack(alignment: .leading) {
                                    Text(url.lastPathComponent)
                                    Text(url.path(percentEncoded: false)).font(.caption).foregroundStyle(.secondary)
                                }
                            }
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(14)
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

/// Small caches so scrolling does not reload icons and thumbnails.
@MainActor
enum IconCache {
    private static let images = NSCache<NSURL, NSImage>()
    private static var appIcons: [String: NSImage?] = [:]

    static func image(at url: URL) -> NSImage? {
        if let cached = images.object(forKey: url as NSURL) { return cached }
        guard let image = NSImage(contentsOf: url) else { return nil }
        images.setObject(image, forKey: url as NSURL)
        return image
    }

    static func appIcon(bundleID: String) -> NSImage? {
        if let cached = appIcons[bundleID] { return cached }
        let icon = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID)
            .map { NSWorkspace.shared.icon(forFile: $0.path) }
        appIcons[bundleID] = icon
        return icon
    }

    static func icon(forFile url: URL) -> NSImage {
        NSWorkspace.shared.icon(forFile: url.path)
    }
}
