import AppKit
import Observation
import SwiftUI

/// Short non-interactive notifications ("Copied: 142 characters"). Never takes focus or
/// clicks, needs no notification permission. A new message replaces the current one.
@MainActor
@Observable
public final class HUDService {
    public enum Style: Sendable { case success, info, error }
    public enum Position: String, CaseIterable, Sendable { case bottomCenter, nearCursor }

    public var isEnabled: Bool { didSet { settings.set(isEnabled, for: "hud.enabled") } }
    public var position: Position { didSet { settings.set(position.rawValue, for: "hud.position") } }

    @ObservationIgnored private let settings: ScopedSettings
    @ObservationIgnored private(set) var panel: NSPanel?
    @ObservationIgnored private var hostingController: NSViewController?
    @ObservationIgnored private var hideTask: Task<Void, Never>?
    @ObservationIgnored private let duration: Duration = .milliseconds(1500)

    init(settings: ScopedSettings) {
        self.settings = settings
        isEnabled = settings.value("hud.enabled", default: true)
        position = Position(rawValue: settings.value("hud.position", default: "")) ?? .bottomCenter
    }

    /// Largest HUD size; longer text is truncated instead of overflowing the panel.
    static let maxSize = CGSize(width: 440, height: 200)

    /// Shows a message with an optional secondary line (e.g. a preview of copied text).
    /// `swatch` replaces the icon with a circle of that color. Errors are shown even when
    /// HUDs are turned off.
    public func show(_ text: String, detail: String? = nil, icon: String? = nil, swatch: RGBColor? = nil, style: Style = .success) {
        guard isEnabled || style == .error else { return }
        let defaultIcon = switch style {
        case .success: "checkmark.circle.fill"
        case .info: "info.circle.fill"
        case .error: "exclamationmark.triangle.fill"
        }
        let symbol = icon ?? defaultIcon
        // `fittingSize` of an NSHostingView measures text unwrapped, so long text made the
        // panel wider than its content. Ask SwiftUI for the size within an explicit maximum.
        let controller = NSHostingController(rootView: HUDView(text: text, detail: detail, icon: symbol, swatch: swatch, style: style))
        let fitted = controller.sizeThatFits(in: Self.maxSize)
        let size = CGSize(width: ceil(min(fitted.width, Self.maxSize.width)),
                          height: ceil(min(fitted.height, Self.maxSize.height)))
        hostingController = controller
        let hosting = controller.view

        let panel = self.panel ?? makePanel()
        self.panel = panel
        // Size the panel first, then put the content in at exactly that size. Adding the
        // content first and resizing afterwards let autoresizing add the size difference
        // again, so the content ended up wider than the panel and shifted out of it.
        var frame = CGRect(origin: panel.frame.origin, size: size)
        if let visible = ScreenGeometry.screenWithMouse()?.visibleFrame {
            frame = switch position {
            case .bottomCenter: ScreenGeometry.bottomCenter(size: size, in: visible)
            case .nearCursor: ScreenGeometry.frame(size: size, near: NSEvent.mouseLocation, in: visible)
            }
        }
        panel.setFrame(frame, display: false)

        let effect = panel.contentView as! NSVisualEffectView
        effect.subviews.forEach { $0.removeFromSuperview() }
        hosting.frame = effect.bounds
        hosting.autoresizingMask = [.width, .height]
        effect.addSubview(hosting)
        panel.display()

        let animate = !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
        if !panel.isVisible {
            panel.alphaValue = animate ? 0 : 1
            panel.orderFrontRegardless()
        }
        if animate {
            NSAnimationContext.runAnimationGroup { $0.duration = 0.15; panel.animator().alphaValue = 1 }
        } else {
            panel.alphaValue = 1
        }

        hideTask?.cancel()
        hideTask = Task { [weak self, duration] in
            try? await Task.sleep(for: duration)
            guard !Task.isCancelled else { return }
            self?.hide(animated: animate)
        }
    }

    private func hide(animated: Bool) {
        guard let panel else { return }
        guard animated else { panel.orderOut(nil); return }
        NSAnimationContext.runAnimationGroup({ $0.duration = 0.25; panel.animator().alphaValue = 0 }) {
            MainActor.assumeIsolated {
                if panel.alphaValue == 0 { panel.orderOut(nil) }
            }
        }
    }

    private func makePanel() -> NSPanel {
        let panel = NSPanel(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel],
                            backing: .buffered, defer: true)
        panel.level = .statusBar
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
        panel.ignoresMouseEvents = true
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.hidesOnDeactivate = false
        let effect = NSVisualEffectView()
        effect.material = .hudWindow
        effect.state = .active
        effect.wantsLayer = true
        effect.layer?.cornerRadius = 12
        effect.layer?.masksToBounds = true
        panel.contentView = effect
        return panel
    }
}

private struct HUDView: View {
    let text: String
    let detail: String?
    let icon: String
    let swatch: RGBColor?
    let style: HUDService.Style

    var body: some View {
        HStack(spacing: 12) {
            if let swatch {
                Circle()
                    .fill(Color(nsColor: swatch.nsColor))
                    // Visible on white and black alike.
                    .overlay(Circle().strokeBorder(Color.primary.opacity(0.3), lineWidth: 1))
                    .frame(width: 22, height: 22)
                    .accessibilityHidden(true)
            } else {
                Image(systemName: icon)
                    .font(.title2)
                    .foregroundStyle(style == .error ? Color.orange : (style == .success ? Color.green : Color.accentColor))
                    .accessibilityHidden(true)
            }
            VStack(alignment: .leading, spacing: 2) {
                Text(text)
                    .font(.body.weight(.semibold))
                    .lineLimit(2)
                if let detail, !detail.isEmpty {
                    Text(detail)
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                        .truncationMode(.tail)
                }
            }
            .multilineTextAlignment(.leading)
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 12)
    }
}
