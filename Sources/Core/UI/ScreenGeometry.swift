import AppKit

/// Placement math for panels and HUD, kept pure for tests.
enum ScreenGeometry {
    /// The screen under the mouse pointer (all our popups appear there).
    @MainActor
    static func screenWithMouse() -> NSScreen? {
        let mouse = NSEvent.mouseLocation
        return NSScreen.screens.first { NSMouseInRect(mouse, $0.frame, false) } ?? NSScreen.main
    }

    /// A frame of `size` next to `point` (below-right of the cursor, like a context menu),
    /// flipped above / to the left when it would leave `visible`, then clamped inside it.
    static func frame(size: CGSize, near point: CGPoint, in visible: CGRect, gap: CGFloat = 12) -> CGRect {
        var x = point.x + gap
        var y = point.y - gap - size.height  // AppKit: origin is bottom-left
        if x + size.width > visible.maxX { x = point.x - gap - size.width }
        if y < visible.minY { y = point.y + gap }
        x = min(max(x, visible.minX), visible.maxX - size.width)
        y = min(max(y, visible.minY), visible.maxY - size.height)
        return CGRect(origin: CGPoint(x: x, y: y), size: size)
    }

    /// Horizontally centered, `bottomInset` above the bottom of `visible`.
    static func bottomCenter(size: CGSize, in visible: CGRect, bottomInset: CGFloat = 96) -> CGRect {
        CGRect(x: visible.midX - size.width / 2, y: visible.minY + bottomInset, width: size.width, height: size.height)
    }

    static func center(size: CGSize, in visible: CGRect) -> CGRect {
        CGRect(x: visible.midX - size.width / 2, y: visible.midY - size.height / 2 + visible.height * 0.1,
               width: size.width, height: size.height)
    }
}
