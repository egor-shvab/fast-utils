import AppKit
import Observation
import SwiftUI

/// A floating panel that takes keyboard input without activating the app, so the app the
/// user was in stays frontmost (Spotlight-style). Shown on every Space and over full-screen
/// apps. Closes on Esc and when it loses focus, unless pinned.
final class FloatingPanel: NSPanel {
    var isPinned = false
    var onClose: (() -> Void)?

    init(size: CGSize) {
        super.init(
            contentRect: CGRect(origin: .zero, size: size),
            styleMask: [.nonactivatingPanel, .titled, .closable, .fullSizeContentView, .resizable],
            backing: .buffered, defer: true
        )
        isFloatingPanel = true
        level = .floating
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .transient]
        titleVisibility = .hidden
        titlebarAppearsTransparent = true
        isMovableByWindowBackground = true
        hidesOnDeactivate = false
        becomesKeyOnlyIfNeeded = false
        animationBehavior = .utilityWindow
        isReleasedWhenClosed = false
        standardWindowButton(.closeButton)?.isHidden = true
        standardWindowButton(.miniaturizeButton)?.isHidden = true
        standardWindowButton(.zoomButton)?.isHidden = true
    }

    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }

    /// Esc.
    override func cancelOperation(_ sender: Any?) { close() }

    override func resignKey() {
        super.resignKey()
        if !isPinned { close() }
    }

    override func close() {
        let wasVisible = isVisible
        super.close()
        if wasVisible { onClose?() }
    }
}

/// Lets panel content pin or close its own panel.
@MainActor
@Observable
public final class PanelHandle {
    public var isPinned = false { didSet { panel?.isPinned = isPinned } }
    @ObservationIgnored weak var panel: FloatingPanel?

    public func close() { panel?.close() }
}

/// Creates floating panels with uniform behavior. One panel per id: presenting an id that
/// is already on screen closes it (pressing the hotkey again hides the panel).
@MainActor
public final class PanelService {
    public enum Placement: Sendable { case nearCursor, center }

    private var panels: [String: FloatingPanel] = [:]

    public init() {}

    public func isPresented(_ id: String) -> Bool { panels[id]?.isVisible == true }

    @discardableResult
    public func toggle<Content: View>(
        id: String,
        size: CGSize,
        placement: Placement = .nearCursor,
        onClose: (() -> Void)? = nil,
        @ViewBuilder content: (PanelHandle) -> Content
    ) -> PanelHandle? {
        if isPresented(id) {
            close(id)
            return nil
        }
        return present(id: id, size: size, placement: placement, onClose: onClose, content: content)
    }

    @discardableResult
    public func present<Content: View>(
        id: String,
        size: CGSize,
        placement: Placement = .nearCursor,
        onClose: (() -> Void)? = nil,
        @ViewBuilder content: (PanelHandle) -> Content
    ) -> PanelHandle {
        close(id)
        let handle = PanelHandle()
        let panel = FloatingPanel(size: size)
        handle.panel = panel

        let effect = NSVisualEffectView()
        effect.material = .popover
        effect.state = .active
        let hosting = NSHostingView(rootView: content(handle))
        hosting.translatesAutoresizingMaskIntoConstraints = false
        effect.addSubview(hosting)
        NSLayoutConstraint.activate([
            hosting.leadingAnchor.constraint(equalTo: effect.leadingAnchor),
            hosting.trailingAnchor.constraint(equalTo: effect.trailingAnchor),
            hosting.topAnchor.constraint(equalTo: effect.topAnchor),
            hosting.bottomAnchor.constraint(equalTo: effect.bottomAnchor),
        ])
        panel.contentView = effect

        if let visible = ScreenGeometry.screenWithMouse()?.visibleFrame {
            let frame = switch placement {
            case .nearCursor: ScreenGeometry.frame(size: size, near: NSEvent.mouseLocation, in: visible)
            case .center: ScreenGeometry.center(size: size, in: visible)
            }
            panel.setFrame(frame, display: false)
        }

        panel.onClose = { [weak self, weak panel] in
            if let panel, self?.panels[id] === panel { self?.panels[id] = nil }
            onClose?()
        }
        panels[id] = panel
        panel.makeKeyAndOrderFront(nil)
        return handle
    }

    public func close(_ id: String) {
        panels[id]?.close()
        panels[id] = nil
    }
}
