import AppKit
import Carbon.HIToolbox
import Combine
import Core

enum HistoryFilter: String, CaseIterable, Sendable {
    case all, text, images, files, links, pinned

    var kind: ClipKind? {
        switch self {
        case .text: .text
        case .images: .image
        case .files: .files
        case .links: .link
        case .all, .pinned: nil
        }
    }

    var icon: String {
        switch self {
        case .all: "tray.full"
        case .text: "text.alignleft"
        case .images: "photo"
        case .files: "doc"
        case .links: "link"
        case .pinned: "pin"
        }
    }

    var title: String { String(localized: String.LocalizationValue("clipboard.filter.\(rawValue)")) }
}

/// Keyboard commands of the history window.
enum HistoryCommand: Equatable {
    case up, down, paste, pastePlain, quickPaste(Int), copy, preview, togglePin, delete, escape
    /// Not ours: let the search field have it.
    case passThrough

    /// ⌘1…⌘9 by physical key, so it works in any layout.
    static let digitKeys = [kVK_ANSI_1, kVK_ANSI_2, kVK_ANSI_3, kVK_ANSI_4, kVK_ANSI_5,
                            kVK_ANSI_6, kVK_ANSI_7, kVK_ANSI_8, kVK_ANSI_9]

    static func from(keyCode: Int, modifiers: NSEvent.ModifierFlags, queryIsEmpty: Bool) -> HistoryCommand {
        let flags = modifiers.intersection([.command, .shift, .option, .control])
        switch (keyCode, flags) {
        case (kVK_UpArrow, []): return .up
        case (kVK_DownArrow, []): return .down
        case (kVK_Return, []), (kVK_ANSI_KeypadEnter, []): return .paste
        case (kVK_Return, [.shift]), (kVK_ANSI_KeypadEnter, [.shift]): return .pastePlain
        case (kVK_Escape, []): return .escape
        case (kVK_Space, []) where queryIsEmpty: return .preview
        case (kVK_ANSI_Y, [.command]): return .preview
        case (kVK_ANSI_C, [.command]): return .copy
        case (kVK_ANSI_P, [.command]): return .togglePin
        case (kVK_Delete, [.command]), (kVK_ForwardDelete, [.command]): return .delete
        default:
            if flags == [.command], let index = digitKeys.firstIndex(of: keyCode) { return .quickPaste(index + 1) }
            return .passThrough
        }
    }
}

/// State of the history window. An ObservableObject, not `@State` (see CLAUDE.md).
@MainActor
final class HistoryViewModel: ObservableObject {
    @Published var query = "" { didSet { if query != oldValue { scheduleReload() } } }
    @Published var filter: HistoryFilter = .all { didSet { if filter != oldValue { scheduleReload() } } }
    @Published private(set) var items: [ClipItem] = []
    @Published var selectedID: Int64? {
        didSet { if selectedID != oldValue, previewOnSelect { loadSidePreview() } }
    }
    /// Full content of the selected item, shown beside the list when `previewOnSelect` is on.
    @Published private(set) var sidePreview: ClipItem?
    var previewOnSelect = false
    /// The item shown in the preview overlay (fully loaded).
    @Published private(set) var preview: ClipItem?
    @Published private(set) var hasLoaded = false

    private let store: HistoryStore
    private let limit: Int
    private var reloadTask: Task<Void, Never>?
    private var sidePreviewTask: Task<Void, Never>?

    /// Actions the window asks for; the feature performs them.
    var onPaste: ((ClipItem, _ plainText: Bool) -> Void)?
    /// Other features' actions for an item ("Translate", "Recognize Text").
    var contentActions: ((ClipItem) -> [FeatureAction])?
    var onRunAction: ((ClipItem, FeatureAction) -> Void)?
    var onCopy: ((ClipItem) -> Void)?
    var onClose: (() -> Void)?

    init(store: HistoryStore, limit: Int) {
        self.store = store
        self.limit = limit
    }

    var pinnedItems: [ClipItem] { items.filter(\.isPinned) }
    var recentItems: [ClipItem] { items.filter { !$0.isPinned } }
    /// Display order: pinned first (the store already sorts so).
    var ordered: [ClipItem] { items }
    var selected: ClipItem? { items.first { $0.id == selectedID } }

    /// "⌘3" hint for the first nine rows.
    func number(of item: ClipItem) -> Int? {
        guard let index = ordered.prefix(9).firstIndex(where: { $0.id == item.id }) else { return nil }
        return index + 1
    }

    // MARK: Loading

    func reload() async {
        let needle = query
        let filter = filter
        let loaded = (try? await store.items(kind: filter.kind, query: needle, pinnedOnly: filter == .pinned, limit: limit)) ?? []
        guard needle == query, filter == self.filter else { return }  // a newer request is coming
        items = loaded
        if selectedID == nil || !loaded.contains(where: { $0.id == selectedID }) {
            selectedID = loaded.first?.id
        }
        hasLoaded = true
    }

    private func scheduleReload() {
        reloadTask?.cancel()
        reloadTask = Task { [weak self] in await self?.reload() }
    }

    // MARK: Commands

    /// Returns `true` if the key was handled.
    func handle(_ command: HistoryCommand) -> Bool {
        switch command {
        case .passThrough:
            return false
        case .up:
            moveSelection(-1)
        case .down:
            moveSelection(1)
        case .paste:
            if let selected { onPaste?(selected, false) }
        case .pastePlain:
            if let selected { onPaste?(selected, true) }
        case .quickPaste(let number):
            if ordered.indices.contains(number - 1) { onPaste?(ordered[number - 1], false) }
        case .copy:
            if let selected { onCopy?(selected) }
        case .preview:
            togglePreview()
        case .togglePin:
            if let selected { Task { await setPinned(selected, !selected.isPinned) } }
        case .delete:
            if let selected { Task { await delete(selected) } }
        case .escape:
            if preview != nil {
                preview = nil
            } else if !query.isEmpty {
                query = ""
            } else {
                onClose?()
            }
        }
        return true
    }

    func moveSelection(_ delta: Int) {
        guard !ordered.isEmpty else { return }
        let current = ordered.firstIndex { $0.id == selectedID } ?? -1
        let next = min(max(current + delta, 0), ordered.count - 1)
        selectedID = ordered[next].id
        if preview != nil { Task { await showPreview(ordered[next]) } }
    }

    func togglePreview() {
        if preview != nil {
            preview = nil
        } else if let selected {
            Task { await showPreview(selected) }
        }
    }

    private func loadSidePreview() {
        sidePreviewTask?.cancel()
        guard let selected else { sidePreview = nil; return }
        sidePreviewTask = Task {
            let full = (try? await store.item(selected.id)) ?? selected
            guard !Task.isCancelled else { return }
            sidePreview = full
        }
    }

    func showPreview(_ item: ClipItem) async {
        preview = (try? await store.item(item.id)) ?? item
    }

    func setPinned(_ item: ClipItem, _ pinned: Bool) async {
        try? await store.setPinned(item.id, pinned)
        await reload()
    }

    func delete(_ item: ClipItem) async {
        let index = ordered.firstIndex { $0.id == item.id }
        try? await store.delete(item.id)
        if preview?.id == item.id { preview = nil }
        await reload()
        // Keep the selection at the same position.
        if let index, !ordered.isEmpty { selectedID = ordered[min(index, ordered.count - 1)].id }
    }
}
