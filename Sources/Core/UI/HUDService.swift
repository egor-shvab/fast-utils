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
    @ObservationIgnored private var panel: NSPanel?
    @ObservationIgnored private var hideTask: Task<Void, Never>?
    @ObservationIgnored private let duration: Duration = .milliseconds(1500)

    init(settings: ScopedSettings) {
        self.settings = settings
        isEnabled = settings.value("hud.enabled", default: true)
        position = Position(rawValue: settings.value("hud.position", default: "")) ?? .bottomCenter
    }

    /// Shows a message. Errors are shown even when HUDs are turned off.
    public func show(_ text: String, icon: String? = nil, style: Style = .success) {
        guard isEnabled || style == .error else { return }
        let defaultIcon = switch style {
        case .success: "checkmark.circle.fill"
        case .info: "info.circle.fill"
        case .error: "exclamationmark.triangle.fill"
        }
        let symbol = icon ?? defaultIcon
        let hosting = NSHostingView(rootView: HUDView(text: text, icon: symbol, style: style))
        let size = hosting.fittingSize

        let panel = self.panel ?? makePanel()
        self.panel = panel
        let effect = panel.contentView as! NSVisualEffectView
        effect.subviews.forEach { $0.removeFromSuperview() }
        hosting.frame = CGRect(origin: .zero, size: size)
        hosting.autoresizingMask = [.width, .height]
        effect.addSubview(hosting)

        if let visible = ScreenGeometry.screenWithMouse()?.visibleFrame {
            let frame = switch position {
            case .bottomCenter: ScreenGeometry.bottomCenter(size: size, in: visible)
            case .nearCursor: ScreenGeometry.frame(size: size, near: NSEvent.mouseLocation, in: visible)
            }
            panel.setFrame(frame, display: true)
        }

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
    let icon: String
    let style: HUDService.Style

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: icon)
                .font(.title2)
                .foregroundStyle(style == .error ? Color.orange : (style == .success ? Color.green : Color.accentColor))
            Text(text)
                .font(.body.weight(.medium))
                .lineLimit(3)
                .frame(maxWidth: 360, alignment: .leading)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 12)
    }
}
