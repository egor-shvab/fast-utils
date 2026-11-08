import AppKit
import SwiftUI

/// What the toolbar asks the session to do.
struct ToolbarActions {
    var copy: () -> Void
    var save: () -> Void
    var close: () -> Void
    /// The grip is dragged: the session moves the panel after the mouse.
    var dragChanged: () -> Void
    var dragEnded: () -> Void
}

/// The floating toolbar above the frozen screen. It never takes the keyboard: the overlay
/// keeps it for Esc, ⌘Z, ⌘C, ⌘S and captions.
final class ToolbarPanel: NSPanel {
    init<Content: View>(content: Content) {
        let hosting = ToolbarHostingView(rootView: content)
        let size = hosting.fittingSize
        super.init(contentRect: CGRect(origin: .zero, size: size), styleMask: [.borderless, .nonactivatingPanel],
                   backing: .buffered, defer: false)
        // Above the overlays (`.screenSaver`).
        level = NSWindow.Level(rawValue: NSWindow.Level.screenSaver.rawValue + 1)
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
        isOpaque = false
        backgroundColor = .clear
        hasShadow = true
        hidesOnDeactivate = false
        animationBehavior = .none

        let effect = NSVisualEffectView(frame: CGRect(origin: .zero, size: size))
        effect.material = .hudWindow
        effect.state = .active
        effect.wantsLayer = true
        effect.layer?.cornerRadius = 10
        effect.layer?.masksToBounds = true
        contentView = effect
        // Window size first, then the content at exactly that size (see "HUD" in CLAUDE.md).
        hosting.frame = effect.bounds
        hosting.autoresizingMask = [.width, .height]
        effect.addSubview(hosting)
    }

    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}

/// Buttons work on the first click although the panel is never key. Over the panel the cursor
/// is always the arrow: otherwise the overlay's crosshair or brush would stay. (Per-button
/// cursors were tried — SwiftUI hover does not fire in a background app, and button frames
/// were unreliable — the owner chose a static arrow.)
private final class ToolbarHostingView<Content: View>: NSHostingView<Content> {
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        trackingAreas.filter { $0.owner === self }.forEach(removeTrackingArea)
        addTrackingArea(NSTrackingArea(rect: bounds, options: [.mouseMoved, .cursorUpdate, .activeAlways, .inVisibleRect],
                                       owner: self))
    }

    override func cursorUpdate(with event: NSEvent) { NSCursor.arrow.set() }

    override func mouseMoved(with event: NSEvent) {
        super.mouseMoved(with: event)
        NSCursor.arrow.set()
    }
}

struct ToolbarView: View {
    @ObservedObject var document: EditorDocument
    let actions: ToolbarActions

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: "line.3.horizontal")
                .rotationEffect(.degrees(90))
                .foregroundStyle(.secondary)
                .frame(width: 16, height: 28)
                .contentShape(Rectangle())
                .gesture(
                    DragGesture(minimumDistance: 0)
                        .onChanged { _ in actions.dragChanged() }
                        .onEnded { _ in actions.dragEnded() }
                )
                .help(String(localized: "screenshot.toolbar.move"))

            ForEach(Tool.allCases, id: \.self) { tool in
                iconButton(tool.symbol, help: String(localized: String.LocalizationValue("screenshot.tool.\(tool.rawValue)")),
                           selected: document.tool == tool) { document.tool = tool }
            }
            separator
            ForEach(InkColor.allCases, id: \.self) { color in
                Button { document.setColor(color) } label: {
                    Circle()
                        .fill(Color(nsColor: color.nsColor))
                        .frame(width: 16, height: 16)
                        .overlay(Circle().strokeBorder(Color.primary.opacity(document.color == color ? 0.9 : 0.25),
                                                       lineWidth: document.color == color ? 2 : 1))
                        .frame(width: 22, height: 28)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .help(String(localized: String.LocalizationValue("screenshot.color.\(color.rawValue)")))
            }
            separator
            ForEach(StrokeSize.allCases, id: \.self) { size in
                Button { document.setSize(size) } label: {
                    Circle()
                        .fill(Color.primary)
                        .frame(width: size.lineWidth + 2, height: size.lineWidth + 2)
                        .frame(width: 24, height: 28)
                        .background(document.size == size ? Color.accentColor.opacity(0.3) : .clear,
                                    in: RoundedRectangle(cornerRadius: 6))
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .help(String(localized: String.LocalizationValue("screenshot.size.\(size.rawValue)")))
            }
            separator
            iconButton("arrow.uturn.backward", help: String(localized: "screenshot.toolbar.undo"), action: document.undo)
                .disabled(!document.canUndo)
            iconButton("arrow.uturn.forward", help: String(localized: "screenshot.toolbar.redo"), action: document.redo)
                .disabled(!document.canRedo)
            separator
            iconButton("doc.on.doc", help: String(localized: "screenshot.toolbar.copy"), action: actions.copy)
            iconButton("square.and.arrow.down", help: String(localized: "screenshot.toolbar.save"), action: actions.save)
            iconButton("xmark", help: String(localized: "screenshot.toolbar.close"), action: actions.close)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
    }

    private var separator: some View {
        Divider().frame(height: 20).padding(.horizontal, 2)
    }

    private func iconButton(_ symbol: String, help: String, selected: Bool = false, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 13, weight: .medium))
                .frame(width: 28, height: 28)
                .background(selected ? Color.accentColor.opacity(0.3) : .clear, in: RoundedRectangle(cornerRadius: 6))
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(help)
        .accessibilityLabel(help)
    }
}
